/**
 * 教学脚手架：
 *   · `DemoScaffold` —— 把「每个页面都要做的那套主题色订阅」收敛到一处，避免重复样板；
 *   · `DemoTopBar`   —— 二级页面顶部返回栏（统一走 `topBarGlassColor()`）；
 *   · `SectionCard`  —— 首页/设置页共用的「标题 + 说明 + 开关行」卡片。
 *
 * 对应参考工程里散落在 11 个页面中的相同写法。
 */

import {
  HwRadius,
  HwSpace,
  hwTextPrimary,
  hwTextSecondary,
  reloadAppTheme,
  resolvePageBackground,
  topBarGlassColor,
  withAlpha,
  HwColor
} from '../utils/DesignTokens';
import { cardGlassBorderColor, cardGlassEffect, cardGlassShadow } from '../utils/SystemMaterial';
import { AccentColorSentinel } from './MaterialCard';
import { CardSurface } from './CardSurface';
import { IconCircleButton } from './IconCircleButton';

/**
 * ────────────────────────────────────────────────────────────────────────────
 * 每个绑定主题色的页面都必须做这三件事（本组件替你做完）
 * ────────────────────────────────────────────────────────────────────────────
 *   ① 订阅 `accentColor`：`@StorageProp('accentColor')`（读）+ `@Watch` 回调里
 *      `reloadAppTheme()` —— 回调负责**重算 token**（HwColor、页面/卡片底色）；
 *   ② 订阅 `pageBackground`：页面底色要走 `resolvePageBackground()`，
 *      **不能直接读 `HwColor.background`**（模块级对象的属性读登记不上依赖）；
 *   ③ 在根容器里挂一个零尺寸的 `AccentColorSentinel()` —— 它才是让页面
 *      **真正重新求值**的那个表达式（@Watch 只调回调，不重建组件）。
 *
 * 用法：
 * ```ets
 * build() {
 *   DemoScaffold({ title: '标题', subtitle: '副标题' }) {
 *     Text('页面内容').fontColor(resolvePrimaryColor(this.isDarkMode, this.accentOrPrimary()))
 *   }
 * }
 * ```
 * ⚠️ 子内容里如果要用主题色，**必须**通过本组件的 `accentOrPrimary()` 取
 *    （脚手架把订阅键建立在本组件上，子内容用 `@BuilderParam` 属于同一棵渲染树，
 *    重新求值时一起重算）。
 */
@Component
export struct DemoScaffold {
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop showTopBar: boolean = true;
  /** 返回动作（showTopBar 为 true 时使用） */
  onBack: () => void = (): void => {
  };
  /** 主题色变化时触发重建，让 HwColor.primary 与选中态取到新色值 */
  @StorageProp('accentColor') @Watch('onAccentColorChanged') accentColor: string = '';
  /** 页面底色（由 applyAppTheme 发布）。**不要**直接读 HwColor.background */
  @StorageProp('pageBackground') pageBackground: string = '';
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @BuilderParam content: () => void = this.emptyContent;

  @Builder
  emptyContent() {
  }

  /**
   * ⚠️ `@Watch` 只负责**重算 token**，它**不会**让组件重新求值。
   *    真正让页面刷新的是根容器里的 `AccentColorSentinel()`。
   *    两者是配套的，缺一个都会出现「部分元素不跟着变色」。
   */
  onAccentColorChanged(): void {
    reloadAppTheme();
  }

  /**
   * 当前主题色。**读 `accentColor` 建立依赖**；
   * 直接写 `HwColor.primary` 在切主题色后不会重新求值。
   */
  accentOrPrimary(): string {
    return this.accentColor.length > 0 ? this.accentColor : HwColor.primary;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // ① 主题色依赖标记：切色时让整页重新求值（零尺寸，不参与布局）
      AccentColorSentinel()

      Column() {
        if (this.showTopBar) {
          this.topBar()
        }
        Scroll() {
          Column() {
            // 不显示顶栏时，也要把内容推离状态栏，否则正文会被时钟/电量压住
            if (!this.showTopBar) {
              Blank().height(this.statusBarHeight)
            }
            this.content()
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
    // ③ 顶到状态栏之下自己铺色（参考工程每个页面都这么做）。
    //    配套动作有两个：本节点 expandSafeArea，以及顶栏 height/padding 里加上
    //    `statusBarHeight` —— 只做前者会让顶栏被状态栏压住。
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
    // ② 页面底色走 resolvePageBackground：把订阅键变成**入参**，
    //    调用点才算真正读到了 pageBackground，依赖才登记得上
    .backgroundColor(resolvePageBackground(this.isDarkMode, this.pageBackground))
  }

  /**
   * 二级页面顶部返回栏。
   *
   * 教学要点｜玻璃色走 `topBarGlassColor(isDark)`，**不要写死 `'#66FFFFFF'`**。
   *   写死的后果：浅色模式看着没问题，深色模式就是**一整条浅灰板**。
   *   参考工程曾有 9 个页面写死这个值，现已全部改走该函数。
   */
  @Builder
  topBar() {
    Row() {
      IconCircleButton({
        symbol: $r('sys.symbol.chevron_left'),
        buttonSize: 36,
        iconSize: 18,
        glass: true,
        tint: hwTextPrimary(this.isDarkMode),
        onAction: (): void => {
          this.onBack();
        }
      })

      Column({ space: 2 }) {
        if (this.title.length > 0) {
          Text(this.title)
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor(hwTextPrimary(this.isDarkMode))
            .maxLines(1)
        }
        if (this.subtitle.length > 0) {
          Text(this.subtitle)
            .fontSize(11)
            .fontColor(hwTextSecondary(this.isDarkMode))
            .maxLines(1)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: HwSpace.md })
    }
    .width('100%')
    // 顶栏高度含状态栏，并靠 padding.top 把内容压到状态栏之下
    // —— 这是参考工程 20+ 处统一的写法（`height(56 + this.statusBarHeight)`）
    .height(56 + this.statusBarHeight)
    .padding({ left: HwSpace.lg, right: HwSpace.lg, top: this.statusBarHeight })
    // 普通 Row 不在沉浸光感生效范围内，用 backgroundEffect 近似玻璃
    .backgroundEffect({ radius: 12, color: topBarGlassColor(this.isDarkMode) })
  }
}

/**
 * 通用的「标题 + 说明 + 尾部开关」行。
 *
 * ⚠️ **`Toggle` 必须显式设 `selectedColor`**：SDK 默认是
 *    `$r('sys.color.ohos_id_color_emphasize')`（系统蓝），不覆盖就永远是蓝的。
 *    这是主题色适配里**最容易漏**的一项（参考工程首次体检就发现 5 处遗漏）。
 */
@Component
export struct SwitchRow {
  @Prop label: string = '';
  @Prop hint: string = '';
  @Link isOn: boolean;
  @StorageProp('accentColor') accentColor: string = '';
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  @Prop rowDivider: boolean = false;
  onToggle: (value: boolean) => void = (): void => {
  };

  private accentOrPrimary(): string {
    return this.accentColor.length > 0 ? this.accentColor : HwColor.primary;
  }

  build() {
    Column() {
      if (this.rowDivider) {
        // 分隔线用「主题色的极淡版」而不是中性的 HwColor.textPrimary：
        // 这样它天然跟随主题色，且该行本身订阅了 isDarkMode / accentColor，会一起刷新
        Divider()
          .color(withAlpha(this.accentOrPrimary(), 0.12))
          .margin({ bottom: HwSpace.md })
      }
      Row({ space: HwSpace.md }) {
        Column({ space: 4 }) {
          Text(this.label)
            .fontSize(15)
            .fontColor(hwTextPrimary(this.isDarkMode))
          if (this.hint.length > 0) {
            Text(this.hint)
              .fontSize(12)
              .fontColor(hwTextSecondary(this.isDarkMode))
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.isOn })
          // ⚠️ 不写这一行，开关永远跟着系统蓝色走
          .selectedColor(this.accentOrPrimary())
          .onChange((value: boolean): void => {
            this.isOn = value;
            this.onToggle(value);
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
  }
}

/**
 * 「带主题色的卡片」标准写法 = CardSurface（材质背板）+ 上面那圈玻璃属性。
 *
 * 之所以做成一个组件：这两件事**必须成对出现**。
 * 只用 CardSurface 而不写 glass helper → 材质不生效的机型上卡片没有底色；
 * 只写 glass helper 而不用 CardSurface → 材质生效的机型上卡片**直接丢掉背景**
 * （三个 helper 此时都返回「无效果」，而没有任何东西接替它们）。
 * 参考工程的自检脚本 `scripts/theme_audit.mjs` 第 1 项检查的就是这件事。
 */
@Component
export struct ThemedCard {
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  /** 卡片圆角，同时传给 CardSurface 与玻璃属性（**必须一致**） */
  @Prop cardRadius: number = HwRadius.card;
  @BuilderParam content: () => void = this.emptyContent;

  @Builder
  emptyContent() {
  }

  /**
   * 外观开关：上游 CLink 有四个可调项（「更优美的卡片」/「经典卡片样式」/
   * 「卡片阴影描边」/「沉浸光感卡片（实验性）」），本 Demo **没有实现它们的设置界面**，
   * 所以这里直接传常量，而不是再挂四个 `@StorageLink`。
   *
   * 上一版挂了 `@StorageLink('beautifulCards')` 等四个键，但**全工程没有任何地方写入它们**
   * ——`@StorageLink` 永远不会变，等于一条没有输入端子的死线；
   * 而且它会让人误以为「外面还有个设置能影响卡片外观」。
   * 取值与那四个键的默认值逐一对应（`false` / `false` / `true` / `false`），外观不变。
   */
  private beautifulCards(): boolean {
    return false;
  }

  private classicCards(): boolean {
    return false;
  }

  private cardShadowBorder(): boolean {
    return true;
  }

  private experimentalCards(): boolean {
    return false;
  }

  build() {
    CardSurface({ radius: this.cardRadius }) {
      Column() {
        this.content()
      }
      .width('100%')
      .padding(HwSpace.lg)
      .borderRadius(this.cardRadius)
      .backgroundColor(Color.Transparent)
      .backgroundEffect(cardGlassEffect(this.beautifulCards(), this.classicCards(),
        this.isDarkMode, this.experimentalCards()))
      .border({
        width: 1,
        color: cardGlassBorderColor(this.beautifulCards(), this.cardShadowBorder(),
          this.isDarkMode, this.experimentalCards())
      })
      .clip(true)
      .shadow(cardGlassShadow(this.beautifulCards(), this.cardShadowBorder(),
        this.isDarkMode, this.experimentalCards()))
    }
  }
}
