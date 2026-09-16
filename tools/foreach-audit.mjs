/**
 * ForEach key 审计（针对 CLink 参考工程的只读检查）
 * ============================================================================
 * 背景：ArkUI 的 ForEach **会复用 key 相同的项**——键不变就不会重建子节点。
 * 子节点里那些「不依赖状态变量」的表达式（例如列表项里按钮的
 * `resolvePrimaryButtonColor(this.isDarkMode, this.accentOrPrimary())`）
 * 在键不变时**永远不会被重新求值**，于是切主题色后列表项停在旧配色。
 *
 * 所以 key 生成器必须把「会影响外观的状态」编进去：选中态、展开态、加载态、主题色。
 * 本脚本找出**没有**把 `this.accentColor` 编进 key 的 ForEach。
 *
 * 实现要点：不能用一个宽泛的正则去猜 —— 那会既漏报又误报。
 * 这里按字符扫描 + 括号配平，精确切出每个 `ForEach(...)` 的完整实参串，
 * 再在其中定位第 3 个实参（key 生成器）。
 *
 * 用法：node tools/foreach-audit.mjs <ets 源码目录>
 */
import fs from 'node:fs';
import path from 'node:path';

const rootArg = process.argv[2];
if (!rootArg) {
  console.error('用法: node tools/foreach-audit.mjs <ets 源码目录>');
  process.exit(2);
}

function walk(p, out = []) {
  const st = fs.statSync(p);
  if (st.isDirectory()) {
    for (const e of fs.readdirSync(p, { withFileTypes: true })) walk(path.join(p, e.name), out);
  } else if (p.endsWith('.ets')) {
    out.push(p);
  }
  return out;
}

/** 生成掩码：注释与字符串内容变空格（保留换行与所有语法符号、括号） */
function mask(src) {
  const chars = src.split('');
  const n = src.length;
  let i = 0;
  while (i < n) {
    const c = src[i];
    const c2 = src[i + 1];
    if (c === '/' && c2 === '/') {
      while (i < n && src[i] !== '\n') {
        chars[i] = ' ';
        i++;
      }
      continue;
    }
    if (c === '/' && c2 === '*') {
      chars[i] = ' ';
      chars[i + 1] = ' ';
      i += 2;
      while (i < n && !(src[i] === '*' && src[i + 1] === '/')) {
        if (src[i] !== '\n') chars[i] = ' ';
        i++;
      }
      if (i < n) {
        chars[i] = ' ';
        chars[i + 1] = ' ';
        i += 2;
      }
      continue;
    }
    if (c === '"' || c === "'" || c === '`') {
      const q = c;
      chars[i] = ' ';
      i++;
      while (i < n) {
        if (src[i] === '\\') {
          chars[i] = ' ';
          if (i + 1 < n && src[i + 1] !== '\n') chars[i + 1] = ' ';
          i += 2;
          continue;
        }
        if (src[i] === q) {
          chars[i] = ' ';
          i++;
          break;
        }
        if (src[i] !== '\n') chars[i] = ' ';
        i++;
      }
      continue;
    }
    i++;
  }
  return chars.join('');
}

/** 从 openParen 位置起，找到与之配对的右括号下标（在掩码串上操作） */
function matchParen(masked, openParen) {
  let depth = 0;
  for (let i = openParen; i < masked.length; i++) {
    const c = masked[i];
    if (c === '(') depth++;
    else if (c === ')') {
      depth--;
      if (depth === 0) return i;
    }
  }
  return -1;
}

/**
 * 找到 `ForEach(a, b, c)` 里**最后一个顶层逗号**的位置。
 *
 * 只数括号层级，**不**特殊处理 `=>`：
 *   · 用「最后一个顶层逗号」定位最后一个实参（= key 生成器）是稳的——
 *     前面的实参无论怎么切分都不影响这个位置；
 *   · 反过来，如果为了正确处理箭头函数体而给 `=>` 也加一层，
 *     反而会让「末位判断」失效（层级永远回不到 0，找不到逗号）。
 *     这正是本脚本第二版踩的坑。
 *
 * 返回 -1 表示没有顶层逗号（即实参不足两个）。
 */
function lastTopLevelComma(masked, from, to) {
  let depth = 0;
  let last = -1;
  for (let i = from; i <= to; i++) {
    const c = masked[i];
    if (c === '(' || c === '{' || c === '[') {
      depth++;
    } else if (c === ')' || c === '}' || c === ']') {
      depth--;
    } else if (c === ',' && depth === 0) {
      last = i;
    }
  }
  return last;
}

/** 从 `ForEach(` 起找到**第一个顶层逗号**（= 数据源与 item 生成器的分界） */
function firstTopLevelComma(masked, from, to) {
  let depth = 0;
  for (let i = from; i <= to; i++) {
    const c = masked[i];
    if (c === '(' || c === '{' || c === '[') depth++;
    else if (c === ')' || c === '}' || c === ']') depth--;
    else if (c === ',' && depth === 0) return i;
  }
  return -1;
}

const files = walk(rootArg);
const rows = [];

for (const file of files) {
  const src = fs.readFileSync(file, 'utf8');
  const masked = mask(src);
  const rel = path.relative(rootArg, file).replace(/\\/g, '/');

  let idx = -1;
  while ((idx = masked.indexOf('ForEach(', idx + 1)) !== -1) {
    // 排除 LazyForEach / Repeat 等前缀误命中：前一个标识符字符必须是分隔符
    const prev = masked[idx - 1];
    if (prev !== undefined && /[A-Za-z0-9_$]/.test(prev)) continue;

    const openParen = idx + 'ForEach'.length;
    const closeParen = matchParen(masked, openParen);
    if (closeParen < 0) continue;

    const line = src.slice(0, idx).split(/\r?\n/).length;

    const argFrom = openParen + 1;
    const argTo = closeParen - 1;
    const firstComma = firstTopLevelComma(masked, argFrom, argTo);
    const lastComma = lastTopLevelComma(masked, argFrom, argTo);
    const argCount = firstComma < 0 ? 1 : (lastComma === firstComma ? 2 : 3);

    // ArkUI 的 ForEach 通常是 3 个实参；只有 2 个时第 3 个（key）缺失
    const hasKey = argCount >= 3;
    // ⚠️ 取文本必须在**原文** `src` 上，不能在掩码串 `masked` 上：
    //    掩码把字符串内容换成了空格，而 key 生成器里恰恰常有字符串拼接，
    //    在掩码串上判断 `this.accentColor` 会全判成「没有」——自检工具自身的假绿。
    const keyText = hasKey ? src.slice(lastComma + 1, closeParen) : '';
    const dataText = src.slice(argFrom, firstComma < 0 ? closeParen : firstComma).trim();

    rows.push({
      file: rel,
      line,
      hasKey,
      dataText,
      keyHasAccent: /this\.accentColor/.test(keyText),
      keyHasSelection: /this\.(picked|selected|active|expanded|is[A-Z])/.test(keyText),
      keyText: keyText.replace(/\s+/g, ' ').trim().slice(0, 90)
    });
  }
}

const total = rows.length;
const noKey = rows.filter((r) => !r.hasKey);
const withKey = rows.filter((r) => r.hasKey);
const keyOk = withKey.filter((r) => r.keyHasAccent);

console.log(`ForEach 调用共 ${total} 处（不含 LazyForEach）`);
console.log(`  · 有 key 生成器：${withKey.length} 处，其中 key 编入了 accentColor：${keyOk.length} 处`);
console.log(`  · 无 key 生成器（仅 2 实参）：${noKey.length} 处`);

if (noKey.length > 0) {
  console.log('\n【无 key 生成器】');
  for (const r of noKey) console.log(`  ${r.file}:${r.line}   数据源=${r.dataText.replace(/\s+/g, ' ')}`);
}

const missing = withKey.filter((r) => !r.keyHasAccent);
if (missing.length > 0) {
  console.log('\n【有 key 但未编入 accentColor】');
  for (const r of missing) console.log(`  ${r.file}:${r.line}   key=${r.keyText}`);
}

if (noKey.length === 0 && missing.length === 0) {
  console.log('\n全部 ForEach 的 key 都已编入 accentColor ✅');
}
