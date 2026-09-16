#!/usr/bin/env node
/**
 * arkcheck 自测（双向反测）
 * ============================================================================
 * 只跑「工程全绿」不足以说明规则有效 —— 一条**永远不报错**的规则看起来也是全绿。
 * 所以这里同时验证两个方向：
 *
 *   bad/  —— 故意写坏的样本，规则**必须**报出问题（否则是漏报）
 *   good/ —— 写法正确的样本，规则**必须**不报问题（否则是误报）
 *
 * 实现说明：直接 import `arkcheck.mjs` 导出的 `checkSource()` 在**同进程内**判定，
 * 不用子进程捕获输出 —— 受限沙箱禁止 `stdio: 'pipe'`，spawnSync 会静默返回 null，
 * 那样自测会「看起来在跑、其实什么都没测」。
 *
 * 用法：node tools/selftest-arkcheck.mjs
 * 退出码：0 表示两个方向都符合预期。
 */

import fs from 'node:fs';
import path from 'node:path';
import { checkSource } from './arkcheck.mjs';

const here = path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'));
const badDir = path.join(here, 'selftest', 'bad');
const goodDir = path.join(here, 'selftest', 'good');

function listEts(dir) {
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir).filter((n) => n.endsWith('.ets'));
}

let failures = 0;

// ---- 方向一：坏样本必须被报出 ----
const badFiles = listEts(badDir);
if (badFiles.length === 0) {
  console.log('✗ bad/ 下没有样本，反测等于没做');
  failures++;
}
for (const name of badFiles) {
  const src = fs.readFileSync(path.join(badDir, name), 'utf8');
  const problems = checkSource(src);
  if (problems.length > 0) {
    console.log(`✓ 漏报检验：bad/${name} 被报出 ${problems.length} 条`);
    for (const p of problems) console.log(`      · ${p}`);
  } else {
    console.log(`✗ 漏报检验失败：bad/${name} **没有被报出**（规则存在假绿）`);
    failures++;
  }
}

// ---- 方向二：好样本必须零问题 ----
const goodFiles = listEts(goodDir);
if (goodFiles.length === 0) {
  console.log('✗ good/ 下没有样本，误报检验等于没做');
  failures++;
}
for (const name of goodFiles) {
  const src = fs.readFileSync(path.join(goodDir, name), 'utf8');
  const problems = checkSource(src);
  if (problems.length === 0) {
    console.log(`✓ 误报检验：good/${name} 全绿`);
  } else {
    console.log(`✗ 误报检验失败：good/${name} 本不该报错，却报了：`);
    for (const p of problems) console.log(`      · ${p}`);
    failures++;
  }
}

// ---- 汇总 ----
if (failures === 0) {
  console.log(`\n双向反测通过：${badFiles.length} 个坏样本全部报出，`
    + `${goodFiles.length} 个好样本全部放行 ✅`);
  process.exit(0);
}
console.log(`\n✗ 双向反测有 ${failures} 项不符合预期`
  + `（坏样本 ${badFiles.length} 个 / 好样本 ${goodFiles.length} 个）`);
process.exit(1);
