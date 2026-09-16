/**
 * 教学用「源码片段」常量
 * ============================================================================
 * 每个教学小节下面挂的代码块，正文都取自**本工程的真实实现**，
 * 由 `components/SourceBlock.ets` 渲染（可一键复制）。
 *
 * 约定：
 *   · 片段**去掉了公共缩进**，行内容逐字保留（注释、⚠️ 标记都不改）；
 *   · 以 `// ① ② ③` 开头的是**教学引导注释**（为讲解另加），其余行均可在
 *     对应文件里找到原样；
 *   · `SRC_*_SOURCE` 常量写明出处，方便打开原文件对照全文。
 *
 * ⚠️ 这些是**模板字符串**常量，改动时注意：正文里若出现反引号或 `${`，
 *    必须转义（`\`` 与 `\${`），否则会被当成插值 —— 当前刻意只摘了不含这两者的片段。
 */

// ============================================================================
// ① 颜色令牌实验室（pages/ThemeLabPage.ets）
// ============================================================================

/** A · 主色的三种用法（调用侧写法，取自 pages/Index.ets） */
export const SRC_LAB_A_SOURCE: string = 'pages/Index.ets';
export const SRC_LAB_A: string = `// ① 页面底色：必须走 resolvePageBackground，不能直接读 HwColor.background
.backgroundColor(resolvePageBackground(this.isDarkMode, this.pageBackground))
.expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])

// ② 标题 / 图标 / 链接：走 resolvePrimaryColor（含深色适配）
.fontColor(resolvePrimaryColor(this.isDarkMode, this.accentOrPrimary()))

// ③ 主题色底上的文字：走 onAccentColor 自动切黑/白
.backgroundColor(this.accentOrPrimary())
.fontColor(onAccentColor(this.accentOrPrimary()))`;

/** B · 控件自带的选中色（三个控件都要显式覆盖） */
export const SRC_LAB_B_SOURCE: string = 'pages/ThemeLabPage.ets';
export const SRC_LAB_B: string = `// Toggle：不写 selectedColor → 永远是系统蓝
Toggle({ type: ToggleType.Switch, isOn: this.demoSwitch })
  .selectedColor(this.accentOrPrimary())
  .onChange((value: boolean): void => {
    this.demoSwitch = value;
  })

// Slider：已选色 / 轨道色 / 滑块色
.selectedColor(this.accentOrPrimary())
.trackColor(withAlpha(HwColor.textPrimary, 0.1))
.blockColor(Color.White)

// TextInput：不覆盖 caretColor，光标就是系统蓝
.caretColor(this.accentOrPrimary())`;

/** C · 浅色底与描边：全部从主题色派生 */
export const SRC_LAB_C_SOURCE: string = 'pages/ThemeLabPage.ets';
export const SRC_LAB_C: string = `// 选中态芯片：底色 = 主题色 12%，文字与描边都从主题色派生
.fontColor(this.pickedChip === index
  ? resolvePrimaryColor(this.isDarkMode, this.accentOrPrimary())
  : hwTextSecondary(this.isDarkMode))
.padding({ left: 16, right: 16, top: 8, bottom: 8 })
.borderRadius(HwRadius.pill)
.backgroundColor(this.pickedChip === index
  ? withAlpha(this.accentOrPrimary(), 0.12)
  : withAlpha(HwColor.textPrimary, 0.05))
.border({
  width: 1,
  color: this.pickedChip === index
    ? resolveGlassBorderColor(this.isDarkMode, this.accentOrPrimary())
    : Color.Transparent
})`;

/** D · 反面对照：为什么「模块级常量」冻不住颜色，什么位置才冻得住 */
export const SRC_LAB_D_SOURCE: string = 'entryability/EntryAbility.ets + pages/ThemeLabPage.ets';
export const SRC_LAB_D: string = `// ① 启动时写一次，之后**永不更新**（EntryAbility.onCreate）
AppStorage.setOrCreate(BOOT_ACCENT_STORAGE, accentColor);

// ② 页面侧只读（@StorageProp 天生只读，不会被写回）
@StorageProp('bootAccentColor') bootAccent: string = '';

// ③ 用它上色：切主题色时它不会变 —— 这就是「停在过去」的颜色
.backgroundColor(this.bootAccent.length > 0 ? this.bootAccent : hwTextSecondary(this.isDarkMode))

// ✗ 这两种写法都**冻不住**（实测）：
//   @Prop frozen: string = HwColor.primary      —— 父组件重渲染时默认值会重新求值
//   const frozen: string = HwColor.primary      —— 页面模块可能被重新求值`;

// ============================================================================
// ② 沉浸光感与材质承载（pages/ImmersiveShowcasePage.ets）
// ============================================================================

/** A · 材质诊断：把判定条件摊开 */
export const SRC_MAT_A_SOURCE: string = 'pages/ImmersiveShowcasePage.ets';
export const SRC_MAT_A: string = `// 诊断文案的两个入参必须是**订阅值**，否则这一行不会随切色/拨开关刷新
Text(materialDiagnostics(this.pressGlowSwitch, this.accentColor))
  .fontSize(11)
  .fontColor(hwTextSecondary(this.isDarkMode))
  .width('100%')

// 判定条件直接摊开，排查「为什么没生效」最快：
// 卡片是否已由系统材质接管
immersiveCardsActive()
// 系统是否支持 uiMaterial（API ≥ 26）
isApi26OrAbove()`;

/** B · 卡片按压缩放光：跟手光斑的条件与渐变 */
export const SRC_MAT_B_SOURCE: string = 'components/CardSurface.ets';
export const SRC_MAT_B: string = `// 跟手光斑：额外要求「卡片流光触感」打开。
// **关掉时按压卡片一点光都不出现** —— 这是该开关的定义。
private touchGlowVisible(): boolean {
  return this.glowVisible() && this.glowTouchEnabled;
}

// 只用一档实色会得到一个**硬边圆盘**，看着像贴纸而不是光。
private glowGradientColors(): Array<[ResourceColor, number]> {
  const accent: string = this.glowAccent();
  return [
    [withAlpha(accent, PRESS_GLOW_ALPHA), 0],
    [withAlpha(accent, PRESS_GLOW_ALPHA * 0.55), 0.42],
    [withAlpha(accent, PRESS_GLOW_ALPHA * 0.18), 0.72],
    [Color.Transparent, 1]
  ];
}`;

/** C · 圆形按钮：为什么载体必须是 ToggleType.Button */
export const SRC_MAT_C_SOURCE: string = 'components/IconCircleButton.ets';
export const SRC_MAT_C: string = `// 材质 + 交互层：普通 Button 挂 systemMaterial 不渲染，必须用 ToggleType.Button
Toggle({ type: ToggleType.Button, isOn: false })
  .width(this.buttonSize)
  .height(this.buttonSize)
  .borderRadius(this.buttonSize / 2)
  .clip(true)
  // 材质生效时必须显式透明（不透明背景会盖在材质层之上）；
  // 材质不可用时保持原有底色，按钮不会变成「只剩一个图标」
  .backgroundColor(this.materialActive() ? Color.Transparent
    : (this.glass ? Color.Transparent : '#14000000'))
  // ⚠️ 关掉按压/选中的主题色填充：ToggleType.Button 的选中态默认取**主题强调色**，
  //    按下时会闪一层色块；isOn 恒为 false 也**挡不住**这个按压填充。
  .selectedColor(Color.Transparent)
  // systemMaterial 放在所有样式属性之后
  .attributeModifier(this.carrierModifier())
  .onChange(() => {
    this.onAction();
  })

// 图标层：触摸**穿透**到下面的 Toggle，保证按压与流光响应在材质上
SymbolGlyph(this.symbol)
  .fontSize(this.iconSize)
  .fontColor([this.resolvedTint()])
  .hitTestBehavior(HitTestMode.None)`;

/** D · 小尺寸芯片要关掉材质投影 */
export const SRC_MAT_D_SOURCE: string = 'pages/ImmersiveShowcasePage.ets';
export const SRC_MAT_D: string = `// layerShadow: true（默认）—— 大卡片上合适
Stack() {
  MaterialCardLayer({ layerRadius: HwRadius.control, layerShadow: true })
  Text('带投影')
    .fontSize(12)
    .hitTestBehavior(HitTestMode.None)
}
.borderRadius(HwRadius.control)

// layerShadow: false —— 小尺寸芯片上更干净
Stack() {
  MaterialCardLayer({ layerRadius: HwRadius.control, layerShadow: false })
  Text('无投影')
    .fontSize(12)
    .hitTestBehavior(HitTestMode.None)
}
.borderRadius(HwRadius.control)`;

/** E · 半模态面板：bindSheet 不生效，必须用承载层 */
export const SRC_MAT_E_SOURCE: string = 'pages/ImmersiveShowcasePage.ets';
export const SRC_MAT_E: string = `// bindSheet：底色必须显式透明，否则会把面板里的材质整块盖住
.bindSheet($$this.showSheet, this.sheetContent(), {
  height: 320,
  dragBar: true,
  showClose: false,
  backgroundColor: Color.Transparent,
  // 沉浸光感可用时不设模糊（交给系统材质），否则回退旧毛玻璃
  blurStyle: sheetBlurStyle(),
  systemMaterial: sheetSystemMaterial()
})

// 面板内容：必须由承载层铺满整块面板，
// 直接给外层 Column 设 systemMaterial 在内容区**不生效**
@Builder
sheetContent() {
  MaterialSheetPanel({ panelPadding: HwSpace.lg }) {
    Column({ space: HwSpace.md }) {
      // 这里放面板真正的内容
    }
  }
}`;

// ============================================================================
// ③ 外观设置（pages/ThemeSettingsPage.ets）
// ============================================================================

/** 主题色：「设置三连」与派生 token 的刷新时机 */
export const SRC_SET_ACCENT_SOURCE: string = 'pages/ThemeSettingsPage.ets';
export const SRC_SET_ACCENT: string = `// 「设置三连」：写存储 → 广播到 AppStorage → 重算 token
private setThemeColorEnabled(enabled: boolean): void {
  AppearanceStore.setBoolean(THEME_COLOR_ENABLED_STORAGE, enabled);
  AppStorage.setOrCreate(THEME_COLOR_ENABLED_STORAGE, enabled);
  reloadAppTheme();
}

// ⚠️ 只改派生 token 的开关**不会**让 accentColor 变化，
//    不能指望它触发刷新 —— 必须让 applyAppTheme 重新发布派生键
private setCardTint(enabled: boolean): void {
  AppearanceStore.setBoolean(CARD_TINT_STORAGE, enabled);
  AppStorage.setOrCreate(CARD_TINT_STORAGE, enabled);
  reloadAppTheme();
}`;

/** 外观模式：三态偏好 + 平台配色 */
export const SRC_SET_MODE_SOURCE: string = 'pages/ThemeSettingsPage.ets';
export const SRC_SET_MODE: string = `private setDarkModePref(pref: string): void {
  this.darkModePref = pref;
  AppearanceStore.setString(DARK_MODE_PREF_STORAGE, pref);
  AppStorage.setOrCreate(DARK_MODE_PREF_STORAGE, pref);
  const enabled: boolean = pref === DARK_MODE_DARK ? true
    : (pref === DARK_MODE_LIGHT ? false : this.systemDarkMode());
  this.applyDarkMode(enabled, pref);
}

// ⚠️ 必须把当前主题色一并传入：背景色是按主题色染的，只传 isDark 会把染色重置回默认
applyAppTheme(enabled, this.currentAccent());

// 平台配色要和自绘颜色一起下发：setColorMode() 管的是系统控件
(getContext(this) as common.UIAbilityContext).getApplicationContext().setColorMode(mode);`;

/** 沉浸光感：开关只广播，判定要三者同时成立 */
export const SRC_SET_LIGHT_SOURCE: string = 'pages/ThemeSettingsPage.ets + utils/SystemMaterial.ets';
export const SRC_SET_LIGHT: string = `// 只影响取色/绘制的开关：写存储 + 广播即可，不需要重算 token
private setPressGlow(enabled: boolean): void {
  AppearanceStore.setBoolean(PRESS_GLOW_STORAGE, enabled);
  AppStorage.setOrCreate(PRESS_GLOW_STORAGE, enabled);
}

// 是否真的生效 = 版本够 + 开关开 + 材质对象构造成功
export function immersiveCardsActive(): boolean {
  return immersiveMaterialActive();
}`;

/** 当前生效值：「设置 → 解析 → 广播」这条链路 */
export const SRC_SET_RESOLVED_SOURCE: string = 'entryability/EntryAbility.ets';
export const SRC_SET_RESOLVED: string = `// 启动时把持久化设置解析成「最终生效值」，再广播给页面
const accentKey: string = EntryAbility.resolveAccentKey();
const accentCustom: string = AppearanceStore.getString(ACCENT_CUSTOM_STORAGE, '');
// ⚠️ 走 effectiveAccentColor 而不是 resolveAccentColor：
//    总开关关闭时要连**广播值**一起换回默认色
const accentColor: string = effectiveAccentColor(accentKey, accentCustom);
AppStorage.setOrCreate(ACCENT_KEY_STORAGE, accentKey);
AppStorage.setOrCreate(ACCENT_CUSTOM_STORAGE, accentCustom);
AppStorage.setOrCreate(ACCENT_COLOR_KEY, accentColor);
applyAppTheme(darkModeEnabled, accentColor);`;
