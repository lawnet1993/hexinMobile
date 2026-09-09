# 872 · 服务端契约修复实服复验

时间：2026-09-09（Asia/Shanghai）  
环境：线上测试环境，仅使用 `AI-UAT-` 测试消息和既有测试审批数据。验证过程未输出密码、令牌、Cookie、完整设备标识或附件地址。

## 结论

**部分通过。** “不可见会话提前已读”已确认修复，OA 任务已真实下发 `completionMode`。群聊事件最终一致性正常，但端到端实时性仍未稳定达到原 P95 ≤ 2 秒标准；`return` 当前没有新的已发布可发起流程和符合资格的运行实例，因此不能仅凭服务端发布说明判定通过。

## 1. 不可见会话已读语义：通过

测试拓扑：test03 Android 模拟器发送，test01 realme 真机接收。

1. test01 停在工作台，从未打开目标单聊。
2. test03 发送 `AI-UAT-SERVERFIX-UNSEEN-...` 消息。
3. test01 本地事件游标已经 `applied=acked=6523`，新消息唯一落库，序号 277。
4. 打开会话前，本地投影为 `lastReadSequence=275`、`unreadCount=2`，证明服务端没有在不可见会话中推进本人已读。
5. test01 真实打开会话后，本地持久化为 `lastReadSequence=277`、`unreadCount=0`。
6. test03 同一条消息由“已发送”更新为“已有接收人已读”。

这同时验证了：只有真实可见阅读才推进游标、SQLite 持久化未读清零、接收人已读事件能反向到达发送端。

## 2. 群事件唤醒：改善但仍未通过实时 SLA

test03 向两端共同存在的测试群发送，test01 停在消息列表：

| 样本 | 列表观察 | 同步阶段证据 |
| --- | --- | --- |
| 首条 | 约 4.7 秒时未显示，约 10.2 秒观察到 | 事件创建后约 3,163 ms 才返回；提交 38 ms，ACK 91 ms |
| 补样 B | 约 10.6 秒上界内可见 | 长轮询返回时事件年龄约 -233 ms（设备时钟偏差）；提交 62 ms，ACK 114 ms |
| 补样 C | 约 10.6 秒上界内可见 | 长轮询返回时事件年龄约 -288 ms（设备时钟偏差）；提交 44 ms，ACK 94 ms |

补样 B/C 表明“事件创建后唤醒”已有明显改善，但从点击发送到事件产生/接收仍约 3.4–3.7 秒；首条还复现了事件已创建后继续等待 3.16 秒。样本没有丢失、重复或乱序，游标 applied=acked。

服务端仍需提供并核对以下时间点，才能判断慢点位于发送 API、事务提交、事件投递还是 Gateway 唤醒：

- `sendAcceptedAt`
- `messageCommittedAt`
- `recipientEventCommittedAt`
- `wakePublishedAt`
- `longPollReturnedAt`

验收标准保持不变：前台网络正常时，单聊和群聊“事件提交至目标长轮询返回”P95 ≤ 2 秒；连续压力样本无丢失、重复和乱序。当前不能用最终一致性替代实时性通过。

## 3. OA `completionMode`：字段通过，多模式样本未闭环

使用 test01 的已授权桌面测试会话只读检查全部、待办、我发起、抄送、已完成和草稿视图，共 37 条唯一申请、125 个任务：

- 125/125 个任务均返回非空 `completionMode`。
- 当前样本全部为 `all`。
- 移动端已经按 `all/any/sequential` 显示“会签/或签/依次审批”，没有自行猜测模式。

因此“详情缺字段”的服务端缺陷已关闭；但测试服仍需提供至少一个 `any` 和一个 `sequential` 的已发布真实流程，才能验证三种模式的运行态语义和移动端展示。

## 4. OA `return`：当前仍缺可执行样本

同一次只读检查结果：

- 37 条唯一申请中有 4 条待办。
- `approve/reject/transfer/add_sign/withdraw/remind` 均有真实下发。
- `returnCandidateCount=0`。
- test01 当前 `/api/oa/bootstrap` 只下发考勤申诉、补卡、请假三个系统模板，原 `AI-UAT-退回验收-20260906-103600` 不在可发起目录。

这不等价于证明服务端仍未修复：旧运行实例不会自动继承修复，且当前没有新的已发布模板可创建合格样本。但也不能判定通过。需要重新发布一个允许退回且至少包含“申请人 → 第一审批节点 → 第二审批节点”的 `AI-UAT-` 流程，创建新申请并推进至第二审批节点；此时详情 `allowedActions` 必须包含 `return`，再由移动端真实退回并核对目标节点、原因、历史和通知。

## 证据

- `test/evidence/server-contract-recheck-20260909/unseen-db.json`
- `test/evidence/server-contract-recheck-20260909/visible-read-db.json`
- `test/evidence/server-contract-recheck-20260909/realme-after-visible-read.xml`
- `test/evidence/server-contract-recheck-20260909/emu-after-peer-read.xml`
- `test/evidence/server-contract-recheck-20260909/group-result.json`
- `test/evidence/server-contract-recheck-20260909/group-three-samples.json`
- `test/evidence/server-contract-recheck-20260909/realme-sync-timing.json`
- `test/evidence/server-contract-recheck-20260909/realme-sync-timing-after-three.json`

## 客户端回归

与本轮契约直接相关的已读会话隔离、接收人回执、同步失效、OA 模型和审批操作入口测试共 **90/90 通过**。本轮没有修改移动端运行逻辑；仅增强只读诊断脚本，允许对已授权真机输出白名单聚合指标，并增加会话投影序号核对。
