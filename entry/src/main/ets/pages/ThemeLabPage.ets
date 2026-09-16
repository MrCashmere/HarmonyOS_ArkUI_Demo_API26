/**
 * 演示一：颜色令牌实验室（ThemeLabPage）
 * ============================================================================
 * 目的：把「哪些写法会跟随主题色、哪些不会」在同一屏里对照出来。
 *
 * 页面分四段：
 *   A. 主色三态对照     —— resolvePrimaryColor / resolvePrimaryButtonColor / onAccentColor
 *   B. 实时跟随的控件   —— Toggle.selectedColor、Slider.selectedColor、TextInput.caretColor
 *   C. 浅色底与描边     —— withAlpha(主题色, α)、resolveGlassBorderColor、ForEach key
 *   D. 反面对照         —— 哪些写法会把颜色「定死」在加载那一刻
 */

import router from '@ohos.router';
import {
  HwColor,
  HwRadius,
  HwSpace,
  hwDanger,
  hwOnline,
  hwTextPrimary,
  hwTextSecondary,
  onAccentColor,
  resolveGlassBorderColor,
  resolvePrimaryButtonColor,
  resolvePrimaryColor,
  withAlpha
} from '../utils/DesignTokens';
import { immersiveCardsActive } from '../utils/SystemMaterial';
import { DemoScaffold, ThemedCard } from '../components/DemoScaffold';
import { SourceBlock } from '../components/SourceBlock';
import {
  SRC_LAB_A, SRC_LAB_A_SOURCE,
  SRC_LAB_B, SRC_LAB_B_SOURCE,
  SRC_LAB_C, SRC_LAB_C_SOURCE,
  SRC_LAB_D, SRC_LAB_D_SOURCE
} from '../teaching/SourceSnippets';
/**
 * D 段的「反面对照」组件。
 *
 * ⚠️ 左边色块是**刻意写坏的示例**：它读的是**应用启动那一刻**的快照
 *    （`AppStorage['bootAccentColor']`，由 EntryAbility 启动时写一次，之后永不更新）。
 *
 *    📌 这个「定死」我们**试错了三次**，过程本身就是最好的教案：
 *      ① `@Prop frozenAccent: string = HwColor.primary`
 *         → **冻不住**：父组件重渲染时，默认值表达式会被重新求值；
 *      ② `const FROZEN_PRIMARY_AT_LOAD: string = HwColor.primary`（模块级常量）
 *         → **还是冻不住**：页面模块每次进入可能被重新求值，常量跟着当前色走；
 *      ③ 应用启动阶段写一次的 AppStorage 键（当前方案）
 *         → 冻住了：它不依赖模块求值时机，也不依赖组件是否被重建。
 *
 *    结论：**「什么时候求值」和「值从哪来」相比，前者才是决定性的。**
 *    要展示一个「停在过去」的颜色，唯一稳的位置是在组件与模块之外只写一次。
 *
 * 判断标准很简单：**这个值会不会在组件存活期间变化？会，就不能在组件里直接读 token。**
 */
@Component
struct FrozenSnapshot {
  /** ③ 启动快照：全程不会被改写，所以它才是真的「定死」 */
  @StorageProp('bootAccentColor') bootAccent: string = '';
  @StorageProp('accentColor') accentColor: string = '';
  @StorageProp('isDarkMode') isDarkMode: boolean = false;

  build() {
    Row({ space: HwSpace.md }) {
      Column({ space: 6 }) {
        Row()
          .width(44)
          .height(44)
          .borderRadius(HwRadius.control)
          // 兜底只为防御（启动时一定已写好）：用中性灰，避免误以为是「跟随了主题色」
          .backgroundColor(this.bootAccent.length > 0 ? this.bootAccent : hwTextSecondary(this.isDarkMode))
        Text('启动快照')
          .fontSize(11)
          .fontColor(hwTextSecondary(this.isDarkMode))
        // 把捕获到的色值**写在脸上**：色块有没有变，看这行字最直接
        Text(this.bootAccent.length > 0 ? this.bootAccent : '—')
          .fontSize(9)
          // ⚠️ 走 hwDanger(isDark)：直接读 HwColor.danger 的话，
          //    深色模式下仍是浅色模式那个 #D94838，对比度会明显不够。
          .fontColor(hwDanger(this.isDarkMode))
      }
      .layoutWeight(1)

      Column({ space: 6 }) {
        Row()
          .width(44)
          .height(44)
          .borderRadius(HwRadius.control)
          // 表达式里读到了订阅键 → 切色时会重新求值。
          // 这里刻意用**原始广播色**（与左边同口径），对照才干净：
          // 实际业务里应写 resolvePrimaryColor(isDark, accent)，它还会做深色适配。
          .backgroundColor(this.accentColor.length > 0 ? this.accentColor : hwTextSecondary(this.isDarkMode))
        Text('订阅表达式')
          .fontSize(11)
          .fontColor(hwTextSecondary(this.isDarkMode))
        Text(this.accentColor.length > 0 ? this.accentColor : '—')
          .fontSize(9)
          // 同理走 hwOnline(isDark)，深色下有专门的提亮取值
          .fontColor(hwOnline(this.isDarkMode))
      }
      .layoutWeight(1)
    }
    .width('100%')
  }
}

@Entry
@Component
struct ThemeLabPage {
  /**
   * 只订阅、不在这里处理重算：token 的重算与「页面整体重新求值」
   * 由 DemoScaffold（@Watch + AccentColorSentinel）统一负责。
   * 本页声明它是为了让**本页自己的表达式**也登记上依赖。
   */
  @StorageProp('accentColor') accentColor: string = '';
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  @State sliderValue: number = 40;
  @State inputText: string = '点这里看光标颜色';
  @State demoSwitch: boolean = true;
  @State pickedChip: number = 0;

  /** 当前主题色：读订阅变量建立依赖 */
  private accentOrPrimary(): string {
    return this.accentColor.length > 0 ? this.accentColor : HwColor.primary;
  }

  /** 主色上的前景色：浅色主题色（涟漪粉 / 流荧绿）上必须切黑字 */
  private onAccent(): string {
    return onAccentColor(this.accentOrPrimary());
  }

  @Builder
  sectionTitle(text: string, note: string) {
    Column({ space: 4 }) {
      Text(text)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(hwTextPrimary(this.isDarkMode))
      Text(note)
        .fontSize(12)
        .fontColor(hwTextSecondary(this.isDarkMode))
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .margin({ top: HwSpace.lg, bottom: HwSpace.md })
  }

  /** 一行小字注解（说明「为什么这么写」） */
  @Builder
  codeHint(text: string) {
    Text(text)
      .fontSize(11)
      .fontColor(hwTextSecondary(this.isDarkMode))
      .width('100%')
      .margin({ top: HwSpace.sm })
  }

  build() {
    // ⚠️ @Entry 的 build 根节点**必须是容器组件**（Column/Stack/Row…），
    //    不能直接是自定义组件。直接写 DemoScaffold(...) 会编译报错：
    //    「build method can have only one root node, which must be a container component」。
    Stack() {
      DemoScaffold({
        title: '颜色令牌实验室',
        subtitle: '哪些写法会跟随主题色',
        onBack: (): void => {
          router.back();
        }
      }) {
        // ==================== A. 主色三态 ====================
        this.sectionTitle('A · 主色的三种用法',
          '同一个主题色，用作前景 / 按钮底 / 底色上的文字，取法各不相同')

        ThemedCard() {
          Column({ space: HwSpace.lg }) {
            Row({ space: HwSpace.md }) {
              Text('主色文字')
                .fontSize(15)
                // 文字/图标/选中态 → resolvePrimaryColor
                .fontColor(resolvePrimaryColor(this.isDarkMode, this.accentOrPrimary()))
              Text('（resolvePrimaryColor）')
                .fontSize(11)
                .fontColor(hwTextSecondary(this.isDarkMode))
            }
            .width('100%')

            Row() {
              Text('主色按钮')
                .fontSize(15)
                .fontColor(this.onAccent())
                .padding({ left: 20, right: 20, top: 10, bottom: 10 })
                .borderRadius(HwRadius.pill)
                // 主按钮底色 → resolvePrimaryButtonColor（深色下会压深，保证白字对比度）
                .backgroundColor(resolvePrimaryButtonColor(this.isDarkMode, this.accentOrPrimary()))
                .onClick((): void => {
                  this.pickedChip = (this.pickedChip + 1) % 3;
                })
            }
            .width('100%')

            Row({ space: HwSpace.md }) {
              Text('主题色底 + 自动前景')
                .fontSize(14)
                .fontColor(this.onAccent())
                .padding({ left: 14, right: 14, top: 8, bottom: 8 })
                .borderRadius(HwRadius.pill)
                .backgroundColor(this.accentOrPrimary())
              Text('（onAccentColor 自动切黑/白字）')
                .fontSize(11)
                .fontColor(hwTextSecondary(this.isDarkMode))
                .layoutWeight(1)
            }
            .width('100%')
          }
          .width('100%')
        }
        this.codeHint('浅色预设（涟漪粉 / 流荧绿）上白字看不清，所以主题色底上的文字一律走 onAccentColor()')

        // 本节对应的真实实现（可一键复制）
        SourceBlock({
          caption: '主色的三种用法',
          source: SRC_LAB_A_SOURCE,
          code: SRC_LAB_A
        })

        // ==================== B. 实时跟随的控件 ====================
        this.sectionTitle('B · 控件自带的选中色（最容易漏）',
          'SDK 默认是系统强调色，不显式覆盖就永远是蓝的')

        ThemedCard() {
          Column({ space: HwSpace.lg }) {
            Row({ space: HwSpace.md }) {
              Text('Toggle')
                .fontSize(15)
                .fontColor(hwTextPrimary(this.isDarkMode))
                .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.demoSwitch })
                // ⚠️ 不写这一行 → 永远跟随系统蓝色
                .selectedColor(this.accentOrPrimary())
                .onChange((value: boolean): void => {
                  this.demoSwitch = value;
                })
            }
            .width('100%')

            Column({ space: HwSpace.sm }) {
              Row() {
                Text('Slider')
                  .fontSize(15)
                  .fontColor(hwTextPrimary(this.isDarkMode))
              }
              .width('100%')

              Slider({
                value: this.sliderValue,
                min: 0,
                max: 100,
                style: SliderStyle.OutSet
              })
                // ⚠️ Slider 也是三件套：已选色 / 轨道色 / 滑块色
                .selectedColor(this.accentOrPrimary())
                .trackColor(withAlpha(HwColor.textPrimary, 0.1))
                .blockColor(Color.White)
                .width('100%')
                .onChange((value: number): void => {
                  this.sliderValue = Math.round(value);
                })
            }
            .width('100%')

            Column({ space: HwSpace.sm }) {
              Row() {
                Text('TextInput 光标')
                  .fontSize(15)
                  .fontColor(hwTextPrimary(this.isDarkMode))
              }
              .width('100%')

              TextInput({ text: this.inputText })
                // ⚠️ 不覆盖 caretColor，光标就是系统蓝
                .caretColor(this.accentOrPrimary())
                .fontSize(14)
                .fontColor(hwTextPrimary(this.isDarkMode))
                .backgroundColor(withAlpha(HwColor.textPrimary, 0.05))
                .borderRadius(HwRadius.control)
                .width('100%')
                .onChange((value: string): void => {
                  this.inputText = value;
                })
            }
            .width('100%')
          }
          .width('100%')
        }

        SourceBlock({
          caption: '三个控件都要显式覆盖选中色',
          source: SRC_LAB_B_SOURCE,
          code: SRC_LAB_B
        })

        // ==================== C. 浅色底 / 描边 / 选中态 ====================
        this.sectionTitle('C · 浅色底与描边',
          '一律从主题色派生，不要写字面量')

        ThemedCard() {
          Column({ space: HwSpace.md }) {
            Text('选中态芯片（底色 = 主题色 12%）')
              .fontSize(13)
              .fontColor(hwTextSecondary(this.isDarkMode))

            Row({ space: HwSpace.sm }) {
              ForEach([0, 1, 2], (index: number): void => {
                Text(`选项 ${index + 1}`)
                  .fontSize(13)
                  // 选中态文字：选中走主色，未选中走次要色
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
                  })
                  .onClick((): void => {
                    this.pickedChip = index;
                  })
              },
                // ⚠️ key 必须带上「选中态」：ForEach 会复用 key 相同的项，
                //    键不变就不重建子节点，「哪个芯片被选中」的样式会停在上一项
                (index: number): string => `chip_${index}_${this.pickedChip === index ? 1 : 0}_${this.accentColor}`)
            }
            .width('100%')

            Text(`withAlpha(主题色, 0.12) = ${withAlpha(this.accentOrPrimary(), 0.12)}`)
              .fontSize(11)
              .fontColor(hwTextSecondary(this.isDarkMode))
          }
          .width('100%')
        }
        this.codeHint('ForEach 的 key 必须编入「会影响外观的状态」：选中态、展开态、加载态、主题色')

        SourceBlock({
          caption: '浅色底 / 描边全部从主题色派生',
          source: SRC_LAB_C_SOURCE,
          code: SRC_LAB_C
        })

        // ==================== D. 反面对照 ====================
        this.sectionTitle('D · 反面对照：为什么有些写法不跟随',
          '左：启动快照（启动时定死，色值写在脸上）；右：表达式里读到订阅键')

        ThemedCard() {
          Column({ space: HwSpace.md }) {
            FrozenSnapshot()
            Text('切换主题色后，左边会一直停在「应用启动那一刻」的颜色——这就是参考工程里'
              + '「页面别处都变色了，唯独这一处没变」的根因。')
              .fontSize(11)
              .fontColor(hwTextSecondary(this.isDarkMode))
          }
          .width('100%')
        }

        SourceBlock({
          caption: '什么位置才冻得住（启动快照）',
          source: SRC_LAB_D_SOURCE,
          code: SRC_LAB_D
        })

        Text(`当前状态：沉浸光感=${immersiveCardsActive() ? '生效' : '未生效（降级毛玻璃）'}`
          + ` · isDarkMode=${this.isDarkMode} · accentColor=${this.accentOrPrimary()}`)
          .fontSize(10)
          .fontColor(hwTextSecondary(this.isDarkMode))
          .width('100%')
          .margin({ top: HwSpace.lg })
      }
    }
    .width('100%')
    .height('100%')
  }
}
