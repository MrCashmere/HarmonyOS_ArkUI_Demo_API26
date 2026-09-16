# 坑位速查表（Pitfalls）

> 从 CLink（羊绒互传）的 `docs/THEME_COLOR.md`（§7，16 条）、`docs/IMMERSIVE_LIGHT.md`、
> `docs/API_COMPAT.md` 以及本次整理的独立审计中汇总。
>
> 格式：**现象 → 根因 → 修法**。按「排查时最可能先想到哪个现象」排序。

---

## A. 「切了主题色，某处没变」

### A1. 页面别处都变了，唯独某个按钮/图标还是旧色

**现象**：同一行里字色变了、底色没变。
**根因**：那个属性用了**纯函数**。
```ets
.backgroundColor(hwPrimaryButton(this.isDarkMode))   // ✗ 表达式里没有订阅变量
```
`hwPrimaryButton(isDark)` 内部读模块级 `HwColor`，ArkUI 按**表达式**登记依赖，登记不上。
**修法**：换订阅版，取值逐档一致。
```ets
.backgroundColor(resolvePrimaryButtonColor(this.isDarkMode, this.accentOrPrimary()))  // ✓
```
**参考工程实例**：主页设置页的「检查权限」按钮、「默认通用动态图片格式」的选中芯片。

### A2. 已打开的页面底色不跟着切，新进的页面又是对的

**现象**：很容易误判成「刷新不及时」。
**根因**：直接读了模块级对象。
```ets
.backgroundColor(this.isDarkMode ? HwColor.backgroundDark : HwColor.background)  // ✗
```
只登记了 `isDarkMode`，切主题色时这个表达式不会重新求值。
**修法**：让订阅键出现在表达式里。
```ets
.backgroundColor(resolvePageBackground(this.isDarkMode, this.pageBackground))   // ✓
```

### A3. `@Watch` 回调被调了，但界面还是不动

**根因**：`@StorageProp` + `@Watch` **只触发回调，不重新求值组件**。
**修法**：在根容器第一个子节点挂 `AccentColorSentinel()`（零尺寸，只为在渲染树里读一次订阅键）。
> ⚠️ 哨兵能让页面**内容**重算，但**不会**让页面根节点自身的属性重新求值 —— 底色仍走 `resolvePageBackground()`。

### A4. 列表项停在旧配色 / 对号停在上一个色块上 / 改完昵称字没变

**根因**：`ForEach` 会**复用 key 相同的项**，键不变就不重建子节点。
**修法**：把一切「会让外观在数据不变时改变」的状态编进 key：
```ets
// 列表项跟随主题色
}, (file) => file.savedPath + ':' + file.name + ':' + this.accentColor)
// 选中态
}, (preset) => `preset_${preset.key}_${this.accentKey === preset.key ? 1 : 0}_${this.accentColor}`)
// 自定义色还要带上昵称
}, (entry) => `custom_${entry.hex}_${entry.name}_${this.isCustomSelected(entry.hex) ? 1 : 0}_${this.accentColor}`)
```
**判断方法**：问「这个列表项的外观会不会在数据不变的情况下改变」。

### A5. 开关 / 滑杆 / 输入框光标永远是系统蓝

**根因**：SDK 默认 `selectedColor` / `caretColor` 是系统强调色，不覆盖就永远不变。
**修法**：`Toggle` → `.selectedColor(accent)`；`Slider` → `.selectedColor()` + `.trackColor()` + `.blockColor()`；
`TextInput` → `.caretColor(accent)`；`Button(EMPHASIZED)` → 显式 `.backgroundColor()`。
**反面**：`ToggleType.Button` 作**承载层**时 `.selectedColor(Color.Transparent)` 是**刻意**的，不要改成主题色。

### A6. 关掉总开关后，开关控件/底栏高亮仍是用户选的颜色

**根因**：只让 `applyAppTheme()` 走了旧版配色，**广播出去的 `accentColor` 还是用户色**。
**修法**：三处入口统一走 `effectiveAccentColor()`：
`reloadAppTheme()`、`EntryAbility.onCreate`、`EntryAbility.onConfigurationUpdate`。

### A7. 切一下深色模式，页面背景从「主题色淡染」变回固定浅灰

**根因**：调 `applyAppTheme()` 时漏了第二个参数。
```ts
applyAppTheme(enabled);                        // ✗ 背景染色被重置回默认
applyAppTheme(enabled, this.currentAccent());  // ✓
```
**最容易漏的两处**：切换深色模式时、`onConfigurationUpdate`（系统深浅色变化）里。

### A8. 升级后用户原有的自定义主题色凭空消失

**根因**：老版本只有一个 `accentCustom` 单值，没有列表；直接按新格式读会读不到。
**修法**：列表为空且 `accentCustom` 有值时把它补进列表；`parseAccentEntries()` 兼容纯 `RRGGBB` 旧格式。

### A9. 想「冻结」一个颜色做反面对照，结果它照样跟着主题色变（**试错三次才成**）

**现象**：做了个负例色块，故意「写死」颜色，用来演示「有些写法不跟随主题色」——
结果切主题色时，**它也跟着变了**，对照完全失效。

这条坑值得完整记录，因为**连续两种「看起来天经地义」的写法都不成立**：

| # | 写法 | 结果 |
| --- | --- | --- |
| ① | `@Prop frozenAccent: string = HwColor.primary` | ❌ 父组件重渲染时**默认值表达式被重新求值** |
| ② | `const FROZEN: string = HwColor.primary`（模块级常量） | ❌ 页面模块**可能被重新求值**，常量跟着当前色走 |
| ③ | **应用启动阶段写一次的 AppStorage 键** | ✅ 真正冻住 |

```ets
// ① ✗
@Prop frozenAccent: string = HwColor.primary;

// ② ✗ 看着万无一失，实测同样会跟随
const FROZEN_PRIMARY_AT_LOAD: string = HwColor.primary;

// ③ ✓ 在 EntryAbility.onCreate 里写一次，之后谁都不改它
AppStorage.setOrCreate(BOOT_ACCENT_STORAGE, accentColor);
// 页面侧只读（@StorageProp 天生只读）
@StorageProp('bootAccentColor') bootAccent: string = '';
```

**为什么 ① 和 ② 都会失败**：它们都把求值时机放在了**会被重复执行的代码**里 ——
① 在组件的（重）渲染路径上，② 在页面模块的求值路径上。
只要宿主会重新执行这段代码，「定死」就无从谈起。

**结论**：在 ArkUI 里，**「什么时候求值」比「值从哪来」更具决定性**。
要展示一个「停在过去」的值，唯一稳的位置是**在组件与模块之外只写一次**
（启动阶段写 AppStorage，或在真正的单例里缓存）。

**反过来说，这条正面意义更大**：想让颜色实时跟随，
唯一可靠的做法就是**在表达式里读到订阅变量**（见 §3 / A1）——
其余所有「看起来像常量」的写法都可能悄悄失效。

> 调试建议：把捕获到的**色值直接显示出来**（本 Demo 的对照色块下面各写了一行 hex）。
> 色块有没有变不好判断时，看数字最快 —— 这次就是靠它把三次试错分辨清楚的。

---

## B. 「沉浸光感没生效」

### B1. 卡片完全没有光感

按顺序查这四条（Demo 的诊断行会把它们都列出来）：

| 检查 | 说明 |
| --- | --- |
| 系统 API ≥ 26？ | `uiMaterial` 是 26.0.0 起的接口 |
| `module.json5` 的 metadata 是 `enable` 吗？ | `ohos.arkui.UIMaterial.state`；**`disable` 时主动设置的材质也一并失效**，只能改配置重装 |
| 应用内「全局沉浸光感」开着吗？ | `AppStorage['immersiveLightEnabled']` |
| 材质对象构造成功吗？ | 失败时 `getImmersiveMaterial()` 返回 `null`（不会静默变 `Material.empty`） |

**另**：设备算力档位会影响材质表现；`ImmersiveOptions.interactive` + `lightEffect`
在部分设备上会让材质**整块消失**（那就退回静态材质）。

### B2. 内容区卡片没光感，但弹窗/底栏有

**根因**：**生效范围**。`Column` / `Row` 等布局容器在**页面内容区**不生效。
系统日志：`Material inactive: out of scope. Use component in navigation title bar or Tabbar.`
**修法**：卡片改用 `Toggle(ToggleType.Button)` 承载（见 `MaterialCardLayer`）。

### B3. 材质被一块灰盖住 / 完全看不见

**根因**：材质的视觉层级在 `backgroundColor`、`backgroundBlurStyle` **之下**。
**修法**：承载层显式 `.backgroundColor(Color.Transparent)`；
`bindSheet` 要显式 `backgroundColor: Color.Transparent`（**默认是 `Color.White`**）。

### B4. 设了 `systemMaterial` 却没反应

**根因**：`systemMaterial` 被后面的样式属性覆盖了。
**修法**：用 `attributeModifier` 把它挂在**属性链最末**。

### B5. 按下的流光完全看不见

**根因**：材质**不采样同一 `Stack` 里的兄弟节点**（采样的是组件背后的窗口内容）。
**修法**：流光层压在材质**之上**、内容**之下**。

### B6. 卡片变成一块死板色块（材质不可用的机型上）

**根因**：降级路径没做全。
**修法**：三件事一起做 —— ① 外壳底色在透明/半透明间切换；② 不生效时补 `backgroundEffect` 模糊；
③ 底色本身必须带透明度（≈70%），否则模糊被完全盖住。
**只做一半的两种失败**：只加模糊而底色不透明 → 模糊看不见；只调透明而不加模糊 → 一层薄纱，背后什么都没有。

### B7. 卡片在材质生效的机型上**直接丢掉背景**

**根因**：用了 `cardGlassEffect` / `cardGlassBorderColor` / `cardGlassShadow` 三件套，
但**没有配 `CardSurface`** —— 三件套此时统一返回「无效果」，而没有任何东西接替它们。
**修法**：两者必须成对出现（自检脚本第 1 项检查的就是这个）。

### B8. 卡片「莫名其妙」变高 / 卡片间距变大

**根因**：`CardSurface` 的**内容为空**。内层 `ToggleType.Button` 有 **28vp 默认高度**，
内容为空时仍把外壳撑出 ≈28vp，外层 `Column({ space: 12 })` 再叠间距 → 多出 ≈80vp 空档。
**只在条件不成立时出现**，很难一眼看出。
```ets
// ✗ 条件不成立时留下一个 28vp 的空壳
CardSurface({ radius: HwRadius.card }) { if (this.items.length > 0) { ... } }
// ✓ 条件写在 CardSurface 外面
if (this.items.length > 0) { CardSurface({ radius: HwRadius.card }) { ... } }
```
**参考工程多处已修正**（`AppearanceSettingsPage`、`AggregatePage` 等页面都有这类条件卡片）。
> ⚠️ 上一版这里写的是「已修正 7 处（`AppearanceSettingsPage` 4 处、`AggregatePage` 3 处）」——
> 这个 **4+3 的拆分无法复现**：两个文件里 `CardSurface(` 调用分别是 20 处与 6 处，
> 按「条件写在里面还是外面」也没有得到 7 这个数。
> 没有可复现的口径就不该写成精确数字，故改为不定量描述。

### B9. 「卡片沾色」开关点了没反应

**根因**：把沾色**混进了卡片底色**。材质生效时外壳底色是**透明的**，混进去的颜色根本画不出来。
**修法**：沾色改为**叠在材质之上的一层**（`CARD_TINT_KEY` + `cardTintLayer()`）。
另外沾色层必须 ① `LayoutPolicy.matchParent`（**不能用 `'100%'`**，百分比按父级可用尺寸解析会把卡片顶大）；
② 自己带圆角（外壳为了不裁掉材质投影没有 `clip`）。

### B10. 小尺寸芯片看起来「背后顶了一层影子」

**根因**：`ImmersiveMaterial` 的 `applyShadow` **默认为 `true`**。
**修法**：小元件传 `layerShadow: false`（实现上单独缓存一档不带阴影的材质，不要关掉全局阴影）。

### B11. 按压时卡片自己变大

**根因**：流光曾写成「比卡片大一圈 + `.position()` 甩到外面」。
`Stack` 的尺寸取**最大子节点**，`position` 只改摆放位置、**不改布局尺寸**，多出来的一圈全算进了卡片。
**修法**：①（本工程采用）光留在卡片内，用 `matchParent` + 自带 `borderRadius` 收住；
② 必须溢出时，把溢出内容放进 `.width(0).height(0)` 的锚点容器再 `position`。

### B12. 手指不动、页面滚动，光斑黏在卡片原处

**根因**：只用了按下那一瞬算出的卡片原点。
**修法**：用 `onAreaChange` 的**位移增量**维护卡片原点（只取增量，因为 `globalPosition` 与
`windowX/Y` 未必同一套原点，但**变化量一致**）。

### B13. 抬起手指后留着一块不消失的光斑

**根因**：只处理了 `TouchType.Up`，漏了 `TouchType.Cancel`（例如被手势打断）。
**修法**：Up 与 Cancel 都要熄灭。

### B14. 光效溢出到卡片之外，像「糊了一块」

**根因**：在**没有沉浸光感材质的区域**（页面底色、卡与卡的缝）画环境光。
那里的观感不是「玻璃被照亮」而是「凭空出现一块亮斑」。
**修法**：光只留在被按的卡片里，并且可见性判定要包含「材质生效」这一条
（低版本/开关关闭/材质构造失败时一点光都不画）。

### B15. 半模态面板全透明，只剩一层模糊，文字像悬在遮罩上

**根因**：`bindSheet` 的 `backgroundColor` 设成了 `Color.Transparent`，
而面板内容也是一个透明的 `Column`。沉浸光感生效时材质由 `sheetSystemMaterial()` 补上，
**材质不可用（低版本 / 开关关闭 / 构造失败）时没有任何东西接替它**。
**修法**：内容用 `MaterialSheetPanel` 包一层 —— 它在材质生效时让出底色，
不生效时用自己的兜底底色（`cardSurface`，回落 `HwGlassCardColor.surface`）：

```ets
.bindSheet($$this.showSheet, this.accentDialog(), {
  height: 360,
  backgroundColor: Color.Transparent,   // ← 这里透明的前提是下面有兜底
  blurStyle: sheetBlurStyle(),
  systemMaterial: sheetSystemMaterial()
})

@Builder
accentDialog() {
  MaterialSheetPanel({ panelPadding: HwSpace.lg }) {   // ← 兜底底色在这里
    Column() { /* 面板内容 */ }
  }
}
```

---

## C. 「低版本闪退 / 白屏」

### C1. 应用启动即闪退（低版本设备）

**根因**：模块级常量触碰了 `uiMaterial`。
```ts
export const MATERIAL_STYLE = uiMaterial.ImmersiveStyle.THIN;   // ✗ 启动即闪退
```
`uiMaterial` 是 API 26 才有的接口，低版本上是 `undefined`，取 `.THIN` 抛出的
`TypeError` 发生在**任何 try/catch 之外** → 整个模块加载失败。
**修法**：惰性求值 + 只做类型断言、**不写类型标注**：
```ts
function materialStyle(): uiMaterial.ImmersiveStyle {
  return uiMaterial.ImmersiveStyle.THIN as uiMaterial.ImmersiveStyle;
}
```
（带类型标注的写法在低版本 SDK 上还会出现类型不相容的**编译错误**。）

### C2. 进入主页即闪退

**根因**：`hdsMaterial` 命名空间是 API 23 起的，低版本上是 `undefined`，
而 `hdsMaterial.MaterialType.ADAPTIVE` 这种**成员读取**会抛 `TypeError`；
它又是在 `build()` 期间求值的 → 整个页面渲染失败。
> `hdsMaterial` 的 **import 本身不报错**，所以编译期看不出来。

**修法**：版本安全工厂，低于 23 返回 `undefined`，调用方据此**不写** `systemMaterialEffect`：
```ts
function hdsAdaptiveMaterialParams(): SystemMaterialParams | undefined {
  if (!isSdkAtLeast(23)) return undefined;
  return { materialType: hdsMaterial.MaterialType.ADAPTIVE,
           materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE };
}
```

### C3. 诊断函数在低版本上让整页渲染失败

**根因**：诊断函数里读了 `uiMaterial.MaterialState`，而它在 API < 26 不存在；
诊断函数在页面 `build()` 期间被调用 → 抛出即整页失败。
**修法**：诊断函数**提前返回**，任何版本调用都不抛异常。

### C4. 深色模式「不跟随系统」了，怎么也回不去

**根因**：用了布尔开关，一旦被拨动过就永久生效。
**修法**：改成三态字符串（`system` / `light` / `dark`），
「跟随系统」时下发 `COLOR_MODE_NOT_SET` 把配色权交还系统。

### C5. 系统深浅色变化后进入死循环 / 自激

**根因**：`onConfigurationUpdate` 里又调了 `setColorMode()`。
**修法**：该回调会被 `setColorMode()` **同步触发**，里面**不能**再调它。

---

## D. 语法 / 编译期

### D1. 自定义组件尾随闭包后不能链式挂属性

```ets
// ✗ 编译错误：尾随闭包之后不能再链式挂属性
CardSurface({ radius: HwRadius.card }) { ... }.margin({ top: 8 })

// ✓ 在外层再包一个容器，把外边距挂在容器上（参考工程的色块就是这么处理的）
Column() {
  CardSurface({ radius: HwRadius.card }) { ... }
}
.margin({ top: 8 })
```
> ⚠️ 不要给组件加一个「万能外边距」参数来绕开这件事。
> 早先的 `CardSurface` 就自造过一个 `cardMargin: Length`，结果两头不讨好：
> `Length` 只接受 `string | number | Resource`，**收不了 `{ top: 8 }` 这种对象**；
> 而写成 `Margin | Length` 又会触发 D2 的 `arkts-no-untyped-obj-literals`。
> 该参数**无人调用**，已作为死 API 从 `CardSurface` 删除 —— 外层包一层才是最省事的写法。

### D2. 自定义组件的参数不要用联合类型

`@Prop accentColor: string` 没问题；但 `Padding | Length` 这类联合类型会让 ArkTS 在传对象字面量时
报 `arkts-no-untyped-obj-literals`。同理 `@Prop` 的默认值要写具体类型。

### D3. 注释里的装饰线误用斜杠，块注释提前结束

```ts
/**
 * 第一段
 * ──────────      ← ✓ 制表符 U+2500
 * /─────────      ← ✗ 这是一个 `* /`，会把块注释**提前结束**
 */
```
现象是一串莫名其妙的语法错误，行号还指向注释**之后**。视觉上 `* /` 与 `*/` 极难区分。
> 本次整理的 `tools/arkcheck.mjs` 专门检查这一条 —— 因为编写过程中真的踩到了。

### D4. 在注释里写出注释结束符

写「如何转义注释结束符」这类说明时，很容易真的把注释结束掉：

```ts
/* 说明：注释里的结束符要写成 转义形式，否则…… */   // ← 这里就已经结束了
```
现象同样是「语法错误出现在注释之后」。**写文档注释时要格外小心**。

### D5. 尾随闭包 + `bindSheet` 的挂载位置

`bindSheet` 挂在**容器**（`Stack` / `Column` / `HdsNavigation`）上最稳，
不要挂在自定义组件尾随闭包之后。

### D6. `@Entry` 的 `build()` 根节点必须是**容器组件**

编译报错原文：

```
In an '@Entry' decorated component, the 'build' method can have only one root node,
which must be a container component.
```

```ets
// ✗ 根节点是自定义组件 → 编译不过
@Entry
@Component
struct ThemeLabPage {
  build() {
    DemoScaffold({ title: '…' }) { /* … */ }
  }
}

// ✓ 外面套一层容器
@Entry
@Component
struct ThemeLabPage {
  build() {
    Stack() {
      DemoScaffold({ title: '…' }) { /* … */ }
    }
    .width('100%')
    .height('100%')
  }
}
```

**这条坑特别隐蔽**：单文件看不出任何问题，`Column`/`Stack`/`Row` 这些容器才能当根。
（顺带好处：`bindSheet` / `bindContentCover` 这类挂在容器上更稳，见 D5。）

### D7. `SymbolGlyph.fontColor()` 收的是**数组**，不是单个颜色

```
No overload matches this call.
  Overload 1 of 2, '(value: ResourceColor[]): SymbolGlyphAttribute'
  Argument of type 'string' is not assignable to parameter of type 'ResourceColor[]'
```

```ets
// ✗ Text 收单个颜色，SymbolGlyph 不收 —— 两者签名不一样，别顺手复制
SymbolGlyph($r('sys.symbol.chevron_right')).fontColor(hwTextSecondary(this.isDarkMode))

// ✓
SymbolGlyph($r('sys.symbol.chevron_right')).fontColor([hwTextSecondary(this.isDarkMode)])
```

### D8. 「符号在别的文件里导出了，本文件忘了 import」

真实编译报错（Demo 里一次犯了 3 处）：

```
Cannot find name 'CardSurface'.            At components/DemoScaffold.ets:260:5
Cannot find name 'immersiveCardsActive'.   At pages/ImmersiveShowcasePage.ets:144:26
Cannot find name 'PRESS_GLOW_STORAGE'.     At utils/SystemMaterial.ets:100:36
```

**为什么静态自检当时全绿**：原来的 `importcheck.mjs` 只查了**一个方向** ——
「import 进来的符号，源模块是否真的导出了」。
反方向（本文件用了却没 import）**根本没查**，于是 3 个错误全部漏过。

修法是给 `importcheck.mjs` 加了第三条规则：拿「项目内所有导出符号名」当候选集，
看每个文件用到候选名时，是否在本文件声明过或导入过。
**两个实现细节**（都踩过）：

1. 必须扫**掩码后**的代码 —— 否则注释里提到 `CardSurface` 会误报；
2. 但掩码会把模板串 `${...}` 里的真代码一并清掉，所以还得把插值内部的
   代码区间**还原回来**再扫 —— 否则 `` Text(`${immersiveCardsActive()}`) `` 会漏报。

> 25 个 UI 文件、一万多行的工程里，这类错误编译一次就能全暴露；
> 没有编译条件时，就靠这条规则兜住。

---

## E. 持久化 / 状态

### E1. 开关「点一下弹回去」

**根因**：该用 `@StorageLink` 却用了 `@StorageProp`。

| 装饰器 | 方向 | 能赋值吗 |
| --- | --- | --- |
| `@StorageProp('k')` | 存储 → 组件，**单向** | ✗ 赋值不生效 |
| `@StorageLink('k')` | 存储 ⇄ 组件，**双向** | ✓ 赋值即写回存储 |

**约定**：读用 Prop，写用 Link。

### E2. 重启后设置丢了

**根因**：只写了 `AppStorage` 没落盘，或只落盘没写 `AppStorage`。
**修法**：设置项标准写法「三连」（落盘 → 更新订阅键 → 重算并广播）。

### E3. 首屏颜色不对，切个页面才变对

**根因**：启动初始化漏了 `applyAppTheme` + 广播 `accentColor`（或没放在 `loadContent` 之前）。
**修法**：`EntryAbility.onCreate` 里必须做完「打开存储 → 下发系统配色 → 建订阅键 → 应用主题 → 广播」。

### E4. `preferences` 存数组失败

**根因**：ArkTS 的 `preferences` **不直接支持数组**。
**修法**：存 JSON 字符串，读入时 `JSON.parse` 失败一律回落默认值。

### E5. 开关「拨完闪一下又弹回去」，或者拨了完全没反应

**根因**：**`Toggle` 的 `isOn` 不是双向绑定**（要 `$$` 才是）。
只写 `Toggle({ isOn: this.x })` 而不写 `.onChange`，拨动只会改**组件内部视觉**，
`x` 根本不会变 —— 于是重渲染时弹回原状，也不会持久化。`Slider` 的 `value` 同理。

```ets
// ✗ 拨了没用：x 永远不会变
Toggle({ type: ToggleType.Switch, isOn: this.immersiveLightEnabled })

// ✓ 显式写 onChange（或 `isOn: $$this.x`）
Toggle({ type: ToggleType.Switch, isOn: this.immersiveLightEnabled })
  .onChange((value: boolean): void => {
    this.immersiveLightEnabled = value;              // @StorageLink 赋值即写回
    AppearanceStore.setBoolean('immersiveLightEnabled', value);  // 落盘
  })
```

**例外（不算错）**：材质**承载层**用 `Toggle({ type: ToggleType.Button, isOn: false })`
—— `isOn` 是**字面量**而不是绑定状态变量，它只是被借来当画布，刻意不需要 `onChange`。

> 演示工程里这一条最初真的犯了（`Index` 与 `ImmersiveShowcasePage` 各一处），
> 现已修正，并把「带注释干扰的精确范围判定」写进了 `tools/arkcheck.mjs` 自动检查。

### E6. 改了开关/字体，界面要等切页面才变

**根因**：**声明了 `@StorageLink` 但没在 `build()` 里读它，等于没有声明** ——
ArkUI 按表达式登记依赖，没被读到就不构成依赖。

```ets
// ✗ 声明了但 build 里从不读 → 拨这个开关不会让卡片重绘
@StorageLink('immersiveLightEnabled') immersiveLightEnabled: boolean = true;

// ✓ 在 build 的判定里真的读它
private materialActive(): boolean {
  return this.immersiveLightEnabled && immersiveMaterialActive();
}
```
> ⚠️ 注意右边不要只写 `isApi26OrAbove()`：版本够不代表材质**构造成功**。
> 判定为真时组件会把底色让成 `Color.Transparent`（材质在底色之下），
> 若只按版本判断而材质恰好构造失败（机型不支持 `ImmersiveMaterial`），
> 就会形成「底色已让出、材质画不出来」的全透明组件。
> 用 `immersiveMaterialActive()`（版本 + 开关 + 构造成功）才能正确走降级分支。
> 详见 B7。

参考工程三个承载层都读了（`CardSurface:121`、`IconCircleButton:66`、`MaterialCard:94`），
所以切换沉浸光感时卡片表面**立刻**更换；字体子系统同理 ——
每个页面重复声明那 6 个字体键，正是因为 `appFontFamily()` 在 `build()` 里读它们。

**自查**：`tools/arkcheck.mjs` 的「声明后从未读取的字段」规则会报出这类字段。
该规则**按 struct / class 作用域**统计（不能按整文件 —— 同一字段名会出现在多个
struct 里，A 的读取会把 B 里的死字段洗白；本工程的 `ThemedCard.accentColor`
正是这样被漏掉的，现已修正规则并删除该字段）。

**双向反测**：`node tools/selftest-arkcheck.mjs` ——
`tools/selftest/bad/` 下故意写坏的样本必须被报出，`tools/selftest/good/` 下
写法正确的样本必须零问题。只跑「工程全绿」证明不了规则有效：
一条**永远不报错**的规则看起来同样是全绿。

---

## G. 布局与安全区

### G1. 顶部返回栏被状态栏（时钟/电量）压住

**根因**：根节点调了 `expandSafeArea` 顶进状态栏区域，但顶栏自身没有加安全区内边距。
**修法**：两件事**必须配套**（参考工程 20 处 / 11 个文件统一这么写）：

```ets
Stack() { /* … */ }
  .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])   // ① 顶进去

Row() { IconCircleButton(...) ; Text(标题) ; Blank() }
  .height(56 + this.statusBarHeight)                            // ② 高度含状态栏
  .padding({ top: this.statusBarHeight, left: 16, right: 16 })  // ③ 内容压到状态栏之下
```

滚动内容再用 `Blank().height(56 + this.statusBarHeight)` 让位，否则首屏内容会被顶栏遮住。

**反向的坑**：只加 ②③ 而不加 ①，内容会**双重下移**（系统已经让过一次位）——
表现为顶部多出一大块空白。`statusBarHeight` 由 `EntryAbility` 通过
`uiContext.px2vp(systemArea.topRect.height)` 发布到 `AppStorage`。

**只声明不使用的典型**：`@StorageProp('statusBarHeight') statusBarHeight` 写了却没在
`build()` 里用 —— 因为没读，它连依赖都登记不上，等于纯粹的死代码（见 E6）。

---

## F. 排查工具箱

```powershell
# Demo 自带（纯静态，改完界面即可跑）—— 在仓库根目录执行
node tools/arkcheck.mjs    entry/src/main/ets
node tools/importcheck.mjs entry/src/main/ets
node tools/configcheck.mjs .
node tools/snippet-audit.mjs entry/src/main/ets
node tools/selftest-arkcheck.mjs            # arkcheck 的双向反测

# 针对参考工程（CLink **不在本仓库内**，需先自行 clone 到仓库上一级）
git clone https://github.com/MrCashmere/CLink ../CLink
node tools/foreach-audit.mjs ../CLink/entry/src/main/ets
node tools/ui-stats.mjs      ../CLink/entry/src/main/ets    # 复现 UI-INDEX 里的数字
node ../CLink/scripts/theme_audit.mjs                        # 参考工程自带的 6 项体检

# 找残留的带色相硬编码色值（命中的不全是问题，带色相的才要改）
#   grep -rn "'#[0-9A-Fa-f]\{8\}'" entry/src/main/ets/
```

**真机排查沉浸光感**：设置页那行诊断文字会把各段判定条件摊开
（API / 材质 / 状态 / 开关 / 流光 / 承载），形如：

```
API=26 材质=已构造 状态=非DISABLE 开关=开 流光=#0A59F7 承载=下发材质
```

> ⚠️ 诊断文案的两个入参必须是**订阅值**，否则它自己不会随切色/拨开关刷新，会停在上一档。
