# 737 · OA 前加签完整真实流转

时间：2026-09-05 02:54–03:04（Asia/Shanghai）。结论为 **本条前加签链路通过，移动端整体目标继续**。

本轮在正常移动端页面完成一条带唯一 AI-UAT 标记的请假申请，依次执行前加签、新处理人同意、原处理人恢复并同意。业务动作全部来自模拟器和真机 UI；服务端接口及 SQLite 只用于动作后的只读核对。没有修改既有申请、正式账号、部门、岗位、数据库或桌面会话。

用户已确认五个主页面基本达到预期，后续不再继续无必要的首页视觉重构；桌面附件预览也已由另一侧修改，本轮只记录，不重复开发。

## 环境与申请

| 对象 | 实际身份与作用 |
| --- | --- |
| Android 16 模拟器 / emulator-5556 | test03 / Test Terminal 03 / 财顺；申请人、原审批人 |
| realme 真机 / dd00d66d | test01 / Test Terminal 01 / 公司总部；前加签审批人 |
| 服务端 | `http://api.sfhkh.com`；动作后只读 GET 核对 |

- 申请 ID：`702821d9-c252-406d-b060-095812719950`
- 唯一说明：`AI-UAT-20260905-025500-OA-ADD-SIGN-737`
- 类型：事假；开始 2026-09-05 18:54，结束 2026-09-06 18:54；后台表单自动计算 2 天；无附件。
- `templateVersion=1`，最终 `requestVersion=4`，`workflowKey=system.default.attendance.leave`。
- 模拟器显示编号 `OA-20260904-702821`，真机显示 `OA-20260905-702821`。同一申请在不同设备出现日期段不一致，延续 732 已记录的服务端/时区显示 P2，不作为本条流转通过项。

## 完整流转

| 服务器 UTC 时间 | 页面真实动作 | 权限与结果 |
| --- | --- | --- |
| 18:55:25 | test03 提交申请 | 原“部门负责人审批”分配 test03，可操作 |
| 18:58:52 | test03 选择 test01，执行前加签；意见 `AI-UAT-737-FRONT-ADD-SIGN` | 原任务转 `waiting` 且操作按钮消失；新增“部门负责人审批（加签）”为 test01 `pending` |
| 19:00:30 | test01 在真机同意；意见 `AI-UAT-737-FRONT-APPROVED` | 加签任务 `approved`；原任务恢复 `pending`，test03 的同意/驳回入口重新出现 |
| 19:01:52 | test03 在模拟器同意；意见 `AI-UAT-737-ORIGINAL-APPROVED` | 原任务 `approved`；整单 `approved`；`allowedActions=[]` |
| 19:01:53 | 系统后续服务完成 | `service_queued` 后 `service_succeeded`，考勤业务回写事件已生成 |

最终服务端任务：

- Test Terminal 03 / 财顺 / “部门负责人审批”：`approved`、`canOperate=false`。
- Test Terminal 01 / 公司总部 / “部门负责人审批（加签）”：`approved`、`canOperate=false`。
- 处理记录保留提交、加签、两次同意、服务排队和服务成功，没有把中间节点同意误判为整单完成，也没有给已处理人保留操作按钮。

## 双设备通知与持久化

- 前加签后，test01 真机首页未读通知 48→49、待办 3→4，并出现“Test Terminal 03 的请假审批”；通知中心存在“当前节点：部门负责人审批（加签）”。
- test01 同意后，test03 模拟器通过自然同步恢复原审批任务，无需刷新页面或重启应用。
- 最终同意后，test03 通知中心按独立事件显示“加签已同意，审批继续流转”“审批已通过”“审批结果已同步到考勤业务”；没有用一条模糊成功提示代替三种状态。
- test03 本地 OA 游标到 610，缓存中存在该申请，已落地 `approval.updated`、`approval.task.created`、`oa.notification.created`、`approval.business-result.updated` 和 `attendance.adjusted` 等事件；test01 游标到 601，已落地加签任务与通知事件。
- 两端 SQLite Outbox 均为空；本轮没有直接修改数据库。

结构化只读摘要见 [flow-summary.json](../test/evidence/oa-advanced-737/flow-summary.json)。服务端核对请求均为 HTTP 200；详情响应请求编号为 `5a5d1e19-b1dc-4592-a3d6-a6412e731514`，OA 同步响应请求编号为 `d2bb6790-7bc4-4938-addf-aeeb26f69b7a`。

## 页面证据

- [提交后](../test/evidence/oa-advanced-737/07-submitted.png)
- [前加签成功、原节点等待](../test/evidence/oa-advanced-737/20-front-add-sign-applied.png)
- [test01 真机收到新待办](../test/evidence/oa-advanced-737/21-phone-after-front-add.png)
- [test01 打开加签任务](../test/evidence/oa-advanced-737/22-phone-front-task.png)
- [test01 同意、原节点恢复](../test/evidence/oa-advanced-737/25-phone-front-approved.png)
- [test03 收到恢复的原任务](../test/evidence/oa-advanced-737/26-emulator-original-resumed.png)
- [test03 最终同意](../test/evidence/oa-advanced-737/29-emulator-final-approved.png)
- [test01 同步最终通过](../test/evidence/oa-advanced-737/30-phone-final-synced.png)
- [test01 加签待办通知](../test/evidence/oa-advanced-737/32-phone-notifications.png)
- [test03 流转、通过及业务回写通知](../test/evidence/oa-advanced-737/33-emulator-notifications.png)

第一次填写加签意见时误发 Android 返回键，底部抽屉被关闭；服务端没有产生加签动作。随后从详情重新进入并完成同一操作，报告只采用 20 及之后的稳定证据，不把失败交互冒充成功。

## 回归与未完成项

- OA 动作并发/会话保护、详情实时刷新、历史标签定向测试 **71/71** 通过。
- 本轮没有修改业务 Dart 源码；此前同一源码全量 **1362/1362**、静态分析 0 问题保持有效。
- 两台设备运行日志未见 `FATAL`、`E/flutter` 或 `RenderFlex overflow`。

本条真实前加签完整链路已关闭 679 中“接收人未实际处理”的证据缺口，但不能据此判定全部 OA 或移动端验收完成。后加签完整终态已在随后 738 关闭；转交接收人最终处理、退回/驳回、会签/或签、复杂金额分支、附件新桌面版本复核、桌面入站 IM P1、真机自然到期与隔夜恢复仍需继续验证。
