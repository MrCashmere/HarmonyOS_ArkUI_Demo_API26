# 教学：ArkUI 全应用主题色与沉浸光感

> 以 CLink（羊绒互传）的真实实现为教材，**从零讲清两套机制**：
> ① 全局主题色 + 深色模式；② API 26 沉浸光感材质。
>
> 配套可运行 Demo：[README.md](../README.md)（本仓库根目录，4 个页面，逐条对照讲解）。
> UI 文件清单见 [UI-INDEX.md](UI-INDEX.md)，坑位速查见 [PITFALLS.md](PITFALLS.md)。

---

## 目录

- [第 0 章 先跑起来](#第-0-章-先跑起来)
- [第 1 章 问题的本质：ArkUI 不会因为「对象属性变化」而刷新](#第-1-章-问题的本质arkui-不会因为对象属性变化而刷新)
- [第 2 章 主题色：值与通知两条线](#第-2-章-主题色值与通知两条线)
- [第 3 章 依赖登记：为什么必须「把订阅值传进函数」](#第-3-章-依赖登记为什么必须把订阅值传进函数)
- [第 4 章 深色模式：与主题色共用同一条广播链](#第-4-章-深色模式与主题色共用同一条广播链)
- [第 5 章 沉浸光感：生效范围是一切的起点](#第-5-章-沉浸光感生效范围是一切的起点)
- [第 6 章 把材质贴到卡片上：承载层](#第-6-章-把材质贴到卡片上承载层)
- [第 7 章 按压跟手流光](#第-7-章-按压跟手流光)
- [第 8 章 持久化与启动顺序](#第-8-章-持久化与启动顺序)
- [第 9 章 字体子系统：第二条横切机制](#第-9-章-字体子系统第二条横切机制)
- [第 10 章 十六条铁律（速记）](#第-10-章-十六条铁律速记)

---

## 第 0 章 先跑起来

```
HarmonyOS_ArkUI_Demo_API26/            ← 本仓库根目录
├── entry/src/main/ets/
│   ├── utils/DesignTokens.ets         ← ① 令牌层（主题色核心）
│   ├── utils/SystemMaterial.ets       ← ② 材质层
│   ├── components/MaterialCard.ets    ← ③ 承载层 + 哨兵
│   ├── components/CardSurface.ets     ← ③ 卡片外壳（含流光）
│   ├── components/IconCircleButton.ets← ③ 圆形按钮
│   ├── components/DemoScaffold.ets    ← ③ 页面脚手架
│   ├── storage/AppearanceStore.ets    ← ④ 持久化
│   ├── entryability/EntryAbility.ets  ← ⑤ 启动初始化
│   └── pages/{Index,ThemeLabPage,ImmersiveShowcasePage,ThemeSettingsPage}.ets
├── docs/                              ← 本教学正文 / 索引 / 坑位速查
└── tools/                             ← 静态自检（arkcheck / importcheck / configcheck 等）
```

**运行**：DevEco Studio 打开本仓库根目录，勾选自动签名
（File → Project Structure → Signing Configs → Automatically generate signature），
然后运行到 API 26 真机。**没有 API 26 设备也能跑**——会自动降级为毛玻璃。

**三个演示页对应三块知识**：

| 页面 | 学什么 |
| --- | --- |
| ① 颜色令牌实验室 | 哪些写法跟随主题色、哪些不跟随（含**反面对照**） |
| ② 沉浸光感与材质承载 | 为什么卡片要用 Toggle 当背板、流光为什么要压在材质之上 |
| ③ 外观设置 | 输入端：颜色选择器、三态深色、光感开关、持久化 |

---

## 第 1 章 问题的本质：ArkUI 不会因为「对象属性变化」而刷新

需求很朴素：**用户在外观设置里选一个颜色，全应用立即变色，无需重启。**

按常规思路，把颜色集中到一个对象里，改它就行：

```ts
export const HwColor = { primary: '#0A59F7' };
// 用户选了粉色
HwColor.primary = '#E86A92';   // ← 界面纹丝不动
```

**为什么不动**：ArkUI 的局部更新是**按表达式登记依赖**的。
它只认「状态变量」（`@State` / `@Prop` / `@StorageLink` / `@StorageProp` …）。
`HwColor` 是个模块级普通对象，读 `HwColor.primary` 这个动作**不会被登记**，
所以改它不会让任何表达式重新求值。

再加一层，用 `AppStorage` 广播与 `@Watch`：

```ts
@StorageProp('accentColor') @Watch('onAccentColorChanged') accentColor: string = '';
onAccentColorChanged(): void { reloadAppTheme(); }   // ← 回调确实被调了
```

**为什么还是不动**：`@Watch` **只负责调回调**，它**不会让组件重新求值**。
回调里可以更新数据，但没有任何渲染表达式被标记为脏，界面自然不重建。

于是第一版机制自然成形 —— 把两者接起来：

> **`HwColor.primary` 负责「值」**（重建时去哪里取色）
> **`AppStorage['accentColor']` 负责「通知」**（通知谁该重建）
> **两者缺一不可。**

---

## 第 2 章 主题色：值与通知两条线

### 2.1 生效链路

```
用户点色块 / 输入 RRGGBB
      │
      ▼
设置页写 @StorageLink('accentKey' | 'accentCustom')     同步进 AppStorage
      │
      ▼
AppearanceStore.setString(...)                          落盘持久化
      │
      ▼
applyAccentNow() → reloadAppTheme()
      ├─ effectiveAccentColor()  算出最终 #RRGGBB
      ├─ applyAppTheme()         改写 HwColor（模块级对象，**静默**）
      └─ AppStorage.setOrCreate('accentColor', resolved) ← 唯一的「通知」
      │
      ▼
所有订阅 accentColor 的页面/组件被标记为脏并重建
      │
      ▼
重建时读到新的 HwColor.primary + accentColor
```

**为什么不会死循环**：`@Watch` 回调里再次 `reloadAppTheme()` 时算出的值相同，
`setOrCreate` 写入**等值**不会触发变更通知。

### 2.2 支点：颜色常量必须是「可变对象」

```ts
// ✓ 可以运行时改写
export const HwColor: HwColorPalette = { primary: '#0A59F7', /* ... */ };

// ✗ 字符串常量，运行时改不了
const PRIMARY = '#0A59F7';
```

这是「主题色能不能做出来」的分水岭。

### 2.3 四条派生规则

| 场景 | 做法 | 为什么 |
| --- | --- | --- |
| 主题色的**浅色底** | `withAlpha(accent, 0.06~0.15)` | 写死半透明色（如 `'#1A3379B7'`）切色后会露出旧色的底 |
| 页面**背景淡染** | `mixHex(base, accent, 0.12/0.18)` | 直接铺主题色会压过正文；**刻意很淡** |
| 主题色上的**文字** | `onAccentColor(accent)` | 涟漪粉 `#FAD6E4`、流荧绿 `#88E4D4` 很浅，压白字看不清——按 sRGB 亮度自动切黑/白，阈值 0.62 |
| 深色模式下的主题色 | `mixHex(accent, '#FFFFFF', 0.4)` 抬亮 | 否则浅色预设在深色底上太暗看不清 |

### 2.4 深色分支也必须由主题色派生

很多实现只把**浅色**分支接了主题色，深色分支写死一个蓝。后果是浅色预设在深色模式下「不像自己」。
正确做法：深色前景 = 主题色向白抬亮 40%，深色按钮底 = 主题色向黑压深 32%
（两者都经过 WCAG 对比度校验，见 `DesignTokens.ets` 的注释表）。

### 2.5 控件自带选中色：**最容易漏的一项**

SDK 的默认值是 `$r('sys.color.ohos_id_color_emphasize')`（系统强调色），
**不显式覆盖就永远是蓝的**：

| 控件 | 必须覆盖 |
| --- | --- |
| `Toggle`（Switch） | `.selectedColor(...)` |
| `Slider` | `.selectedColor()` + `.trackColor()` + `.blockColor()` |
| `TextInput` | `.caretColor(...)` |
| `Button(EMPHASIZED)` | `.backgroundColor(...)` + `.fontColor(...)` |
| **`ToggleType.Button` 承载层** | `.selectedColor(Color.Transparent)` ← **刻意不用主题色** |

参考工程首次全量体检就发现了 5 处遗漏（「更优美的卡片」「卡片阴影描边」等 5 个开关）。
Demo 的 `ThemeLabPage` B 段把这三类控件并排放在一起，切色即可验证。

---

## 第 3 章 依赖登记：为什么必须「把订阅值传进函数」

这是最容易写错、也最难自查的一条。

### 3.1 坏写法与好写法

```ets
// ✗ 切主题色后，这个按钮的底色不会变
.backgroundColor(hwPrimaryButton(this.isDarkMode))

// ✓ 取值逐档一致，但表达式里读了 accentColor，切色时会重新求值
.backgroundColor(resolvePrimaryButtonColor(this.isDarkMode, this.accentOrPrimary()))
```

`hwPrimaryButton(isDark)` 是**普通纯函数**，内部读模块级 `HwColor`；
这个表达式里**没有订阅变量**，ArkUI 按表达式登记依赖时登记不上。

参考工程实际报障的两处正是这类：主页设置页的「检查权限」按钮、
「默认通用动态图片格式」的选中芯片 —— 它们的**字色**用了
`onAccentColor(this.accentOrPrimary())` 所以会变，**底色**却停在旧色。
同一行里两种写法并存，恰好证明 ArkUI 是**按表达式**分别登记依赖的。

### 3.2 三个「必须走订阅版」的位置

| 位置 | 原因 |
| --- | --- |
| 页面底色 | 直接读 `HwColor.background` 只登记了 `isDarkMode` → 切色时底色不刷新（而新进页面又是对的，极易误判成「刷新不及时」） |
| 底栏图标高亮 | `HdsTabs` 没有 `selectedColor`，高亮要**单独下发**，且必须读 `this.accentColor` |
| 流光颜色 | `pressLightColor(订阅开关, 订阅主题色)` —— 纯函数，订阅值由调用方传入 |

### 3.3 `AccentColorSentinel`：让页面真正重新求值

```ets
@Component
export struct AccentColorSentinel {
  @StorageProp('accentColor') accentColor: string = '';
  build() {
    Row().width(0).height(0).opacity(0)
      .hitTestBehavior(HitTestMode.None)
      .accessibilityLevel('no')
      .backgroundColor(this.accentColor.length > 0 ? this.accentColor : Color.Transparent)
  }
}
```

它零尺寸、不参与布局与命中测试，**存在的唯一目的是「在渲染树里读一次订阅键」**。
放在页面根 `Stack` 的**第一个子节点**即可。

**能力边界**：它能让页面**内容**的表达式重算，
但**不会**让页面根节点自身的属性重新求值 —— 页面底色仍然必须走 `resolvePageBackground()`。

### 3.4 `ForEach` 的 key：第二种「不刷新」的成因

`ForEach` **会复用 key 相同的项**：键不变就不重建子节点，
子节点里那些不依赖状态变量的表达式**永远不会被重新求值**。

```ets
// ✗ 切色后列表项里的按钮底色停在旧色
}, (file: IncomingFile) => file.savedPath + ':' + file.name)

// ✓ 把主题色编进 key
}, (file: IncomingFile) => file.savedPath + ':' + file.name + ':' + this.accentColor)
```

**同一个坑还有第二种表现：选中态本身就是状态。** 主题色选择器里的色块就是例子 ——
色块内容没变，但「哪个带对号」变了：

```ets
// ✗ 对号永远停在上一个被点的色块上
}, (preset: AccentPreset) => `preset_${preset.key}`)

// ✓ 选中态编进 key，被选中/被取消的两项都会重建
}, (preset: AccentPreset) => `preset_${preset.key}_${this.accentKey === preset.key ? 1 : 0}_${this.accentColor}`)
```

自定义色块还要**同时**带上昵称（改完昵称色块上的字才会变）：

```ets
}, (entry: AccentCustom) =>
  `custom_${entry.hex}_${entry.name}_${this.isCustomSelected(entry.hex) ? 1 : 0}_${this.accentColor}`)
```

**判断方法**：问自己「这个列表项的外观会不会在**数据不变**的情况下改变」。
只要会（选中、展开、加载中、禁用、跟随主题色），key 就必须把它编进去。

> 参考工程实测：23 处 `ForEach` **全部**已编入 `accentColor`
> （可用 `tools/foreach-audit.mjs` 独立复核）。

---

## 第 4 章 深色模式：与主题色共用同一条广播链

深色模式和主题色**不是两套机制**，而是同一条链上的两个键：
`applyAppTheme(isDark, accent)` 一次同时改写 `HwColor.primary` 与
`background / surface / textPrimary / textSecondary / HwGlassCardColor.*`，
再由 `accentColor` + `isDarkMode` 两个键一起广播。

### 4.1 为什么必须是三态字符串，而不是布尔开关

**布尔一旦被用户拨动过就永久生效，再也没法回到「跟随系统」**
（表现为「深色模式不跟随系统」，只能靠重置设置救回来）。

三态让「跟随系统」始终是一个**能选回来的状态**：

```ts
export const DARK_MODE_PREF_STORAGE = 'darkModePreference';  // 'system' | 'light' | 'dark'
```

### 4.2 三个必须同时做对的点

1. **平台配色要和自绘颜色一起下发。**
   `setColorMode()` 管系统控件（弹窗、输入法、滚动条），`applyAppTheme()` 管自绘颜色。
   只做后者 → 「自绘是浅色、系统弹窗是深色」的错配。

2. **`COLOR_MODE_NOT_SET` 表示交还给系统。**
   用户没选过时下发这个值，系统切深浅色应用会自动跟；
   一旦下发过明确值，就**不再跟随**。

3. **`onConfigurationUpdate` 里也要走 `resolveDarkMode()`，且内部不能再调 `setColorMode()`**
   —— 该回调会被 `setColorMode()` **同步触发**，否则自激。

### 4.3 切深色时最容易漏的一处

```ts
applyAppTheme(enabled);                       // ✗ 背景染色被重置回默认
applyAppTheme(enabled, this.currentAccent()); // ✓ 必须带上当前主题色
```

**排查方式**：切一下深色模式，如果页面背景从「主题色淡染」变回固定浅灰，就是这里漏了。

---

## 第 5 章 沉浸光感：生效范围是一切的起点

> **如果不理解「生效范围」，后面所有设计看起来都是没必要的绕路。**

### 5.1 系统行为变更（targetSdkVersion ≥ 26）

只有这两类组件能在页面内**全部区域**生效：

| 类别 | 例子 |
| --- | --- |
| 弹窗类组件与接口 | `AlertDialog`、`CustomDialog`、`bindSheet`、`Popup`、菜单、`Toast`、`PromptAction` |
| 按钮与选择类 | `Button` / `Select` / **`Toggle`** / `Slider` / `ChipGroup` / `SegmentButton` |

**其他组件（含 `Column` / `Row` 等布局容器）只在 Navigation/NavDestination 标题栏、
或横向 Tab 的底部悬浮 TabBar 中生效。** 在别处设置会看到系统日志：

```
Material inactive: out of scope. Use component in navigation title bar or Tabbar.
```

> 这条约束直接解释了「内容区卡片为什么不能把 `systemMaterial` 挂在 `Column` 上」。

### 5.2 为什么是 `ToggleType.Button`

官方对三种 ToggleType 的说明：

| 类型 | 行为 |
| --- | --- |
| `Checkbox` | 当前**未适配**沉浸光感，设置后无效果 |
| `Switch` | 材质参数仅作为开启标记，实际用组件内部预设视觉参数，**只覆盖开关本体** |
| **`Button`** | 效果与 Button 组件相同，影响背景色、边框、阴影 → **卡片要的就是它** |

而且 SDK `toggle.d.ts` 明确写着：

> *"This component can contain child components only when ToggleType is set to Button."*

**既能全区域生效、又能包含子组件** —— 这让 `ToggleType.Button` 成为内容区唯一的承载形态。

### 5.3 应用级开关与「自锁」教训

`module.json5` 里配置 metadata：

```json5
"metadata": [{ "name": "ohos.arkui.UIMaterial.state", "value": "enable" }]
```

`uiMaterial.getMaterialInfo().state` 读的就是它：`DEFAULT` / `ENABLE` / `DISABLE`。

> ⚠️ **历史坑（已在参考工程移除）**：曾把「`state === DISABLE`」当成
> 「本应用不能渲染」，直接返回 `Material.empty`，又把这个状态用作降级条件
> —— 等于**应用自己把光感关掉**，是个自锁。
> 现在 `MaterialState` **只用于诊断展示**：材质只要构造成功就下发，画不画由系统按生效范围决定。

### 5.4 材质构造的正确姿势

```ts
// ⚠️ 必须惰性求值，不能写成模块级常量
function materialStyle(): uiMaterial.ImmersiveStyle {
  return uiMaterial.ImmersiveStyle.THIN as uiMaterial.ImmersiveStyle;
}
```

写成模块级常量会在**模块加载期**解引用 `uiMaterial`；
而它是 API 26 才有的接口，在低版本设备上是 `undefined`，
取 `.THIN` 抛出的 `TypeError` 发生在**任何 try/catch 之外** ——
结果不是「没有光感」，而是**整个模块加载失败、应用启动即闪退**。

构造失败时返回 **`null`**（降级），**绝不返回 `Material.empty`**（那是「显式不画」，
会把失败伪装成静默失效）。

### 5.5 四条层级规则（官方《沉浸光感常见问题》，每条都踩过）

| # | 规则 | 后果 |
| --- | --- | --- |
| 1 | 材质的视觉层级在 `backgroundColor` / `backgroundBlurStyle` **之下** | 承载层不显式 `Color.Transparent` → 底色盖住材质 |
| 2 | `systemMaterial` 要放在其他样式属性**之后** | 否则材质被后面的属性覆盖 → 用 `attributeModifier` 挂链尾 |
| 3 | 材质**不采样同一 Stack 里的兄弟节点**（采样的是组件背后的窗口内容） | 流光塞到材质底下 → **完全看不见** |
| 4 | `bindSheet` 的 `backgroundColor` **默认是 `Color.White`** | 不显式透明 → 材质被整块盖住 |

### 5.6 降级路径必须「三件事一起做」

沉浸光感不可用时（API < 26 / 开关关闭 / 构造失败），
只把不透明底色画上去，卡片会变成一块死板色块。正确的降级是：

```ts
// ① 外壳底色在半透明与透明之间切换（材质生效时让位，不生效时作为玻璃底色）
.backgroundColor(materialActive() ? Color.Transparent : HwGlassCardColor.surface)
// ② 不生效时补一层模糊；生效时用 NONE 关掉，避免与材质叠加
.backgroundEffect(cardGlassEffect(...))
// ③ 底色本身必须带透明度（HwGlassCardColor.surface 约 70%），否则模糊被完全盖住
```

**三条缺一不可**：只加模糊而底色不透明，模糊根本看不见；
只调透明度而不加模糊，卡片变成一层薄纱但背后什么都没有。

---

## 第 6 章 把材质贴到卡片上：承载层

### 6.1 五条缺一不可的属性

```ets
@Component
export struct MaterialCardLayer {
  @Prop layerRadius: Length = HwRadius.card;
  @Prop layerShadow: boolean = true;

  build() {
    Toggle({ type: ToggleType.Button, isOn: false })
      .width(LayoutPolicy.matchParent)         // ① 尺寸塌成 0 就画不出材质
      .height(LayoutPolicy.matchParent)
      .borderRadius(this.layerRadius)          // ② 否则画出 Toggle 自己的按钮图形
      .backgroundColor(Color.Transparent)      // ③ 不透明底色会垫在材质之下
      .selectedColor(Color.Transparent)        //    选中态默认取系统强调色
      .enabled(false).focusable(false)
      .accessibilityLevel('no')
      .hitTestBehavior(HitTestMode.None)       // ④ 承载层抢点击会让内容点不动
      .attributeModifier({                     // ⑤ systemMaterial 放在属性链最末
        applyNormalAttribute: (instance: ToggleAttribute): void => {
          applyMaterialCarrier(instance, false, false, this.layerShadow);
        }
      })
  }
}
```

**① 为什么用 `LayoutPolicy.matchParent` 而不是 `'100%'`**：
百分比在 `Stack` 内按**父级可用尺寸**解析，高度会撑到容器满高、把卡片顶大。

**② `layerShadow` 为什么要有**：材质的 `applyShadow` **默认为 `true`**。
大卡片上这层投影是加分项，但**小尺寸芯片**上会显得像「按钮背后顶了一层影子」。
实现上是单独缓存了一档不带阴影的材质，而不是关掉全局阴影 —— 卡片的投影要保留。

### 6.2 卡片 = 承载层 + 玻璃三件套（**必须成对**）

```ets
CardSurface({ radius: HwRadius.card }) {
  Row({ space: 12 }) { /* 卡片内容 */ }
    .width('100%')
    .padding(HwSpace.lg)
    .borderRadius(HwRadius.card)
    .backgroundColor(Color.Transparent)
    .backgroundEffect(cardGlassEffect(...))        // ┐
    .border({ width: 1,                            // │ 三件套
      color: cardGlassBorderColor(...) })          // │ 材质生效时
    .clip(true)                                    // │ 统一返回「无效果」
    .shadow(cardGlassShadow(...))                  // ┘
}
```

三个 helper 在**材质生效**时返回「无效果」，把表面完全让给系统材质；
**不生效**时保持原有毛玻璃外观。

> **这一对必须同时出现。**
> 只用 `CardSurface` 不写三件套 → 材质不生效的机型上卡片没有底色；
> 只写三件套不用 `CardSurface` → 材质生效的机型上卡片**直接丢掉背景**
> （三件套都返回「无效果」，而没有任何东西接替它们）。
> 参考工程的自检脚本第 1 项检查的就是这件事。

**另外**：`CardSurface` 还额外给承载层留了一层很淡的兜底底色
（`cardMaterialSurfaceEffect`）。因为「材质是否真正生效」由系统按组件类型/算力决定，
一旦没生效而卡片自身又把毛玻璃置为「无效果」，卡片就会变成**全透明**。

### 6.3 沾色：叠在材质之上，不能混进底色

```ets
@Builder
cardTintLayer() {
  if (this.cardTint.length > 0) {
    Column()
      .width(LayoutPolicy.matchParent)   // ⚠️ 必须 matchParent，不能用 '100%'
      .height(LayoutPolicy.matchParent)
      .borderRadius(this.radius)         // ⚠️ 必须自己带圆角（外壳没有 clip）
      .backgroundColor(this.cardTint)
      .hitTestBehavior(HitTestMode.None)
  }
}
```

**为什么不能把沾色混进卡片底色**：材质生效时外壳底色是**透明的**（让位给材质），
混进底色的主题色**根本不会被画出来** —— 这正是「沾色开关点了没反应」的原因。

### 6.4 圆形按钮：与静态承载层的三点差异

```ets
// ① 载体必须还是 ToggleType.Button —— 真机实测普通 Button 挂 systemMaterial 不渲染
Toggle({ type: ToggleType.Button, isOn: false })
  .attributeModifier(this.carrierModifier())   // 必须写成方法，见下

// ② 图标层触摸穿透，让按压与流光响应在材质上
SymbolGlyph(this.symbol).hitTestBehavior(HitTestMode.None)

// ③ 这里是交互层 → **不能**设 hitTestBehavior(None)（与静态承载层相反）
```

**承载修饰器必须写成方法并在 build 里调用**：

```ts
private carrierModifier(): AttributeModifier<ToggleAttribute> {
  const lightColor = pressLightColor(this.pressGlowSwitch, this.accentColor);
  return {
    applyNormalAttribute: (instance: ToggleAttribute): void => {
      applyMaterialCarrier(instance, false, this.buttonInteractive, true, lightColor);
    }
  };
}
```

流光的颜色要在这里**现读订阅变量**，读发生在**渲染期**才会被登记成依赖。
写成内联字面量的话闭包体不在渲染期执行，读什么都登记不上。

> `interactive: true` + `lightEffect` 与**静态承载层**不兼容：
> 实测单独给静态承载层加这两个参数会让材质**完全不渲染**。
> 所以卡片走静态材质，`interactive` 只给确实需要流光跟随的小元件。
> 若某设备上开启后材质整块消失，把 `buttonInteractive` 改回 `false`。

---

## 第 7 章 按压跟手流光

### 7.1 光只留在卡片内

流光**不是描边**，是跟着手指走的一小团柔光。两个参数：

```ts
const PRESS_GLOW_RADIUS = 64;    // 半径收着给：130 会盖住大半张卡，像「整卡高亮选中」
const PRESS_GLOW_ALPHA = 0.32;   // 再浓就变成往卡片上刷了一层主题色
```

**三档淡出的径向渐变**（只用一档实色会得到一个**硬边圆盘**，像贴纸而不是光）：

```ts
private glowGradientColors(): Array<[ResourceColor, number]> {
  const accent = this.glowAccent();
  return [
    [withAlpha(accent, PRESS_GLOW_ALPHA), 0],
    [withAlpha(accent, PRESS_GLOW_ALPHA * 0.55), 0.42],
    [withAlpha(accent, PRESS_GLOW_ALPHA * 0.18), 0.72],
    [Color.Transparent, 1]
  ];
}
```

**必须压在材质之上、内容之下**：材质不采样同 Stack 的兄弟节点，塞到下面就完全看不见。

**刻意不做「溢出到卡间缝隙」的环境光**：卡片之外（页面底色、卡与卡的缝）没有沉浸光感材质，
在那里画光等于在非沉浸光感区域**凭空出现一块亮斑**，观感是「糊了一块」而不是「玻璃被照亮」。

### 7.2 跟手：窗口坐标 → 卡片内坐标

触摸事件给的是**窗口坐标**，而光斑要画在卡片坐标系里：

```ts
private updatePressGlow(event: TouchEvent): void {
  if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
    this.glowOn = false;      // ⚠️ 抬起与取消都必须熄灭，否则留一块不会消失的光斑
    return;
  }
  const touch = event.touches[0];   // touches[0].x/y 相对**绑定 onTouch 的组件**
  if (event.type === TouchType.Down) {
    // 按下这一瞬 x/y 一定准，用它反推卡片在窗口中的原点
    this.cardWinX = touch.windowX - touch.x;
    this.cardWinY = touch.windowY - touch.y;
  }
  this.lastTouchWinX = touch.windowX;
  this.lastTouchWinY = touch.windowY;
  this.syncGlowPosition();
  this.glowOn = true;
}
```

**为什么还要 `onAreaChange`**：列表滚动时卡片在动。
手指不动、页面在滚，光斑会**黏在卡片原处** —— 必须用 `onAreaChange` 的**位移增量**维护卡片原点：

```ts
.onAreaChange((_old: Area, now: Area): void => {
  const gx = typeof now.globalPosition.x === 'number' ? now.globalPosition.x : this.lastAreaX;
  const gy = typeof now.globalPosition.y === 'number' ? now.globalPosition.y : this.lastAreaY;
  if (this.areaReady) {
    this.cardWinX += gx - this.lastAreaX;   // 只取增量
    this.cardWinY += gy - this.lastAreaY;
    if (this.glowOn) this.syncGlowPosition();
  }
  this.lastAreaX = gx; this.lastAreaY = gy; this.areaReady = true;
})
```

> **只取增量、不用绝对值**：`globalPosition` 的原点与 `windowX/Y` 未必是同一套，
> 但两者在滚动中的**变化量**必然一致。

### 7.3 两个开关的分工

| 开关 | 默认 | 作用 |
| --- | --- | --- |
| 主题色流光 `immersivePressGlow` | 开 | 流光用主题色；关 = 系统默认白光 |
| 卡片流光触感 `cardGlowTouch` | **关** | 关 = 按压卡片**一点光都不出现**；开 = 跟手光斑 |

两者都要**同时**满足才会出现光（`glowVisible() && glowTouchEnabled`）。

---

## 第 8 章 持久化与启动顺序

### 8.1 设置项标准写法「三连」

```ts
AppearanceStore.setBoolean(KEY, v);   // ① 落盘（重启后还在）
AppStorage.setOrCreate(KEY, v);       // ② 建/更新订阅键（@StorageLink 才有初值）
reloadAppTheme();                     // ③ 重算 token 并广播 accentColor
```

| 漏掉 | 后果 |
| --- | --- |
| ① | 重启后设置丢失 |
| ② | `@StorageLink` 拿不到初值，开关「点一下弹回去」 |
| ③ | token 是旧值，界面不刷新 |

> **`@StorageProp` vs `@StorageLink`**：读用 Prop（单向，赋值不生效），
> 写用 Link（双向，赋值即写回存储）。给用户操作的开关**必须**用 `@StorageLink`。

### 8.2 启动顺序（**必须在 `loadContent` 之前**）

```ts
onCreate() {
  AppearanceStore.init(this.context);                       // ① 打开 preferences
  const pref = resolveDarkModePref();
  setColorMode(resolveColorMode(pref));                      // ② 系统控件配色
  AppStorage.setOrCreate(/* 各项设置 */);                     // ③ 建订阅键
  const accent = effectiveAccentColor(key, custom);
  applyAppTheme(darkMode, accent);                           // ④ 自绘颜色
  AppStorage.setOrCreate('accentColor', accent);             // ⑤ 广播
}
```

**漏掉 ④/⑤ 的后果**：首屏用默认蓝渲染，切到另一个页面才变色。

**顺序细节**：主题色的两个延伸开关（卡片沾色、高权限自定义色）必须在
`applyAppTheme` **之前**写进 `AppStorage` —— 因为 `applyAppTheme` 会读它们来决定
「沾色层要不要画」「背景要不要跟随自定义色」。

### 8.3 存储的两个务实做法

- ArkTS 的 `preferences` **不支持数组** → 统一存成 JSON 字符串，
  读入时解析失败一律回落默认值（**存储内容可能被外部改坏或残留旧版本数据**）。
- **自定义色列表元素格式：`RRGGBB` 或 `RRGGBB|昵称`**。
  `parseAccentEntries()` 兼容旧版的纯 `RRGGBB` 数组；
  读入时还要把历史遗留的单个 `accentCustom` 补进列表，
  否则升级后用户原有的自定义色会**凭空消失**。

---

## 第 9 章 字体子系统：第二条横切机制

主题色讲完后必须补这一章 —— 它和主题色是**同一类问题**（全局变更 + 逐节点生效），
但规模更大：**6 个设置键 × 19 个文件订阅，`appFontFamily()` 调用 322 处 / 18 个文件，
`appFontWeight()` 233 处**。参考工程的每个页面都抄了同一份实现。

### 9.1 六个设置键

| 键 | 取值 | 订阅文件数 |
| --- | --- | --- |
| `fontMode` | `system` / `custom` | 19 |
| `fontFamilyEn` | 英文字体别名 / `system` | 19 |
| `fontFamilyZh` | 中文字体别名 / `system` | 19 |
| `fontWeightMode` | `system` / `custom` | 19 |
| `fontWeightValue` | 100–900 | 19 |
| `fontSizeMode` / `fontSizeValue` | 字号模式与基准字号 | 2 |

### 9.2 核心实现：为什么它要收「文本内容」这个参数

```ets
private appFontWeight(): number {
  return this.fontWeightMode === 'custom' ? this.fontWeightValue : 400;
}

private appFontFamily(content: string): string {      // ← 注意这个参数
  if (this.fontMode !== 'custom') {
    return 'HarmonyOS Sans';
  }
  const family = this.hasCjk(content) ? this.fontFamilyZh : this.fontFamilyEn;
  return family === 'system' || family.length === 0 ? 'HarmonyOS Sans' : family;
}

private hasCjk(content: string): boolean {            // 汉字区 0x4E00–0x9FFF
  for (let i = 0; i < content.length; i++) {
    const code = content.charCodeAt(i);
    if (code >= 0x4E00 && code <= 0x9FFF) { return true; }
  }
  return false;
}
```

**ArkUI 不会把自定义字体级联给子 `Text`。** 所以：

1. 每个文本节点都必须**显式**写 `.fontFamily(this.appFontFamily(该文本))` —— 这就是 322 处调用的来源；
2. 中英文要分流选字体（`fontFamilyZh` / `fontFamilyEn`），
   于是 `appFontFamily` **必须知道「这段文字是什么」**，调用点传的就是这段文本本身。
   拼接出来的动态文本常写成等价的字面量：

```ets
Text('已接收 ' + this.receivedFiles.length + ' 个文件')
  .fontFamily(this.appFontFamily('已接收 个文件'))   // ← 只用于判断中英文，取个代表串
  .fontWeight(this.appFontWeight())
```

### 9.3 依赖登记：又一个「必须由入参带入」的例子

`appFontFamily()` **是在 `build()` 期间被调用的**，而它内部读的是
`this.fontMode` / `this.fontFamilyZh` … 这些 `@StorageLink` 字段 ——
**正是这一步读取，让「字体设置变化」成为被登记的渲染依赖。**

> 反过来说：如果把字体解析塞进一个模块级纯函数、直接去读 `AppStorage`，
> 那么改字体后**界面不会刷新** —— 和主题色 `hwPrimary(isDark)` 那个坑是同一个道理（§3.1）。

这也解释了「为什么每个页面都要重复声明这 6 个 `@StorageLink` 」：
它们不是重复的样板，而是**每个页面各自的依赖登记点**。

### 9.4 自定义字体的加载链路

```ets
// utils/CustomFonts.ets（31 行）—— 启动时调一次
const alias = fileName.substring(0, fileName.length - 4);   // 别名 = 文件名去掉扩展名
text.FontCollection.getGlobalInstance().loadFontSyncWithCheck(alias, `file://${targetPath}`);
```

| 环节 | 位置 |
| --- | --- |
| 字体文件存放 | `filesDir/custom_fonts/` |
| 注册到全局字体集合 | `loadCustomFonts()`（`EntryAbility` 启动时调用） |
| 上传 / 重命名 / 删除 | `pages/FontManagePage.ets`（463 行） |
| 消费 | 每个 `Text` 的 `.fontFamily(appFontFamily(...))` |

所以「换字体」实际是**三件事的组合**：文件管理 + 全局字体集合注册 + 每个文本节点显式指定。
只做前两件，界面上不会有任何变化 —— 这是最容易漏的第三件。

---

## 第 10 章 十六条铁律（速记）

1. **值是值，通知是通知。** `HwColor.primary` 给值，`AppStorage['accentColor']` 给通知，缺一不可。
2. **表达式里必须有订阅变量。** 需要实时跟随就用 `resolve*(isDark, this.accentOrPrimary())`，
   不要用 `hw*(this.isDarkMode)`。
3. **`@Watch` 不刷新，哨兵才刷新。** `@Watch` 里 `reloadAppTheme()`，
   根容器里挂零尺寸 `AccentColorSentinel()`，页面底色单独走 `resolvePageBackground()`。
4. **`ForEach` 的 key 要编入一切会影响外观的状态**：主题色、选中态、昵称、展开态。
5. **SDK 控件的选中色不覆盖就永远是蓝的**：`Toggle` / `Slider` / `TextInput` / `Button`。
6. **内容区卡片必须用 `Toggle(ToggleType.Button)` 承载材质**，
   `Column`/`Row` 在内容区不生效；五条属性缺一不可。
7. **材质生效时，卡片自身的底色/毛玻璃/描边/阴影全部让位**（三件套返回「无效果」），
   同时要留一层兜底底色，防止卡片变全透明。
8. **低版本安全 = 惰性求值 + try/catch + 版本判断**：
   任何接触 `uiMaterial` 的模块级常量都会导致低版本**启动闪退**。
9. **`Toggle` 的 `isOn` 不是双向绑定。** 只写 `isOn: this.x` 而不写 `.onChange`，
   拨动只会改组件内部视觉，`x` 根本不变 —— 表现为「拨完闪一下又弹回」，且不持久化。
   （`Slider` 同理）
10. **声明了 `@StorageLink` 但没在 `build()` 里读，等于没声明** —— 不构成渲染依赖。
    主题色、字体、沉浸光感三套机制都栽在这条上。
11. **顶栏要顶到状态栏，必须两件事配套**：根节点 `expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])`
    **加上** `height(56 + this.statusBarHeight)` 与 `padding({ top: this.statusBarHeight })`。
    只做前者，顶栏会被状态栏压住。
12. **半模态面板要自己给兜底底色**：`bindSheet` 的 `backgroundColor` 设透明之后，
    材质不可用的机型上没有东西接替它 —— 必须用 `MaterialSheetPanel` 包一层。
13. **`@Prop` 的默认值不是常量**：父组件重渲染时默认值表达式会**被重新求值**，
    所以它**冻不住**任何东西。想固定一个值，必须把求值时机挪出组件生命周期
    （模块级常量，或在不被重建的页面里 `aboutToAppear` 取快照）。
14. **`@Entry` 的 `build()` 根节点必须是容器组件**（`Column`/`Stack`/`Row`），
    不能直接是自定义组件，否则编译报
    「can have only one root node, which must be a container component」。
15. **`SymbolGlyph.fontColor()` 收的是数组**（`ResourceColor[]`），
    而 `Text.fontColor()` 收单个颜色 —— 两者签名不同，别顺手复制。
16. **用了别的模块导出的符号就必须 `import`**。这类错误单文件看不出来，
    只有编译期报 `Cannot find name 'Xxx'`（本 Demo 一次犯了 3 处）。

这份清单里 **9～16 条**全部由真实编译/真机运行暴露出来，而不是静态推演出来的 ——
其中 9、13、14、15、16 都是我的第一版 Demo 真犯过的错（详见 `PITFALLS.md` 与顶层 `README.md`）。

---

## 附：自检工具

Demo 自带四个**纯静态**检查脚本，改完界面不用编译就能跑：

```powershell
node tools/arkcheck.mjs    entry/src/main/ets   # 注释闭合、装饰线误用斜杠、括号配平、
                                                # 未定义成员调用、全角标点、
                                                # Toggle/Slider 缺 onChange、字段声明后未读取
node tools/importcheck.mjs entry/src/main/ets   # 导入符号是否真实导出、是否未使用、
                                                # **用了却没 import**（编译期错误的等价检查）
node tools/configcheck.mjs .                    # JSON/JSON5 良构、路由页面存在、资源引用有效
node tools/snippet-audit.mjs entry/src/main/ets # 页面上的源码片段是否逐字来自本工程

# 针对参考工程的只读审计（CLink 不在本仓库内，先 clone 到仓库上一级）
git clone https://github.com/MrCashmere/CLink ../CLink
node tools/foreach-audit.mjs ../CLink/entry/src/main/ets   # ForEach key 是否编入 accentColor
node tools/ui-stats.mjs      ../CLink/entry/src/main/ets   # UI 文件/行数/接线点/字体/色值统计
```

> 这些脚本在编写过程中**各自抓到过真实错误**（导错模块、调用不存在的 builder、
> 路由页面漏登记）；`arkcheck` 的规则另有一份可执行的双向反测
> （`tools/selftest-arkcheck.mjs` + `tools/selftest/{bad,good}/`），可以两个方向都验一遍。
>
> ⚠️ 但要清醒：**静态自检全绿 ≠ 能编译**。
> 本 Demo 就出现过「三个脚本全绿、真实编译却报 6 个错」的情况 ——
> 根因是当时只检查了「导入的符号是否存在」这**一个方向**，
> 「用了却没 import」压根没查。补上该方向后，同类错误的 3 处全部能被抓出。
> 剩下 2 类（类型不匹配、结构约束）本质上只能靠编译器，静态检查无法替代。
