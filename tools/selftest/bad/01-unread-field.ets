/**
 * 反测样本 ①：同一文件里两个 struct 声明了**同名字段**，
 * 其中 StructB 那个从未被读取。
 *
 * 期望：arkcheck 报出 StructB 的 accentColor（第 21 行附近）。
 * 若规则退回「整文件统计 this.accentColor」，StructA 的读取会把它洗白 → 漏报。
 */
@Component
export struct StructA {
  @StorageProp('accentColor') accentColor: string = '';

  build() {
    Text(this.accentColor)
  }
}

@Component
export struct StructB {
  @StorageProp('accentColor') accentColor: string = '';

  build() {
    Text('this struct never reads accentColor')
  }
}
