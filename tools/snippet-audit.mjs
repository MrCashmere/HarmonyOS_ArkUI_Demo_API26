#!/usr/bin/env node
/**
 * 源码片段审计（只读）
 * ============================================================================
 * 校验 `teaching/SourceSnippets.ets` 里的每个代码块，其「非注释行」
 * 是否真的能在工程里逐字找到（即：不是凭印象编的、也不是改写过的）。
 *
 * 约定（与 SourceSnippets.ets 头部一致）：
 *   · 以 `//` 开头的行视为**教学引导注释**，允许自由编写，不参与比对；
 *   · 空行、单独的 `}`/`})` 等结构性收尾行太普遍，也不参与比对。
 *
 * 用法：node tools/snippet-audit.mjs entry/src/main/ets
 */

import fs from 'node:fs';
import path from 'node:path';

const etsRoot = path.resolve(process.argv[2] ?? 'entry/src/main/ets');
const snippetsFile = path.join(etsRoot, 'teaching', 'SourceSnippets.ets');

if (!fs.existsSync(snippetsFile)) {
  console.error(`✗ 找不到 ${snippetsFile}`);
  process.exit(1);
}
const src = fs.readFileSync(snippetsFile, 'utf8');

/** 1. 抽出所有常量：代码块是模板字符串，来源是普通单引号字符串 */
const blocks = [];
let m;
const tplRe = /export const (\w+): string = `([\s\S]*?)`;/g;
while ((m = tplRe.exec(src)) !== null) {
  blocks.push({ name: m[1], raw: m[2], quoted: false });
}
const strRe = /export const (\w+): string = '([^']*)';/g;
while ((m = strRe.exec(src)) !== null) {
  blocks.push({ name: m[1], raw: m[2], quoted: true });
}

/** 2. 反转义模板字符串里的转义序列 */
function unescapeTpl(s) {
  return s
    .replace(/\\`/g, '`')
    .replace(/\\\$\{/g, '${')
    .replace(/\\n/g, '\n')
    .replace(/\\\\/g, '\\');
}

/** 3. 收集工程内所有 .ets 文本（排除片段文件自身） */
function walk(dir, out) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) {
      walk(p, out);
    } else if (e.name.endsWith('.ets')) {
      out.push(p);
    }
  }
}
const allFiles = [];
walk(etsRoot, allFiles);

const corpus = allFiles
  .filter((f) => path.resolve(f) !== snippetsFile)
  .map((f) => ({ file: path.relative(etsRoot, f).replace(/\\/g, '/'), text: fs.readFileSync(f, 'utf8') }));

/** 4. 逐行比对 */
const SOURCE_SUFFIX = '_SOURCE';
const codeBlocks = blocks.filter((b) => !b.name.endsWith(SOURCE_SUFFIX) && !b.quoted);
const problems = [];
let checked = 0;
let skipped = 0;

for (const b of codeBlocks) {
  const lines = unescapeTpl(b.raw).split('\n');
  lines.forEach((line, idx) => {
    const t = line.trim();
    if (t.length === 0 || t.startsWith('//') || /^[)}\]\};,]*$/.test(t)) {
      skipped++;
      return;
    }
    checked++;
    const hit = corpus.find((c) => c.text.includes(t));
    if (!hit) {
      problems.push({ snippet: b.name, line: idx + 1, text: t });
    }
  });
}

/** 5. 每个片段都必须有配对的 `_SOURCE` 常量 */
const names = new Set(blocks.filter((b) => b.quoted).map((b) => b.name));
const missingSource = codeBlocks
  .filter((b) => !names.has(b.name + SOURCE_SUFFIX))
  .map((b) => b.name);

/** 6. 报告 */
console.log(`— 源码片段审计：${codeBlocks.length} 段代码块 / ${blocks.length - codeBlocks.length} 个来源常量 —`);
console.log(`  比对 ${checked} 行，跳过 ${skipped} 行（注释 / 空行 / 结构收尾）`);

if (missingSource.length > 0) {
  console.log(`\n✗ 缺少配对的 _SOURCE 常量：`);
  for (const n of missingSource) console.log(`   · ${n} 需要 ${n}${SOURCE_SUFFIX}`);
}

if (problems.length === 0) {
  console.log('\n全部片段的代码行都能在工程里逐字找到 ✅');
  if (missingSource.length > 0) process.exit(1);
  process.exit(0);
}

console.log(`\n✗ 有 ${problems.length} 行在工程里找不到（可能是改写或凭印象写的）：`);
let current = '';
for (const p of problems) {
  if (p.snippet !== current) {
    current = p.snippet;
    console.log(`\n  ${current}:`);
  }
  console.log(`     第 ${p.line} 行 | ${p.text}`);
}
process.exit(1);
