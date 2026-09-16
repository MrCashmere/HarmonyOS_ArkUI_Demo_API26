/**
 * 正样本：同一文件里两个 struct 各自声明**同名** `accentColor`，
 * 但**两个都真的读了**。
 *
 * 期望：不报任何问题（防止上一条规则变成「见同名就报」的误报机器）。
 */
@Component
export struct GoodA {
  @StorageProp('accentColor') accentColor: string = '';

  build() {
    Text(this.accentColor)
  }
}

@Component
export struct GoodB {
  @StorageProp('accentColor') accentColor: string = '';

  build() {
    Row() {
      Text(this.accentColor)
    }
  }
}
