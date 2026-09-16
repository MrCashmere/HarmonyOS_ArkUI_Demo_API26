/**
 * 应用入口能力（EntryAbility）—— 教学版
 * 对应 `CLink/entry/src/main/ets/entryability/EntryAbility.ets`。
 *
 * ────────────────────────────────────────────────────────────────────────────
 * 本文件承担「启动初始化」这一步，它是主题色能不能在**首帧**就正确的关键
 * ────────────────────────────────────────────────────────────────────────────
 * 必须在这里做完、且**必须在 loadContent 之前**做完：
 *   ① `AppearanceStore.init(context)` —— 打开 preferences（后面读设置要用）；
 *   ② 读出深色模式偏好并 **`setColorMode()`** —— 管**系统控件**
 *      （弹窗、输入法、滚动条）的配色；
 *   ③ 把设置写进 `AppStorage`（`accentKey` / `accentCustom` 等）——
 *      页面的 `@StorageLink` 才有初值，否则会「点一下弹回去」；
 *   ④ `applyAppTheme(是否深色, 生效主题色)` + 写 `accentColor` 广播键
 *      —— 管**自绘颜色**。
 *
 * **漏掉第 ④ 步的后果**：首屏会用默认蓝渲染，切到另一个页面才变色
 * （那种「颜色要切页才生效」的怪现象，根因就在这里）。
 *
 * ⚠️ 第 ② 与第 ④ 步**缺一不可**：只做 `applyAppTheme` 会出现
 *    「自绘是浅色、系统弹窗是深色」的错配；只做 `setColorMode` 则自绘颜色不跟着走。
 */

import { AbilityConstant, common, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { resourceManager } from '@kit.LocalizationKit';
import { window } from '@kit.ArkUI';
import { AppearanceStore } from '../storage/AppearanceStore';
import {
  ACCENT_COLOR_KEY,
  ACCENT_CUSTOM_STORAGE,
  ACCENT_KEY_STORAGE,
  applyAppTheme,
  BOOT_ACCENT_STORAGE,
  CARD_GLOW_TOUCH_STORAGE,
  CARD_TINT_STORAGE,
  CUSTOM_ACCENT_FULL_ACCESS_STORAGE,
  DARK_MODE_DARK,
  DARK_MODE_KEY,
  DARK_MODE_LIGHT,
  DARK_MODE_PREF_STORAGE,
  DARK_MODE_SYSTEM,
  DEFAULT_ACCENT_KEY,
  effectiveAccentColor,
  isPresetAccentKey,
  PRESS_GLOW_STORAGE,
  THEME_COLOR_ENABLED_STORAGE
} from '../utils/DesignTokens';

export default class EntryAbility extends UIAbility {
  private mainWindow: window.Window | null = null;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // ① 打开持久化存储（后面所有读设置都依赖它）
    AppearanceStore.init(this.context);

    // ② 深色模式偏好（三态）：必须在**首屏渲染前**解析出来，
    //    并把平台配色一起下发——setColorMode() 管系统控件，applyAppTheme() 管自绘颜色。
    const darkModePref: string = EntryAbility.resolveDarkModePref();
    AppStorage.setOrCreate(DARK_MODE_PREF_STORAGE, darkModePref);
    try {
      this.context.getApplicationContext().setColorMode(EntryAbility.resolveColorMode(darkModePref));
    } catch (err) {
    }

    // ③ 读外观设置并写进 AppStorage。
    //    ⚠️ 顺序很重要：主题色的两个延伸开关必须在 applyAppTheme **之前**落进
    //       AppStorage，因为 applyAppTheme 会读它们来决定
    //       「卡片沾色层要不要画」「页面背景要不要跟随自定义色」。
    const immersiveLightEnabled: boolean = AppearanceStore.getBoolean('immersiveLightEnabled', true);
    const cardTintEnabled: boolean = AppearanceStore.getBoolean(CARD_TINT_STORAGE, false);
    const customAccentFullAccess: boolean =
      AppearanceStore.getBoolean(CUSTOM_ACCENT_FULL_ACCESS_STORAGE, false);
    const themeColorEnabled: boolean = AppearanceStore.getBoolean(THEME_COLOR_ENABLED_STORAGE, true);
    const pressGlow: boolean = AppearanceStore.getBoolean(PRESS_GLOW_STORAGE, true);
    //    卡片流光触感：本 Demo **默认开**（上游 CLink 默认关）
    const cardGlowTouch: boolean = AppearanceStore.getBoolean(CARD_GLOW_TOUCH_STORAGE, true);

    AppStorage.setOrCreate('immersiveLightEnabled', immersiveLightEnabled);
    AppStorage.setOrCreate(CARD_TINT_STORAGE, cardTintEnabled);
    AppStorage.setOrCreate(CUSTOM_ACCENT_FULL_ACCESS_STORAGE, customAccentFullAccess);
    AppStorage.setOrCreate(THEME_COLOR_ENABLED_STORAGE, themeColorEnabled);
    AppStorage.setOrCreate(PRESS_GLOW_STORAGE, pressGlow);
    AppStorage.setOrCreate(CARD_GLOW_TOUCH_STORAGE, cardGlowTouch);

    // ④ 深色模式的实际取值 + 主题色
    const darkModeEnabled: boolean = EntryAbility.resolveDarkMode(this.context, darkModePref);
    AppStorage.setOrCreate(DARK_MODE_KEY, darkModeEnabled);

    // 持久化键要先建好（页面的 @StorageLink 才有初值），
    // 解析出颜色后写 accentColor 并调 applyAppTheme。
    const accentKey: string = EntryAbility.resolveAccentKey();
    const accentCustom: string = AppearanceStore.getString(ACCENT_CUSTOM_STORAGE, '');
    // ⚠️ 走 effectiveAccentColor 而不是 resolveAccentColor：
    //    总开关关闭时要连**广播值**一起换回默认色（见 DesignTokens 里的坑 5）
    const accentColor: string = effectiveAccentColor(accentKey, accentCustom);
    AppStorage.setOrCreate(ACCENT_KEY_STORAGE, accentKey);
    AppStorage.setOrCreate(ACCENT_CUSTOM_STORAGE, accentCustom);
    AppStorage.setOrCreate(ACCENT_COLOR_KEY, accentColor);
    applyAppTheme(darkModeEnabled, accentColor);

    // ⑤ 启动快照：把「启动那一刻的主题色」定死，之后**永不更新**。
    //    只服务于 ThemeLabPage 的「反面对照」（演示「颜色被定死在启动时」这种写法）。
    //    ⚠️ 必须放在 applyAppTheme 之后：要拿的是**生效后**的真实颜色。
    //    也正因为它只写这一次，它才不受「页面模块重新求值 / 组件重建」影响 ——
    //    在页面里写模块级常量或 @Prop 默认值都冻不住（两条路都实测过）。
    AppStorage.setOrCreate(BOOT_ACCENT_STORAGE, accentColor);
  }

  /**
   * 读主题色设置里的 key，顺带兜底：
   * 旧版本或异常写入可能留下一个**已经不存在的预设 key**，
   * 这时回落默认预设并写回存储。
   */
  private static resolveAccentKey(): string {
    const stored: string = AppearanceStore.getString(ACCENT_KEY_STORAGE, DEFAULT_ACCENT_KEY);
    if (stored === 'custom' || isPresetAccentKey(stored)) {
      return stored;
    }
    AppearanceStore.setString(ACCENT_KEY_STORAGE, DEFAULT_ACCENT_KEY);
    return DEFAULT_ACCENT_KEY;
  }

  /** 读深色模式偏好；没有记录时一律「跟随系统」 */
  private static resolveDarkModePref(): string {
    try {
      const stored: string = AppearanceStore.getString(DARK_MODE_PREF_STORAGE, '');
      if (stored === DARK_MODE_SYSTEM || stored === DARK_MODE_LIGHT || stored === DARK_MODE_DARK) {
        return stored;
      }
    } catch (err) {
    }
    return DARK_MODE_SYSTEM;
  }

  /** 偏好为「跟随系统」时读系统，其余按偏好取值 */
  private static resolveDarkMode(context: common.UIAbilityContext, pref: string): boolean {
    if (pref === DARK_MODE_DARK) {
      return true;
    }
    if (pref === DARK_MODE_LIGHT) {
      return false;
    }
    return EntryAbility.systemDarkMode(context);
  }

  /** 读系统当前的深色模式 */
  private static systemDarkMode(context: common.UIAbilityContext): boolean {
    try {
      const config = context.getApplicationContext().resourceManager.getConfigurationSync();
      return config.colorMode === resourceManager.ColorMode.DARK;
    } catch (err) {
      return false;
    }
  }

  /**
   * 跟随系统时下发 `COLOR_MODE_NOT_SET` 把配色权**交还系统**；选了明确值才固定。
   * 只要下发过 `COLOR_MODE_DARK` / `COLOR_MODE_LIGHT`，
   * 系统再切深浅色应用也**不会**跟——这就是「跟随系统」必须用三态表达的原因。
   */
  private static resolveColorMode(pref: string): ConfigurationConstant.ColorMode {
    if (pref === DARK_MODE_DARK) {
      return ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    }
    if (pref === DARK_MODE_LIGHT) {
      return ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    }
    return ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    const isDarkMode: boolean = AppStorage.get<boolean>(DARK_MODE_KEY) === true;
    // 状态栏/导航栏内容色随深浅模式切换：深色用浅色文字，浅色用深色文字。
    // 背景保持透明，由页面通过 expandSafeArea 顶到状态栏并自行铺色。
    const statusContentColor: string = isDarkMode ? '#F0F2F5' : '#182431';
    const mainWindow = windowStage.getMainWindowSync();
    this.mainWindow = mainWindow;
    mainWindow.setWindowLayoutFullScreen(true).catch((err: Error) => {
      console.error(`setWindowLayoutFullScreen failed: ${err.message}`);
    });
    mainWindow.setWindowSystemBarProperties({
      statusBarColor: '#00000000',
      navigationBarColor: '#00000000',
      statusBarContentColor: statusContentColor,
      navigationBarContentColor: statusContentColor
    }).catch((err: Error) => {
      console.error(`setWindowSystemBarProperties failed: ${err.message}`);
    });

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        console.error(`loadContent failed: ${JSON.stringify(err)}`);
        return;
      }
      // 把状态栏高度发布出去，页面据此避让（Index 的 header 用到）
      this.publishWindowInsets(mainWindow);
      mainWindow.on('avoidAreaChange', (): void => {
        this.publishWindowInsets(mainWindow);
      });
    });
  }

  private publishWindowInsets(win: window.Window): void {
    try {
      const uiContext = win.getUIContext();
      const systemArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const navArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      const statusBarHeight = uiContext.px2vp(systemArea.topRect.height);
      const navigationBarHeight = Math.max(
        uiContext.px2vp(systemArea.bottomRect.height),
        uiContext.px2vp(navArea.bottomRect.height)
      );
      AppStorage.setOrCreate('statusBarHeight', statusBarHeight);
      AppStorage.setOrCreate('navigationBarHeight', navigationBarHeight);
    } catch (err) {
      console.error('publishWindowInsets failed');
    }
  }

  onWindowStageDestroy(): void {
    if (this.mainWindow !== null) {
      // 窗口销毁后对旧引用调 off 会抛 1300002，且监听器随窗口销毁自动释放
      try {
        this.mainWindow.off('avoidAreaChange');
      } catch (err) {
      }
      this.mainWindow = null;
    }
  }

  onDestroy(): void {
  }

  /**
   * 系统深浅色变化。
   *
   * ⚠️ **这个回调会被 `setColorMode()` 同步触发**，所以它内部**不能**再调
   *    `setColorMode()`，否则会自激。
   * ⚠️ 也必须把**已保存的主题色**一起传进 `applyAppTheme`：
   *    只传 `isDark` 会把页面背景染色重置回默认色。
   */
  onConfigurationUpdate(newConfig: Configuration): void {
    let pref: string = DARK_MODE_SYSTEM;
    try {
      const stored = AppStorage.get<string>(DARK_MODE_PREF_STORAGE);
      if (stored !== undefined && stored.length > 0) {
        pref = stored;
      }
    } catch (err) {
      pref = DARK_MODE_SYSTEM;
    }
    const systemDark: boolean =
      newConfig.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    const isDarkMode: boolean = pref === DARK_MODE_DARK ? true
      : (pref === DARK_MODE_LIGHT ? false : systemDark);
    AppStorage.setOrCreate(DARK_MODE_KEY, isDarkMode);
    try {
      const accentColor = effectiveAccentColor(
        AppearanceStore.getString(ACCENT_KEY_STORAGE, DEFAULT_ACCENT_KEY),
        AppearanceStore.getString(ACCENT_CUSTOM_STORAGE, ''));
      applyAppTheme(isDarkMode, accentColor);
      AppStorage.setOrCreate(ACCENT_COLOR_KEY, accentColor);
    } catch (err) {
      applyAppTheme(isDarkMode);
    }
    // 同步刷新状态栏/导航栏内容色，避免深色模式下状态栏文字仍是深色
    try {
      if (this.mainWindow !== null) {
        const statusContentColor: string = isDarkMode ? '#F0F2F5' : '#182431';
        this.mainWindow.setWindowSystemBarProperties({
          statusBarColor: '#00000000',
          navigationBarColor: '#00000000',
          statusBarContentColor: statusContentColor,
          navigationBarContentColor: statusContentColor
        });
      }
    } catch (err) {
    }
  }
}
