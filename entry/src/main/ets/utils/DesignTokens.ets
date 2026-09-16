/**
 * 设计令牌（DesignTokens）—— 教学版
 * ============================================================================
 * 本文件是 CLink（羊绒互传）主题色机制的最小可运行提炼，逐条对应
 * `CLink/entry/src/main/ets/utils/DesignTokens.ets`。
 *
 * ────────────────────────────────────────────────────────────────────────────
 * 一、这套机制要解决什么
 * ────────────────────────────────────────────────────────────────────────────
 * 目标：用户选一个颜色（或输入任意 RRGGBB），**全应用立即变色**，无需重启。
 * 三个难点决定了它的形态：
 *
 *   难点 1｜ArkUI 不会因为「普通对象的属性」变化而刷新
 *          → 颜色必须集中放在一个**模块级可变对象** `HwColor` 里，运行时改写；
 *            但改写它本身**不触发任何重建**，所以还需要第二条线（见难点 2）。
 *
 *   难点 2｜`@StorageProp` + `@Watch` 只触发回调，**不重新求值组件**
 *          → 必须有一个**真正渲染出来的表达式**读到订阅键，ArkUI 才会把节点标脏。
 *            所以颜色要走 `AppStorage` 广播（`accentColor` 等键）。
 *
 *   难点 3｜SDK 控件自带默认选中色
 *          → `Toggle` / `Slider` 的 `selectedColor` 默认是系统强调色（蓝），
 *            `TextInput` 的 `caretColor` 同理。不显式覆盖就永远是蓝的。
 *
 * 一句话结论（整套机制的核心）：
 *
 *      HwColor.primary  负责「值」        —— 重建时去哪里取色
 *      AppStorage['accentColor'] 负责「通知」—— 通知谁该重建
 *      **两者缺一不可。**
 *
 * ────────────────────────────────────────────────────────────────────────────
 * 二、生效链路（从点击到全应用变色）
 * ────────────────────────────────────────────────────────────────────────────
 *   用户点色块 / 输入 RRGGBB
 *     → 设置页写 @StorageLink('accentKey' | 'accentCustom')     同步进 AppStorage
 *     → AppearanceStore.setString(...)                          落盘持久化
 *     → applyAccentNow() → reloadAppTheme()
 *         ├─ effectiveAccentColor() 算出最终 #RRGGBB
 *         ├─ applyAppTheme() 改写 HwColor（模块级对象，**静默**）
 *         └─ AppStorage.setOrCreate('accentColor', resolved)     ← 唯一的「通知」
 *     → 所有订阅 accentColor 的页面/组件被标记为脏并重建
 *     → 重建时读到新的 HwColor.primary + accentColor
 *
 * ────────────────────────────────────────────────────────────────────────────
 * 三、两条最容易踩的规则（本文件里到处都在防它们）
 * ────────────────────────────────────────────────────────────────────────────
 *   规则 A｜**表达式里必须出现订阅变量**
 *           `HwColor` 只是普通对象，读它的属性登记不上依赖。所以：
 *             ✗ `.backgroundColor(hwPrimary(this.isDarkMode))`      ← 切色后不刷新
 *             ✓ `.backgroundColor(resolvePrimaryColor(this.isDarkMode, this.accentOrPrimary()))`
 *           `resolve*` 系列与 `hw*` 系列**取值逐档一致**，差别只在于前者把
 *           `accentColor` 作为入参，于是表达式里真正读到了订阅键。
 *
 *   规则 B｜**`@Prop` 默认值 / 模块级常量只在构造时求值一次**
 *           需要在其生命周期内变化的值，都不能用 `@Prop` 默认值承接。
 */

// ============================================================================
// 0. 可变色板：整套机制的支点
// ============================================================================

export interface HwColorPalette {
  primary: string;
  background: string;
  backgroundDark: string;
  surface: string;
  textPrimary: string;
  textSecondary: string;
  danger: string;
  online: string;
}

/**
 * ⚠️ 必须是 `export const HwColor = { ... }`（**可变对象**），
 * 不能写成 `const PRIMARY = '#0A59F7'` 这种字符串常量——后者无法在运行时改写。
 *
 * 这个区别就是「主题色能不能做出来」的分水岭：ArkUI 不会因为它的属性变化而刷新，
 * 但它保证了「重建发生时，所有取色点都能拿到新值」。
 */
export const HwColor: HwColorPalette = {
  // 默认主题色（鸿蒙蓝）；切色后由 applyAppTheme 覆盖
  primary: '#0A59F7',
  background: '#F1F3F5',
  backgroundDark: '#000000',
  surface: '#FFFFFF',
  textPrimary: '#182431',
  textSecondary: '#8A8F99',
  danger: '#D94838',
  online: '#00AA72'
};

/** 圆角刻度 */
export interface HwRadiusScale {
  card: number;
  control: number;
  pill: number;
}

export const HwRadius: HwRadiusScale = {
  card: 24,
  control: 16,
  pill: 999
};

/** 间距刻度 */
export interface HwSpaceScale {
  xs: number;
  sm: number;
  md: number;
  lg: number;
  xl: number;
}

export const HwSpace: HwSpaceScale = {
  xs: 4,
  sm: 8,
  md: 12,
  lg: 16,
  xl: 24
};

// ============================================================================
// 1. 主题色：预设、默认值、存储键
// ============================================================================

export interface AccentPreset {
  key: string;
  label: string;
  value: string;
}

export const DEFAULT_ACCENT_KEY: string = 'harmony';
export const DEFAULT_ACCENT_VALUE: string = '#0A59F7';

/**
 * 主题色预设。
 *
 * 教学要点 1｜**「默认色」不要单列成一个预设。**
 *   它就该等于预设首位那一档。否则设置页会同时出现「默认色」和「鸿蒙蓝」两个蓝，
 *   用户分不清哪个才是默认，主色还与应用其它部分的配色对不上。
 *   「默认」是一个**语义**，不是一个颜色。
 *
 * 教学要点 2｜**预设里要有浅色。**
 *   `ripple`（涟漪粉 #FAD6E4）与 `firefly`（流荧绿 #88E4D4）都很浅，
 *   压在它们上面的文字**不能用白色**。凡是「主题色底 + 文字」的地方，
 *   一律走 `onAccentColor()` 按亮度自动切黑/白字（见 §3）。
 *   新增浅色预设时不必再去逐个调用点改字色。
 */
export const ACCENT_PRESETS: AccentPreset[] = [
  { key: 'harmony', label: '鸿蒙蓝', value: '#0A59F7' },
  { key: 'rose', label: '往昔粉', value: '#E86A92' },
  { key: 'ripple', label: '涟漪粉', value: '#FAD6E4' },
  { key: 'firefly', label: '流荧绿', value: '#88E4D4' }
];

/** 主题色设置键：存预设 key 或字符串 'custom' */
export const ACCENT_KEY_STORAGE: string = 'accentKey';
/** 自定义主题色设置键：存 RRGGBB（不含 #） */
export const ACCENT_CUSTOM_STORAGE: string = 'accentCustom';
/**
 * 自定义主题色列表设置键。
 * 元素格式：`'RRGGBB'`（无昵称）或 **`'RRGGBB|昵称'`**（有昵称）。
 * 旧版本存的是纯 `'RRGGBB'` 数组，读入时由 `parseAccentEntries()` 兼容解析。
 */
export const ACCENT_CUSTOM_LIST_STORAGE: string = 'accentCustomList';

/**
 * 「主题色」总开关（**默认开**）。
 *
 * 关闭后**所有主题色都不生效**，配色回到「加主题色功能之前的那一版」
 * （见文末 LEGACY_* 常量）。用户选过的颜色与自定义列表**原样保留**，
 * 重新打开即恢复——所以是「走另一支配色」，而不是清空设置。
 */
export const THEME_COLOR_ENABLED_STORAGE: string = 'themeColorEnabled';

/** 主题色广播键：最终解析好的 `#RRGGBB`。所有 UI 依赖的是它，不是上面的持久化键 */
export const ACCENT_COLOR_KEY: string = 'accentColor';
/** 页面底色广播键：由 applyAppTheme 发布，页面订阅它 */
export const PAGE_BACKGROUND_KEY: string = 'pageBackground';
/** 卡片底色广播键 */
export const CARD_SURFACE_KEY: string = 'cardSurface';
/**
 * 卡片沾色叠加层广播键：空串表示不沾色。
 *
 * 教学要点｜**沾色必须是「叠在材质之上的一层」，不能把颜色混进卡片底色。**
 *   沉浸光感生效时外壳底色是透明的（让位给系统材质），混进底色的颜色
 *   根本不会被画出来——这正是「沾色开关点了没反应」的原因。
 */
export const CARD_TINT_KEY: string = 'cardTintColor';
/** 卡片沾色开关 */
export const CARD_TINT_STORAGE: string = 'cardTintEnabled';
/** 高权限自定义主题色：打开后自定义色也参与**页面背景淡染**（默认只允许内置预设色） */
export const CUSTOM_ACCENT_FULL_ACCESS_STORAGE: string = 'customAccentFullAccess';

/** 沉浸光感「主题色流光」开关（默认开）：关 = 回到系统默认白光 */
export const PRESS_GLOW_STORAGE: string = 'immersivePressGlow';
/**
 * 卡片「流光触感」开关（**默认开**）：开 = 按压卡片出现跟手流光；
 * 关 = 按压卡片一点光都不出现。
 *
 * ⚠️ 与原项目的差异：CLink 里这个开关默认是**关**的
 *    （`AppSettingsStore.getBoolean(CARD_GLOW_TOUCH_STORAGE, false)`），
 *    本 Demo 改成默认开，便于一上手就看到流光效果。
 *    要还原上游行为，把这里三处默认值改回 false 即可：
 *    EntryAbility 的读取默认值、CardSurface 的 `glowTouchEnabled`、本开关的设置页初值。
 */
export const CARD_GLOW_TOUCH_STORAGE: string = 'cardGlowTouch';

/**
 * **启动快照**：应用启动那一刻的主题色，由 `EntryAbility` 写一次，**之后永不更新**。
 *
 * 这是本 Demo 专用键，CLink 里没有 —— 它只服务于 `ThemeLabPage` 的「反面对照」，
 * 用来演示「什么样的写法会把颜色定死在启动那一刻」。
 *
 * 为什么不直接在页面里写常量或 `@Prop` 默认值（两条路都实测失败过）：
 *   · `@Prop frozen: string = HwColor.primary` —— 父组件重渲染时默认值**会重新求值**；
 *   · `const FROZEN: string = HwColor.primary` —— 页面模块**可能被重新求值**，
 *     常量跟着当前主题色走，照样「跟随」。
 * 唯一稳定的是「在组件与模块之外只写一次」，也就是启动阶段写进 AppStorage 的这个键。
 *
 * 顺带一个真实用途：**「启动时的外观」本身是需要展示的信息**
 * （比如「本次启动用的是哪套配色」），这种值就该这样存。
 */
export const BOOT_ACCENT_STORAGE: string = 'bootAccentColor';

/**
 * 深色模式偏好：`'system'` / `'light'` / `'dark'`。
 *
 * 教学要点｜**为什么是字符串三态而不是布尔开关：**
 *   布尔一旦被用户拨动过就永久生效，**再也没法回到「跟随系统」**
 *   （表现为「深色模式不跟随系统」，只能靠重置设置救回来）。
 *   三态让「跟随系统」始终是一个能选回来的状态。
 */
export const DARK_MODE_PREF_STORAGE: string = 'darkModePreference';
export const DARK_MODE_SYSTEM: string = 'system';
export const DARK_MODE_LIGHT: string = 'light';
export const DARK_MODE_DARK: string = 'dark';
/** 深色模式广播键（其它页面只读它） */
export const DARK_MODE_KEY: string = 'isDarkMode';

/** 读一个布尔开关，读取失败时用默认值 */
function readFlag(key: string, fallback: boolean): boolean {
  try {
    const value = AppStorage.get<boolean>(key);
    return value === undefined ? fallback : value;
  } catch (err) {
    return fallback;
  }
}

// ============================================================================
// 2. 校验与派生工具
// ============================================================================

/**
 * 校验自定义主题色输入：只接受 6 位十六进制（可带 #），大小写均可。
 * 返回规范化后的 `#RRGGBB`，**非法时返回空串**（调用方据此判定非法）。
 */
export function normalizeAccentHex(input: string): string {
  const raw = input.trim().replace('#', '');
  if (raw.length !== 6) {
    return '';
  }
  for (let i = 0; i < raw.length; i++) {
    const c = raw.charAt(i).toLowerCase();
    const isDigit = c >= '0' && c <= '9';
    const isHex = c >= 'a' && c <= 'f';
    if (!isDigit && !isHex) {
      return '';
    }
  }
  return `#${raw.toUpperCase()}`;
}

/** 自定义主题色条目：色值 + 用户起的昵称 */
export interface AccentCustom {
  /** `RRGGBB`（不含 `#`），始终是大写 */
  hex: string;
  /** 用户起的昵称，空串表示没起名字 */
  name: string;
}

/** 列表元素的分隔符：`RRGGBB|昵称` */
const ACCENT_ENTRY_SEPARATOR: string = '|';

/**
 * 解析持久化的自定义主题色列表。
 *
 * **兼容两种格式**：旧版纯 `'RRGGBB'`、新版 `'RRGGBB|昵称'`。
 * 逐项过滤非法色值并按色值去重（同色值只保留第一条，昵称取第一条非空的）。
 *
 * 教学要点｜**改数据结构时永远要写兼容解析。**
 *   用户升级后，老格式的数据还在存储里；直接按新格式读会让老用户
 *   「原有的自定义色凭空消失」。
 */
export function parseAccentEntries(raw: string[]): AccentCustom[] {
  const list: AccentCustom[] = [];
  for (let i = 0; i < raw.length; i++) {
    const text = String(raw[i]);
    const cut = text.indexOf(ACCENT_ENTRY_SEPARATOR);
    const hexPart = cut >= 0 ? text.substring(0, cut) : text;
    const namePart = cut >= 0 ? text.substring(cut + 1).trim() : '';
    const hex = normalizeAccentHex(hexPart).replace('#', '');
    if (hex.length !== 6) {
      continue;
    }
    let merged = false;
    for (let j = 0; j < list.length; j++) {
      if (list[j].hex === hex) {
        if (list[j].name.length === 0 && namePart.length > 0) {
          list[j].name = namePart;
        }
        merged = true;
        break;
      }
    }
    if (!merged) {
      list.push({ hex: hex, name: namePart });
    }
  }
  return list;
}

/** 把自定义列表写回持久化格式（有昵称的带上 `|昵称`） */
export function serializeAccentEntries(list: AccentCustom[]): string[] {
  const out: string[] = [];
  for (let i = 0; i < list.length; i++) {
    out.push(list[i].name.length > 0
      ? `${list[i].hex}${ACCENT_ENTRY_SEPARATOR}${list[i].name}`
      : list[i].hex);
  }
  return out;
}

/** 色块上显示的名字：**有昵称就只显示昵称**，没有才回落到 `#RRGGBB` */
export function accentEntryLabel(entry: AccentCustom): string {
  return entry.name.length > 0 ? entry.name : `#${entry.hex}`;
}

/**
 * 给 `#RRGGBB` 叠加透明度，返回 `#AARRGGBB`。
 *
 * 教学要点｜凡是「主题色的浅色底」**都用它，不要写字面量**。
 *   写死的半透明色（例如历史上的 `'#1A3379B7'`）切主题色后不会跟着变，
 *   选中态会露出旧色的底。`alpha` 取 0~1。
 */
export function withAlpha(color: string, alpha: number): string {
  const normalized = normalizeAccentHex(color);
  if (normalized.length === 0) {
    return color;
  }
  const clamped = Math.max(0, Math.min(1, alpha));
  const channel = Math.round(clamped * 255).toString(16).toUpperCase().padStart(2, '0');
  return `#${channel}${normalized.substring(1)}`;
}

/**
 * 两个 `#RRGGBB` 线性混合：ratio=0 取 base，ratio=1 取 tint。
 * 用于把主题色调成「很淡的底色」——直接铺主题色会盖过正文。
 * 任一输入非法时原样返回 base，**绝不返回半成品颜色**。
 */
export function mixHex(base: string, tint: string, ratio: number): string {
  const a = normalizeAccentHex(base);
  const b = normalizeAccentHex(tint);
  if (a.length === 0 || b.length === 0) {
    return a.length > 0 ? a : base;
  }
  const clamped = Math.max(0, Math.min(1, ratio));
  let out = '#';
  for (let i = 1; i < 7; i += 2) {
    const ca = parseInt(a.substring(i, i + 2), 16);
    const cb = parseInt(b.substring(i, i + 2), 16);
    const mixed = Math.round(ca + (cb - ca) * clamped);
    out += mixed.toString(16).toUpperCase().padStart(2, '0');
  }
  return out;
}

/**
 * 压在主题色上的前景色（黑或白）。
 *
 * 教学要点｜**按相对亮度自动决定，不要让调用点各写各的。**
 *   主题色不都是深色：涟漪粉、流荧绿都很浅，上面再压白字基本看不清。
 *   这里统一按 sRGB 加权亮度算，阈值 0.62（偏保守，宁可早一点切黑字）：
 *     鸿蒙蓝 0.33、往昔粉 0.58 → 走白字
 *     涟漪粉 0.89、流荧绿 0.78 → 走黑字
 *
 * ⚠️ 调用时要把**订阅变量**传进来（`onAccentColor(this.accentOrPrimary())`）：
 *    直接写 `onAccentColor(HwColor.primary)` 读的是模块级对象、登记不上依赖，
 *    切色后字色不会跟着变。
 */
export function onAccentColor(accentColor: string): string {
  const normalized = normalizeAccentHex(accentColor);
  if (normalized.length === 0) {
    return '#FFFFFF';
  }
  const r = parseInt(normalized.substring(1, 3), 16);
  const g = parseInt(normalized.substring(3, 5), 16);
  const b = parseInt(normalized.substring(5, 7), 16);
  const luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
  return luminance > 0.62 ? '#1A1A1A' : '#FFFFFF';
}

/** 是否是内置预设的 key（`'custom'` 不是预设，返回 false） */
export function isPresetAccentKey(key: string): boolean {
  for (let i = 0; i < ACCENT_PRESETS.length; i++) {
    if (ACCENT_PRESETS[i].key === key) {
      return true;
    }
  }
  return false;
}

/**
 * 是否是内置预设主题色（按**颜色值**判定）。
 *
 * 教学要点｜页面背景只跟随**预设色**：自定义色是用户随手输的，
 *   拿它铺满整页底色很容易脏，也可能与正文对比度不足。
 *   「高权限自定义主题色」开关只是把这个门槛去掉，淡染算法完全一样。
 */
export function isPresetAccent(color: string): boolean {
  const normalized = normalizeAccentHex(color);
  if (normalized.length === 0) {
    return false;
  }
  for (let i = 0; i < ACCENT_PRESETS.length; i++) {
    if (normalizeAccentHex(ACCENT_PRESETS[i].value) === normalized) {
      return true;
    }
  }
  return false;
}

/**
 * 按当前设置解析主题色。
 * 预设命中则用预设值；未命中（custom）时用自定义值，**自定义非法则回落默认主题色**。
 */
export function resolveAccentColor(accentKey: string, customHex: string): string {
  for (let i = 0; i < ACCENT_PRESETS.length; i++) {
    if (ACCENT_PRESETS[i].key === accentKey) {
      return ACCENT_PRESETS[i].value;
    }
  }
  const normalized = normalizeAccentHex(customHex);
  return normalized.length > 0 ? normalized : DEFAULT_ACCENT_VALUE;
}

/**
 * 当前**实际生效**的主题色。
 *
 * 与 `resolveAccentColor()` 的区别**只在总开关**：`themeColorEnabled` 关闭时
 * 固定返回默认鸿蒙蓝，用户存下来的 key / 自定义色不动。
 *
 * 教学要点｜启动初始化、`onConfigurationUpdate`、`reloadAppTheme` 三处**都要走它**。
 *   否则关掉总开关后会出现「HwColor 已经是旧版配色，而 `accentColor` 仍是用户的粉色」
 *   ——开关控件、底栏高亮、流光会跟页面其余部分不同色（见 §5 的坑 5）。
 */
export function effectiveAccentColor(accentKey: string, customHex: string): string {
  return themeColorOn() ? resolveAccentColor(accentKey, customHex) : DEFAULT_ACCENT_VALUE;
}

/** 读 AppStorage 里的当前主题色；读不到时回落默认主题色 */
export function currentAccentColor(): string {
  try {
    const stored = AppStorage.get<string>(ACCENT_COLOR_KEY);
    if (stored !== undefined && normalizeAccentHex(stored).length > 0) {
      return normalizeAccentHex(stored);
    }
  } catch (err) {
  }
  return HwColor.primary;
}

// ============================================================================
// 3. 深浅模式取值函数族
// ============================================================================

/**
 * 深色模式下主题色向白色抬升的比例（越大越亮）。
 *
 * 教学要点｜**深色分支也要由主题色派生，不能写死一个蓝。**
 *   否则浅色预设（涟漪粉、流荧绿）在深色模式下会因为太暗而看不清。
 *   这里用 `mixHex(主题色, '#FFFFFF', 0.4)` 抬亮，
 *   保证纯黑底上仍有 >=3:1 的对比度（WCAG 2.1）。
 */
const DARK_ACCENT_LIFT: number = 0.4;
/** 深色模式下主按钮底色向黑色压深的比例（越大越暗，配白字越清晰，>=4.5:1） */
const DARK_BUTTON_DEEPEN: number = 0.32;

// --- 「主题色」关闭时的旧版配色（加主题色功能之前的那一版） -------------------
// 关闭总开关后不走「由主题色派生」，而是原样回到这几个写死的值，
// 这样关闭后的观感与引入主题色之前逐像素一致。
const LEGACY_PRIMARY_DARK: string = '#5AA0FF';
const LEGACY_PRIMARY_BUTTON_DARK: string = '#1F5FCC';
const LEGACY_PAGE_LIGHT: string = '#F1F3F5';
const LEGACY_PAGE_DARK: string = '#000000';
const LEGACY_CARD_SURFACE_LIGHT: string = '#B3FFFFFF';
const LEGACY_CARD_SURFACE_DARK: string = '#24272B';
const LEGACY_CARD_BORDER: string = '#1AFFFFFF';

/** 主题色总开关当前是否打开（默认开） */
export function themeColorOn(): boolean {
  return readFlag(THEME_COLOR_ENABLED_STORAGE, true);
}

/**
 * 当前生效的配色是否来自「主题色」功能。
 * `applyAppTheme()` 每次跑都会刷新它，深色派生函数读它决定走「派生」还是「旧版」。
 */
let themeColorActive: boolean = true;

function textPrimaryDark(): string {
  return '#F0F2F5';
}

function textSecondaryDark(): string {
  return '#C0C5CB';
}

function dangerDark(): string {
  return '#FF8A7A';
}

function onlineDark(): string {
  return '#40DB94';
}

function surfaceDark(): string {
  return '#24272B';
}

function surfaceBorderDark(): string {
  return '#3A3F45';
}

/** 正文/标题文字色 */
export function hwTextPrimary(isDark: boolean): string {
  return isDark ? textPrimaryDark() : HwColor.textPrimary;
}

/** 次要/辅助文字色 */
export function hwTextSecondary(isDark: boolean): string {
  return isDark ? textSecondaryDark() : HwColor.textSecondary;
}

/**
 * 主色（前景：文字、链接、选中态图标）。**按钮背景请用 `hwPrimaryButton`。**
 *
 * ⚠️ **本函数是普通纯函数：登记不上依赖。**
 *    它读的是模块级 `HwColor`，表达式里没有订阅变量，所以切主题色时
 *    已经画出来的这一处属性**不会**重新求值
 *    （表现：页面别的地方都变色了，唯独这个按钮/图标还是旧色）。
 *
 * 需要实时跟随的地方请用 `resolvePrimaryColor(isDark, this.accentOrPrimary())`。
 */
export function hwPrimary(isDark: boolean): string {
  if (!isDark) {
    return HwColor.primary;
  }
  return themeColorActive ? mixHex(HwColor.primary, '#FFFFFF', DARK_ACCENT_LIFT) : LEGACY_PRIMARY_DARK;
}

/** 主按钮背景色（配白字），深浅模式下发色号不同以保证白字对比度。同样登记不上依赖。 */
export function hwPrimaryButton(isDark: boolean): string {
  if (!isDark) {
    return HwColor.primary;
  }
  return themeColorActive
    ? mixHex(HwColor.primary, '#000000', DARK_BUTTON_DEEPEN) : LEGACY_PRIMARY_BUTTON_DARK;
}

/** 取一个合法的主题色入参：为空或非法时回落到当前 token */
function accentOrFallback(accentColor: string): string {
  const normalized = normalizeAccentHex(accentColor);
  return normalized.length > 0 ? normalized : HwColor.primary;
}

/**
 * 主色的**订阅版**：把 `accentColor` 作为入参传进来，表达式里就真正读到了订阅键。
 * 取值与 `hwPrimary(isDark)` **逐档一致**（含深色抬亮、含总开关关闭时回落旧版浅蓝）。
 *
 * ```ets
 * .fontColor(resolvePrimaryColor(this.isDarkMode, this.accentOrPrimary()))
 * ```
 */
export function resolvePrimaryColor(isDark: boolean, accentColor: string): string {
  const accent = accentOrFallback(accentColor);
  if (!isDark) {
    return accent;
  }
  return themeColorActive ? mixHex(accent, '#FFFFFF', DARK_ACCENT_LIFT) : LEGACY_PRIMARY_DARK;
}

/** 主按钮底色的**订阅版**：取值与 `hwPrimaryButton(isDark)` 逐档一致 */
export function resolvePrimaryButtonColor(isDark: boolean, accentColor: string): string {
  const accent = accentOrFallback(accentColor);
  if (!isDark) {
    return accent;
  }
  return themeColorActive ? mixHex(accent, '#000000', DARK_BUTTON_DEEPEN) : LEGACY_PRIMARY_BUTTON_DARK;
}

/**
 * 卡片/芯片描边色的**订阅版**：浅色是「主题色的 10%」，深色是固定的中性边框。
 * 取值与 `hwGlassBorder(isDark)` 逐档一致。
 */
export function resolveGlassBorderColor(isDark: boolean, accentColor: string): string {
  if (isDark) {
    return surfaceBorderDark();
  }
  return withAlpha(accentOrFallback(accentColor), 0.1);
}

/** 危险/错误文字色 */
export function hwDanger(isDark: boolean): string {
  return isDark ? dangerDark() : HwColor.danger;
}

/** 在线/成功态颜色 */
export function hwOnline(isDark: boolean): string {
  return isDark ? onlineDark() : HwColor.online;
}

/** 卡片、输入框等内容表面色 */
export function hwSurface(isDark: boolean): string {
  return isDark ? surfaceDark() : HwColor.surface;
}

/** 卡片边框色（纯函数版） */
export function hwGlassBorder(isDark: boolean): string {
  return isDark ? surfaceBorderDark() : HwGlassCardColor.border;
}

export interface HwGlassCardPalette {
  surface: string;
  border: string;
}

/**
 * 浅色玻璃卡片色板。**真实值由 `applyAppTheme()` 按深浅/主题色派生。**
 *
 * 教学要点｜卡片底色刻意留 **70% 透明度**：
 *   沉浸光感不可用时要降级为毛玻璃（`backgroundBlurStyle` / `backgroundEffect`），
 *   不透明的底色会把模糊整个盖住，等于没有降级效果。
 */
export const HwGlassCardColor: HwGlassCardPalette = {
  surface: '#B3FFFFFF',
  // 占位值（默认主题色 10% 透明），真实值由 applyAppTheme 派生
  border: '#1A0A59F7'
};

/** 玻璃卡片表面色（深浅分支） */
export function hwGlassSurface(isDark: boolean): string {
  return isDark ? surfaceDark() : HwGlassCardColor.surface;
}

// ============================================================================
// 4. 顶部栏毛玻璃色
// ============================================================================

/** 浅色模式：白玻璃（40% 白）。压在浅色页面/内容上是一层通透的磨砂白。 */
export const TOP_BAR_GLASS_LIGHT: string = '#66FFFFFF';

/**
 * 深色模式：**压暗**的黑玻璃。
 *
 * 教学要点｜**深色不能简单沿用浅色那一档的「深色近亲」。**
 *   对比三种取值压在深色页面（近黑）上的结果：
 *     `#66FFFFFF`（40% 白）  → 变**亮灰板**，深色模式下最刺眼的一种
 *     `#6624282B`（40% 深灰）→ 仍然**比页面更亮**、发灰；低不透明度还会让内容透出来顶成浅板
 *     `#99000000`（60% 黑）  → 比页面**更深一档**，是「压暗」而非「提亮」✓
 *   配合 blurRadius: 12，观感是「压暗的烟熏玻璃」而不是「发亮的磨砂板」。
 */
export const TOP_BAR_GLASS_DARK: string = '#99000000';

/** 顶部栏毛玻璃色：按深浅模式取色。所有顶栏统一走它，**不要写死 `'#66FFFFFF'`**。 */
export function topBarGlassColor(isDark: boolean): string {
  return isDark ? TOP_BAR_GLASS_DARK : TOP_BAR_GLASS_LIGHT;
}

/** 深色模式下顶栏按钮的玻璃色 */
export const TOP_BAR_BUTTON_GLASS_DARK: string = '#6624282B';

/**
 * 顶栏上「圆形玻璃按钮」的底色。
 *
 * 教学要点｜刻意**不直接复用** `topBarGlassColor()`：
 *   深色模式下如果按钮和栏底同色，两者会糊在一起、看不出这里有个按钮，
 *   所以按钮保留一层略亮的玻璃。浅色模式则与栏底同色（本来就是白玻璃 + 细描边）。
 */
export function topBarButtonGlassColor(isDark: boolean): string {
  return isDark ? TOP_BAR_BUTTON_GLASS_DARK : TOP_BAR_GLASS_LIGHT;
}

// ============================================================================
// 5. applyAppTheme / reloadAppTheme：把值写进 token 并广播
// ============================================================================

/** 浅色模式页面底色基数（未跟随主题色时） */
const PAGE_BASE_LIGHT: string = '#F1F3F5';
/** 深色模式页面底色基数 */
const PAGE_BASE_DARK: string = '#000000';
/** 浅色背景混入主题色的比例（**刻意很淡**：直接铺主题色会压过正文） */
const PAGE_TINT_LIGHT: number = 0.12;
/** 深色背景混入主题色的比例 */
const PAGE_TINT_DARK: number = 0.18;

/**
 * 应用主题：把暗/浅色值写入可变 token，并发布三个广播键。
 *
 * ⚠️ **第二个参数一定要传当前主题色。**
 *    省略时背景染色会被重置回默认值——因为函数内部要靠 `accentColor`
 *    判断「要不要跟随主题色」。最容易漏的两处：
 *      · 切换深色模式时
 *      · `onConfigurationUpdate`（系统深浅色变化）里
 *    排查方式：切一下深色模式，如果页面背景从「主题色淡染」变回固定浅灰，就是这里漏了。
 */
export function applyAppTheme(isDark: boolean, accentColor: string = ''): void {
  // 总开关关闭 → 整条主题色链路停用，配色逐项回到旧版
  themeColorActive = themeColorOn();
  if (!themeColorActive) {
    HwColor.primary = DEFAULT_ACCENT_VALUE;
    HwColor.background = isDark ? LEGACY_PAGE_DARK : LEGACY_PAGE_LIGHT;
    HwColor.backgroundDark = LEGACY_PAGE_DARK;
    HwColor.surface = isDark ? surfaceDark() : '#FFFFFF';
    HwColor.textPrimary = isDark ? textPrimaryDark() : '#182431';
    HwColor.textSecondary = isDark ? textSecondaryDark() : '#8A8F99';
    HwGlassCardColor.surface = isDark ? LEGACY_CARD_SURFACE_DARK : LEGACY_CARD_SURFACE_LIGHT;
    HwGlassCardColor.border = LEGACY_CARD_BORDER;
    AppStorage.setOrCreate(PAGE_BACKGROUND_KEY, HwColor.background);
    AppStorage.setOrCreate(CARD_SURFACE_KEY, HwGlassCardColor.surface);
    // 沾色层同样停用：它是「主题色的 10% 叠加」，总开关关了就不该出现
    AppStorage.setOrCreate(CARD_TINT_KEY, '');
    return;
  }
  if (accentColor.length > 0) {
    HwColor.primary = normalizeAccentHex(accentColor).length > 0
      ? normalizeAccentHex(accentColor) : HwColor.primary;
  }
  // 背景只跟随**预设**色，且刻意压得很淡：浅色混 12%、深色混 18%。
  // 「高权限自定义主题色」开关只是把 isPresetAccent() 这个门槛去掉。
  const fullAccess = readFlag(CUSTOM_ACCENT_FULL_ACCESS_STORAGE, false);
  const followed = accentColor.length > 0 && (isPresetAccent(accentColor) || fullAccess);
  const tintedLight = followed ? mixHex(PAGE_BASE_LIGHT, accentColor, PAGE_TINT_LIGHT) : PAGE_BASE_LIGHT;
  const tintedDark = followed ? mixHex(PAGE_BASE_DARK, accentColor, PAGE_TINT_DARK) : PAGE_BASE_DARK;
  HwColor.background = isDark ? tintedDark : tintedLight;
  HwColor.backgroundDark = tintedDark;
  // 深色模式的表面/文字保持既有 WCAG 校验过的取值
  HwColor.surface = isDark ? surfaceDark() : '#FFFFFF';
  HwColor.textPrimary = isDark ? textPrimaryDark() : '#182431';
  HwColor.textSecondary = isDark ? textSecondaryDark() : '#8A8F99';
  // 卡片底色留 70% 透明度（降级毛玻璃时底色不能把模糊盖住）。
  // 刻意**不把沾色混进这里**：材质生效时外壳底色是透明的，混进去根本画不出来；
  // 沾色改为叠在材质之上的一层（见 CARD_TINT_KEY 与 CardSurface）。
  HwGlassCardColor.surface = isDark ? '#B326364F' : '#B3E8F0F8';
  // 卡片描边跟主题色走，不要写死某个蓝
  HwGlassCardColor.border = withAlpha(HwColor.primary, 0.1);

  // 发布广播键。页面与卡片**必须订阅它们**而不是直接读 HwColor：
  // ArkUI 按表达式记录依赖，模块级对象的属性读取不会被登记。
  AppStorage.setOrCreate(PAGE_BACKGROUND_KEY, HwColor.background);
  AppStorage.setOrCreate(CARD_SURFACE_KEY, HwGlassCardColor.surface);
  AppStorage.setOrCreate(CARD_TINT_KEY,
    accentColor.length > 0 && readFlag(CARD_TINT_STORAGE, false)
      ? withAlpha(accentColor, 0.1) : '');
}

/**
 * 按已保存的设置重建主题并广播。
 *
 * 主题色切换要「实时生效」：`HwColor` 是模块级对象，直接改属性不会触发刷新，
 * 所以这里把新值写进 `AppStorage` 的 `accentColor`，页面订阅它并重建，颜色立即切换。
 *
 * **总开关关闭时广播的是旧版默认色**（鸿蒙蓝）：订阅 `accentColor` 的开关、
 * 底栏高亮、流光都会跟着回到旧版观感；用户选过的 key / 自定义色原样保留。
 *
 * 这里为什么**不会死循环**：`@Watch` 回调里再次调 `reloadAppTheme()` 时
 * 算出的值相同，`setOrCreate` 写入等值不会触发变更通知。
 */
export function reloadAppTheme(): void {
  let isDark = false;
  let accentKey = DEFAULT_ACCENT_KEY;
  let accentCustom = '';
  try {
    isDark = AppStorage.get<boolean>(DARK_MODE_KEY) === true;
  } catch (err) {
    isDark = false;
  }
  try {
    const stored = AppStorage.get<string>(ACCENT_KEY_STORAGE);
    if (stored !== undefined && stored.length > 0) {
      accentKey = stored;
    }
    const custom = AppStorage.get<string>(ACCENT_CUSTOM_STORAGE);
    if (custom !== undefined) {
      accentCustom = custom;
    }
  } catch (err) {
    // 存储不可用时用默认预设
  }
  const resolved = effectiveAccentColor(accentKey, accentCustom);
  applyAppTheme(isDark, resolved);
  AppStorage.setOrCreate(ACCENT_COLOR_KEY, resolved);
}

/**
 * 页面底色。**所有页面统一走这个函数，不要直接读 `HwColor.background`。**
 *
 * 为什么要绕一层函数：ArkUI 的局部更新按**表达式**记录依赖，而 `HwColor`
 * 是模块级对象——读它的属性不会被登记。直接写
 * `this.isDarkMode ? HwColor.backgroundDark : HwColor.background`
 * 只登记了 `isDarkMode`，于是**切换主题色时底色不会重新求值**，
 * 已打开的页面会停在旧色上（而新建/重进的页面又是对的，很容易误判成「刷新不及时」）。
 *
 * 把 `pageBackground` 作为入参传进来，调用点就真正读到了这个订阅键，依赖才登记得上。
 * 两个参数都必须是调用方声明的订阅变量（`@StorageProp` / `@StorageLink`）。
 */
export function resolvePageBackground(isDark: boolean, background: string): string {
  if (background.length > 0) {
    return background;
  }
  // 兜底：applyAppTheme 尚未跑过时退回当前 token
  return isDark ? HwColor.backgroundDark : HwColor.background;
}
