/**
 * 演示二：沉浸光感与材质承载（ImmersiveShowcasePage）
 * ============================================================================
 * 目的：把「材质承载层」这件事看明白——为什么卡片要用 Toggle 承载、
 *      按压流光为什么要压在材质之上、为什么必须让出底色。
 *
 * 页面分五段：
 *   A. 诊断面板       —— 把各段判定条件摊开，真机排查「为什么没生效」
 *   B. 卡片按压流光   —— CardSurface + 跟手光斑（受两个开关控制）
 *   C. 圆形按钮       —— ToggleType.Button 作交互层，SymbolGlyph 触摸穿透
 *   D. 芯片尺寸对照   —— layerShadow 该关的地方（小尺寸上投影像「背后顶了一层影子」）
 *   E. 半模态面板     —— bindSheet 自身不生效，要靠 MaterialSheetPanel
 */

import promptAction from '@ohos.promptAction';
import { SourceBlock } from '../components/SourceBlock';
import {
  SRC_MAT_A, SRC_MAT_A_SOURCE,
  SRC_MAT_B, SRC_MAT_B_SOURCE,
  SRC_MAT_C, SRC_MAT_C_SOURCE,
  SRC_MAT_D, SRC_MAT_D_SOURCE,
  SRC_MAT_E, SRC_MAT_E_SOURCE
} from '../teaching/SourceSnippets';
import router from '@ohos.router';
import { HwColor, HwRadius, HwSpace, hwTextPrimary, hwTextSecondary, withAlpha } from '../utils/DesignTokens';
import {
  dialogSystemMaterial,
  immersiveCardsActive,
  isApi26OrAbove,
  materialDiagnostics,
  sheetBlurStyle,
  sheetSystemMaterial,
  toastSystemMaterial
} from '../utils/SystemMaterial';
import { DemoScaffold, SwitchRow, ThemedCard } from '../components/DemoScaffold';
import { MaterialCardLayer, MaterialSheetPanel } from '../components/MaterialCard';
import { CardSurface } from '../components/CardSurface';
import { IconCircleButton } from '../components/IconCircleButton';
import { AppearanceStore } from '../storage/AppearanceStore';

@Entry
@Component
struct ImmersiveShowcasePage {
  @StorageProp('accentColor') accentColor: string = '';
  @StorageProp('immersivePressGlow') pressGlowSwitch: boolean = true;
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  @StorageLink('immersiveLightEnabled') immersiveLightEnabled: boolean = true;
  @State showSheet: boolean = false;
  @State tapCount: number = 0;

  private accentOrPrimary(): string {
    return this.accentColor.length > 0 ? this.accentColor : HwColor.primary;
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

  @Builder
  codeHint(text: string) {
    Text(text)
      .fontSize(11)
      .fontColor(hwTextSecondary(this.isDarkMode))
      .width('100%')
      .margin({ top: HwSpace.sm })
  }

  /**
   * 一个可用手指「按」的卡片。
   *
   * 流光能不能看见，需要**三个条件同时成立**：
   *   ① 系统 API >= 26 且材质构造成功（`immersiveCardsActive()`）；
   *   ② 「全局沉浸光感」开关开着；
   *   ③ 「主题色流光」开着（否则流光颜色是空串，卡片流光直接不画）。
   * 想看到跟手光斑，还要再打开「卡片流光触感」。
   *
   * （本 Demo 刻意**不做**「溢出到卡间缝隙」的环境光：卡片之外没有沉浸光感材质，
   *   在那里画光等于在非沉浸光感区域凭空出现一块亮斑。）
   */
  @Builder
  pressableCard(label: string) {
    // ⚠️ 条件写在 CardSurface **外面**：写在里面会让承载层（ToggleType.Button，
    //    有 28vp 默认高度）留下一个空壳，卡片之间凭空多出间距。
    CardSurface({ radius: HwRadius.card }) {
      Column({ space: HwSpace.sm }) {
        Text(label)
          .fontSize(15)
          .fontColor(hwTextPrimary(this.isDarkMode))
        Text('按住并滑动手指，光斑会跟着走')
          .fontSize(12)
          .fontColor(hwTextSecondary(this.isDarkMode))
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding(HwSpace.lg)
      .borderRadius(HwRadius.card)
      // ⚠️ 材质生效时这个底色必须让位（helper 会自动返回「无效果」）
      .backgroundColor(Color.Transparent)
      .onClick((): void => {
        this.tapCount = this.tapCount + 1;
      })
    }
  }

  build() {
    // ⚠️ `bindSheet` 挂在**容器**（Stack）上，而不是挂在自定义组件 `DemoScaffold` 后面：
    //    尾随闭包后链式调属性在 ArkUI 里限制很多（见 CardSurface 文件头的「坑 2」）。
    Stack() {
      DemoScaffold({
        title: '沉浸光感与材质承载',
        subtitle: '为什么必须用 Toggle 当背板',
        onBack: (): void => {
          router.back();
        }
      }) {
      // ==================== A. 诊断面板 ====================
      this.sectionTitle('A · 材质诊断',
        '把判定条件摊开：这是排查「为什么没生效」最快的方式')

      ThemedCard() {
        Column({ space: HwSpace.md }) {
          // ⚠️ 原来的写法（`Toggle({ isOn: this.immersiveLightEnabled })` 且不写
          //    `.onChange`）是**错的**：`isOn` 不是双向绑定，拨动只改组件内部视觉，
          //    `immersiveLightEnabled` 不变 → 闪一下弹回、不持久化。
          //    改用 SwitchRow（内部 `@Link` + `.onChange`）。
          SwitchRow({
            label: '全局沉浸光感',
            hint: '关闭后所有卡片回退毛玻璃；诊断行会同步变化',
            isOn: this.immersiveLightEnabled,
            onToggle: (value: boolean): void => {
              AppearanceStore.setBoolean('immersiveLightEnabled', value);
            }
          })

          // 诊断文案的两个入参必须是**订阅值**，否则这一行不会随切色/拨开关刷新
          Text(materialDiagnostics(this.pressGlowSwitch, this.accentColor))
            .fontSize(11)
            .fontColor(hwTextSecondary(this.isDarkMode))
            .width('100%')

          Text(`卡片材质接管=${immersiveCardsActive() ? '是' : '否'}`
            + ` · API≥26=${isApi26OrAbove() ? '是' : '否'}`
            + ` · 点击次数=${this.tapCount}`)
            .fontSize(11)
            .fontColor(hwTextSecondary(this.isDarkMode))
            .width('100%')
        }
        .width('100%')
      }

      SourceBlock({
        caption: '诊断文案与判定条件',
        source: SRC_MAT_A_SOURCE,
        code: SRC_MAT_A
      })

      // ==================== B. 卡片按压流光 ====================
      this.sectionTitle('B · 卡片按压缩放光',
        '光只留在卡片内：到圆角处被裁断，接上材质自身的边缘折射')

      this.pressableCard('按压我（卡片流光触感）')

      ThemedCard() {
        Column({ space: HwSpace.sm }) {
          Text('想要看到光，需要同时满足 4 个条件：')
            .fontSize(12)
            .fontColor(hwTextPrimary(this.isDarkMode))
          Text(`① 系统 API ≥ 26：${isApi26OrAbove() ? '满足' : '不满足'}`
            + `\n② 全局沉浸光感：${this.immersiveLightEnabled ? '开' : '关'}`
            + `\n③ 主题色流光：${this.pressGlowSwitch ? '开（光=主题色）' : '关（回退系统白光）'}`
            + `\n④ 卡片流光触感：在「外观设置」里开关`)
            .fontSize(11)
            .fontColor(hwTextSecondary(this.isDarkMode))
        }
        .width('100%')
      }
      this.codeHint('光只压在材质之上：材质**不采样同一 Stack 里的兄弟节点**，'
        + '塞到材质底下会完全看不见')

      SourceBlock({
        caption: '跟手光斑的条件与四档渐变',
        source: SRC_MAT_B_SOURCE,
        code: SRC_MAT_B
      })

      // ==================== C. 圆形按钮 ====================
      this.sectionTitle('C · 圆形按钮',
        'ToggleType.Button 作交互层承载材质；SymbolGlyph 触摸穿透到它')

      ThemedCard() {
        Row({ space: HwSpace.lg }) {
          IconCircleButton({
            symbol: $r('sys.symbol.checkmark'),
            buttonSize: 44,
            iconSize: 20,
            buttonInteractive: true,
            tint: this.accentOrPrimary(),
            onAction: (): void => {
              this.tapCount = this.tapCount + 1;
            }
          })
          IconCircleButton({
            symbol: $r('sys.symbol.xmark'),
            buttonSize: 44,
            iconSize: 20,
            glass: true,
            tint: this.accentOrPrimary(),
            onAction: (): void => {
              this.tapCount = this.tapCount + 1;
            }
          })
          IconCircleButton({
            symbol: $r('sys.symbol.plus'),
            buttonSize: 44,
            iconSize: 20,
            buttonInteractive: false,
            tint: hwTextSecondary(this.isDarkMode),
            onAction: (): void => {
              this.tapCount = this.tapCount + 1;
            }
          })
          Text(`（按压有弹性形变 + 流光跟随）\n点击次数：${this.tapCount}`)
            .fontSize(11)
            .fontColor(hwTextSecondary(this.isDarkMode))
            .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      this.codeHint('第三个 buttonInteractive=false：该设备若不支持交互材质，'
        + '开启后材质会整块消失——这时就该退回静态材质')

      SourceBlock({
        caption: '载体为什么必须是 ToggleType.Button',
        source: SRC_MAT_C_SOURCE,
        code: SRC_MAT_C
      })

      // ==================== D. 芯片尺寸对照 ====================
      this.sectionTitle('D · 小尺寸芯片要关掉材质投影',
        'ImmersiveMaterial 的 applyShadow 默认为 true，小元件上会像「背后顶了一层影子」')

      Row({ space: HwSpace.md }) {
        // layerShadow: true（默认）—— 大卡片上合适
        Stack() {
          MaterialCardLayer({ layerRadius: HwRadius.control, layerShadow: true })
          Text('带投影')
            .fontSize(12)
            .fontColor(hwTextPrimary(this.isDarkMode))
            .padding({ left: 16, right: 16, top: 10, bottom: 10 })
            .hitTestBehavior(HitTestMode.None)
        }
        .borderRadius(HwRadius.control)

        // layerShadow: false —— 小尺寸芯片上更干净
        Stack() {
          MaterialCardLayer({ layerRadius: HwRadius.control, layerShadow: false })
          Text('无投影')
            .fontSize(12)
            .fontColor(hwTextPrimary(this.isDarkMode))
            .padding({ left: 16, right: 16, top: 10, bottom: 10 })
            .hitTestBehavior(HitTestMode.None)
        }
        .borderRadius(HwRadius.control)

        Text('尺寸小时选右边那种')
          .fontSize(11)
          .fontColor(hwTextSecondary(this.isDarkMode))
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      SourceBlock({
        caption: '大卡片带投影 / 小芯片关投影',
        source: SRC_MAT_D_SOURCE,
        code: SRC_MAT_D
      })

      // ==================== E. 半模态面板 ====================
      this.sectionTitle('E · 半模态面板（bindSheet）',
        'bindSheet 自身挂材质在内容区不生效，必须用承载层铺满面板')

      Row({ space: HwSpace.md }) {
        Text('打开半模态面板')
          .fontSize(14)
          .fontColor(this.accentOrPrimary())
          .padding({ left: 18, right: 18, top: 10, bottom: 10 })
          .borderRadius(HwRadius.pill)
          .backgroundColor(withAlpha(this.accentOrPrimary(), 0.12))
          .onClick((): void => {
            this.showSheet = true;
          })

        Text('弹 Toast')
          .fontSize(14)
          .fontColor(this.accentOrPrimary())
          .padding({ left: 18, right: 18, top: 10, bottom: 10 })
          .borderRadius(HwRadius.pill)
          .backgroundColor(withAlpha(this.accentOrPrimary(), 0.12))
          .onClick((): void => {
            promptAction.showToast({
              message: 'Toast 自带沉浸光感（弹窗类在全区域生效）',
              // 弹窗类组件在「页面内全部区域」都能生效，可直接下发材质
              systemMaterial: toastSystemMaterial()
            });
          })
      }
      .width('100%')

      this.codeHint('bindSheet / Toast / Dialog 属于「弹窗类」，本来就能全区域生效；'
        + '真正需要承载层的是**内容区卡片**')

      SourceBlock({
        caption: 'bindSheet 配置 + 承载层铺满面板',
        source: SRC_MAT_E_SOURCE,
        code: SRC_MAT_E
      })
      }
    }
    .width('100%')
    .height('100%')
    // ⚠️ bindSheet 的 backgroundColor 默认是 Color.White，
    //    不显式设 Transparent 会把面板里的材质整块盖住
    .bindSheet($$this.showSheet, this.sheetContent(), {
      height: 320,
      dragBar: true,
      showClose: false,
      backgroundColor: Color.Transparent,
      // 沉浸光感可用时不设模糊（交给系统材质），否则回退旧毛玻璃
      blurStyle: sheetBlurStyle(),
      systemMaterial: sheetSystemMaterial()
    })
  }

  /**
   * 半模态面板内容。
   *
   * ⚠️ 这里**不能**直接给外层 Column 设 systemMaterial：非选择类组件
   *    在内容区不生效。必须由 `MaterialSheetPanel` 里的
   *    ToggleType.Button 承载层铺满整块面板来画材质。
   */
  @Builder
  sheetContent() {
    MaterialSheetPanel({ panelPadding: HwSpace.lg }) {
      Column({ space: HwSpace.md }) {
        Text('半模态面板')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(hwTextPrimary(this.isDarkMode))
        Text('这块面板的材质来自面板里的 ToggleType.Button 承载层，'
          + '而不是 bindSheet 自身的 systemMaterial。')
          .fontSize(13)
          .fontColor(hwTextSecondary(this.isDarkMode))
        Text(`sheetSystemMaterial() = ${sheetSystemMaterial() === undefined ? 'undefined（走降级）' : '已下发'}`)
          .fontSize(11)
          .fontColor(hwTextSecondary(this.isDarkMode))

        Row({ space: HwSpace.md }) {
          Text('关闭')
            .fontSize(14)
            .fontColor(this.accentOrPrimary())
            .padding({ left: 18, right: 18, top: 10, bottom: 10 })
            .borderRadius(HwRadius.pill)
            .backgroundColor(withAlpha(this.accentOrPrimary(), 0.12))
            .onClick((): void => {
              this.showSheet = false;
            })
          Text('弹出对话框')
            .fontSize(14)
            .fontColor(this.accentOrPrimary())
            .padding({ left: 18, right: 18, top: 10, bottom: 10 })
            .borderRadius(HwRadius.pill)
            .backgroundColor(withAlpha(this.accentOrPrimary(), 0.12))
            .onClick((): void => {
              this.showSheet = false;
              promptAction.showDialog({
                title: '沉浸光感对话框',
                message: '弹出框用 ULTRA_THICK 档材质（见 styleOf(MaterialScene.DIALOG)）。',
                systemMaterial: dialogSystemMaterial()
              });
            })
        }
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }
}

