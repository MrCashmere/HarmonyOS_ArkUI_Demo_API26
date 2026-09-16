/**
 * 反测样本 ②：Toggle 缺 `.onChange`。
 * 期望：报「缺少 `.onChange`」。
 */
@Component
export struct MissingOnChange {
  @State on: boolean = true;

  build() {
    Column() {
      Toggle({ type: ToggleType.Switch, isOn: this.on })
    }
  }
}
