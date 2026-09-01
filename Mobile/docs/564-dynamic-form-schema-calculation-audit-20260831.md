# 564 OA 动态计算字段对齐验收

## 结论

本轮通过。移动端审批发起页不再把“自动计算”“只读”或“单位天”当作表单文本和值展示，而是按后台可视化表单下发的 `formSchemaJson` 解释字段行为：`calculation` 决定公式，`readOnly` 决定能否输入，`unit` 只作为字段尾缀，`scale/roundingMode` 决定精度和舍入。

## 实现范围

- 数字和金额字段支持后台公式中的字段引用、数字、括号及 `+ - * /`。
- 支持计算字段依赖另一个计算字段，并按依赖顺序更新结果。
- 支持 0–8 位小数以及四舍五入、向下取整、向上取整和直接截断。
- 除零、字段缺失、非数字引用、循环依赖和结果精度溢出均失败关闭，不保留旧计算值。
- `readOnly`、计算字段和自动时长字段均禁止获得文本输入焦点。
- 金额字段移除移动端硬编码的 `¥`；币种或其他单位完全使用 schema 的 `unit`。
- 计算结果按 schema 小数位显示，但提交值仍为数值，不把格式说明混入表单数据。
- “站点”等普通字段继续严格服从后台字段类型；移动端不按字段名称猜测选择器或数据源。

## 当前线上表单观察

- 设备：realme RMX3366，Android 14，1080×2400。
- 应用：`com.hexing.zhilian.hexing_terminal_mobile`，v1.0.1 (2)。
- Profile APK SHA-256：`FBF19BFD3DFC6E3D5DF6D4816B5A1FD84E8F4735D83C955F8BBA4E8B55100464`。
- 线上“测试 · 分级请款审批”v1 的“请款金额”真实显示后台单位 `CNY`；UI 树中不存在“自动计算”或“只读”说明文本。
- 真机只点按空的“请款金额”字段，键盘能够打开，说明当前下发版本把该字段配置为可编辑；移动端没有依据“请款金额/成本”等标签擅自推断公式或只读状态。后台发布带 `calculation/readOnly` 的版本后，移动端会按同一 schema 自动切换为计算只读字段。
- 验证过程中没有输入值、选择数据、保存草稿或提交申请；返回“全部应用”后现有线上数据未改变。

## 证据

- 表单全貌：[01-tiered-payment-form.png](device-acceptance/dynamic-form-calculation-20260831/01-tiered-payment-form.png)
- 表单 UI 树：[01-tiered-payment-form.xml](device-acceptance/dynamic-form-calculation-20260831/01-tiered-payment-form.xml)
- 单位和计算字段区域：[02-calculation-field-area.png](device-acceptance/dynamic-form-calculation-20260831/02-calculation-field-area.png)
- 对应 UI 树：[02-calculation-field-area.xml](device-acceptance/dynamic-form-calculation-20260831/02-calculation-field-area.xml)

## 回归

- `flutter analyze`：0 问题。
- `flutter test`：189/189 通过。
- 新增公式引擎单元测试：链式双公式、旧值清除、除零和循环依赖。
- 新增页面测试：后台公式计算、只读不可聚焦、单位、币种、精度和无说明文本。
- 真机安装、冷启动、打开线上表单、聚焦空字段、关闭键盘和返回均正常；关键崩溃日志匹配 0 条。
