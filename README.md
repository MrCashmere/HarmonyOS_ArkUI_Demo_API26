# HarmonyOS ArkUI Demo (API 26)

> **全局主题色 · 深色模式 · 沉浸光感（systemMaterial）** 三套 UI 机制的最小可运行示例。
> 每一处实现都带「为什么这么写」的注释，并配一段可在页面上直接复制的源码。
>
> 工程名 **羊绒应用主题样板 / CashmereAppThemeDemo** · `bundleName: com.cashmere.appthemedemo`
> 本仓库地址：<https://github.com/MrCashmere/HarmonyOS_ArkUI_Demo_API26>

---

## 这是什么

一个**自包含**的 HarmonyOS NEXT 工程（不依赖任何其它工程即可编译运行），
用来把「应用内主题色怎么做到全局实时生效」「深色模式怎么跟随系统」
「API 26 的沉浸光感材质为什么必须用 Toggle 承载」这三件事讲清楚。

| 文档 | 内容 |
| --- | --- |
| [docs/UI-INDEX.md](docs/UI-INDEX.md) | 参考工程 CLink 全部 UI 代码的整理：25 个 UI 文件（+3 个主题/字体工具层）、五层结构、跟随主题色的完整清单（数字由脚本产出，可复现） |
| [docs/UI-TEACHING.md](docs/UI-TEACHING.md) | **教学正文**：11 章，从「ArkUI 为什么不刷新」讲到流光跟手坐标换算与字体子系统 |
| [docs/PITFALLS.md](docs/PITFALLS.md) | **坑位速查**：按「现象 → 根因 → 修法」组织的 44 条（含编译期与真机实测发现的） |

---

## 运行

1. 用 DevEco Studio 打开本目录。
2. 勾选自动签名：**File → Project Structure → Signing Configs →
   Automatically generate signature**（本工程刻意不写死证书路径，见下方说明）。
3. 运行到设备。

| 设备 | 表现 |
| --- | --- |
| **API 26（HarmonyOS 7）真机** | 可看到完整的沉浸光感材质 |
| **较低版本设备（最低 API 20）** | 也能正常运行 —— 自动降级为毛玻璃（这正是要演示的降级路径） |

> 工程配置：`compileSdkVersion` / `targetSdkVersion` = `26.0.0`（沉浸光感需要），
> `compatibleSdkVersion` = `6.0.0(20)`。
>
> ⚠️ `build-profile.json5` **刻意不含 `signingConfigs`**：写死证书路径会让别人 clone 后
> 直接报 `00303074 Configuration Error`。勾选自动签名后 DevEco 会自行补上。

---

## 三个演示页

> 每个教学小节下面都挂了一段「源码」代码块（`components/SourceBlock.ets` 渲染）：
> 正文是本工程的**真实实现片段**，右上角「复制」一键写入系统剪贴板，
> 也可以长按代码走系统菜单复制 —— 看完现象直接抄进自己的组件。
> 片段正文集中在 `teaching/SourceSnippets.ets`，出处写在每个代码块的「来源：」一行。

### ① 颜色令牌实验室 — `pages/ThemeLabPage.ets`

同一屏对照「哪些写法跟随主题色、哪些不跟随」：

| 段 | 内容 |
| --- | --- |
| A | 主色的三种用法（前景 / 按钮底 / 底色上的自动前景） |
| B | 控件自带选中色：`Toggle` / `Slider` / `TextInput` 光标 |
| C | 浅色底与描边（`withAlpha` 派生）、`ForEach` key 的选中态问题 |
| D | **反面对照**：`@Prop` 默认值 vs 订阅表达式，并排放在一起看差别 |

### ② 沉浸光感与材质承载 — `pages/ImmersiveShowcasePage.ets`

| 段 | 内容 |
| --- | --- |
| A | 材质诊断（API / 材质 / 状态 / 开关 / 流光 / 承载） |
| B | 卡片按压跟手流光（可按住滑动，看光斑跟随） |
| C | 圆形按钮：`ToggleType.Button` 交互层 + `SymbolGlyph` 触摸穿透 |
| D | 小尺寸芯片的 `layerShadow` 对照 |
| E | 半模态面板（`bindSheet` 自身不生效，要靠承载层）+ Toast / Dialog |

### ③ 外观设置 — `pages/ThemeSettingsPage.ets`

机制的**输入端**：主题色总开关、4 个预设 + 自定义色（昵称 / 长按编辑 / 删除角标）、
卡片沾色、高权限自定义色、外观模式三态、三个光感开关，以及「当前生效值」核对面板。
所有设置**持久化**，重启后仍然生效。

---

## 两条核心机制（先看结论）

**主题色链** —— `HwColor.primary` 负责「值」，`AppStorage['accentColor']` 负责「通知」，
两者缺一不可；**表达式里必须真正读到订阅变量**，否则切色后那一处不会刷新。

**沉浸光感链** —— API 26 的 `systemMaterial` 在**页面内容区**只对弹窗类与按钮选择类组件生效，
所以内容区卡片必须用 `Toggle(ToggleType.Button)` 当「看不见的画布」承载材质，
并且材质生效时卡片自身的底色 / 毛玻璃 / 描边 / 阴影要**全部让位**。

---

## 代码结构（五层）

```
① 令牌层   utils/DesignTokens.ets         颜色的「值」与「通知」、可变色板 HwColor
② 材质层   utils/SystemMaterial.ets       系统沉浸光感适配 + 降级路径
③ 承载层   components/MaterialCard.ets    Toggle 承载层 / 半模态面板 / 主题色哨兵
           components/CardSurface.ets     卡片外壳（材质 + 沾色 + 跟手流光）
           components/IconCircleButton.ets 圆形按钮（交互材质 + 流光）
           components/DemoScaffold.ets    页面脚手架（把订阅样板收敛到一处）
④ 页面层   pages/*.ets
⑤ 启动层   entryability/EntryAbility.ets  首帧前解析设置并广播
           storage/AppearanceStore.ets    偏好持久化

教学用     components/SourceBlock.ets     页面上的「源码」代码块（可一键复制）
           teaching/SourceSnippets.ets    各小节的真实实现片段（逐字摘自本工程）
```

---

## 自检脚本

四个**纯静态**检查 + 一个双向反测，都不需要编译（无 GUI / 无网络也能跑）。
**在仓库根目录执行**：

```powershell
node tools/arkcheck.mjs    entry/src/main/ets   # 注释闭合、装饰线误用斜杠、括号配平、
                                                # 调用未定义成员、全角标点、
                                                # Toggle/Slider 缺 onChange、
                                                # 字段声明后未读取（**按 struct 作用域**）
node tools/importcheck.mjs entry/src/main/ets   # 导入的符号是否真的被导出、是否未使用、
                                                # **用了却没 import**（编译期错误的等价检查）
node tools/configcheck.mjs .                    # JSON/JSON5 良构、路由页面文件存在、
                                                # pushUrl 目标已登记、$string/$media 引用有效
node tools/snippet-audit.mjs entry/src/main/ets # 页面上的源码片段是否**逐字**来自本工程
                                                # （防止教学代码被写成「凭印象的改写版」）

# arkcheck 的**双向反测**：坏样本必须报出、好样本必须零问题
node tools/selftest-arkcheck.mjs
```

> 这些脚本**各自抓到过真实错误**（导错模块、调用不存在的 builder、路由漏登记、
> 跨 struct 同名字段掩盖死代码）。
>
> 「规则真的有效」不是靠嘴说的：`tools/selftest/bad/` 下放着故意写坏的样本，
> `tools/selftest/good/` 下放着写法正确、**不该**报错的样本，
> `node tools/selftest-arkcheck.mjs` 会两个方向都验一遍。
> 只跑「工程全绿」证明不了任何事 —— 一条**永远不报错**的规则看起来同样是全绿。
>
> **它们不能替代编译。** 请在 DevEco Studio 里编译运行一次以确认。

### 针对参考工程的只读审计

`tools/foreach-audit.mjs` 与 `tools/ui-stats.mjs` 用来扫描**参考工程**，
而**参考工程不在本仓库内**（见下节原因）。先把 CLink clone 到仓库上一级即可：

```powershell
git clone https://github.com/MrCashmere/CLink ../CLink
node tools/foreach-audit.mjs ../CLink/entry/src/main/ets   # ForEach key 是否编入 accentColor
node tools/ui-stats.mjs      ../CLink/entry/src/main/ets   # UI 文件/行数/接线点/字体/色值统计
```

`docs/UI-INDEX.md` 里的全部数字都由 `ui-stats.mjs` 产出，可复现。

---

## 相关链接

- 参考工程 **CLink**（羊绒互传 / Cashmere Link）：<https://github.com/MrCashmere/CLink>
  > ℹ️ 原名 **pri-cl**，已更名；旧地址 <https://github.com/MrCashmere/pri-cl> 现已 404。
  >
  > 本仓库**刻意不包含** CLink 的源码：它是 GPL-3.0 的第三方工程（含其完整 git 历史，约 26MB）。
  > 需要对照阅读时请自行 clone（命令见上节）。
- 上游文档（CLink 内）：`docs/THEME_COLOR.md`、`docs/IMMERSIVE_LIGHT.md`、
  `docs/IMMERSIVE_LIGHT_CARD_TUTORIAL.md`、`docs/API_COMPAT.md`
- 同源姊妹工程 **miha_hm**（鸿蒙原生 ArkTS / ArkUI 的米家控制应用，与本套机制同源）：
  <https://github.com/MrCashmere/miha_hm>
- 本仓库：<https://github.com/MrCashmere/HarmonyOS_ArkUI_Demo_API26>

### 首页的「关于」卡片

首页最底部有一张「关于」卡片，点击跳转系统浏览器，地址已指向本仓库
（`entry/src/main/ets/pages/Index.ets` 的 `PROJECT_URL`）。

跳转本身**不需要任何权限**：构造 `ohos.want.action.viewData` +
`entity.system.browsable` 的 Want，交给系统挑浏览器。
地址若留空，卡片会显示「项目地址：待填写」并给出 Toast 提示（而不是「点了没反应」）。

---

## 应用名与标识

| 项 | 值 |
| --- | --- |
| 中文名 | **羊绒应用主题样板**（`AppScope/resources/zh_CN/element/string.json`） |
| 英文名 / 回退值 | **CashmereAppThemeDemo**（`AppScope/resources/base/element/string.json`） |
| `bundleName` | `com.cashmere.appthemedemo` |
| 最低支持 | API 20（`6.0.0(20)`） |
| 目标 | API 26（`26.0.0`，沉浸光感所需） |

---

## 许可

本仓库为教学示例代码。参考工程 **CLink** 以 **GPL-3.0** 发布，
本仓库未包含其源码；文中引用的片段仅用于讲解，版权归原工程所有。
