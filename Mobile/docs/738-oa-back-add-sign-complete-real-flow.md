# 738 · OA 后加签完整真实流转

时间：2026-09-05 03:07–03:12（Asia/Shanghai）。结论为 **本条后加签链路通过，移动端整体目标继续**。

在 737 前加签通过后，继续使用正常移动端页面新建一条独立 AI-UAT 请假申请，完成后加签、原节点同意、新节点激活、加签人同意及业务回写。业务动作全部来自 test03 模拟器和 test01 真机 UI；服务端与 SQLite 仅用于动作后的只读核对。

## 申请

- 申请 ID：`fe4e924e-1cef-4928-a933-b399be4fa602`
- 唯一说明：`AI-UAT-20260905-031000-OA-BACK-SIGN-738`
- 申请人：test03 / Test Terminal 03 / 财顺。
- 加签人：test01 / Test Terminal 01 / 公司总部。
- 事假，2026-09-05 19:07 至 2026-09-06 19:07，自动计算 2 天，无附件。
- `templateVersion=1`，最终 `requestVersion=4`，`workflowKey=system.default.attendance.leave`。

模拟器显示 `OA-20260904-FE4E92`，真机显示 `OA-20260905-FE4E92`；日期段跨设备不一致继续归入既有 P2，不影响本条同一 ID 的流转判断。

## 状态序列

| 服务器 UTC 时间 | 真实 UI 动作 | 原 test03 节点 | 新 test01 加签节点 | 整单 |
| --- | --- | --- | --- | --- |
| 19:07:56 | test03 提交 | `pending`、可操作 | 不存在 | `submitted` |
| 19:09:13 | test03 选择 test01，后加签；意见 `AI-UAT-738-BACK-ADD-SIGN` | 仍 `pending`、可操作 | `waiting`、不可操作 | `submitted` |
| 19:09:57 | test03 同意；意见 `AI-UAT-738-ORIGINAL-APPROVED` | `approved`、不可操作 | `pending`、test01 可操作 | `submitted` |
| 19:11:30 | test01 真机同意；意见 `AI-UAT-738-BACK-APPROVED` | `approved` | `approved` | `approved`、`allowedActions=[]` |
| 19:11:32 | 系统后续服务成功 | `approved` | `approved` | 考勤回写完成 |

关键交互符合后加签语义：新节点在原节点完成前只显示“等待中”，test01 首页没有提前出现可处理任务；原节点同意后 test01 首页待办 3→4、通知 49→50，新节点才显示“待你处理”。原处理人同意后没有提前提示整单通过；只有 test01 最后同意后整单变为“已通过”。

服务端详情 HTTP 200，两个任务最终均 `approved/canOperate=false`；处理记录保留提交、加签、test03 同意、test01 同意、服务排队和服务成功。`service_queued` 与最后一次 `approved` 的服务器时间完全相同，页面中的同秒记录顺序不能用于推断业务先后；任务终态和整单完成时间是权威结果。

## 双设备同步

- test01 本地 OA 游标到 620，落地 `approval.task.created` 与对应通知事件；缓存中存在目标申请，Outbox 为空。
- test03 本地 OA 游标到 625，落地最终 `approval.updated`、通知、`attendance.adjusted` 与 `approval.business-result.updated`；缓存中存在目标申请，Outbox 为空。
- test01 完成最后一步后，test03 当前详情在约一个同步周期内自然更新为“已通过”，无需退出、刷新或重新登录。
- 两台设备运行日志未见 `FATAL EXCEPTION`、`E/flutter` 或 `RenderFlex overflowed`。

结构化摘要见 [back-sign-flow-summary.json](../test/evidence/oa-advanced-737/back-sign-flow-summary.json)。服务端详情响应请求编号 `59c3eb91-45aa-4ac8-af6e-16ccbc404b25`，同步响应请求编号 `6c7a1839-00db-44ae-850b-7787d83cb482`。

## 页面证据

- [独立申请表单](../test/evidence/oa-advanced-737/34-back-sign-form.png)
- [提交后原节点待处理](../test/evidence/oa-advanced-737/35-back-sign-submitted.png)
- [后加签成功：新增节点等待](../test/evidence/oa-advanced-737/36-back-sign-applied.png)
- [原节点同意：新增节点激活](../test/evidence/oa-advanced-737/38-back-original-approved.png)
- [test01 首页收到激活任务](../test/evidence/oa-advanced-737/39-phone-back-task-home.png)
- [test01 打开后加签任务](../test/evidence/oa-advanced-737/40-phone-back-task.png)
- [test01 最终同意](../test/evidence/oa-advanced-737/41-phone-back-approved.png)
- [test03 自然同步最终通过](../test/evidence/oa-advanced-737/42-emulator-back-final-synced.png)

`37-back-original-approved.*` 是软键盘弹出后、确认按钮坐标改变时采到的确认抽屉，不是审批成功证据；报告采用随后真实确认后的 38。

## 结论边界

679 中“后加签接收人没有实际处理、最终通过未证明”的缺口已经关闭。737 与 738 合起来证明当前普通移动包的前/后加签基本状态机、权限迁移、跨设备 OA 事件和业务回写可工作。

仍未完成：转交接收人最终同意、退回/驳回、会签/或签、复杂金额分支、附件新桌面版本复核、桌面入站 IM P1、真机自然到期与隔夜恢复。不能用本条通过替代整体 OA 或移动端验收通过。
