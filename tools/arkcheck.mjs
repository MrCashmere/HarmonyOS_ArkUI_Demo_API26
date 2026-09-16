/**
 * 轻量 ArkTS/TS 结构自检（教学 Demo 自检用，纯静态、无依赖）
 * ============================================================================
 * 为什么需要它：本 Demo 无法在会话内编译（hvigor 需要写工作区外的缓存目录）。
 * 所以用一个可靠的静态检查兜住「结构性错误」这一大类问题：
 *
 *   1. 块注释是否闭合
 *   2. 装饰线是否误用斜杠（`* /` 会**提前结束块注释**，是中文注释里最常见的坑）
 *   3. 字符串是否闭合（单双引号不允许跨行）
 *   4. 括号配平：{} () [] 是否成对
 *   5. 全角标点是否混进了**可执行代码**（注释与字符串里合法）
 *
 * 实现要点：**先对全文做一次状态机扫描**，算出每一行「哪些列区间属于注释/字符串」，
 * 之后的判定全部基于这份掩码 —— 不要逐行猜注释状态（单行 jsdoc、注释内的 `//`
 * 都会让逐行猜测误判）。
 *
 * 用法：node tools/arkcheck.mjs <目录或文件>
 */
import fs from 'node:fs';
import path from 'node:path';

/** 本文件路径（兼容 Windows 盘符） */
const SELF_PATH = new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');

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
 * 单次状态机扫描。
 * 返回按行组织的掩码：commentMask[line] = 该行落入「注释」的字符数（用于判定整行是否注释），
 * 以及 codeOnly[line] = 去掉注释与字符串内容后的文本（供全角标点判定）。
 */
function scan(src) {
  const lines = src.split(/\r?\n/);
  // 每行的字符区间标记：true = 属于注释或字符串（非代码）
  const masked = lines.map((l) => new Array(l.length).fill(false));
  const problems = [];

  let line = 0;
  let col = 0;
  let blockStartLine = -1;
  let blockStartCol = -1;
  let sawBlockComment = false;

  const mark = (l, from, to) => {
    if (l < 0 || l >= masked.length) return;
    for (let c = from; c < to && c < masked[l].length; c++) masked[l][c] = true;
  };

  let i = 0;
  const n = src.length;
  // 逐字符推进，同时维护 line/col
  const advance = () => {
    if (src[i] === '\n') {
      line++;
      col = 0;
    } else {
      col++;
    }
    i++;
  };

  while (i < n) {
    const c = src[i];
    const c2 = src[i + 1];

    // 行注释
    if (c === '/' && c2 === '/') {
      const l = line;
      const from = col;
      let len = 0;
      while (i < n && src[i] !== '\n') {
        advance();
        len++;
      }
      mark(l, from, from + len);
      continue;
    }

    // 块注释
    if (c === '/' && c2 === '*') {
      sawBlockComment = true;
      blockStartLine = line;
      blockStartCol = col;
      advance();
      advance();
      let closed = false;
      while (i < n) {
        if (src[i] === '*' && src[i + 1] === '/') {
          advance();
          advance();
          closed = true;
          break;
        }
        advance();
      }
      // 标记整段注释
      if (closed) {
        for (let l = blockStartLine; l <= line; l++) {
          const from = l === blockStartLine ? blockStartCol : 0;
          const to = l === line ? col : masked[l].length;
          mark(l, from, to);
        }
      } else {
        for (let l = blockStartLine; l < masked.length; l++) mark(l, 0, masked[l].length);
        problems.push(`第 ${blockStartLine + 1} 行开始的块注释**没有闭合**（缺少注释结束符）`);
      }
      continue;
    }

    // 字符串 / 模板串
    if (c === '"' || c === "'" || c === '`') {
      const quote = c;
      const startLine = line;
      const startCol = col;
      advance();
      let closed = false;
      while (i < n) {
        if (src[i] === '\\') {
          advance();
          if (i < n) advance();
          continue;
        }
        if (src[i] === quote) {
          advance();
          closed = true;
          break;
        }
        if (src[i] === '\n' && quote !== '`') break; // 单双引号不允许跨行
        advance();
      }
      if (closed) {
        if (startLine === line) {
          mark(startLine, startCol, col);
        } else {
          mark(startLine, startCol, masked[startLine].length);
          for (let l = startLine + 1; l < line; l++) mark(l, 0, masked[l].length);
          mark(line, 0, col);
        }
      } else {
        problems.push(`第 ${startLine + 1} 行的字符串疑似**没有闭合**（引号未配对）`);
        mark(startLine, startCol, masked[startLine].length);
      }
      continue;
    }

    advance();
  }

  // 生成「仅代码」文本：掩码位置替换为空格，保留其余原字符
  const codeOnly = lines.map((l, idx) =>
    l.split('').map((ch, c) => (masked[idx][c] ? ' ' : ch)).join(''));

  // 判定每一行是否「整行都是注释/空白」
  const commentOnly = lines.map((l, idx) => l.trim().length > 0 && codeOnly[idx].trim().length === 0);

  return { lines, masked, codeOnly, commentOnly, problems, sawBlockComment };
}

/**
 * 检查一段源码，返回问题列表（纯函数，不打印、不退出）。
 *
 * 之所以做成可复用的纯函数：`tools/selftest-arkcheck.mjs` 需要在**同进程内**
 * 对「故意写坏的样本」跑同一套规则。用子进程 + 管道捕获输出在受限沙箱里会直接
 * 失败（`stdio: 'pipe'` 被禁止），所以自测改为直接调用本函数。
 *
 * @param {string} src 文件全文
 * @returns {string[]} 问题描述（空数组 = 通过）
 */
export function checkSource(src) {
  const problems = [];
  const { lines, commentOnly, codeOnly, problems: scanProblems } = scan(src);
  problems.push(...scanProblems);

  // 1) 括号配平（只看代码部分）
  const stack = [];
  const opens = { '{': '}', '(': ')', '[': ']' };
  const closes = { '}': '{', ')': '(', ']': '[' };
  lines.forEach((l, idx) => {
    const code = codeOnly[idx];
    for (let c = 0; c < code.length; c++) {
      const ch = code[c];
      if (opens[ch]) stack.push({ ch, line: idx + 1 });
      else if (closes[ch]) {
        const top = stack.pop();
        if (!top) problems.push(`第 ${idx + 1} 行有多余的 '${ch}'（无匹配的开括号）`);
        else if (top.ch !== closes[ch]) {
          problems.push(`第 ${idx + 1} 行的 '${ch}' 与第 ${top.line} 行的 '${top.ch}' 不匹配`);
        }
      }
    }
  });
  if (stack.length > 0) {
    const t = stack[stack.length - 1];
    problems.push(`第 ${t.line} 行的 '${t.ch}' 未闭合（文件结束仍差 ${stack.length} 个闭合符号）`);
  }

  // 2) 注释里的装饰线：`* /` 会提前结束块注释
  //    合法情况必须排除，否则全是误报：
  //      · `*/`            —— 块注释的结束行本身
  //      · `/** xxx */`    —— 单行 jsdoc
  //      · `* ... // ...`  —— 注释行里出现双斜杠（例如代码示例），不是 `* /`
  lines.forEach((l, idx) => {
    if (!commentOnly[idx]) return;
    const t = l.trim();
    if (t === '*/') return;                      // 块注释结束行
    if (t.startsWith('/**') && t.endsWith('*/')) return; // 单行 jsdoc
    // 只看「星号 + 空格 + 单斜杠」，且该斜杠不是双斜杠的一部分
    const m = /^\*\s*\/(?!\/)/.exec(t);
    if (m && !/\\\*/.test(t)) {
      problems.push(`第 ${idx + 1} 行装饰线误用斜杠（'* /'），会提前结束块注释 → ${t.slice(0, 44)}`);
    }
  });

  // 3) 全角标点混进代码
  lines.forEach((l, idx) => {
    const code = codeOnly[idx];
    if (/[；：，（）【】]/.test(code)) {
      problems.push(`第 ${idx + 1} 行在代码里用了全角标点：${code.trim().slice(0, 60)}`);
    }
  });

  // 4) `this.xxx(` 调用是否都有定义
  //    结构检查抓不到这类错误：「调用了不存在的 builder/方法」在编译期才报，
  //    而在无法编译的环境里它会静默漏过。
  const src2 = codeOnly.join('\n');
  const defined = new Set();
  // 成员声明：`name(`（含 @Builder / 方法）、`name:`（@State/@Prop/属性）、
  // 以及 struct/class 内的字段声明的各种形态
  for (const m of src2.matchAll(/(?:^|\n)\s*(?:@\w+(?:\([^)]*\))?\s*)*(?:private\s+|public\s+|protected\s+|static\s+|readonly\s+)*([A-Za-z_$][\w$]*)\s*[:(]/g)) {
    defined.add(m[1]);
  }
  // `this.x = ...` 形式的赋值也算定义
  for (const m of src2.matchAll(/this\.([A-Za-z_$][\w$]*)\s*=/g)) defined.add(m[1]);
  // 解构/lambda 参数等常见名，避免误报
  for (const m of src2.matchAll(/\b([A-Za-z_$][\w$]*)\s*=>/g)) defined.add(m[1]);
  for (const m of src2.matchAll(/\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)/g)) defined.add(m[1]);
  for (const m of src2.matchAll(/\bfunction\s+([A-Za-z_$][\w$]*)/g)) defined.add(m[1]);
  for (const m of src2.matchAll(/(?:import|export)\s+(?:type\s+)?\{([^}]*)\}/g)) {
    for (const name of m[1].split(',')) {
      const t = name.trim().split(/\s+as\s+/).pop().trim();
      if (t) defined.add(t);
    }
  }
  // 常见内建/局部名白名单，避免噪音
  const whitelist = new Set(['build', 'aboutToAppear', 'aboutToDisappear', 'onPageShow', 'onPageHide',
    'onBackPress', 'constructor', 'toString', 'valueOf', 'then', 'catch', 'finally',
    'map', 'filter', 'forEach', 'find', 'push', 'slice', 'splice', 'concat', 'indexOf',
    'substring', 'charAt', 'toUpperCase', 'toLowerCase', 'trim', 'padStart', 'replace',
    'split', 'join', 'includes', 'startsWith', 'endsWith', 'keys', 'values', 'entries',
    'get', 'set', 'has', 'delete', 'add', 'parseInt', 'parseFloat', 'stringify', 'parse',
    'toFixed', 'round', 'max', 'min', 'abs', 'sort', 'reverse', 'every', 'some', 'reduce']);

  const used = new Set();
  for (const m of src2.matchAll(/this\.([A-Za-z_$][\w$]*)\s*\(/g)) used.add(m[1]);
  for (const name of used) {
    if (whitelist.has(name)) continue;
    if (!defined.has(name)) {
      problems.push(`调用了未定义的成员：this.${name}()（本文件里找不到它的声明）`);
    }
  }

  // 5) `Toggle` / `Slider` 是否漏了 `.onChange`
  //
  //    这是本项目最容易犯、也最难自查的一类错误，**纯结构检查抓不到**：
  //      `Toggle` 的 `isOn` **不是双向绑定**（要 `$$` 才是）。只写
  //      `Toggle({ isOn: this.x })` 而不写 `.onChange`，拨动只会改**组件内部视觉**，
  //      `x` 根本不变 —— 表现为「拨完闪一下又弹回去」，而且不会持久化。
  //      `Slider` 同理（滑块位置由内部维护）。
  //
  //    例外：材质**承载层**用 `isOn: false` 字面量（不是绑定状态变量）+
  //    `enabled(false)`，它刻意不需要 onChange。这里用「isOn 是否为字面量 false」
  //    区分，比判断 `.enabled()` 稳（承载层的 enabled 也可能是变量）。
  for (let idx = 0; idx < lines.length; idx++) {
    // ⚠️ 必须在 `codeOnly` 上匹配，不能扫原始行：注释里常会写到
    //    `Toggle({ isOn: ... })` 这类**示例代码**，扫原文会把注释当成真控件（误报）。
    if (!/\b(?:Toggle|Slider)\s*\(\s*\{/.test(codeOnly[idx])) continue;
    const kind = /\bSlider\s*\(/.test(codeOnly[idx]) ? 'Slider' : 'Toggle';

    // 精确框定这个控件的范围，**不能用固定行数窗口**：
    //   固定窗口会把「下一个 Toggle 的 isOn: false（承载层）」也算进来，
    //   于是上面那个真的漏了 onChange 的 Toggle 会被例外规则放过（假绿）。
    // 规则：参数括号还没闭合，或**跳过空行/纯注释行后**的下一行以 `.` 开头（属性链），
    //       就继续收集。
    // ⚠️ 必须跳过注释行：属性链中间常插一行 `// ⚠️ 不写这一行…` 的说明，
    //    直接在注释行处收尾会让后面真正的 `.onChange(...)` 落在范围外（假阳性）。
    let depth = 0;
    let block = '';
    for (let j = idx; j < lines.length; j++) {
      block += lines[j] + '\n';
      for (const ch of codeOnly[j]) {
        if (ch === '(' || ch === '{' || ch === '[') depth++;
        else if (ch === ')' || ch === '}' || ch === ']') depth--;
      }
      let k = j + 1;
      while (k < lines.length && codeOnly[k].trim() === '') k++;
      const next = k < lines.length ? codeOnly[k].trim() : '';
      if (depth <= 0 && !next.startsWith('.')) break;
    }

    if (kind === 'Toggle' && /isOn\s*:\s*false\b/.test(block)) continue; // 承载层
    if (/\.onChange\s*\(/.test(block)) continue;
    problems.push(`第 ${idx + 1} 行的 ${kind} 缺少 \`.onChange\`：`
      + `${kind === 'Toggle' ? 'isOn' : 'value'} 不是双向绑定，拨动不会写回状态变量`);
  }

  // 6) 声明后从未读取的字段（死代码）—— **按 struct/class 作用域**统计
  //
  //    典型是复制粘贴留下的 `@Prop glowTouch`、或加了参数却忘了用。
  //    判据：在**该字段所属的 struct/class 体内**，`this.<name>` 出现 0 次。
  //
  //    ⚠️ 为什么必须按作用域、不能按整文件统计（这是第 5 次踩到的坑）：
  //       同一个字段名会出现在**多个** struct 里 —— 本工程就有三个 struct 各自声明
  //       `@StorageProp('accentColor') accentColor`。按整文件数 `this.accentColor`
  //       时，A 里的读取会把 B 里那个**从未被读的死字段**一并洗白。
  //       真实的漏报就是这么发生的：`ThemedCard.accentColor` 曾被
  //       `DemoScaffold` / `SwitchRow` 的同名读取掩盖，整文件计数全绿。
  //
  //    取值来源仍旧分开（见上一版的教训）：
  //      · **声明**只能在 `codeOnly`（只含代码）里找 —— 否则**注释里**写出的示例
  //        `@Prop c: string = HwColor.primary` 会被当成真声明，
  //        再因为没人读它而误报成死代码（文档注释里引用写法太常见了）。
  //      · **读取**必须在**原文** `src` 里数 —— 模板字符串
  //        `` `${this.pressGlowSwitch ? '开' : '关'}` `` 里是真读取，
  //        但它会被掩码清空，用 codeOnly 数会误判成死代码。
  //        `codeOnly` 与原文字符位置逐一对齐（掩码是等长替换），
  //        所以作用域区间可以直接套用到原文上。
  const codeText = codeOnly.join('\n');
  const rawText = src.split(/\r?\n/).join('\n');

  /** 每个行首在 codeText 里的偏移，用来把下标换回行号 */
  const lineStarts = [0];
  for (let i = 0; i < codeText.length; i++) {
    if (codeText[i] === '\n') lineStarts.push(i + 1);
  }
  const lineOf = (idx) => {
    let lo = 0;
    let hi = lineStarts.length - 1;
    while (lo < hi) {
      const mid = (lo + hi + 1) >> 1;
      if (lineStarts[mid] <= idx) lo = mid;
      else hi = mid - 1;
    }
    return lo + 1;
  };
  /** 从 `{` 的下标出发，返回配对 `}` 的下标（括号已配平，故不会越界） */
  const matchBrace = (from) => {
    let depth = 0;
    for (let i = from; i < codeText.length; i++) {
      if (codeText[i] === '{') depth++;
      else if (codeText[i] === '}') {
        depth--;
        if (depth === 0) return i;
      }
    }
    return -1;
  };

  const scopes = [];
  for (const m of codeText.matchAll(/\b(?:export\s+)?(?:struct|class)\s+([A-Za-z_$][\w$]*)[^{]*\{/g)) {
    const open = m.index + m[0].length - 1; // m[0] 以 `{` 结尾
    const close = matchBrace(open);
    if (close > open) scopes.push({ name: m[1], start: open, end: close });
  }
  // 嵌套的 struct/class 会被外层的区间整个包住，导致同一字段被统计两次；
  // 只保留最外层作用域。
  const outerScopes = scopes.filter(
    (s) => !scopes.some((o) => o !== s && o.start < s.start && s.end < o.end));

  for (const sc of outerScopes) {
    const bodyCode = codeText.slice(sc.start, sc.end);
    const bodyRaw = rawText.slice(sc.start, sc.end);
    for (const m of bodyCode.matchAll(
      /@(?:Prop|Link|State|StorageProp|StorageLink|ObjectLink|Provide|Consume|BuilderParam)(?:\([^)]*\))?\s+([A-Za-z_$][\w$]*)/g)) {
      const name = m[1];
      const reads = (bodyRaw.match(new RegExp(`this\\.${name}\\b`, 'g')) ?? []).length;
      if (reads === 0) {
        const line = lineOf(sc.start + m.index);
        problems.push(
          `第 ${line} 行 ${sc.name} 里声明的字段 ${name} 在该 struct/class 内从未被读取`
          + `（this.${name} 0 次），疑似死代码`);
      }
    }
  }

  return problems;
}

// ============================================================================
// CLI 入口（被 import 时不执行）
// ============================================================================
function main() {
  const target = process.argv[2];
  if (!target) {
    console.error('用法: node tools/arkcheck.mjs <目录或文件>');
    process.exit(2);
  }

  let totalProblems = 0;
  const files = walk(target);

  for (const f of files) {
    const src = fs.readFileSync(f, 'utf8');
    const rel = path.relative('.', f).replace(/\\/g, '/');
    const problems = checkSource(src);

    if (problems.length > 0) {
      totalProblems += problems.length;
      console.log(`\n✗ ${rel}`);
      for (const p of problems) console.log(`    · ${p}`);
    } else {
      console.log(`✓ ${rel}`);
    }
  }

  console.log(`\n扫描 ${files.length} 个文件，发现 ${totalProblems} 个结构问题`);
  process.exit(totalProblems > 0 ? 1 : 0);
}

// 仅当作为脚本直接运行时才执行 CLI；
// 被 selftest 以模块方式 import 时（此时 process.argv[1] 是 selftest 自己）跳过。
const invokedDirectly =
  process.argv[1] && path.resolve(process.argv[1]) === path.resolve(SELF_PATH);
if (invokedDirectly) {
  main();
}

