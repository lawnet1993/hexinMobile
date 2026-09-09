# 873 · 服务端更新后实服复验

时间：2026-09-09（Asia/Shanghai）  
环境：线上测试环境；test03 Android 模拟器发送，test01 realme 真机接收。仅写入 `AI-UAT-` 测试消息，证据不包含密码、令牌、Cookie、完整设备标识或消息正文之外的敏感数据。

## 结论

**本次服务端更新部分通过。** 不可见会话已读语义继续通过，OA 任务详情继续完整下发 `completionMode`。群聊 Gateway 长轮询唤醒已明显恢复，但“点击发送至收件人事件生成”连续约 3.9–4.0 秒，用户可见到达耗时为 3.2–6.0 秒，发送链路实时性仍未通过。`return` 和 `any/sequential` 仍缺可执行运行态样本，不能按发布声明判定通过。

## 1. 不可见会话已读：通过

1. test01 保持在工作台，未打开 test03 单聊。
2. test03 发送唯一 `AI-UAT-SERVERUPDATE-UNSEEN-...` 消息。
3. 消息序号 281 已唯一落库、事件游标 `applied=acked=6587` 后，test01 仍为 `lastReadSequence=280`、`unreadCount=1`。
4. test01 真实打开会话后，SQLite 投影才更新为 `lastReadSequence=281`、`unreadCount=0`。
5. test03 随后显示“已有接收人已读”。

这证明服务端更新没有重新引入“后台或不可见会话被提前读掉”的错误语义，且跨端已读事件、未读持久化和发送端回执一致。

## 2. 群消息实时性：Gateway 唤醒通过，发送前段仍慢

共同测试群前台连续发送 B/C/D 三条消息，接收 App 始终为前台：

| 样本 | 点击发送至收件人事件生成 | 首次 UI 观察到消息 | 结论 |
| --- | ---: | ---: | --- |
| B | 约 3.95 秒 | 3.23 秒观察到 | 事件生成后长轮询立即返回 |
| C | 约 3.90 秒 | 3.27 秒观察到 | 事件生成前后存在设备时钟偏差，但无额外长轮询尾延迟 |
| D | 约 3.98 秒 | 3.04 秒未见、6.00 秒已见 | 同步记录在事件生成约 2.30 秒后落日志，事件未丢失 |

事件序号依次为 6581、6583、6585，无丢失、重复或乱序，游标最终 `applied=acked=6585`。B 的同步提交 93 ms、ACK 114 ms；D 的提交 47 ms、ACK 108 ms。更新后没有再复现“事件已经创建但长轮询仍无故等待数秒”的原问题。

仍需服务端排查发送链路前段，因为三次 `recipientEventCommittedAt - sendTapAt` 均约 4 秒。建议在同一请求编号下记录：

- `sendRequestReceivedAt`
- `messageCommittedAt`
- `recipientEventCommittedAt`
- `wakePublishedAt`
- `longPollReturnedAt`

验收应拆成两个指标：事件提交至长轮询返回 P95 ≤ 2 秒；用户点击发送至目标前台可见 P95 ≤ 2 秒。当前前者本轮样本通过，后者未通过。

## 3. OA 契约：字段存在，运行态覆盖仍不足

更新后重新只读检查全部、待办、我发起、抄送、已完成和草稿：

- 37 条唯一申请，4 条待办，125 个任务。
- 125/125 个任务均有非空 `completionMode`。
- 125 个样本仍全部为 `all`，没有 `any` 或 `sequential`。
- 已下发操作仍为 `approve/reject/transfer/add_sign/withdraw/remind`，`returnCandidateCount=0`。
- bootstrap 当前有 6 个系统模板：出差、加班、考勤申诉、补卡、请假、报销；没有可用于退回验收的 `AI-UAT-` 多节点流程。

因此 `completionMode` 字段缺失问题保持关闭；但服务端仍需提供已发布的 `any`、`sequential` 流程样本。`return` 必须在新发布的多节点流程、新建实例推进至第二审批节点后，真实出现于 `allowedActions` 并完成一次退回，才可通过。

## 证据

- `test/evidence/server-contract-recheck-20260909-after-update/oa-actions.json`
- `test/evidence/server-contract-recheck-20260909-after-update/group-B-result.json`
- `test/evidence/server-contract-recheck-20260909-after-update/group-CD-result.json`
- `test/evidence/server-contract-recheck-20260909-after-update/realme-sync-timing.json`
- `test/evidence/server-contract-recheck-20260909-after-update/realme-sync-timing-after-CD.json`
- `test/evidence/server-contract-recheck-20260909-after-update/unseen-before-open.json`
- `test/evidence/server-contract-recheck-20260909-after-update/unseen-after-open.json`
- `test/evidence/server-contract-recheck-20260909-after-update/emulator-sender-read-receipt.xml`

本轮未修改移动端运行逻辑；结论来自更新后同一测试环境的真实双设备操作和只读本地/接口证据。
