# CLink UI 全景索引

> 对 <https://github.com/MrCashmere/CLink>（羊绒互传，HarmonyOS NEXT / ArkTS）
> **全部 UI 相关代码**的整理结果。本地 checkout：`1.0.3`（commit `09343a4`）。
>
> 机制讲解见 [UI-TEACHING.md](UI-TEACHING.md)，坑位清单见 [PITFALLS.md](PITFALLS.md)，
> 可运行示例见仓库根目录（[README.md](../README.md)）。

> **本文所有数字都由脚本产出，可复现**（先把 CLink clone 到仓库上一级）：
> ```powershell
> git clone https://github.com/MrCashmere/CLink ../CLink
> node tools/ui-stats.mjs ../CLink/entry/src/main/ets
> ```
> 上一版手算的数字错了（把两个 `utils/` 文件误记进 `components/`，
> 于是「27 个文件 / components=10」看起来自洽，实际是 25 个文件 / components=8）。
> 统计口径：**整树扫描**声明了 `@Component` / `@Entry` / `@CustomDialog` 的 `.ets`；
> 行数按 `\n` 切分（含空行）。

---

## 1. 总览

| 项 | 数量 |
| --- | --- |
| **UI 文件**（`components/` + `pages/` + `view/`） | **25 个 / 11,495 行** |
| 　├ `components/` | 8 个 / 1,283 行 |
| 　├ `pages/` | 12 个 / 6,075 行 |
| 　└ `view/` | 5 个 / 4,137 行 |
| **主题与材质工具层**（`utils/`） | 3 个 / 1,431 行 |
| **UI 相关合计** | **28 个 / 12,926 行** |
| 非 UI 组件文件但含 UI 调用（`common/`） | 3 个 / 2,308 行 |

**UI 只出现在 `components/` `pages/` `view/` 三个目录** —— 这一点是整树扫描确认的，
不是按约定推断的。`service/` `windowsnearby/` `quickshare/` `model/` `storage/`
里没有任何 `@Component`。

---

## 2. 分层结构

依赖方向严格向下，共五层（外加一个横切的字体子系统）：

```
① 令牌层   utils/DesignTokens.ets        颜色的「值」与「通知」、可变色板 HwColor
② 材质层   utils/SystemMaterial.ets      系统沉浸光感（API 26）适配 + 降级路径
③ 承载层   components/MaterialCard.ets   Toggle 承载层 / 半模态面板 / 主题色哨兵
           components/CardSurface.ets    卡片外壳（材质 + 沾色 + 跟手流光）
           components/IconCircleButton.ets 圆形按钮（交互材质 + 流光）
④ 页面层   view/*.ets  pages/*.ets        业务界面
⑤ 启动层   entryability/EntryAbility.ets  首帧前解析设置并广播
           storage/AppSettingsStore.ets   偏好持久化
─────────
横切       utils/CustomFonts.ets + 各页面的 appFontFamily()   字体子系统（见 §8）
```

---

## 3. ① 令牌层 —— `utils/DesignTokens.ets`（804 行）

**可变色板 `HwColor`**（模块级**可变对象**，这是主题色能做出来的前提）：
`primary` / `background` / `backgroundDark` / `surface` / `textPrimary` / `textSecondary` / `danger` / `online`。
另有 `HwGlassCardColor`（`surface` / `border`）、`HwRadius`（`card 24`/`control 16`/`pill 999`）、`HwSpace`。

**取色函数族 —— 最容易用错的地方**

| 纯函数（**不跟随**切色） | 订阅版（**实时跟随**） | UI 里的调用数 |
| --- | --- | --- |
| `hwPrimary(isDark)` | `resolvePrimaryColor(isDark, accent)` | 27 处 / 15 文件 |
| `hwPrimaryButton(isDark)` | `resolvePrimaryButtonColor(isDark, accent)` | 19 处 / 9 文件 |
| `hwGlassBorder(isDark)` | `resolveGlassBorderColor(isDark, accent)` | 2 处 / 2 文件 |
| — | `resolvePageBackground(isDark, bg)` | 13 处 / 13 文件 |
| — | `onAccentColor(accent)` | 21 处 / 11 文件 |
| — | `topBarGlassColor(isDark)` | 12 处 / 12 文件 |
| — | `pressLightColor(themed, accent)` | 3 处 / 3 文件 |

> 两者**取值逐档一致**，差别只在前者把订阅键作为入参 —— 于是表达式里真正读到了它，
> ArkUI 才登记得上依赖。`withAlpha` 在 UI 文件里 7 处；`mixHex` **0 处**
> （只在 `DesignTokens` 内部用于背景淡染与深色抬亮）。

---

## 4. ② 材质层 —— `utils/SystemMaterial.ets`（596 行）

承载三件事：**版本安全**（`isSdkAtLeast` / `isApi26OrAbove`）、
**材质构造与缓存**（惰性求值，失败返回 `null` 而不是 `Material.empty`）、
**降级**（`applyMaterialCarrier` 在不可用时回落 `backgroundBlurStyle`）。

对外分四组：承载层 API、弹窗类 API（`toastSystemMaterial` / `menuSystemMaterial` /
`dialogSystemMaterial` / `sheetSystemMaterial` / `sheetBlurStyle`）、
卡片玻璃三件套（`cardGlassEffect` / `cardGlassBorderColor` / `cardGlassShadow`，
UI 里各 **103 处 / 17 文件**）、诊断（`materialDiagnostics`）。

---

## 5. ③ 承载层 —— `components/`（8 个文件 / 1,283 行）

| 文件 | 行 | 导出 | 作用 |
| --- | --- | --- | --- |
| `MaterialCard.ets` | 147 | `MaterialCardLayer` | **Toggle 承载层**（`ToggleType.Button`），卡片/面板/芯片的材质背板（10 处） |
| | | `MaterialSheetPanel` | 半模态面板的材质承载（4 处）；材质不可用时**提供兜底底色** |
| | | `AccentColorSentinel` | 主题色依赖标记（16 处，零尺寸） |
| `CardSurface.ets` | 290 | `CardSurface` | 卡片外壳：材质承载 + 沾色层 + 跟手按压流光（**98 处 / 17 文件**） |
| `IconCircleButton.ets` | 129 | `IconCircleButton` | 圆形按钮：Toggle 承载 + `SymbolGlyph` 触摸穿透 + 流光（26 处 / 13 文件） |
| `AppBackground.ets` | 20 | `AppBackground` | 全局自定义背景图（`AppStorage['backgroundImage']`） |
| `SolutionPanel.ets` | 212 | `SolutionPanel` | 常见问题面板（也订阅主题色） |
| `PendingDynamicPhotoCard.ets` | 193 | — | 待保存动态照片卡片 |
| `PendingDynamicPhotoDialog.ets` | 210 | — | 待保存动态照片弹窗（`@CustomDialog`，**全项目唯一**） |
| `PendingDynamicPhotoWatcher.ets` | 82 | — | 全局兜底提示（不订阅主题色） |

**承载层五条缺一不可的属性**（详见 PITFALLS.md）：

```ets
Toggle({ type: ToggleType.Button, isOn: false })
  .width(LayoutPolicy.matchParent)     // ① 尺寸塌成 0 就画不出材质
  .height(LayoutPolicy.matchParent)
  .borderRadius(this.layerRadius)      // ② 否则画出 Toggle 自己的按钮图形
  .backgroundColor(Color.Transparent)  // ③ 不透明底色垫在材质之下
  .selectedColor(Color.Transparent)    //    选中态默认取系统强调色
  .enabled(false).hitTestBehavior(HitTestMode.None)  // ④ 别抢交互
  .attributeModifier({ ... })          // ⑤ systemMaterial 必须在属性链最末
```

---

## 6. ④ 页面层

### 6.1 `view/`（主页内的面板级组件，5 个 / 4,137 行）

| 文件 | 行 | 说明 |
| --- | --- | --- |
| `MainPage.ets` | 2,194 | 主页：`HdsNavigation` + `HdsTabs` 四页签；39 个 `@Builder` |
| `SettingsPage.ets` | 925 | 设置页签（20 个 `@Builder`） |
| `AggregatePage.ets` | 713 | 聚合页（三协议设备与任务汇总，9 个 `@Builder`） |
| `TransferProgress.ets` | 189 | 传输进度列表 |
| `DeviceList.ets` | 116 | 设备列表（协议徽标色是全仓**唯一**带色相硬编码色例外，见 §11） |

### 6.2 `pages/`（路由页面，12 个 / 6,075 行）

| 文件 | 行 | 说明 |
| --- | --- | --- |
| `AppearanceSettingsPage.ets` | 1,961 | **外观设置**：主题色选择器、外观模式三态、沉浸光感开关（本套机制的核心 UI） |
| `QuickShare.ets` | 711 | Quick Share 独立入口 |
| `LocalSend.ets` | 543 | LocalSend 页面 |
| `NearSharing.ets` | 501 | Windows 附近共享 |
| `LanWebTransfer.ets` | 483 | 局域网网页传输 |
| `FontManagePage.ets` | 463 | **字体管理**（见 §8） |
| `BackgroundCropPage.ets` | 427 | 背景图裁剪（壁纸系统） |
| `AboutPage.ets` | 383 | 关于 |
| `ShareChoosePage.ets` | 293 | 分享选择 |
| `NearSharingReceive.ets` | 273 | 接收页 |
| `Index.ets` | 24 | 入口（转发到 `MainPage`） |
| `Settings.ets` | 13 | 壳页面 |

### 6.3 每个页面都有的三件事

```ets
@StorageProp('accentColor') @Watch('onAccentColorChanged') accentColor: string = '';  // ① 订阅
@StorageProp('pageBackground') pageBackground: string = '';                            // ② 底色
onAccentColorChanged(): void { reloadAppTheme(); }

build() {
  Stack({ alignContent: Alignment.TopStart }) {
    AccentColorSentinel()      // ③ 零尺寸哨兵，放在最前面
    AppBackground()
    // … 顶栏与内容
  }
  .backgroundColor(resolvePageBackground(this.isDarkMode, this.pageBackground))
}
```

实测：`accentColor` 订阅 **21 处 / 21 个 UI 文件**；`AccentColorSentinel()` **16 处**。

**顶栏统一写法**（20 处 / 11 个文件）：

```ets
Row() { IconCircleButton(...) ; Text(标题) ; Blank() }
  .width('100%')
  .height(56 + this.statusBarHeight)                       // ← 高度含状态栏
  .padding({ left: 16, right: 16, top: this.statusBarHeight })  // ← 内容压到状态栏之下
  .backgroundEffect({ radius: 12, color: topBarGlassColor(this.isDarkMode) })
```

配套的滚动内容用 `Blank().height(56 + this.statusBarHeight)` 让位。
`statusBarHeight` 在 UI 文件里被读 **35 处 / 13 文件** —— 这是「顶到状态栏自己铺色」的代价，
**只加 `expandSafeArea` 而不加这两处 `statusBarHeight`，顶栏就会被状态栏压住**。

---

## 7. ⑤ 启动层

| 文件 | 行 | 职责 |
| --- | --- | --- |
| `entryability/EntryAbility.ets` | 349 | 启动初始化、深色模式下发、**发布 `statusBarHeight`**、响应系统深浅色变化 |
| `storage/AppSettingsStore.ets` | 91 | `preferences` 读写（库名 `cashmere_appearance`，含 `getStringArray` 兜底） |

---

## 8. 字体子系统（**上一版文档完全漏掉的一块**）

这是与主题色并列的第二大横切 UI 机制：**6 个设置键 × 19 个文件订阅，
`appFontFamily()` 调用 322 处 / 18 个文件，`appFontWeight()` 233 处**。

| 设置键 | 订阅文件数 | 取值 |
| --- | --- | --- |
| `fontMode` | 19 | `system` / `custom` |
| `fontFamilyEn` | 19 | 英文字体别名或 `system` |
| `fontFamilyZh` | 19 | 中文字体别名或 `system` |
| `fontWeightMode` | 19 | `system` / `custom` |
| `fontWeightValue` | 19 | 100–900 |
| `fontSizeMode` / `fontSizeValue` | 2 | 字号模式与基准字号 |

**核心实现**（每个页面各写一份，不是共享工具）：

```ets
private appFontWeight(): number {
  return this.fontWeightMode === 'custom' ? this.fontWeightValue : 400;
}

private appFontFamily(content: string): string {      // ← 必须把「这段文本」传进来
  if (this.fontMode !== 'custom') {
    return 'HarmonyOS Sans';
  }
  const family = this.hasCjk(content) ? this.fontFamilyZh : this.fontFamilyEn;
  return family === 'system' || family.length === 0 ? 'HarmonyOS Sans' : family;
}

private hasCjk(content: string): boolean {            // 0x4E00–0x9FFF
  for (let i = 0; i < content.length; i++) {
    const code = content.charCodeAt(i);
    if (code >= 0x4E00 && code <= 0x9FFF) { return true; }
  }
  return false;
}
```

**为什么每个 `Text` 都要写一遍**：ArkUI **不会把自定义字体级联给子 `Text`**，
所以每个文本节点都得显式写 `.fontFamily(this.appFontFamily(该文本))`。
`appFontFamily` 之所以要收「内容」参数，是因为它要按**中英文分流**选字体
（`fontFamilyZh` / `fontFamilyEn`）—— 所以调用点传的是这段文字本身，
常见写法是传一个等价的字面量，例如：

```ets
Text('已接收 ' + this.receivedFiles.length + ' 个文件')
  .fontFamily(this.appFontFamily('已接收 个文件'))   // ← 只用来判断中英文
  .fontWeight(this.appFontWeight())
```

**自定义字体加载**（`utils/CustomFonts.ets`，31 行，启动时调一次）：

```ets
text.FontCollection.getGlobalInstance().loadFontSyncWithCheck(alias, `file://${targetPath}`);
```
字体文件放在 `filesDir/custom_fonts/`，**别名 = 文件名去掉扩展名**，
`FontManagePage` 负责上传/重命名/删除。所以「字体设置」实际是
「文件管理 + 全局字体集合注册 + 每个 Text 显式指定」三件事的组合。

---

## 9. 非 UI 目录里的 UI 代码（**上一版把 `common/` 整体判为「非 UI」，是错的**）

`common/` 里没有 `@Component`，但有 3 个文件直接做 UI 反馈
（Toast + 沉浸光感材质 + 读 `HwColor`），共 **2,308 行**：

| 文件 | 行 | 用到的 UI API |
| --- | --- | --- |
| `common/AppServices.ets` | 622 | `promptAction` / `showToast` / `systemMaterial` / `HwColor` |
| `common/DynamicPhotoService.ets` | 906 | `promptAction` / `showToast` / `systemMaterial` |
| `common/NearbyScanHub.ets` | 780 | `promptAction` / `showToast` / `systemMaterial` / `HwColor` |

典型调用形如：

```ets
promptAction.showToast({ systemMaterial: toastSystemMaterial(), message: error.message })
```

**这带来一条维护要求**：Toast 的材质与配色也走同一套主题机制，
所以改主题相关 API 时要连带检查这 3 个文件（它们不在 `components/pages/view` 里，
最容易在做「UI 专项」时被漏掉）。

`service/` `windowsnearby/` `quickshare/` 全树扫描**没有任何 UI 调用**，可安全排除。

---

## 10. 必须跟随主题色的清单（实测值）

### 10.1 控件自带选中色（**最容易漏**）

| 控件 | 属性 | 实测 |
| --- | --- | --- |
| `Toggle`（共 37 处） | `.selectedColor(...)` | `selectedColor` **39 处 / 5 文件**（含 Slider） |
| `Slider`（2 处） | `.selectedColor()` + `.trackColor()` + `.blockColor()` | 同上 |
| 输入控件 | `.caretColor(...)` | **12 处 / 7 文件** |
| 主按钮 | `.backgroundColor(resolvePrimaryButtonColor(...))` | 19 处 |

`ToggleType.Switch` 35 处、`ToggleType.Button` 17 处（承载层用后者）。

### 10.2 其余跟随点

| 位置 | 写法 | 实测 |
| --- | --- | --- |
| 文字/图标 | `resolvePrimaryColor` | 27 处 / 15 文件 |
| 主按钮底色 | `resolvePrimaryButtonColor` | 19 处 / 9 文件 |
| 芯片描边 | `resolveGlassBorderColor` | 2 处 / 2 文件 |
| 主题色浅底 | `withAlpha(accent, 0.06~0.15)` | 7 处 / 2 文件 |
| 主题色上的前景 | `onAccentColor` | 21 处 / 11 文件 |
| 页面底色 | `resolvePageBackground` | 13 处 / 13 文件 |
| 顶栏玻璃 | `topBarGlassColor` | 12 处 / 12 文件 |
| 流光取色 | `pressLightColor` | 3 处 / 3 文件 |

### 10.3 卡片玻璃三件套与承载层

`cardGlassEffect` / `cardGlassBorderColor` / `cardGlassShadow` 各 **103 处 / 17 文件**，
`CardSurface` **98 处 / 17 文件** —— **一一对应**（参考工程自检第 1 项检查的就是这件事）。
`MaterialCardLayer` 10 处、`MaterialSheetPanel` 4 处、`bindSheet` 4 处。

**卡片流光触感的默认值（Demo 与原项目的一个刻意差异）**：
原项目 `cardGlowTouch` **默认关** ——
`DesignTokens.ets:130` 注释写明「默认关」，`EntryAbility.ets:95` 读的是
`AppSettingsStore.getBoolean(CARD_GLOW_TOUCH_STORAGE, false)`，
`CardSurface.ets:83` 与 `AppearanceSettingsPage.ets:59` 的初值也都是 `false`，
开关在「外观设置」页暴露给用户。
**本 Demo 改成默认开**（3 处默认值统一为 `true`：`EntryAbility.ets:76`、
`CardSurface.ets:107`、`ThemeSettingsPage.ets:85`），这样一上手就能看到跟手流光；
要还原上游行为，把这 3 处改回 `false` 即可（`DesignTokens.ets:204` 里已注明具体位置）。
> ⚠️ 上一版这里写的是「4 处」—— 实际只有 3 处，`DesignTokens` 自己的注释写的也是「三处」。
> 另外「上游四处都是 `false`」也不准确：原项目 `pressGlow`（主题色流光）本来就是 `true`，
> 只有 `cardGlowTouch` 这一个开关是 `false`。

### 10.4 `ForEach` key

`ForEach` **23 处 / 15 文件**（无 `LazyForEach`），
`tools/foreach-audit.mjs` 独立复核：**23/23 全部把 `accentColor` 编入 key** ✅

---

## 11. 硬编码色值盘点（含「带色相」判定）

全树 `'#RRGGBB'` / `'#AARRGGBB'` 字面量 **90 处**；其中 **带色相 44 处**
（无彩色的 `#99000000` / `#33FFFFFF` / `#00000000` 这类阴影、遮罩、轨道、全透明不算 —— 与主题色无关）。

| 位置 | 带色相处数 | 判定 |
| --- | --- | --- |
| `utils/DesignTokens.ets` | 29 | ✅ **合法**：预设值、旧版配色常量、语义色、token 初值 |
| `utils/SystemMaterial.ets` | 5 | ✅ 合法：深色表面/边框的中性深色（`#6624282B` 等） |
| `model/TransferModels.ets` | 5 | ✅ 合法：协议品牌色（非 UI 文件） |
| `entryability/EntryAbility.ets` | 4 | ✅ 合法：窗口背景与状态栏文字（`#F0F2F5` / `#182431`） |
| **UI 文件** | **1** | ✅ 白名单例外：`view/DeviceList.ets:79` 的 `#04121F` —— 协议徽标上的文字色，底色是协议品牌色，与主题色无关 |

**结论：25 个 UI 文件里只有 1 处带色相硬编码色值，且是合理例外。** ✅

---

## 12. 官方已有文档对照

| 文档 | 内容 | 与本文关系 |
| --- | --- | --- |
| `docs/THEME_COLOR.md`（877 行） | 主题色完整实现与维护指南、移植清单、16 条踩坑 | 本文 §3/§10 是其索引化摘要 |
| `docs/IMMERSIVE_LIGHT.md` | 沉浸光感机制与元件接线 | 本文 §4/§5 对应 |
| `docs/IMMERSIVE_LIGHT_CARD_TUTORIAL.md` | 承载层通用写法 | 与 `CardSurface` 同源 |
| `docs/API_COMPAT.md` | 最低 API(20) 兼容与低版本闪退排查 | §7 与 PITFALLS 的闪退条 |
| `scripts/theme_audit.mjs` | 工程自带静态自检（6 项） | 本仓库 `tools/` 是同方法论的延伸 |

---

## 13. ⚠️ 本次整理**没有**覆盖的部分（如实列出）

上一版文档只按「主题色 + 沉浸光感」两条线做横切整理，
以下 UI 内容**在本文里没有展开**，移植时不能只看本文：

| 未覆盖内容 | 说明 |
| --- | --- |
| **底部 TabBar** | `MainPage` 的 `HdsNavigation` + `HdsTabs` 四页签：底栏高亮色下发、悬浮栏、`gradientMask`、以及 **API < 23 的降级路径**。Demo 里没有 TabBar |
| **HDS 材质（`hdsMaterial`，API 23）** | 与 `uiMaterial`（API 26）**两条并行的材质路径**；Demo 只实现了后者 |
| **字体子系统** | 已补 §8 的机制说明，但 Demo 未实现（每个 `Text` 挂 `appFontFamily` 的改造量很大） |
| **壁纸系统** | `AppBackground` + `BackgroundCropPage`（裁剪）+ `backgroundImage` 键的完整链路 |
| **各业务页面的排版结构** | `QuickShare` 711 行、`LocalSend` 543 行、`NearSharing*`、`LanWebTransfer` 等只登记了行数与用途，没有逐页 UI 结构说明 |
| **`AboutPage` / `ShareChoosePage` / `FontManagePage` / `BackgroundCropPage`** | 同上，只登记未展开 |
| **`SolutionPanel` 与 `PendingDynamicPhoto*`** | 只登记；未分析其布局与状态机 |
| **`common/` 三个文件的 Toast 调用点** | 只定位了文件与所用 API，没有逐条梳理触发时机 |
| **卡片沾色在参考工程各页面的应用分布** | 只说明了机制与键，没有统计各页面的实际使用 |
| **`scripts/theme_audit.mjs` 的 6 项检查细节** | 只引用了结论，没有逐项拆解实现 |
| **深色顶栏 `#99000000` 的真机效果** | 上游也标注为「待真机验证」 |

---

## 14. 如何复现本文统计

```powershell
# 参考工程 CLink 不在本仓库内，先把它的 clone 放在仓库上一级
git clone https://github.com/MrCashmere/CLink ../CLink

# ① 全部统计（文件清单 / 行数 / 各接线点计数 / 字体子系统 / 硬编码色值）
node tools/ui-stats.mjs ../CLink/entry/src/main/ets

# ② ForEach key 是否编入 accentColor（括号配平精确切分实参）
node tools/foreach-audit.mjs ../CLink/entry/src/main/ets

# ③ 参考工程自带的自检
node ../CLink/scripts/theme_audit.mjs
```
