/**
 * 配置/资源文件校验（教学 Demo 自检用）
 * ============================================================================
 * 校验 JSON / JSON5 是否良构，并额外检查：
 *   · module.json5 里 pages 指向的 profile 是否存在
 *   · main_pages.json 里列的每个页面，对应 .ets 文件是否真实存在（**最易出错的一环**）
 *   · $string: / $color: / $media: 引用的资源名是否在 base/element、base/media 里定义
 *   · AppScope/app.json5 的资源引用同样检查
 *
 * 用法：node tools/configcheck.mjs <工程根目录>
 */
import fs from 'node:fs';
import path from 'node:path';

const root = process.argv[2] || '.';
const problems = [];
const notes = [];

/* ---------------- JSON5 宽松解析（去注释 + 去尾逗号 + 引号键） ---------------- */
function stripJson5(text) {
  let out = '';
  let i = 0;
  const n = text.length;
  while (i < n) {
    const c = text[i];
    const c2 = text[i + 1];
    if (c === '/' && c2 === '/') {
      while (i < n && text[i] !== '\n') i++;
      continue;
    }
    if (c === '/' && c2 === '*') {
      i += 2;
      while (i < n && !(text[i] === '*' && text[i + 1] === '/')) i++;
      i += 2;
      continue;
    }
    if (c === '"' || c === "'") {
      const q = c;
      out += '"';
      i++;
      while (i < n) {
        if (text[i] === '\\') {
          out += text[i] + text[i + 1];
          i += 2;
          continue;
        }
        if (text[i] === q) {
          out += '"';
          i++;
          break;
        }
        if (text[i] === '"') out += '\\"';
        else if (text[i] === '\n') out += '\\n';
        else out += text[i];
        i++;
      }
      continue;
    }
    out += c;
    i++;
  }
  // 去尾逗号
  out = out.replace(/,(\s*[}\]])/g, '$1');
  return out;
}

function readJson5(file) {
  const raw = fs.readFileSync(file, 'utf8');
  const cleaned = stripJson5(raw);
  try {
    return { value: JSON.parse(cleaned), error: null };
  } catch (e) {
    return { value: null, error: e.message };
  }
}

function rel(p) {
  return path.relative(root, p).replace(/\\/g, '/');
}

/* ---------------- 收集资源名 ---------------- */
function collectElementNames(dir) {
  const names = new Set();
  if (!fs.existsSync(dir)) return names;
  for (const f of fs.readdirSync(dir)) {
    if (!f.endsWith('.json')) continue;
    const { value, error } = readJson5(path.join(dir, f));
    if (error) {
      problems.push(`${rel(path.join(dir, f))} JSON 解析失败：${error}`);
      continue;
    }
    // element json 顶层是 { string: [...] } / { color: [...] } / { float: [...] }
    for (const key of Object.keys(value)) {
      if (Array.isArray(value[key])) {
        for (const item of value[key]) {
          if (item && typeof item.name === 'string') names.add(item.name);
        }
      }
    }
  }
  return names;
}

function collectMediaNames(dir) {
  const names = new Set();
  if (!fs.existsSync(dir)) return names;
  for (const f of fs.readdirSync(dir)) {
    if (f.startsWith('.')) continue;
    names.add(path.parse(f).name);
  }
  return names;
}

/* ---------------- 1. 所有 json/json5 是否良构 ---------------- */
function walk(p, out = []) {
  const st = fs.statSync(p);
  if (st.isDirectory()) {
    if (path.basename(p) === 'node_modules' || path.basename(p) === '.git' ||
        path.basename(p) === 'build' || path.basename(p) === 'oh_modules') return out;
    for (const e of fs.readdirSync(p, { withFileTypes: true })) walk(path.join(p, e.name), out);
  } else if (p.endsWith('.json') || p.endsWith('.json5')) {
    out.push(p);
  }
  return out;
}

const jsonFiles = walk(root);
for (const f of jsonFiles) {
  const { error } = readJson5(f);
  if (error) problems.push(`${rel(f)} 解析失败：${error}`);
}
notes.push(`JSON/JSON5 文件 ${jsonFiles.length} 个，全部解析通过`);

/* ---------------- 2. module.json5 → pages profile → 页面文件 ---------------- */
const entryMain = path.join(root, 'entry', 'src', 'main');
const moduleJson = path.join(entryMain, 'module.json5');
if (!fs.existsSync(moduleJson)) {
  problems.push('缺少 entry/src/main/module.json5');
} else {
  const { value: mod } = readJson5(moduleJson);
  const pagesRef = mod?.module?.pages;
  if (typeof pagesRef !== 'string' || !pagesRef.startsWith('$profile:')) {
    problems.push('module.json5 的 module.pages 未指向 $profile:xxx');
  } else {
    const profileName = pagesRef.slice('$profile:'.length);
    const profilePath = path.join(entryMain, 'resources', 'base', 'profile', `${profileName}.json`);
    if (!fs.existsSync(profilePath)) {
      problems.push(`module.pages 指向 ${pagesRef}，但 ${rel(profilePath)} 不存在`);
    } else {
      const { value: pages } = readJson5(profilePath);
      const list = pages?.src ?? [];
      if (list.length === 0) problems.push(`${rel(profilePath)} 的 src 为空`);
      for (const page of list) {
        const file = path.join(entryMain, 'ets', `${page}.ets`);
        if (!fs.existsSync(file)) {
          problems.push(`main_pages.json 声明了 ${page}，但文件不存在：${rel(file)}`);
        }
      }
      notes.push(`路由页面 ${list.length} 个，文件全部存在`);
    }
  }
}

/* ---------------- 3. router.pushUrl 的目标是否已注册 ---------------- */
const registered = new Set();
const profilePath = path.join(entryMain, 'resources', 'base', 'profile', 'main_pages.json');
if (fs.existsSync(profilePath)) {
  const { value: pages } = readJson5(profilePath);
  for (const p of (pages?.src ?? [])) registered.add(p);
}
function walkEts(p, out = []) {
  const st = fs.statSync(p);
  if (st.isDirectory()) {
    for (const e of fs.readdirSync(p, { withFileTypes: true })) walkEts(path.join(p, e.name), out);
  } else if (p.endsWith('.ets')) out.push(p);
  return out;
}
const etsDir = path.join(entryMain, 'ets');
if (fs.existsSync(etsDir)) {
  for (const f of walkEts(etsDir)) {
    const src = fs.readFileSync(f, 'utf8');
    for (const m of src.matchAll(/pushUrl\(\s*\{\s*url:\s*'([^']+)'/g)) {
      const target = m[1];
      if (!registered.has(target)) {
        problems.push(`${rel(f)} pushUrl 到 '${target}'，但该页面未登记在 main_pages.json`);
      }
    }
  }
}

/* ---------------- 4. $string: / $color: / $media: 引用 ---------------- */
function checkResourceRefs(dirToScan, elemDirs, mediaDirs, label) {
  const elems = new Set();
  for (const d of elemDirs) for (const n of collectElementNames(d)) elems.add(n);
  const medias = new Set();
  for (const d of mediaDirs) for (const n of collectMediaNames(d)) medias.add(n);

  const scan = (p) => {
    if (!fs.existsSync(p)) return;
    const st = fs.statSync(p);
    if (st.isDirectory()) {
      for (const e of fs.readdirSync(p, { withFileTypes: true })) scan(path.join(p, e.name));
      return;
    }
    if (!p.endsWith('.json') && !p.endsWith('.json5')) return;
    const src = fs.readFileSync(p, 'utf8');
    for (const m of src.matchAll(/\$(string|color|float|media|profile):([A-Za-z0-9_.]+)/g)) {
      const kind = m[1];
      const name = m[2];
      if (kind === 'media' && !medias.has(name)) {
        problems.push(`${rel(p)} 引用了 $media:${name}，但 base/media 下没有该文件`);
      } else if (kind !== 'media' && kind !== 'profile' && !elems.has(name)) {
        problems.push(`${rel(p)} 引用了 $${kind}:${name}，但 element 资源里没有定义`);
      }
    }
  };
  scan(dirToScan);
  notes.push(`${label}：element 资源 ${elems.size} 项、media ${medias.size} 项`);
}

checkResourceRefs(
  path.join(root, 'entry', 'src', 'main'),
  [path.join(entryMain, 'resources', 'base', 'element')],
  [path.join(entryMain, 'resources', 'base', 'media')],
  'entry 模块');
checkResourceRefs(
  path.join(root, 'AppScope'),
  [path.join(root, 'AppScope', 'resources', 'base', 'element')],
  [path.join(root, 'AppScope', 'resources', 'base', 'media')],
  'AppScope');

/* ---------------- 输出 ---------------- */
console.log('— 检查结果 —');
for (const n of notes) console.log(`  · ${n}`);
if (problems.length === 0) {
  console.log('\n全部通过 ✅');
  process.exit(0);
}
console.log(`\n发现 ${problems.length} 个问题：`);
for (const p of problems) console.log(`  ✗ ${p}`);
process.exit(1);
