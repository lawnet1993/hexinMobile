# 806 · 真机 OA 选择交互与个人页语言语义复验

日期：2026-09-08（Asia/Shanghai）

## 结论

- 当前桌面功能基准继续采用用户确认的 Windows `v1.0.105`。
- realme 真机上的真实“请假审批”正确读取服务端 v1 表单：请假类型、起止时间、只读请假天数、事由、附件与会签路径均存在。
- 请假类型和日期选择均使用向上展开的底部抽屉，没有回退为中心弹窗；字段约 38dp、底部操作按钮约 34dp，符合当前紧凑移动端基线。
- 未填写、保存或提交申请，线上业务数据没有变化。

## 修复

真机“我的”页此前显示“浅色 · English”，但 App 根层当前固定为简体中文；服务端 `language` 实际是账号内容语言偏好，并不会切换现有硬编码界面。

- “我的 → 外观与语言”摘要仅展示真实生效的主题模式。
- 设置页把“账号语言”明确为“内容语言”，保留简体中文、繁體中文、English 的服务端偏好能力。
- 不再把内容语言描述成已生效的 App 界面语言，也没有伪造尚未实现的全量英文界面。

## 真机证据

- [真实请假表单](../test/evidence/real-device-main-pages-20260908/oa-leave-form-current.png)
- [请假类型底部抽屉](../test/evidence/real-device-main-pages-20260908/oa-leave-type-picker-current.png)
- [日期选择底部抽屉](../test/evidence/real-device-main-pages-20260908/oa-leave-datetime-picker-current.png)
- [个人页真实主题摘要](../test/evidence/real-device-main-pages-20260908/profile-truthful-language-summary.png)
- [内容语言设置](../test/evidence/real-device-main-pages-20260908/appearance-content-language-current.png)

## 验证

- 内容语言专项 Widget 测试：通过。
- Golden 回归：17/17 通过。
- 完整 Flutter 测试：1407/1407 通过。
- `flutter analyze`：0 issue。
- Android Profile APK：85,792,566 bytes。
- SHA-256：`70A1AC8F129A978DDEF62436582BC06248D10B87FD57B691057F08B75B91F826`。

## 边界

- 本轮没有宣称移动端已经支持完整多语言界面；要做到界面语言切换，仍需把现有硬编码文案迁移到 Flutter 本地化资源并逐页验收。
- 桌面 v1.0.105 的真实窗口功能抽查、iOS 真机及系统通知权限链路仍未闭环。
