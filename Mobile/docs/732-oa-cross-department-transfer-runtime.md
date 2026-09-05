# 732 OA 跨部门转交、完成状态与通知实测

时间：2026-09-05 01:54–02:05（Asia/Shanghai）。本轮核心链路通过，但完整 IM/OA 对齐目标仍未完成。

## 真实链路

- M3 以 Test Terminal 03（财顺）在移动端真实发起请假申请，唯一测试标记为 `AI-UAT-20260905-015500-OA-TRANSFER-732`。
- 请求 ID 为 `6aef7a25-5e20-442b-9136-986e3f7022fc`，模板为 `system.default.attendance.leave` v1；没有修改模板、账号、部门或已有业务数据。
- 初始节点实际解析给 Test Terminal 03；随后通过移动端把任务真实转交给跨部门的 Test Terminal 01（公司总部），转交理由为 `AI-UAT-732-cross-department-transfer`。
- 原任务状态变为 `transferred`、不可操作；新任务由 Test Terminal 01 接收。真机待办数从 3 变为 4，打开的是同一请求。
- 真机以 Test Terminal 01 真实同意，意见为 `AI-UAT-732-approved-by-test01`。最终请求状态 `approved`，两项后续业务动作 `service_queued`、`service_succeeded` 均完成。
- 只读 API 在 02:04 再核验为 HTTP 200；请求完成时间、两项任务及三位实际处理记录均与两台移动端 UI 一致。

## 跨端状态和通知

- M3 一直停留在转交后的详情页。审批完成约 15 秒时曾截到“审批中”，随后未重新打开页面便自动变为“已通过”。本地事件 588 `approval.updated` 于 17:58:40Z 落地，距离服务端完成 17:58:22Z 约 18 秒，符合当前 20 秒长轮询窗口；不能把中间截图定性为永久不刷新。
- 最终详情同时保留“已转交”的旧任务和 Test Terminal 01 的“已同意”任务，已处理账号没有重新出现同意/驳回入口。
- M3 收到“审批结果”和“业务回写完成”两条不同语义的通知。点击审批结果后进入正确申请，未读总数 39→38；回执 `state=sent`、`attempts=0`，OA Outbox 为空。
- 强制停止并冷启动 M3 后，Test Terminal 03 自动登录仍保留；未读仍为 38、该条不再显示未读圆点、已读回执与 cursor 593 均持久化。
- 冷启动进程日志检查：FATAL、Unhandled Exception、RenderFlex overflow 均为 0。

## 自动化保护

`oa_approval_live_refresh_test.dart` 新增两项真实状态形态回归：

1. `submitted + 原任务 transferred + 新任务 pending` 经目标请求事件刷新后成为 approved；
2. 没有事件扇出的情况下，经 30 秒可见详情兜底刷新成为 approved。

两项都验证旧转交记录保留、新处理人已同意、旧处理人始终无同意/驳回按钮、终态后停止轮询。本文件全部 14/14、全量 1361/1361 通过；定向分析无问题。

## 发现的问题

### P2：临时申请编号受设备时区影响

同一请求在真机显示 `OA-20260905-6AEF7A`，M3 显示 `OA-20260904-6AEF7A`。M3 系统时区是 GMT，真机是 Asia/Kuala_Lumpur；当前移动端使用 `createdAt` 的设备本地日期拼接编号，列表页和详情页各实现了一次。服务端详情没有正式 `requestNumber` 字段，因此移动端无法在不改变协议的情况下生成稳定且和桌面一致的业务编号。

建议桌面/服务端处理提示词：

> 请检查 OA 审批详情和分页协议。当前服务端只有请求 UUID 与 UTC createdAt，没有稳定的业务申请编号；客户端按本地时区拼接 `OA-yyyyMMdd-UUID前6位`，导致同一申请在 GMT 和 UTC+8 设备显示不同编号。请由服务端在创建时生成并持久化不可变 `requestNumber`，在 bootstrap、审批分页、详情、通知目标及桌面端统一返回和展示。不得根据查看设备时区重新计算，也不得使历史请求编号随时区变化。兼容期可返回空值，但新客户端应优先使用服务端编号；请补跨时区、分页/详情一致、通知跳转、历史兼容和唯一性测试。不要通过固定客户端时区掩盖协议缺口。

本轮没有让移动端单方面固定 UTC 或 UTC+8，以免继续制造与桌面端不同的编号规则。

## 证据

- `test/evidence/oa-transfer-732/02-ready.png`：提交前最终字段。
- `03-submitted.png`、`05-transferred.png`：发起与转交后的真实详情。
- `08-phone-task.png`、`09-phone-approved.png`：真机接收任务与完成。
- `10-server-approved.json`：服务端最终状态。
- `11-m3-live-approved.png`：约 15 秒时仍在审批中的中间态（文件名沿用现场命名，内容不是终态）。
- `12-m3-confirmed-approved.png`：未重新打开详情的 M3 最终状态。
- `13-m3-notifications.png`、`14-m3-notification-read.png`：通知到达与点击后状态。
- `15-m3-cold-notification-read.png`、`16-m3-cold-oa-metadata.json`：冷启动持久化和只读元数据。

## 边界

- 本轮只证明单节点请假流程的跨部门转交、审批、终态刷新和一条通知已读链路；不代表多节点、会签/或签、加签、退回、撤回、附件及所有模板已通过。
- 桌面端仅使用既有 test01 会话做只读 HTTP 最终状态核验，没有把本轮描述成桌面 UI 操作证明。
- 自动生成标题仍沿用后台模板规则 `Test Terminal 03的请假审批`；AI-UAT 唯一标记保存在请假事由中，没有重新引入不属于可视化表单的标题输入框。
