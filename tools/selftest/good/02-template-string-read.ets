/**
 * 正样本：模板字符串里的 `this.<字段>` 是真读取，不能被判成死代码。
 *
 * 期望：不报任何问题。这是上一版规则的另一个已知易错点
 * （字符串内容会被掩码清空，用 codeOnly 数字段会误报）。
 */
@Component
export struct TemplateRead {
  @StorageProp('immersivePressGlow') pressGlowSwitch: boolean = true;

  build() {
    Column() {
      Text(`流光：${this.pressGlowSwitch ? '开' : '关'}`)
    }
  }
}
