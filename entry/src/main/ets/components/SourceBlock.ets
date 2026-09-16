/**
 * 「源码」代码块（教学用）
 * ============================================================================
 * 每个教学小节下面挂一段**本工程的真实实现**，目标是「看完现象就能直接抄」：
 *   · 右上角「复制」把整段源码写进系统剪贴板，可直接粘到 DevEco Studio；
 *   · 长按代码本身也能走系统菜单复制（`copyOption`）；
 *   · 等宽字体 + 极淡的内嵌底色，和正文明确区分。
 *
 * ⚠️ 代码正文是**真换行**（模板字符串里的换行），复制出来是可直接编译的片段，
 *    所以这里刻意不做任何「为了排版好看」的改写：注释、⚠️ 标记都原样保留。
 */

import pasteboard from '@ohos.pasteboard';
import promptAction from '@ohos.promptAction';
import { BusinessError } from '@kit.BasicServicesKit';
import {
  HwRadius,
  HwSpace,
  hwTextPrimary,
  hwTextSecondary,
  resolvePrimaryColor,
  withAlpha
} from '../utils/DesignTokens';
import { toastSystemMaterial } from '../utils/SystemMaterial';

/**
 * 代码字体：首选系统等宽别名。
 * 该别名不存在时 ArkUI 会**静默回落到默认字体**（不会崩，只是不等宽），
 * 所以这么写是安全的；真正的等宽需要自带字体文件（见 docs/UI-INDEX.md §8）。
 */
const CODE_FONT: string = 'monospace';
/** 代码字号 / 行高：比正文小一号，才能在一屏里多塞几行 */
const CODE_FONT_SIZE: number = 11;
const CODE_LINE_HEIGHT: number = 17;

@Component
export struct SourceBlock {
  /** 一句话点出「这段代码解决了什么」 */
  @Prop caption: string = '';
  /** 来源文件：照实写工程内路径，方便直接打开对照 */
  @Prop source: string = '';
  /** 源码正文（真换行） */
  @Prop code: string = '';
  @StorageProp('accentColor') accentColor: string = '';
  @StorageProp('isDarkMode') isDarkMode: boolean = false;

  /** 当前主题色：读订阅变量建立依赖，代码块会跟着主题色一起变 */
  private accent(): string {
    return resolvePrimaryColor(this.isDarkMode, this.accentColor);
  }

  /**
   * 复制整段源码到系统剪贴板。
   *
   * 用的是参考工程 `LanWebTransfer` 里「复制链接」那套 API：
   * `pasteboard.createData()` + `getSystemPasteboard().setData()`。
   * 注意 **写剪贴板不需要任何权限**（读才需要），所以这里不用申请权限。
   */
  private copyCode(): void {
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.code);
      pasteboard.getSystemPasteboard().setData(data).then((): void => {
        promptAction.showToast({
          systemMaterial: toastSystemMaterial(),
          message: '源码已复制，可直接粘贴',
          duration: 1500
        });
      }).catch((error: BusinessError): void => {
        promptAction.showToast({
          systemMaterial: toastSystemMaterial(),
          message: '复制失败：' + error.message,
          duration: 2000
        });
      });
    } catch (error) {
      // 兜底：哪怕剪贴板不可用，代码本身仍然可以长按手动复制
      promptAction.showToast({
        systemMaterial: toastSystemMaterial(),
        message: '复制失败，请长按代码手动复制',
        duration: 2000
      });
    }
  }

  build() {
    Column({ space: HwSpace.sm }) {
      // ---------- 头部：说明 + 复制按钮 ----------
      Row({ space: HwSpace.sm }) {
        SymbolGlyph($r('sys.symbol.doc_text'))
          .fontSize(12)
          .fontColor([hwTextSecondary(this.isDarkMode)])

        Text(this.caption.length > 0 ? this.caption : '对应实现')
          .fontSize(10)
          .fontColor(hwTextSecondary(this.isDarkMode))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text('复制')
          .fontSize(11)
          .fontColor(this.accent())
          .padding({ left: 10, right: 10, top: 3, bottom: 3 })
          .borderRadius(HwRadius.pill)
          .backgroundColor(withAlpha(this.accent(), 0.12))
          .onClick((): void => {
            this.copyCode();
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text('来源：' + this.source)
        .fontSize(10)
        .fontColor(hwTextSecondary(this.isDarkMode))
        .width('100%')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      // ---------- 代码正文 ----------
      Text(this.code)
        .fontSize(CODE_FONT_SIZE)
        .fontFamily(CODE_FONT)
        .lineHeight(CODE_LINE_HEIGHT)
        .fontColor(hwTextPrimary(this.isDarkMode))
        .width('100%')
        .textAlign(TextAlign.Start)
        // 长按可直接用系统菜单复制（不依赖上面的按钮）
        .copyOption(CopyOptions.LocalDevice)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(HwSpace.md)
    .borderRadius(HwRadius.control)
    // 底色取「文字色的极淡版」：深浅色下都成立，且不会和主题色打架
    .backgroundColor(withAlpha(hwTextPrimary(this.isDarkMode), this.isDarkMode ? 0.08 : 0.04))
    .border({ width: 1, color: withAlpha(hwTextPrimary(this.isDarkMode), 0.08) })
  }
}
