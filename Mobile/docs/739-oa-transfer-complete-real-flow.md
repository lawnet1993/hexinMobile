# 739 · OA 转交后接收人完整处理

时间：2026-09-05 03:13–03:16（Asia/Shanghai）。结论为 **本条转交链路通过，移动端整体目标继续**。

继续使用正常移动端 UI 新建一条独立 AI-UAT 请假申请，test03 将原审批任务转交给 test01，test01 真机收到任务后实际同意，test03 模拟器自然同步最终状态。服务端与 SQLite 仅作动作后的只读核对。

## 申请与身份

- 申请 ID：`21748765-9829-4152-8ce7-0413a6842d75`
- 唯一说明：`AI-UAT-20260905-031400-OA-TRANSFER-739`
- 申请人及原审批人：test03 / Test Terminal 03 / 财顺。
- 转交接收人：test01 / Test Terminal 01 / 公司总部。
- 事假，2026-09-05 19:13 至 2026-09-06 19:13，自动计算 2 天，无附件。
- `templateVersion=1`，最终 `requestVersion=3`，`workflowKey=system.default.attendance.leave`。

## 真实流转

| 服务器 UTC 时间 | 动作 | 任务与权限结果 |
| --- | --- | --- |
| 19:13:49 | test03 提交 | 原任务 test03 `pending`、可操作 |
| 19:14:31 | test03 转交 test01；意见 `AI-UAT-739-TRANSFER-TO-TEST01` | 原任务 `transferred/canOperate=false`；新任务 test01 `pending` |
| 19:15:50 | test01 真机同意；意见 `AI-UAT-739-TRANSFER-APPROVED` | 新任务 `approved/canOperate=false`；整单 `approved`、`allowedActions=[]` |
| 19:15:50–19:15:51 | 系统后续服务 | 排队并成功，考勤业务回写完成 |

转交后 test03 页面只保留“更多”，同意/驳回消失；test01 首页收到同一申请的新待办并可操作。test01 完成后，test03 当前详情在一个同步周期内自然变成“已通过”，没有刷新、重启或重新登录。旧任务保持“已转交”，没有误显示为“已同意”或继续占用处理权限。

test01 首页通知数量 50→51；待办总数在上一条后加签完成并移除的同时新增本条转交任务，因此保持 4，不把总数未增加误判成没有收到任务。

服务端详情 HTTP 200，处理记录保留提交、转交、test01 同意、服务排队和服务成功。`service_queued` 与最后一次 `approved` 时间相同，不用同秒列表展示顺序推导动作因果。

test03 本地 OA 游标到 640，已落地 `approval.task.transferred`、`approval.updated`、通知、`attendance.adjusted` 和 `approval.business-result.updated`，目标申请缓存更新时间为 19:15:54Z，Outbox 为空。

结构化摘要见 [transfer-flow-summary.json](../test/evidence/oa-advanced-737/transfer-flow-summary.json)。详情响应请求编号 `3982f3b7-708e-43d2-89e9-b11b90c1b497`，test01 同步响应请求编号 `8083609d-8356-4d94-9a93-4390d276a8ed`。

## 页面证据

- [独立申请表单](../test/evidence/oa-advanced-737/43-transfer-form.png)
- [提交后原任务可处理](../test/evidence/oa-advanced-737/44-transfer-submitted.png)
- [转交完成、原任务失权](../test/evidence/oa-advanced-737/45-transferred.png)
- [test01 首页收到转交任务](../test/evidence/oa-advanced-737/46-phone-transfer-home.png)
- [test01 打开可操作任务](../test/evidence/oa-advanced-737/47-phone-transfer-task.png)
- [test01 同意、整单通过](../test/evidence/oa-advanced-737/48-phone-transfer-approved.png)
- [test03 自然同步终态](../test/evidence/oa-advanced-737/49-emulator-transfer-final-synced.png)

## 结论边界

679 中“转交接收人未实际同意”的缺口已关闭。737、738、739 已分别完成前加签、后加签和转交的双设备完整终态；三条申请彼此独立，均使用 AI-UAT 标记。

退回、驳回、会签/或签、复杂金额分支、附件新桌面版本复核、桌面入站 IM P1、真机自然到期和隔夜恢复仍未完成，因此不能判定整体移动端或 OA 验收通过。
