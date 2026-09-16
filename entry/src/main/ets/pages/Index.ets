/**
 * 入口页：教学 Demo 导航（Index）
 * ============================================================================
 * 同时也是**主页最简单的示范**：整个应用只有一处「壳」，
 * 这里演示了主题色在页面级的三种典型用法：
 *   · 页面底色  → resolvePageBackground（不能直接读 HwColor.background）
 *   · 标题/图标 → resolvePrimaryColor
 *   · 强调块    → 主题色 + onAccentColor 自动前景
 */

import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import { common, Want } from '@kit.AbilityKit';
import {
  HwColor,
  HwRadius,
  HwSpace,
  hwTextPrimary,
  hwTextSecondary,
  onAccentColor,
  reloadAppTheme,
  resolvePageBackground,
  resolvePrimaryColor,
  withAlpha
} from '../utils/DesignTokens';
import { AccentColorSentinel } from '../components/MaterialCard';
import { SwitchRow, ThemedCard } from '../components/DemoScaffold';
import { immersiveCardsActive, toastSystemMaterial } from '../utils/SystemMaterial';
import { AppearanceStore } from '../storage/AppearanceStore';

/**
 * 「关于」卡片要贴的项目地址（本工程自己的仓库）。
 *
 * 地址留空时的降级表现也保留了（不是必须的，但作为示例有用）：
 *    · 卡片照常显示，地址位显示「待填写」，点击给一句 Toast 提示，
 *      而不是「点了没反应」让人以为是坏的。
 */
const PROJECT_URL: string = 'https://github.com/MrCashmere/HarmonyOS_ArkUI_Demo_API26';

/** 关于卡片上的项目标识 */
const PROJECT_TITLE: string = '羊绒应用主题样板';
const PROJECT_SUBTITLE: string = 'CashmereAppThemeDemo';
const PROJECT_DESC: string = '从 CLink 提炼的 HarmonyOS UI 教学样板：主题色 · 深色模式 · 沉浸光感';

/** 一个演示入口 */
interface DemoEntry {
  title: string;
  desc: string;
  route: string;
}

const DEMO_ENTRIES: DemoEntry[] = [
  {
    title: '① 颜色令牌实验室',
    desc: '哪些写法会跟随主题色、哪些不会。含控件选中色与 ForEach key 的坑',
    route: 'pages/ThemeLabPage'
  },
  {
    title: '② 沉浸光感与材质承载',
    desc: '为什么卡片必须用 Toggle 当背板、流光为什么要压在材质之上',
    route: 'pages/ImmersiveShowcasePage'
  },
  {
    title: '③ 外观设置',
    desc: '主题色选择器（预设 + 自定义 + 昵称 + 长按编辑）、三态深色、光感开关',
    route: 'pages/ThemeSettingsPage'
  }
];

@Entry
@Component
struct Index {
  /** 订阅 + @Watch：回调里重算 token（HwColor、页面/卡片底色） */
  @StorageProp('accentColor') @Watch('onAccentColorChanged') accentColor: string = '';
  /** 页面底色广播键：必须订阅它，不能直接读 HwColor.background */
  @StorageProp('pageBackground') pageBackground: string = '';
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('immersivePressGlow') pressGlowSwitch: boolean = true;
  @StorageLink('immersiveLightEnabled') immersiveLightEnabled: boolean = true;

  /**
   * ⚠️ 这个回调**只负责重算 token**，它**不会**让页面重新求值。
   *    真正让页面刷新的是 build 里的 `AccentColorSentinel()`。两者配套使用。
   */
  onAccentColorChanged(): void {
    reloadAppTheme();
  }

  /** 当前主题色：读订阅变量建立依赖 */
  private accentOrPrimary(): string {
    return this.accentColor.length > 0 ? this.accentColor : HwColor.primary;
  }

  /**
   * 打开项目地址。
   *
   * 教学点：跳外部网页**不需要任何权限**，也不需要 Web 组件 ——
   * 构造一个 `ohos.want.action.viewData` + `entity.system.browsable` 的 Want，
   * 交给系统去挑浏览器即可（与参考工程 `AboutPage.openUrl` 写法一致）。
   * 地址留空时只给提示，不静默失败。
   */
  private openProjectUrl(): void {
    if (PROJECT_URL.length === 0) {
      promptAction.showToast({
        systemMaterial: toastSystemMaterial(),
        message: '项目地址待填写'
      });
      return;
    }
    const context = getContext(this) as common.UIAbilityContext;
    const want: Want = {
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: PROJECT_URL
    };
    context.startAbility(want).catch((err: Error) => {
      promptAction.showToast({
        systemMaterial: toastSystemMaterial(),
        message: `打开失败：${err.message}`
      });
    });
  }

  @Builder
  header() {
    Column({ space: HwSpace.sm }) {
      Text('羊绒应用主题样板')
        .fontSize(13)
        .fontColor(resolvePrimaryColor(this.isDarkMode, this.accentOrPrimary()))

      Text('主题色 · 深色模式 · 沉浸光感')
        .fontSize(26)
        .fontWeight(FontWeight.Bold)
        .fontColor(hwTextPrimary(this.isDarkMode))

      Text('从 CLink（羊绒互传）提炼的三套 UI 机制，可独立运行、逐步对照')
        .fontSize(12)
        .fontColor(hwTextSecondary(this.isDarkMode))
        .width('100%')

      // 当前主题色实况条：改主题色时它会立刻变
      Row({ space: HwSpace.sm }) {
        Row()
          .width(18)
          .height(18)
          .borderRadius(9)
          .backgroundColor(this.accentOrPrimary())
        Text(`当前主题色 ${this.accentOrPrimary()}`)
          .fontSize(12)
          .fontColor(onAccentColor(this.accentOrPrimary()))
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: HwSpace.md, right: HwSpace.md, top: 10, bottom: 10 })
      .borderRadius(HwRadius.pill)
      .backgroundColor(this.accentOrPrimary())
      .margin({ top: HwSpace.sm })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({
      left: HwSpace.lg,
      right: HwSpace.lg,
      top: this.statusBarHeight + HwSpace.xl,
      bottom: HwSpace.md
    })
  }

  @Builder
  entryCard(entry: DemoEntry, index: number) {
    // ⚠️ 卡片 = CardSurface（材质背板）+ ThemedCard（玻璃 helper），两者必须成对
    ThemedCard() {
      Row({ space: HwSpace.md }) {
        Text(`${index + 1}`)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(onAccentColor(this.accentOrPrimary()))
          .width(30)
          .height(30)
          .textAlign(TextAlign.Center)
          .borderRadius(15)
          .backgroundColor(this.accentOrPrimary())

        Column({ space: 4 }) {
          Text(entry.title)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(hwTextPrimary(this.isDarkMode))
          Text(entry.desc)
            .fontSize(12)
            .fontColor(hwTextSecondary(this.isDarkMode))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16)
          // ⚠️ SymbolGlyph 的 fontColor 收的是**数组**（ResourceColor[]），
          //    传字符串会报「No overload matches this call」（Text 才是收单个颜色）。
          .fontColor([hwTextSecondary(this.isDarkMode)])
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .onClick((): void => {
        router.pushUrl({ url: entry.route });
      })
    }
  }

  /**
   * 「关于」卡片（页面最底部）——可跳转卡片的标准写法。
   *
   * ① 整张卡片可点：`.onClick` 挂在内容 Column 上，
   *    不影响 CardSurface 自己的按压流光（它走的是 onTouch）；
   * ② 跳转逻辑统一收在 `openProjectUrl()`，地址留空也能安全点击；
   * ③ 图标与描边都走主题色，切色时这张卡片会跟着一起变。
   */
  @Builder
  aboutCard() {
    ThemedCard() {
      Column({ space: HwSpace.sm }) {
        Row({ space: HwSpace.md }) {
          Column({ space: 2 }) {
            Text(PROJECT_TITLE)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(hwTextPrimary(this.isDarkMode))
            Text(PROJECT_SUBTITLE)
              .fontSize(11)
              .fontColor(hwTextSecondary(this.isDarkMode))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          SymbolGlyph($r('sys.symbol.info_circle'))
            .fontSize(16)
            // ⚠️ SymbolGlyph 的 fontColor 收的是**数组**（ResourceColor[]）
            .fontColor([resolvePrimaryColor(this.isDarkMode, this.accentOrPrimary())])
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Text(PROJECT_DESC)
          .fontSize(11)
          .fontColor(hwTextSecondary(this.isDarkMode))
          .width('100%')

        Divider()
          .color(withAlpha(this.accentOrPrimary(), 0.12))
          .margin({ top: HwSpace.xs, bottom: HwSpace.xs })

        // 项目地址行：留空时显示「待填写」，整张卡片仍然可点
        Row({ space: HwSpace.sm }) {
          Text(PROJECT_URL.length > 0 ? PROJECT_URL : '项目地址：待填写')
            .fontSize(12)
            .fontColor(resolvePrimaryColor(this.isDarkMode, this.accentOrPrimary()))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(14)
            .fontColor([hwTextSecondary(this.isDarkMode)])
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .onClick((): void => {
        this.openProjectUrl();
      })
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 主题色依赖标记：放在**最前面**，零尺寸、不影响布局。
      // 没有它，切主题色时页面内容不会重新求值（@Watch 只调回调，不重建组件）。
      AccentColorSentinel()

      Column() {
        this.header()

        Scroll() {
          Column({ space: HwSpace.md }) {
            ForEach(DEMO_ENTRIES, (entry: DemoEntry, index: number): void => {
              this.entryCard(entry, index)
            },
              // key 带上当前主题色：卡片内部有依赖主题色的表达式（数字徽标底色等），
              // 键不变就不会重建子节点，切色后可能停在旧配色
              (entry: DemoEntry): string => `${entry.route}_${this.accentColor}`)

            // 快捷开关：不动设置页也能立刻看到效果
            ThemedCard() {
              Column({ space: HwSpace.md }) {
                Text('快捷开关')
                  .fontSize(13)
                  .fontColor(hwTextSecondary(this.isDarkMode))
                  .width('100%')

                // ⚠️ 这里**必须**用 SwitchRow（或自己写 .onChange）。
                //    `Toggle` 的 `isOn` **不是双向绑定**：只写 `isOn: this.x` 而不写
                //    `.onChange`，拨动只会改组件内部视觉，`x` 根本不会变
                //    —— 表现为「拨完闪一下又弹回去」，且不会持久化。
                SwitchRow({
                  label: '全局沉浸光感',
                  hint: '开启后卡片改由系统材质承载，关闭则全部回退毛玻璃',
                  isOn: this.immersiveLightEnabled,
                  onToggle: (value: boolean): void => {
                    AppearanceStore.setBoolean('immersiveLightEnabled', value);
                  }
                })

                Text(`材质状态：${immersiveCardsActive() ? '已接管卡片表面' : '未生效，降级为毛玻璃'}`
                  + `\n主题色流光：${this.pressGlowSwitch ? '开（流光用主题色）' : '关（系统白光）'}`)
                  .fontSize(11)
                  .fontColor(hwTextSecondary(this.isDarkMode))
                  .width('100%')
              }
              .width('100%')
            }

            Text('提示：所有设置都会被持久化，重启应用后仍然生效')
              .fontSize(11)
              .fontColor(hwTextSecondary(this.isDarkMode))
              .width('100%')
              .margin({ top: HwSpace.sm })

            // ==================== 关于（页面最底部） ====================
            Text('关于')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(hwTextSecondary(this.isDarkMode))
              .width('100%')
              .margin({ top: HwSpace.xl, bottom: HwSpace.sm })

            this.aboutCard()
          }
          .width('100%')
          .padding({ left: HwSpace.lg, right: HwSpace.lg, bottom: 40 })
        }
        .width('100%')
        .layoutWeight(1)
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    // ⚠️ 页面自身的底色**必须**走 resolvePageBackground：
    //    直接写 this.isDarkMode ? HwColor.backgroundDark : HwColor.background
    //    只登记了 isDarkMode，切主题色时这个表达式不会重新求值，
    //    已打开的页面会停在旧底色（而新建/重进的页面又是对的，很容易误判成「刷新不及时」）
    .backgroundColor(resolvePageBackground(this.isDarkMode, this.pageBackground))
    // 顶到状态栏：页面自己铺色（配合 EntryAbility 里的全屏布局与透明系统栏）
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
  }
}
