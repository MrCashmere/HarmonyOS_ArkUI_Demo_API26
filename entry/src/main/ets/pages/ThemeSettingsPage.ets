/**
 * 演示三：外观设置（ThemeSettingsPage）
 * ============================================================================
 * 这是整套机制的「输入端」：用户在这里改设置，全应用跟着变。
 *
 * 包含：
 *   ① 主题色总开关（themeColorEnabled）
 *   ② 4 个内置预设色块 + 自定义色块（昵称 / 长按编辑 / 删除角标）
 *   ③ 卡片沾色、高权限自定义主题色
 *   ④ 外观模式三态（跟随系统 / 浅色 / 深色）
 *   ⑤ 全局沉浸光感、主题色流光、卡片流光触感 + 材质诊断
 *
 * ⚠️ 本页演示了设置项标准写法「三连」（见 AppearanceStore 文件头）：
 *      AppearanceStore.setXxx(KEY, v)   // ① 落盘
 *      AppStorage.setOrCreate(KEY, v)    // ② 更新订阅键（@StorageLink 才有初值）
 *      reloadAppTheme()                  // ③ 重算 token 并广播 accentColor
 */

import { common } from '@kit.AbilityKit';
import { resourceManager } from '@kit.LocalizationKit';
import { ConfigurationConstant } from '@kit.AbilityKit';
import router from '@ohos.router';
import {
  ACCENT_CUSTOM_LIST_STORAGE,
  ACCENT_CUSTOM_STORAGE,
  ACCENT_KEY_STORAGE,
  ACCENT_PRESETS,
  AccentCustom,
  AccentPreset,
  CARD_GLOW_TOUCH_STORAGE,
  CARD_TINT_STORAGE,
  CUSTOM_ACCENT_FULL_ACCESS_STORAGE,
  DARK_MODE_DARK,
  DARK_MODE_LIGHT,
  DARK_MODE_PREF_STORAGE,
  DARK_MODE_SYSTEM,
  HwColor,
  HwRadius,
  HwSpace,
  PRESS_GLOW_STORAGE,
  THEME_COLOR_ENABLED_STORAGE,
  accentEntryLabel,
  applyAppTheme,
  hwDanger,
  hwTextPrimary,
  hwTextSecondary,
  normalizeAccentHex,
  onAccentColor,
  parseAccentEntries,
  reloadAppTheme,
  resolveAccentColor,
  serializeAccentEntries,
  withAlpha
} from '../utils/DesignTokens';
import {
  cardGlassBorderColor,
  cardGlassEffect,
  cardGlassShadow,
  isApi26OrAbove,
  materialDiagnostics
} from '../utils/SystemMaterial';
import { AppearanceStore } from '../storage/AppearanceStore';
import { DemoScaffold, SwitchRow, ThemedCard } from '../components/DemoScaffold';
import { MaterialCardLayer, MaterialSheetPanel } from '../components/MaterialCard';
import { SourceBlock } from '../components/SourceBlock';
import {
  SRC_SET_ACCENT, SRC_SET_ACCENT_SOURCE,
  SRC_SET_MODE, SRC_SET_MODE_SOURCE,
  SRC_SET_LIGHT, SRC_SET_LIGHT_SOURCE,
  SRC_SET_RESOLVED, SRC_SET_RESOLVED_SOURCE
} from '../teaching/SourceSnippets';

@Entry
@Component
struct ThemeSettingsPage {
  @StorageProp('accentColor') @Watch('onAccentColorChanged') accentColor: string = '';
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  @StorageProp('immersivePressGlow') pressGlowEnabled: boolean = true;
  @StorageLink('immersiveLightEnabled') immersiveLightEnabled: boolean = true;
  /** 写用 @StorageLink：赋值即写回 AppStorage，其余订阅同一键的页面一起重建 */
  @StorageLink(ACCENT_KEY_STORAGE) accentKey: string = 'harmony';
  @StorageLink(ACCENT_CUSTOM_STORAGE) accentCustom: string = '';
  @StorageLink('cardTintEnabled') cardTintEnabled: boolean = false;
  @StorageLink('customAccentFullAccess') customAccentFullAccess: boolean = false;
  /** 卡片流光触感（**默认开**，与原项目相反） */
  @StorageLink('cardGlowTouch') cardGlowTouch: boolean = true;
  @StorageLink(THEME_COLOR_ENABLED_STORAGE) themeColorEnabled: boolean = true;
  @StorageLink(DARK_MODE_PREF_STORAGE) darkModePref: string = DARK_MODE_SYSTEM;
  /** 自定义色列表（界面展示用） */
  @State accentList: AccentCustom[] = [];
  /** 自定义色弹窗 */
  @State showAccentDialog: boolean = false;
  @State dialogHex: string = '';
  @State dialogName: string = '';
  /** 弹窗处于「编辑已有色」还是「新增」 */
  @State editingHex: string = '';
  @State hexError: string = '';

  aboutToAppear(): void {
    this.loadAccentList();
  }

  onAccentColorChanged(): void {
    // 其它页面改色时同步刷新本页（token 重算在 reloadAppTheme 里，这里只需重建）
  }

  private accentOrPrimary(): string {
    return this.accentColor.length > 0 ? this.accentColor : HwColor.primary;
  }

  /**
   * 读自定义色列表。
   *
   * **兼容旧数据**：老版本只有一个 `accentCustom` 单值，没有列表。
   * 如果用户升级后列表为空、而 `accentCustom` 有值，就把它补进列表，
   * 否则用户原有的自定义色会**凭空消失**。
   */
  private loadAccentList(): void {
    const raw: string[] = AppearanceStore.getStringArray(ACCENT_CUSTOM_LIST_STORAGE, []);
    const list: AccentCustom[] = parseAccentEntries(raw);
    const current: string = this.accentCustom.replace('#', '').toUpperCase();
    if (current.length === 6) {
      let exists = false;
      for (let i = 0; i < list.length; i++) {
        if (list[i].hex === current) {
          exists = true;
          break;
        }
      }
      if (!exists) {
        list.push({ hex: current, name: '' });
      }
    }
    this.accentList = list;
  }

  private persistAccentList(): void {
    AppearanceStore.setStringArray(ACCENT_CUSTOM_LIST_STORAGE, serializeAccentEntries(this.accentList));
  }

  // ==================== 主题色：生效链路 ====================

  /**
   * 主题色实时生效。
   *
   * `accentKey` / `accentCustom` 已是 @StorageLink，赋值即同步进 AppStorage；
   * 再 `reloadAppTheme()` 广播 `accentColor`，各页面的 @Watch 会重建并读到新色值。
   * **只改 HwColor 属性不会触发刷新**，所以必须走这条广播链。
   */
  private applyAccentNow(): void {
    AppStorage.setOrCreate(ACCENT_KEY_STORAGE, this.accentKey);
    AppStorage.setOrCreate(ACCENT_CUSTOM_STORAGE, this.accentCustom);
    reloadAppTheme();
  }

  private selectAccentPreset(key: string): void {
    this.accentKey = key;
    AppearanceStore.setString(ACCENT_KEY_STORAGE, key);
    this.applyAccentNow();
  }

  private isCustomSelected(hex: string): boolean {
    if (this.accentKey !== 'custom') {
      return false;
    }
    return this.accentCustom.replace('#', '').toUpperCase() === hex.toUpperCase();
  }

  private selectCustomAccent(hex: string): void {
    this.accentKey = 'custom';
    this.accentCustom = hex;
    AppearanceStore.setString(ACCENT_KEY_STORAGE, 'custom');
    AppearanceStore.setString(ACCENT_CUSTOM_STORAGE, hex);
    this.applyAccentNow();
  }

  /**
   * 「主题色」总开关。
   *
   * 关闭后所有主题色不生效、配色回到加主题色功能之前的那一版；
   * **用户选过的颜色与自定义列表原样保留**，重新打开即恢复。
   */
  private setThemeColorEnabled(enabled: boolean): void {
    AppearanceStore.setBoolean(THEME_COLOR_ENABLED_STORAGE, enabled);
    AppStorage.setOrCreate(THEME_COLOR_ENABLED_STORAGE, enabled);
    reloadAppTheme();
  }

  /**
   * 卡片沾色开关。
   *
   * 这个开关**只改派生 token、不改主题色本身**，不能指望 `accentColor` 变化来触发刷新：
   * `applyAppTheme()` 会把沾色层颜色发布到 `cardTintColor`，订阅了它的卡片才会更新。
   */
  private setCardTint(enabled: boolean): void {
    AppearanceStore.setBoolean(CARD_TINT_STORAGE, enabled);
    AppStorage.setOrCreate(CARD_TINT_STORAGE, enabled);
    reloadAppTheme();
  }

  /** 高权限自定义主题色：只是把「只跟随预设色」的门槛去掉，淡染算法不变 */
  private setCustomAccentFullAccess(enabled: boolean): void {
    AppearanceStore.setBoolean(CUSTOM_ACCENT_FULL_ACCESS_STORAGE, enabled);
    AppStorage.setOrCreate(CUSTOM_ACCENT_FULL_ACCESS_STORAGE, enabled);
    reloadAppTheme();
  }

  /** 主题色流光：只影响流光取色，卡片与圆形按钮订阅了它，写一次即可重绘 */
  private setPressGlow(enabled: boolean): void {
    AppearanceStore.setBoolean(PRESS_GLOW_STORAGE, enabled);
    AppStorage.setOrCreate(PRESS_GLOW_STORAGE, enabled);
  }

  /** 卡片流光触感：只改卡片上画不画流光，**与底栏流光无关** */
  private setCardGlowTouch(enabled: boolean): void {
    AppearanceStore.setBoolean(CARD_GLOW_TOUCH_STORAGE, enabled);
    AppStorage.setOrCreate(CARD_GLOW_TOUCH_STORAGE, enabled);
  }

  // ==================== 自定义色：新增 / 编辑 / 删除 ====================

  private openAddDialog(): void {
    this.editingHex = '';
    // 昵称放在色值**前面**：它才是用户真正看到的标签
    this.dialogName = '';
    // 默认填当前主题色，用户改一两个字符就能得到一个相近的新色
    this.dialogHex = this.currentAccent().replace('#', '');
    this.hexError = '';
    this.showAccentDialog = true;
  }

  private startEditAccent(hex: string): void {
    this.editingHex = hex;
    let name = '';
    for (let i = 0; i < this.accentList.length; i++) {
      if (this.accentList[i].hex.toUpperCase() === hex.toUpperCase()) {
        name = this.accentList[i].name;
        break;
      }
    }
    this.dialogHex = hex;
    this.dialogName = name;
    this.hexError = '';
    this.showAccentDialog = true;
  }

  /**
   * 保存自定义色。
   *
   * 编辑模式下若把色值改成列表里**已存在**的一项，会**合并**成一项（不产生重复色值）；
   * 改的正好是当前选中色时，`accentCustom` 与选中态一起跟着改，
   * 不会出现「选中态凭空消失」。
   */
  private saveAccent(): void {
    const normalized = normalizeAccentHex(this.dialogHex);
    if (normalized.length === 0) {
      this.hexError = '请输入 6 位十六进制色值，例如 0A59F7';
      return;
    }
    const hex = normalized.replace('#', '').toUpperCase();
    const name = this.dialogName.trim();
    const editing = this.editingHex.toUpperCase();

    const next: AccentCustom[] = [];
    for (let i = 0; i < this.accentList.length; i++) {
      const entry = this.accentList[i];
      if (entry.hex.toUpperCase() === editing) {
        continue;
      }
      if (entry.hex.toUpperCase() === hex) {
        // 合并：保留已有项，补上新昵称
        if (name.length > 0) {
          next.push({ hex: entry.hex, name: name });
        } else {
          next.push(entry);
        }
        continue;
      }
      next.push(entry);
    }
    // 若合并没有命中任何已有项，则作为新项加入
    let merged = false;
    for (let i = 0; i < next.length; i++) {
      if (next[i].hex.toUpperCase() === hex) {
        merged = true;
        break;
      }
    }
    if (!merged) {
      next.push({ hex: hex, name: name });
    }
    this.accentList = next;
    this.persistAccentList();

    // 编辑的正好是当前选中色 → 选中值跟着改
    if (editing.length === 6 && this.isCustomSelected(editing)) {
      this.accentCustom = hex;
      AppearanceStore.setString(ACCENT_CUSTOM_STORAGE, hex);
      this.applyAccentNow();
    }
    this.showAccentDialog = false;
  }

  /**
   * 删除自定义色。
   * 删掉的正好是当前选中色时，**回落到第一个预设**，
   * 避免 `accentCustom` 指向一个列表里已经不存在、界面上也没有的色值。
   */
  private removeCustomAccent(hex: string): void {
    const next: AccentCustom[] = [];
    for (let i = 0; i < this.accentList.length; i++) {
      if (this.accentList[i].hex.toUpperCase() !== hex.toUpperCase()) {
        next.push(this.accentList[i]);
      }
    }
    this.accentList = next;
    this.persistAccentList();
    if (this.isCustomSelected(hex)) {
      const fallback: AccentPreset = ACCENT_PRESETS[0];
      this.accentKey = fallback.key;
      this.accentCustom = '';
      AppearanceStore.setString(ACCENT_KEY_STORAGE, fallback.key);
      AppearanceStore.setString(ACCENT_CUSTOM_STORAGE, '');
      this.applyAccentNow();
    }
  }

  // ==================== 深色模式（三态） ====================

  /** 读系统当前深浅色（偏好为「跟随系统」时用） */
  private systemDarkMode(): boolean {
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      const config = ctx.getApplicationContext().resourceManager.getConfigurationSync();
      return config.colorMode === resourceManager.ColorMode.DARK;
    } catch (err) {
      return false;
    }
  }

  /**
   * 切换深色模式偏好。
   *
   * 三个必须同时做对的点：
   *   ① **平台配色要和自绘颜色一起下发**：`setColorMode()` 管系统控件
   *      （弹窗、输入法、滚动条），`applyAppTheme()` 管自绘颜色；
   *      只做后者会出现「自绘是浅色、系统弹窗是深色」的错配。
   *   ② **`COLOR_MODE_NOT_SET` 表示交还给系统**：用户没选过时下发这个值，
   *      系统切深浅色应用会自动跟；一旦下发过明确值，就**不再跟随**。
   *   ③ **`applyAppTheme` 必须带上当前主题色**，否则背景染色被重置回默认。
   */
  private setDarkModePref(pref: string): void {
    this.darkModePref = pref;
    AppearanceStore.setString(DARK_MODE_PREF_STORAGE, pref);
    AppStorage.setOrCreate(DARK_MODE_PREF_STORAGE, pref);
    const enabled: boolean = pref === DARK_MODE_DARK ? true
      : (pref === DARK_MODE_LIGHT ? false : this.systemDarkMode());
    this.applyDarkMode(enabled, pref);
  }

  private applyDarkMode(enabled: boolean, pref: string): void {
    // ⚠️ 必须把当前主题色一并传入：背景色是按主题色染的，只传 isDark 会把染色重置回默认
    applyAppTheme(enabled, this.currentAccent());
    // isDarkMode 是 @StorageLink，赋值会同步写回 AppStorage，其余订阅该键的页面随即重建
    AppStorage.setOrCreate('isDarkMode', enabled);
    AppStorage.setOrCreate(ACCENT_KEY_STORAGE, this.accentKey);
    AppStorage.setOrCreate(ACCENT_CUSTOM_STORAGE, this.accentCustom);
    AppStorage.setOrCreate('accentColor', this.accentColor);
    try {
      const mode = pref === DARK_MODE_DARK
        ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
        : (pref === DARK_MODE_LIGHT
          ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
          : ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
      (getContext(this) as common.UIAbilityContext).getApplicationContext().setColorMode(mode);
    } catch (err) {
    }
  }

  /** 当前选中色（用于解析最终色值） */
  private currentAccent(): string {
    return resolveAccentColor(this.accentKey, this.accentCustom);
  }

  // ==================== UI 片段 ====================

  @Builder
  sectionTitle(text: string, note: string) {
    Column({ space: 4 }) {
      Text(text)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(hwTextPrimary(this.isDarkMode))
      if (note.length > 0) {
        Text(note)
          .fontSize(12)
          .fontColor(hwTextSecondary(this.isDarkMode))
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .margin({ top: HwSpace.lg, bottom: HwSpace.md })
  }

  /**
   * 外观模式三态芯片。
   *
   * 结构是「选中态芯片」的标准写法：
   *   自绘底色 + 材质承载层（小尺寸 → layerShadow: false）+ 文字触摸穿透。
   *
   * ⚠️ `MaterialCardLayer` 用 ToggleType.Button 承载材质，它是**画布**，
   *    所以文字要设 `hitTestBehavior(HitTestMode.None)`，
   *    点击交给外层的 Stack 响应。
   */
  @Builder
  darkModeChip(mode: string, label: string) {
    Stack() {
      Row()
        .width(LayoutPolicy.matchParent)
        .height(LayoutPolicy.matchParent)
        .borderRadius(HwRadius.pill)
        .backgroundColor(this.darkModePref === mode
          ? this.accentOrPrimary() : withAlpha(HwColor.textPrimary, 0.06))

      // 小尺寸芯片关掉材质自带投影
      MaterialCardLayer({ layerRadius: HwRadius.pill, layerShadow: false })

      Text(label)
        .fontSize(13)
        // 主题色底上的字色按亮度自动取黑/白（浅色主题色上白字看不清）
        .fontColor(this.darkModePref === mode
          ? onAccentColor(this.accentOrPrimary()) : hwTextPrimary(this.isDarkMode))
        .padding({ left: 16, right: 16, top: 7, bottom: 7 })
        .hitTestBehavior(HitTestMode.None)
        .accessibilityLevel('no')
    }
    .onClick((): void => {
      this.setDarkModePref(mode);
    })
  }

  /**
   * 一个主题色色块。
   *
   * 预设色块与自定义色块**完全同构**（圆点 + 名称），差别有两处：
   *   · 自定义色 `removable` 为 true：右上角叠删除角标，且**长按可编辑**；
   *   · 标签只显示**昵称**（没起名字才回落 `#RRGGBB`），界面上不展示色值本身。
   *
   * ⚠️ 删除角标是色块的**兄弟节点**而不是子节点：ArkUI 的点击会向父级冒泡，
   *    做成子节点的话点删除会**连带触发一次选中**。
   */
  @Builder
  accentSwatch(hex: string, color: string, label: string, selected: boolean, removable: boolean) {
    Stack({ alignContent: Alignment.TopEnd }) {
      Stack() {
        // 与卡片同源的 Toggle 承载层：小尺寸芯片关掉材质自带投影
        MaterialCardLayer({ layerRadius: HwRadius.control, layerShadow: false })

        Column({ space: 6 }) {
          Stack({ alignContent: Alignment.Center }) {
            Circle()
              .width(34)
              .height(34)
              .fill(color)
            if (selected) {
              // 对勾压在这个色块**自己的颜色**上：
              // 浅色主题色（涟漪粉 / 流荧绿）上白勾看不见，按亮度自动切黑勾
              SymbolGlyph($r('sys.symbol.checkmark'))
                .fontSize(16)
                .fontColor([onAccentColor(color)])
            }
          }
          .width(34)
          .height(34)

          Text(label)
            .fontSize(12)
            .fontColor(selected ? this.accentOrPrimary() : hwTextSecondary(this.isDarkMode))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width(64)
        .padding(8)
        .borderRadius(HwRadius.control)
        .backgroundColor(Color.Transparent)
        .backgroundEffect(cardGlassEffect(false, false, this.isDarkMode, false))
        .border({ width: 1, color: cardGlassBorderColor(false, true, this.isDarkMode, false) })
        .clip(true)
        .shadow(cardGlassShadow(false, true, this.isDarkMode, false))
        .onClick((): void => {
          if (removable) {
            this.selectCustomAccent(hex);
          } else {
            this.selectAccentPreset(hex);
          }
        })
      }
      .width(64)
      .borderRadius(HwRadius.control)
      // 长按编辑：只对自定义色挂手势，内置预设不响应
      .gesture(
        LongPressGesture()
          .onAction((): void => {
            if (removable) {
              this.startEditAccent(hex);
            }
          })
      )

      if (removable) {
        // 删除角标：半透明黑底保证在浅色/深色材质上都看得清
        Stack({ alignContent: Alignment.Center }) {
          Circle()
            .width(20)
            .height(20)
            .fill('#99000000')
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(11)
            .fontColor([Color.White])
        }
        .width(20)
        .height(20)
        .margin({ top: 4, right: 4 })
        .onClick((): void => {
          this.removeCustomAccent(hex);
        })
      }
    }
    .margin({ right: HwSpace.md, bottom: HwSpace.md })
  }

  /** 「新增自定义色」按钮：与色块同尺寸同排版，只把圆点换成加号 */
  @Builder
  addAccentSwatch() {
    Stack() {
      MaterialCardLayer({ layerRadius: HwRadius.control, layerShadow: false })
      Column({ space: 6 }) {
        Stack({ alignContent: Alignment.Center }) {
          Circle()
            .width(34)
            .height(34)
            .fill(withAlpha(HwColor.textPrimary, 0.08))
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(18)
            .fontColor([hwTextSecondary(this.isDarkMode)])
        }
        .width(34)
        .height(34)

        Text('自定义')
          .fontSize(12)
          .fontColor(hwTextSecondary(this.isDarkMode))
          .maxLines(1)
      }
      .width(64)
      .padding(8)
      .borderRadius(HwRadius.control)
      .backgroundColor(Color.Transparent)
      .backgroundEffect(cardGlassEffect(false, false, this.isDarkMode, false))
      .border({ width: 1, color: cardGlassBorderColor(false, true, this.isDarkMode, false) })
      .clip(true)
      .shadow(cardGlassShadow(false, true, this.isDarkMode, false))
    }
    .width(64)
    .margin({ right: HwSpace.md, bottom: HwSpace.md })
    .onClick((): void => {
      this.openAddDialog();
    })
  }

  build() {
    Stack() {
      DemoScaffold({
        title: '外观设置',
        subtitle: '主题色 / 外观模式 / 沉浸光感',
        onBack: (): void => {
          router.back();
        }
      }) {
        // ==================== 主题色 ====================
        this.sectionTitle('主题色', '影响开关、选中态、链接与高亮文字等全局配色')

        ThemedCard() {
          Column({ space: HwSpace.md }) {
            SwitchRow({
              label: '主题色',
              hint: '关闭后所有主题色不生效，回到默认配色；你选过的颜色会保留',
              isOn: this.themeColorEnabled,
              onToggle: (value: boolean): void => {
                this.setThemeColorEnabled(value);
              }
            })

            if (!this.themeColorEnabled) {
              // 关掉总开关后色块与延伸开关一起收起，避免「选了没反应」的困惑
              // （用户的选择仍然保留在存储里，重新打开即恢复）
              Text('已关闭：配色回到默认样式，你选过的颜色会保留，重新打开即恢复')
                .fontSize(12)
                .fontColor(hwTextSecondary(this.isDarkMode))
                .width('100%')
            } else {
              Flex({ wrap: FlexWrap.Wrap }) {
                // key 必须带上**选中态**：ForEach 会复用 key 相同的项，
                // 键不变就不重建子节点，对号会一直停在上一个被点的色块上
                ForEach(ACCENT_PRESETS, (preset: AccentPreset): void => {
                  this.accentSwatch(preset.key, preset.value, preset.label,
                    this.accentKey === preset.key, false)
                }, (preset: AccentPreset): string =>
                `preset_${preset.key}_${this.accentKey === preset.key ? 1 : 0}_${this.accentColor}`)

                // 自定义色：key 要同时带上「色值 + 昵称 + 选中态」。
                // 漏掉昵称的表现是「改完昵称，色块上的字没变」
                ForEach(this.accentList, (entry: AccentCustom): void => {
                  this.accentSwatch(entry.hex, `#${entry.hex}`, accentEntryLabel(entry),
                    this.isCustomSelected(entry.hex), true)
                }, (entry: AccentCustom): string =>
                `custom_${entry.hex}_${entry.name}_${this.isCustomSelected(entry.hex) ? 1 : 0}_${this.accentColor}`)

                this.addAccentSwatch()
              }
              .width('100%')

              Text('长按自定义色块可改色值或昵称；点右上角 ✕ 删除')
                .fontSize(11)
                .fontColor(hwTextSecondary(this.isDarkMode))
            }
          }
          .width('100%')
        }

        SourceBlock({
          caption: '「设置三连」与派生 token 的刷新时机',
          source: SRC_SET_ACCENT_SOURCE,
          code: SRC_SET_ACCENT
        })

        // ==================== 主题色延伸 ====================
        if (this.themeColorEnabled) {
          ThemedCard() {
            Column({ space: HwSpace.md }) {
              SwitchRow({
                label: '卡片沾色',
                hint: '卡片叠一层 10% 主题色（叠在材质之上，不是混进底色）',
                isOn: this.cardTintEnabled,
                onToggle: (value: boolean): void => {
                  this.setCardTint(value);
                }
              })
              SwitchRow({
                label: '高权限自定义主题色',
                hint: '默认只有内置预设色参与页面背景淡染；打开后自定义色也放行',
                isOn: this.customAccentFullAccess,
                rowDivider: true,
                onToggle: (value: boolean): void => {
                  this.setCustomAccentFullAccess(value);
                }
              })
            }
            .width('100%')
          }
        }

        // ==================== 外观模式（三态） ====================
        this.sectionTitle('外观模式', '跟随系统时，系统切换深浅色应用会自动跟随')

        ThemedCard() {
          Column({ space: HwSpace.md }) {
            Row({ space: HwSpace.sm }) {
              this.darkModeChip(DARK_MODE_SYSTEM, '跟随系统')
              this.darkModeChip(DARK_MODE_LIGHT, '浅色')
              this.darkModeChip(DARK_MODE_DARK, '深色')
            }
            .width('100%')
          }
          .width('100%')
        }

        SourceBlock({
          caption: '三态偏好 + 平台配色一起下发',
          source: SRC_SET_MODE_SOURCE,
          code: SRC_SET_MODE
        })

        // ==================== 沉浸光感 ====================
        this.sectionTitle('沉浸光感', 'API 26 起的系统材质；不可用时自动降级为毛玻璃')

        ThemedCard() {
          Column({ space: HwSpace.md }) {
            SwitchRow({
              label: '全局沉浸光感',
              hint: '开启后卡片改由系统材质承载，关闭则全部回退毛玻璃',
              isOn: this.immersiveLightEnabled,
              onToggle: (value: boolean): void => {
                AppearanceStore.setBoolean('immersiveLightEnabled', value);
              }
            })

            // 诊断行：两个入参必须是**订阅值**，否则这行不会随切色/拨开关刷新
            if (this.immersiveLightEnabled && isApi26OrAbove()) {
              Text(materialDiagnostics(this.pressGlowEnabled, this.accentColor))
                .fontSize(11)
                .fontColor(hwTextSecondary(this.isDarkMode))
                .width('100%')
            }

            SwitchRow({
              label: '主题色流光',
              hint: '按压卡片的流光与光晕用主题色；关 = 系统默认白光',
              isOn: this.pressGlowEnabled,
              rowDivider: true,
              onToggle: (value: boolean): void => {
                this.setPressGlow(value);
              }
            })

            SwitchRow({
              label: '卡片流光触感',
              hint: '开 = 按压卡片出现跟手流光；关 = 按压卡片一点光都不出现',
              isOn: this.cardGlowTouch,
              rowDivider: true,
              onToggle: (value: boolean): void => {
                this.setCardGlowTouch(value);
              }
            })
          }
          .width('100%')
        }

        SourceBlock({
          caption: '开关只广播；生效判定要三者同时成立',
          source: SRC_SET_LIGHT_SOURCE,
          code: SRC_SET_LIGHT
        })

        // ==================== 当前解析结果 ====================
        this.sectionTitle('当前生效值', '用来核对「设置 → 解析 → 广播」这条链路')

        ThemedCard() {
          Column({ space: 6 }) {
            Text(`accentKey        = ${this.accentKey}`)
              .fontSize(11)
              .fontColor(hwTextSecondary(this.isDarkMode))
            Text(`accentCustom     = ${this.accentCustom.length > 0 ? this.accentCustom : '(空)'}`)
              .fontSize(11)
              .fontColor(hwTextSecondary(this.isDarkMode))
            Text(`currentAccent()  = ${this.currentAccent()}`)
              .fontSize(11)
              .fontColor(hwTextSecondary(this.isDarkMode))
            Text(`accentColor(广播) = ${this.accentColor}`)
              .fontSize(11)
              .fontColor(hwTextSecondary(this.isDarkMode))
            Text(`isDarkMode       = ${this.isDarkMode}`)
              .fontSize(11)
              .fontColor(hwTextSecondary(this.isDarkMode))
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }

        SourceBlock({
          caption: '「设置 → 解析 → 广播」这条链路',
          source: SRC_SET_RESOLVED_SOURCE,
          code: SRC_SET_RESOLVED
        })
      }
    }
    .width('100%')
    .height('100%')
    // 自定义色弹窗：昵称在前（它是用户真正看到的标签），色值在后
    .bindSheet($$this.showAccentDialog, this.accentDialog(), {
      height: 360,
      dragBar: true,
      showClose: false,
      backgroundColor: Color.Transparent
    })
  }

  /** 自定义主题色弹窗（新增 / 编辑共用） */
  @Builder
  accentDialog() {
    // ⚠️ 半模态面板**不能**只靠 `bindSheet` 的 `backgroundColor: Color.Transparent`。
    //    沉浸光感生效时，材质由 `sheetSystemMaterial()` 提供；而在低版本 / 开关关闭 /
    //    材质构造失败时，必须由 `MaterialSheetPanel` 给出兜底底色，
    //    否则面板整体透明 —— 只剩一层模糊，文字像悬在遮罩上（见 docs/PITFALLS.md B6）。
    MaterialSheetPanel({ panelPadding: HwSpace.lg }) {
      Column({ space: HwSpace.lg }) {
        Text(this.editingHex.length > 0 ? '编辑主题色' : '自定义主题色')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(hwTextPrimary(this.isDarkMode))

        Column({ space: HwSpace.sm }) {
          Text('昵称（可选，色块上显示它）')
            .fontSize(12)
            .fontColor(hwTextSecondary(this.isDarkMode))
          TextInput({ text: this.dialogName, placeholder: '例如：我的羊绒色' })
            .caretColor(this.accentOrPrimary())
            .fontSize(14)
            .fontColor(hwTextPrimary(this.isDarkMode))
            .backgroundColor(withAlpha(HwColor.textPrimary, 0.05))
            .borderRadius(HwRadius.control)
            .maxLength(12)
            .width('100%')
            .onChange((value: string): void => {
              this.dialogName = value;
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        Column({ space: HwSpace.sm }) {
          Text('色值（6 位十六进制，可带 #）')
            .fontSize(12)
            .fontColor(hwTextSecondary(this.isDarkMode))
          TextInput({ text: this.dialogHex, placeholder: '例如：0A59F7' })
            .caretColor(this.accentOrPrimary())
            .fontSize(14)
            .fontColor(hwTextPrimary(this.isDarkMode))
            .backgroundColor(withAlpha(HwColor.textPrimary, 0.05))
            .borderRadius(HwRadius.control)
            .maxLength(7)
            .width('100%')
            .onChange((value: string): void => {
              this.dialogHex = value;
              this.hexError = '';
            })
          if (this.hexError.length > 0) {
            Text(this.hexError)
              .fontSize(11)
              // ⚠️ 走 hwDanger(isDark)：直接读 HwColor.danger 在深色模式下
              //    仍是浅色模式的 #D94838，深底上对比度不足。
              .fontColor(hwDanger(this.isDarkMode))
          } else if (normalizeAccentHex(this.dialogHex).length > 0) {
            // 实时预览：让用户输入时就看到颜色
            Row({ space: HwSpace.sm }) {
              Circle()
                .width(18)
                .height(18)
                .fill(normalizeAccentHex(this.dialogHex))
              Text(`预览 ${normalizeAccentHex(this.dialogHex)}`)
                .fontSize(11)
                .fontColor(hwTextSecondary(this.isDarkMode))
            }
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        Row({ space: HwSpace.md }) {
          Text('取消')
            .fontSize(14)
            .fontColor(hwTextSecondary(this.isDarkMode))
            .padding({ left: 20, right: 20, top: 10, bottom: 10 })
            .borderRadius(HwRadius.pill)
            .backgroundColor(withAlpha(HwColor.textPrimary, 0.06))
            .onClick((): void => {
              this.showAccentDialog = false;
            })
          Text(this.editingHex.length > 0 ? '保存' : '添加')
            .fontSize(14)
            .fontColor(onAccentColor(this.accentOrPrimary()))
            .padding({ left: 20, right: 20, top: 10, bottom: 10 })
            .borderRadius(HwRadius.pill)
            .backgroundColor(this.accentOrPrimary())
            .onClick((): void => {
              this.saveAccent();
            })
        }
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }
}
