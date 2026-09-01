# 582 OA 动态表单输入、附件与撤回真机验收

## 结论

本轮在 realme RMX3366（Android 14）真机上完成了一条真实 OA 请假申请的创建、附件上传、提交、进程重启后回查、附件再次预览和撤回清理闭环。

- 动态表单连续输入丢焦点问题已修复。
- 后台表单字段、自动计算天数和展开的审批流程保持由服务端 schema 驱动。
- 图片附件提交后由服务端持久化，强制停止并重启应用后仍可从申请详情打开。
- OA 审批意见、驳回原因、撤回原因等文本操作已统一为覆盖底部 Tab 的紧凑上拉抽屉。
- 仅创建并撤回本轮 `AI-UAT` 测试申请，没有修改现有申请、正式流程、账号或组织数据。

总体判定：**本轮范围通过**。这不代表整个移动端与桌面端功能对齐目标已经完成。

## 测试环境

| 项目 | 值 |
| --- | --- |
| 日期 | 2026-09-01（Asia/Shanghai） |
| 设备 | realme RMX3366 |
| 系统 | Android 14 |
| 应用 | `com.hexing.zhilian.hexing_terminal_mobile` |
| 构建 | Flutter Profile APK |
| APK SHA-256 | `A56120053F1C1E5171C02B2AE75602C0FAD1366F611B08461A38B23C2FA3AD4F` |
| 静态检查 | `flutter analyze`，0 个问题 |
| 自动化回归 | 209/209 通过 |
| 运行时回放 | 清空日志后复现抽屉打开与取消，关键异常 0 条 |

## 真实申请记录

| 项目 | 实际结果 |
| --- | --- |
| 申请编号 | `OA-20260901-C5084D` |
| 流程 | 请假审批 |
| 请假类型 | 事假 |
| 开始时间 | 2026-09-02 02:28 |
| 结束时间 | 2026-09-03 02:28 |
| 自动计算 | 2 天（自然日） |
| 请假事由 | `AI-UAT-OA-ATTACHMENT-20260901-0230` |
| 附件 | `AI-UAT-attachment-preview-20260831.png`，161.6 KB |
| 提交时间 | 2026-09-01 02:33 |
| 实际审批人 | 测试-管理员测试 |
| 提交后状态 | 审批中 |
| 清理后状态 | 已撤回；审批任务已取消 |
| 撤回原因 | `AI-UAT-TEST-CLEANUP` |

## 问题与修正

### P1：动态表单连续输入时丢失焦点

复现：在“请假事由”中连续输入字符。修复前每次 `onChanged` 都触发父级刷新，而可编辑输入框的 Key 包含实时值；输入一个字符后 Key 改变，Flutter 重建输入框并释放焦点，后续字符无法连续输入。

实际修正：可编辑字段改为稳定的字段 ID Key；只读计算字段继续包含显示值，以便服务端公式计算结果刷新。真机连续输入完整 `AI-UAT-OA-ATTACHMENT-20260901-0230` 后，输入框仍保持焦点。

自动化补充：动态申请页按字符连续输入，并断言每次刷新后可编辑字段仍保持焦点。

### P2：OA 文本操作抽屉视觉与移动端规范不一致

审批意见、驳回原因和撤回原因此前使用高亮蓝色大输入框及通栏大按钮，与联系人等已收敛页面不一致。

实际修正：统一复用紧凑移动端文本输入抽屉，保留必填校验、500 字限制、2–4 行输入、键盘安全区和右对齐 36dp 操作按钮。真机打开现有申请的撤回抽屉后仅取消，没有修改该申请。

## 真实验收步骤与结果

1. 打开请假审批，恢复带一张图片附件的本地草稿。
2. 通过上拉选择器选择“事假”，通过日期与时间选择器设置起止时间。
3. 验证“请假天数”由后台字段规则自动计算为 2 天，字段只读且没有把 schema 配置对象当作文本值展示。
4. 连续输入完整 AI-UAT 事由，确认焦点不再因页面刷新丢失。
5. 提交申请并进入服务端详情，记录编号、状态、审批人、表单值、附件和流程。
6. 打开附件，确认图片能够实际预览。
7. 强制停止并重启应用，在“我发起的”顶部重新找到同一申请。
8. 再次打开详情与附件，确认数据来自服务端持久化，而非仅存于当前页面或本地草稿。
9. 撤回本轮申请，确认详情变为“已撤回”，审批任务变为“已取消”，并出现“再次发起”入口。
10. 在另一条既有申请上仅打开新的紧凑撤回抽屉并取消，验证新样式没有产生写操作。

## 截图证据

- `docs/device-acceptance/582-leave-form-initial.png`：初始动态表单与附件
- `docs/device-acceptance/582-leave-type-sheet.png`：请假类型上拉选择
- `docs/device-acceptance/582-leave-start-picker.png`：日期选择器
- `docs/device-acceptance/582-leave-start-time-picker.png`：时间选择器
- `docs/device-acceptance/582-leave-dates-selected.png`：起止时间与自动天数
- `docs/device-acceptance/582-reason-after-b.png`：修复前输入后丢焦点
- `docs/device-acceptance/582-reason-after-c.png`：修复前连续输入被中断
- `docs/device-acceptance/582-reason-focus-fixed.png`：修复后完整连续输入且保持焦点
- `docs/device-acceptance/582-ready-after-keyboard-dismiss.png`：提交前完整表单
- `docs/device-acceptance/582-submit-result.png`：服务端申请详情与申请编号
- `docs/device-acceptance/582-submitted-attachment-preview.png`：提交后的附件预览
- `docs/device-acceptance/582-initiated-after-restart.png`：强制重启后“我发起的”列表
- `docs/device-acceptance/582-detail-after-restart.png`：重启后服务端详情
- `docs/device-acceptance/582-attachment-after-restart-settled.png`：重启后再次打开附件
- `docs/device-acceptance/582-withdraw-result.png`：撤回成功及审批任务取消
- `docs/device-acceptance/582-withdraw-compact-fixed.png`：统一后的紧凑撤回抽屉

## 代码与回归覆盖

- `lib/features/todos/presentation/approval_request_page.dart`：稳定可编辑字段 Key，保留只读计算值刷新。
- `lib/features/todos/presentation/approval_detail_page.dart`：审批与原因输入改用共享移动端抽屉。
- `lib/shared/widgets/mobile_bottom_sheets.dart`：文本输入抽屉支持按业务控制自动聚焦。
- `test/oa_mobile_pages_test.dart`：增加连续输入焦点、紧凑操作尺寸、计算字段和附件 schema 回归。

## 未覆盖与后续

- 本轮没有代替审批人执行同意、驳回、转交、加签等业务操作，避免扩大线上写入范围。
- 复杂金额分支、会签/或签和通知全链路仍应使用专门的 AI-UAT 流程与多账号验收。
- 桌面端到移动端反向消息发送仍需单独操作确认；不属于本轮 OA 表单范围。
