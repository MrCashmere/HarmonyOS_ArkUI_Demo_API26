/**
 * CLink UI 统计（只读扫描，用于生成 UI-INDEX.md 里的数字）
 * ============================================================================
 * 为什么要有这个脚本：**手算的统计会错**。
 * 本文档第一版里的「27 个 UI 文件 / components=10」就是手工数出来的，
 * 实际是 25 个（components=8 / pages=12 / view=5）——
 * 多出来的 2 个其实是被错记进 components 的两个 utils 文件。
 *
 * 所以所有对外公布的数字都由本脚本产出，任何人可复现：
 *
 *    node tools/ui-stats.mjs <CLink 的 entry/src/main/ets 目录>
 *
 * == 判定口径（写清楚，避免再次各说各话）==
 *   · 「UI 文件」= components/ + pages/ + view/ 下声明了
 *     @Component / @Entry / @CustomDialog 的 .ets 文件。
 *   · 「行数」= 按 \n 切分后的行数（**含空行**），与编辑器状态栏一致。
 *   · 通过整棵树扫描（而不是只看某几个约定目录）反查是否有 UI 代码漏在别处。
 */
import fs from 'node:fs';
import path from 'node:path';

const root = process.argv[2];
if (!root) {
  console.error('用法: node tools/ui-stats.mjs <CLink 的 entry/src/main/ets 目录>');
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

const files = walk(root);
const info = files.map((f) => {
  const text = fs.readFileSync(f, 'utf8');
  const rel = path.relative(root, f).replace(/\\/g, '/');
  return {
    f,
    rel,
    dir: rel.includes('/') ? rel.split('/')[0] : '(root)',
    lines: text.split('\n').length,
    text,
    isUi: /@Component|@Entry|@CustomDialog/.test(text)
  };
});

const count = (text, re) => (text.match(re) ?? []).length;
const sum = (arr, fn) => arr.reduce((a, b) => a + fn(b), 0);

console.log('='.repeat(72));
console.log('① UI 文件清单（整树扫描 @Component / @Entry / @CustomDialog）');
console.log('='.repeat(72));
const ui = info.filter((x) => x.isUi);
for (const dir of ['components', 'pages', 'view']) {
  const g = ui.filter((x) => x.dir === dir).sort((a, b) => a.rel.localeCompare(b.rel));
  console.log(`\n[${dir}]  ${g.length} 个文件 / ${sum(g, (x) => x.lines)} 行`);
  for (const x of g) console.log(`   ${String(x.lines).padStart(5)} 行  ${x.rel}`);
}
console.log(`\nUI 文件合计：${ui.length} 个 / ${sum(ui, (x) => x.lines)} 行`);
const uiDirs = [...new Set(ui.map((x) => x.dir))];
console.log(`UI 文件所在目录：${uiDirs.join(', ')}`);

console.log('\n' + '='.repeat(72));
console.log('② 主题/材质工具层');
console.log('='.repeat(72));
for (const x of info.filter((i) => i.dir === 'utils').sort((a, b) => a.rel.localeCompare(b.rel))) {
  console.log(`   ${String(x.lines).padStart(5)} 行  ${x.rel}`);
}
console.log(`\n（UI 文件 + 上述工具层 = ${ui.length + info.filter((i) => i.dir === 'utils').length} 个文件 / `
  + `${sum(ui, (x) => x.lines) + sum(info.filter((i) => i.dir === 'utils'), (x) => x.lines)} 行）`);

console.log('\n' + '='.repeat(72));
console.log('③ 整棵树里「含 UI 调用但不是 UI 组件文件」的文件（容易漏掉的部分）');
console.log('='.repeat(72));
const UI_APIS = ['promptAction', 'showToast', 'systemMaterial', 'uiMaterial', 'HwColor',
  'withAlpha', 'mixHex', 'AlertDialog', 'bindSheet'];
for (const x of info) {
  if (x.isUi) continue;
  if (['components', 'pages', 'view'].includes(x.dir)) continue;
  const hit = UI_APIS.filter((p) => x.text.includes(p));
  if (hit.length === 0) continue;
  console.log(`   ${String(x.lines).padStart(5)} 行  ${x.rel}`);
  console.log(`          用到：${hit.join(', ')}`);
}

console.log('\n' + '='.repeat(72));
console.log('④ 主题色接线点');
console.log('='.repeat(72));
const row = (label, re) => {
  const per = ui.map((x) => count(x.text, re)).filter((n) => n > 0);
  console.log(`   ${label.padEnd(34)} ${String(sum(ui, (x) => count(x.text, re))).padStart(4)} 处`
    + `   分布在 ${per.length} 个 UI 文件`);
};
row('@StorageProp/Link(accentColor)', /@(?:StorageProp|StorageLink)\('accentColor'\)/g);
row('AccentColorSentinel()', /AccentColorSentinel\s*\(\s*\)/g);
row('ForEach(', /\bForEach\s*\(/g);
row('LazyForEach(', /\bLazyForEach\s*\(/g);
row('resolvePrimaryColor', /\bresolvePrimaryColor\s*\(/g);
row('resolvePrimaryButtonColor', /\bresolvePrimaryButtonColor\s*\(/g);
row('resolveGlassBorderColor', /\bresolveGlassBorderColor\s*\(/g);
row('resolvePageBackground', /\bresolvePageBackground\s*\(/g);
row('onAccentColor', /\bonAccentColor\s*\(/g);
row('withAlpha', /\bwithAlpha\s*\(/g);
row('mixHex', /\bmixHex\s*\(/g);
row('topBarGlassColor', /\btopBarGlassColor\s*\(/g);
row('pressLightColor', /\bpressLightColor\s*\(/g);
row('selectedColor（控件选中色）', /\.selectedColor\s*\(/g);
row('caretColor（输入光标）', /\.caretColor\s*\(/g);
row('CardSurface(', /\bCardSurface\s*\(/g);
row('MaterialCardLayer(', /\bMaterialCardLayer\s*\(/g);
row('MaterialSheetPanel(', /\bMaterialSheetPanel\s*\(/g);
row('IconCircleButton(', /\bIconCircleButton\s*\(/g);
row('cardGlassEffect', /\bcardGlassEffect\s*\(/g);
row('cardGlassBorderColor', /\bcardGlassBorderColor\s*\(/g);
row('cardGlassShadow', /\bcardGlassShadow\s*\(/g);
row('statusBarHeight 读取', /this\.statusBarHeight/g);
row('height(56 + statusBarHeight)', /56\s*\+\s*this\.statusBarHeight/g);
row('SwitchRow(', /\bSwitchRow\s*\(/g);
row('Toggle(', /\bToggle\s*\(/g);
row('ToggleType.Switch', /ToggleType\.Switch/g);
row('ToggleType.Button', /ToggleType\.Button/g);
row('Slider(', /\bSlider\s*\(/g);
row('bindSheet', /\.bindSheet\s*\(/g);
row('appFontFamily(', /\bappFontFamily\s*\(/g);
row('appFontWeight(', /\bappFontWeight\s*\(/g);

console.log('\n' + '='.repeat(72));
console.log('⑤ 字体子系统（本次补漏：第一版文档完全没提到）');
console.log('='.repeat(72));
for (const key of ['fontMode', 'fontFamilyEn', 'fontFamilyZh', 'fontSizeMode',
  'fontSizeValue', 'fontWeightMode', 'fontWeightValue']) {
  const n = info.filter((x) => new RegExp(`'${key}'|@Storage\\w+\\(\\s*'${key}'`).test(x.text)).length;
  console.log(`   ${key.padEnd(18)} 出现在 ${n} 个文件中`);
}
console.log(`   appFontFamily 总调用 ${sum(info, (x) => count(x.text, /appFontFamily\s*\(/g))} 处 `
  + `（分布在 ${info.filter((x) => /appFontFamily\s*\(/.test(x.text)).length} 个文件）`);

console.log('\n' + '='.repeat(72));
console.log('⑥ 硬编码色值：区分「带色相」与「无彩色」');
console.log('='.repeat(72));
// 关键区分：`#99000000` / `#33FFFFFF` / `#00000000` 这类**无彩色**（R=G=B）是
// 阴影、遮罩、轨道、全透明的正常写法，**与主题色无关**，不该算「硬编码颜色」。
// 只有 R/G/B 不全相等的才叫带色相，才是真的会在切主题色后露出旧色的问题点。
const isAchromatic = (lit) => {
  const h = lit.slice(2, -1);            // 去掉 '# 与结尾引号
  const rgb = h.length === 8 ? h.slice(2) : h;  // 8 位是 AARRGGBB，去掉 AA
  const r = rgb.slice(0, 2), g = rgb.slice(2, 4), b = rgb.slice(4, 6);
  return r.toLowerCase() === g.toLowerCase() && g.toLowerCase() === b.toLowerCase();
};
let allTotal = 0;
let hueTotal2 = 0;
const hueByFile = [];
for (const x of info) {
  const lits = x.text.match(/'#(?:[0-9A-Fa-f]{8}|[0-9A-Fa-f]{6})'/g) ?? [];
  if (lits.length === 0) continue;
  allTotal += lits.length;
  const hue = lits.filter((l) => !isAchromatic(l));
  if (hue.length === 0) continue;
  hueTotal2 += hue.length;
  hueByFile.push({ rel: x.rel, n: hue.length, isUi: x.isUi, sample: [...new Set(hue)].slice(0, 4) });
}
for (const r of hueByFile.sort((a, b) => b.n - a.n)) {
  console.log(`   ${String(r.n).padStart(4)} 处  ${r.rel}${r.isUi ? '' : '   (非 UI 文件)'}`);
  console.log(`          ${r.sample.join(' ')}`);
}
console.log(`\n色值字面量合计 ${allTotal} 处；其中**带色相**的 ${hueTotal2} 处`);
console.log(`带色相且位于 UI 文件的：${sum(hueByFile.filter((r) => r.isUi), (r) => r.n)} 处`);
