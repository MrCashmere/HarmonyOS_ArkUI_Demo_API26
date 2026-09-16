/**
 * 跨文件「导出 / 导入」一致性检查（教学 Demo 自检用）
 * ============================================================================
 * 补 arkcheck.mjs 的盲区：结构检查只看单个文件内部，
 * **抓不到**「从错误的模块导入了不存在的符号」——例如
 * `materialDiagnostics` 实际定义在 SystemMaterial.ets，
 * 却写进了 DesignTokens 的 import 列表里。这类错误只有编译期才报。
 *
 * 检查内容：
 *   ① 每个 import 的符号，在源模块里是否**真的有导出**；
 *   ② 每个 import 的符号，在本文件里是否**真的被用到**（未使用告警，不致命）；
 *   ③ 相对路径能否解析到真实文件。
 *
 * ────────────────────────────────────────────────────────────────────────────
 * 实现上踩过的四个坑（留在这里，避免重犯）
 * ────────────────────────────────────────────────────────────────────────────
 *   坑 1｜关键字正则前**不能**加 `\b`：行首的 `import` / `export` 左边没有单词字符，
 *        `\b` 不成立 → 整条语句被跳过 → **静默全绿**（最危险的「通过」）。
 *   坑 2｜清理字符串时**必须保留** `from '...'` 里的模块路径，
 *        否则 import 正则再也匹配不到任何东西。
 *   坑 3｜清理必须是**原位等长**（把字符换成空格），不能拼接新字符串：
 *        模板串里含换行，抽掉内容会让行列错位，后续位置判定全部失准。
 *   坑 4｜**不能「边扫描边把占位符写回同一个缓冲区」**：
 *        占位符本身会被后续扫描重新扫到，且 `precededByFrom()` 会把
 *        占位符里的 `from` 误当作关键字。正确做法是：
 *        扫描时只**记录**「哪些位置是字符串、哪些字符串是模块路径」，
 *        扫描结束后再统一替换。
 *
 * 用法：node tools/importcheck.mjs <ets 源码目录>
 */
import fs from 'node:fs';
import path from 'node:path';

const rootArg = process.argv[2] || '.';

function walk(p, out = []) {
  const st = fs.statSync(p);
  if (st.isDirectory()) {
    for (const e of fs.readdirSync(p, { withFileTypes: true })) walk(path.join(p, e.name), out);
  } else if (p.endsWith('.ets') || p.endsWith('.ts') || p.endsWith('.mjs')) {
    out.push(p);
  }
  return out;
}

/**
 * 生成「掩码后的源码」与「收集到的模块路径」。
 *
 * 分两趟：
 *   第一趟只扫描并记录（不改动缓冲区）—— `inString[i]` 标记第 i 个字符是否属于字符串，
 *   同时把 `from` 后面的字符串内容收进 `specs`；
 *   第二趟按记录统一替换：字符串内容 → 空格；模块路径 → 占位符 `\x00Sn\x00`。
 *
 * @returns {{ masked: string, specs: string[] }}
 */
function maskCode(input) {
  // 去掉 UTF-8 BOM：Windows 上不少工具写文件会带上它，留在行首会让关键字匹配偏移一位
  const src = input.charCodeAt(0) === 0xFEFF ? input.slice(1) : input;
  const n = src.length;
  const inString = new Array(n).fill(false);
  /** 模块路径字符串的区间与内容 */
  const specRanges = [];
  let i = 0;

  /** 在**只认代码**的视角下，某位置之前（跳过空白）是否紧跟 `from` */
  const precededByFrom = (pos) => {
    let j = pos - 1;
    while (j >= 0 && (/\s/.test(src[j]) || inString[j])) j--;
    return j >= 3 && src.slice(j - 3, j + 1) === 'from' && !inString[j];
  };

  while (i < n) {
    const c = src[i];
    const c2 = src[i + 1];

    // 行注释
    if (c === '/' && c2 === '/') {
      while (i < n && src[i] !== '\n') {
        inString[i] = true; // 复用同一个掩码：注释与字符串都要被清掉
        i++;
      }
      continue;
    }

    // 块注释
    if (c === '/' && c2 === '*') {
      inString[i] = true;
      inString[i + 1] = true;
      i += 2;
      while (i < n && !(src[i] === '*' && src[i + 1] === '/')) {
        if (src[i] !== '\n') inString[i] = true;
        i++;
      }
      if (i < n) {
        inString[i] = true;
        inString[i + 1] = true;
        i += 2;
      }
      continue;
    }

    // 字符串 / 模板串
    if (c === '"' || c === "'" || c === '`') {
      const q = c;
      const keep = q !== '`' && precededByFrom(i);
      const start = i;
      inString[i] = true;
      i++;
      let closed = false;
      while (i < n) {
        if (src[i] === '\\') {
          inString[i] = true;
          if (i + 1 < n && src[i + 1] !== '\n') inString[i + 1] = true;
          i += 2;
          continue;
        }
        if (src[i] === q) {
          inString[i] = true;
          i++;
          closed = true;
          break;
        }
        if (src[i] !== '\n') inString[i] = true;
        i++;
      }
      if (keep && closed) {
        specRanges.push({ start: start + 1, end: i - 1, value: src.slice(start + 1, i - 1) });
      }
      continue;
    }

    i++;
  }

  // 第二趟：统一替换
  const chars = src.split('');
  for (let k = 0; k < n; k++) {
    if (inString[k] && src[k] !== '\n') chars[k] = ' ';
  }
  const specs = [];
  for (const r of specRanges) {
    const token = `\x00S${specs.length}\x00`;
    specs.push(r.value);
    for (let k = 0; k < token.length && r.start + k < r.end; k++) {
      chars[r.start + k] = token[k];
    }
  }
  return { masked: chars.join(''), specs };
}

/** 收集一个模块导出的符号名 */
function exportedSymbols(file) {
  const { masked } = maskCode(fs.readFileSync(file, 'utf8'));
  const names = new Set();

  // 注意：不能在 `export` 前加 `\b`（见文件头「坑 1」）。
  // `export` 后面已要求空白，足以避免匹配到 `exported` 这类标识符。
  const declRe = /export\s+(?:declare\s+)?(?:async\s+)?(?:function|const|let|var|class|interface|type|enum|struct)\s+([A-Za-z_$][\w$]*)/g;
  for (const m of masked.matchAll(declRe)) {
    names.add(m[1]);
  }
  for (const m of masked.matchAll(/export\s*\{([^}]*)\}/g)) {
    for (const part of m[1].split(',')) {
      const t = part.trim();
      if (!t) continue;
      const alias = t.split(/\s+as\s+/);
      names.add((alias[1] ?? alias[0]).trim());
    }
  }
  if (/export\s+default\b/.test(masked)) names.add('default');
  return names;
}

const files = walk(rootArg);
const cache = new Map();
function exportsOf(file) {
  if (!cache.has(file)) cache.set(file, exportedSymbols(file));
  return cache.get(file);
}

const problems = [];
const warnings = [];

for (const file of files) {
  const raw = fs.readFileSync(file, 'utf8');
  const { masked, specs } = maskCode(raw);
  const dir = path.dirname(file);
  const rel = path.relative(rootArg, file).replace(/\\/g, '/');

  const importRe = /import\s+([\s\S]*?)\s+from\s+\x00S(\d+)\x00/g;
  for (const m of masked.matchAll(importRe)) {
    const clause = m[1].trim();
    const spec = specs[Number(m[2])];

    // 只检查相对路径（@kit.* 等系统模块无法静态解析）
    if (!spec.startsWith('.')) continue;

    const resolvedBase = path.resolve(dir, spec);
    let resolved = null;
    const candidates = [`${resolvedBase}.ets`, `${resolvedBase}.ts`, `${resolvedBase}.mjs`,
      path.join(resolvedBase, 'index.ets')];
    for (const cand of candidates) {
      if (fs.existsSync(cand)) {
        resolved = cand;
        break;
      }
    }
    if (resolved === null) {
      problems.push(`${rel} → import '${spec}' 无法解析到文件`);
      continue;
    }

    const exported = exportsOf(resolved);

    // 解析 clause：具名 / 默认 / 命名空间
    const named = [];
    let hasDefault = false;
    let skip = false;
    const braceMatch = /\{([\s\S]*)\}/.exec(clause);
    if (braceMatch) {
      for (const part of braceMatch[1].split(',')) {
        const t = part.trim();
        if (!t) continue;
        const clean = t.replace(/^type\s+/, '');
        const alias = clean.split(/\s+as\s+/);
        named.push({ imported: alias[0].trim(), local: (alias[1] ?? alias[0]).trim() });
      }
      const before = clause.slice(0, braceMatch.index).replace(/,\s*$/, '').trim();
      if (before.length > 0 && !before.startsWith('*')) hasDefault = true;
    } else if (clause.startsWith('*')) {
      skip = true; // 命名空间导入，跳过符号校验
    } else {
      hasDefault = true;
    }
    if (skip) continue;

    if (hasDefault && !exported.has('default')) {
      problems.push(`${rel} → 从 '${spec}' 导入了 default，但该模块没有 export default`);
    }

    for (const { imported, local } of named) {
      if (!exported.has(imported)) {
        problems.push(`${rel} → 从 '${spec}' 导入了 { ${imported} }，但该模块没有导出这个符号`);
        continue;
      }
      // 使用检查分两段看，避免误报：
      //   ① 掩码后（只含代码）出现次数 > 1 → 除了 import 那一处还有别处，用到了；
      //   ② 掩码后只剩 1 处时，**再看未掩码的原文**（把 import 语句本体换成等长空格）：
      //      模板串 `${...}` 里的调用是**真代码**，但会被掩码成空格，
      //      只看掩码就会把「只在模板串里用过」误判成「从未使用」。
      const esc = local.replace(/[$]/g, '\\$');
      const inCode = (masked.match(new RegExp(`\\b${esc}\\b`, 'g')) ?? []).length;
      if (inCode > 1) continue;
      const body = raw.replace(m[0], ' '.repeat(m[0].length));
      if (new RegExp(`\\b${esc}\\b`).test(body)) continue;
      warnings.push(`${rel} → 导入了 { ${local} } 但从未使用`);
    }
  }
}

// ────────────────────────────────────────────────────────────────────────────
// 附加检查：「用了但没导入」——本文件最初**漏掉的方向**
// ────────────────────────────────────────────────────────────────────────────
// 上面的规则只查「导入的符号是否真的被导出」，查不到反方向的错误：
// 符号在**别的文件**里定义并导出，本文件直接拿来用，却忘了 import。
//
// 这正是真实编译报错 `Cannot find name 'CardSurface'`（Demo 里犯过 3 次：
// CardSurface / immersiveCardsActive / PRESS_GLOW_STORAGE）的成因，
// 而当时这套自检**全绿**——因为它压根没朝这个方向看。
//
// 判定方式：把「项目内所有导出符号名」当候选集，再看每个文件里用到候选名时，
// 是否在本文件**声明过**或**导入过**。ArkUI 内建名（Text/Column/…）
// 不在项目导出集里，所以不会误报。
const exportOwners = new Map(); // 符号名 -> 定义它的文件
for (const f of files) {
  for (const name of exportsOf(f)) {
    if (name === 'default') continue;
    if (!exportOwners.has(name)) exportOwners.set(name, f);
  }
}

/** 收集本文件里「声明过或导入过」的全部本地名 */
function localNames(masked) {
  const names = new Set();
  const declRe = /(?:^|[\s;{}])(?:export\s+)?(?:declare\s+)?(?:async\s+)?(?:function|const|let|var|class|interface|type|enum|struct)\s+([A-Za-z_$][\w$]*)/g;
  for (const m of masked.matchAll(declRe)) names.add(m[1]);

  // 解构声明：`const { a, b } = ...` / `const [x, y] = ...`
  for (const m of masked.matchAll(/(?:const|let|var)\s*\{([^}]*)\}/g)) {
    for (const part of m[1].split(',')) {
      const t = part.trim().split(':')[0].split('=')[0].trim();
      if (t) names.add(t);
    }
  }
  for (const m of masked.matchAll(/(?:const|let|var)\s*\[([^\]]*)\]/g)) {
    for (const part of m[1].split(',')) {
      const t = part.trim().split('=')[0].trim();
      if (t) names.add(t);
    }
  }

  // 导入产生的本地名（含默认导入与命名空间导入）
  for (const m of masked.matchAll(/import\s+([\s\S]*?)\s+from\s+\x00S\d+\x00/g)) {
    const clause = m[1];
    const brace = /\{([\s\S]*)\}/.exec(clause);
    if (brace) {
      for (const part of brace[1].split(',')) {
        const t = part.trim().replace(/^type\s+/, '');
        if (!t) continue;
        const alias = t.split(/\s+as\s+/);
        names.add((alias[1] ?? alias[0]).trim());
      }
    }
    const before = (brace ? clause.slice(0, brace.index) : clause).replace(/,\s*$/, '').trim();
    if (before) {
      if (before.startsWith('*')) {
        const ns = before.split(/\s+as\s+/)[1];
        if (ns) names.add(ns.trim());
      } else {
        names.add(before.split(/\s+as\s+/).pop().trim());
      }
    }
  }
  return names;
}

/**
 * 找出所有模板串 `${...}` **内部**的区间。
 *
 * 为什么要单独做这件事：掩码阶段把整个模板串（含 `${...}`）都当成字符串清掉了，
 * 于是只在模板串里出现的调用（`Text(\`…${immersiveCardsActive()}\`)`）在掩码文本里
 * 彻底消失 —— 「用了但没 import」这一条就会漏报（实测漏掉过 immersiveCardsActive）。
 * 这里把插值内部的**真代码**区间找出来，还原回掩码文本再扫。
 */
function templateInterpRanges(src) {
  const ranges = [];
  const n = src.length;
  let i = 0;
  while (i < n) {
    const c = src[i];
    if (c === '/' && src[i + 1] === '/') {
      while (i < n && src[i] !== '\n') i++;
      continue;
    }
    if (c === '/' && src[i + 1] === '*') {
      i += 2;
      while (i < n && !(src[i] === '*' && src[i + 1] === '/')) i++;
      i += 2;
      continue;
    }
    if (c === '"' || c === "'") {
      const q = c;
      i++;
      while (i < n && src[i] !== q) {
        if (src[i] === '\\') i++;
        i++;
      }
      i++;
      continue;
    }
    if (c === '`') {
      i++;
      while (i < n) {
        if (src[i] === '\\') { i += 2; continue; }
        if (src[i] === '`') { i++; break; }
        if (src[i] === '$' && src[i + 1] === '{') {
          const start = i + 2;
          let depth = 1;
          let j = start;
          while (j < n && depth > 0) {
            const d = src[j];
            if (d === '"' || d === "'" || d === '`') {
              const q2 = d;
              j++;
              while (j < n && src[j] !== q2) {
                if (src[j] === '\\') j++;
                j++;
              }
              j++;
              continue;
            }
            if (d === '{') depth++;
            else if (d === '}') { depth--; if (depth === 0) break; }
            j++;
          }
          ranges.push({ start, end: j });
          i = j + 1;
          continue;
        }
        i++;
      }
      continue;
    }
    i++;
  }
  return ranges;
}

/** 掩码文本 + 还原模板串插值内的真代码 */
function codeWithInterpolations(raw, masked) {
  const src = raw.charCodeAt(0) === 0xFEFF ? raw.slice(1) : raw;
  if (masked.length !== src.length) return masked; // 长度必须一致，否则不还原（安全兜底）
  let out = masked;
  for (const r of templateInterpRanges(src)) {
    out = out.slice(0, r.start) + src.slice(r.start, r.end) + out.slice(r.end);
  }
  return out;
}

for (const file of files) {
  const raw = fs.readFileSync(file, 'utf8');
  const { masked } = maskCode(raw);
  const rel = path.relative(rootArg, file).replace(/\\/g, '/');
  const local = localNames(masked);
  const scan = codeWithInterpolations(raw, masked);
  const seen = new Set();
  for (const m of scan.matchAll(/\b([A-Za-z_$][\w$]*)\b/g)) {
    const name = m[1];
    if (seen.has(name)) continue;
    seen.add(name);
    if (!exportOwners.has(name)) continue;               // 不是项目内符号
    if (exportOwners.get(name) === file) continue;       // 本文件就是定义处
    if (local.has(name)) continue;                       // 本文件声明/导入过
    problems.push(`${rel} → 使用了 ${name}（定义在 `
      + `${path.relative(rootArg, exportOwners.get(name)).replace(/\\/g, '/')}），但本文件没有 import`);
  }
}

console.log(`— 跨文件导入检查：${files.length} 个文件 —`);
if (warnings.length > 0) {
  console.log(`\n未使用导入（${warnings.length} 条，不致命，建议清理）：`);
  for (const w of warnings) console.log(`  · ${w}`);
}
if (problems.length === 0) {
  console.log('\n全部通过 ✅');
  process.exit(0);
}
console.log(`\n发现 ${problems.length} 个问题：`);
for (const p of problems) console.log(`  ✗ ${p}`);
process.exit(1);
