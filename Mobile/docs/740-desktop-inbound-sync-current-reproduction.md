# 740 · 当前桌面 v1.0.91 入站消息再次复现

时间：2026-09-05 03:19–03:22（Asia/Shanghai）。结论：**移动端与服务端通过，当前运行的 Windows v1.0.91 入站同步仍为 P1 不通过**。

本轮没有重启、重登、刷新或清理 Windows 客户端，也没有修改桌面数据库。D1 仍是用户当前打开的 test01 会话；进程 `hexing-zhilian` PID 139028，自 2026-09-04 23:52:54 启动，检查时正常响应。

## 真实复现

- 会话：`2a2ea21f-2ad6-49b3-b3da-407d1e7e4136`，服务端类型 `direct`。
- M3/test03 在正常聊天 UI 输入并发送 `AI-UAT-20260905-032000-M3-D1-DIRECT`。
- M3 页面显示已发送；服务端生成消息 ID `5815436e-bc6f-40d4-8111-8528169040ff`、`clientMessageId=fa46d7c1-6525-4600-9ede-013eb695ea9b`、会话序号 18。
- M1/test01 真机约数秒内在会话列表显示相同正文和未读 1；SQLite 中目标消息唯一、状态 sent、会话 18 条、游标 2361 已落地并 ACK、Outbox 为空、integrity=ok。
- 随后从 test01 真机会话列表真正打开该消息：服务端 `lastReadSequence` 17→18、未读 1→0，并生成 `conversation.read` 事件 2363；M3 在当前聊天自然显示“已有接收人已读”，本地 recipient-read=18、事件游标 applied/acked=2364。
- M3 SQLite 同样只有一条目标消息、状态 sent、会话序号 18、游标已落地并 ACK、Outbox 为空、integrity=ok。

页面证据：[M3 发送成功](../test/evidence/im-desktop-inbound-740/01-m3-sent.png)、[M1 收到未读](../test/evidence/im-desktop-inbound-740/02-phone-received.png)、[M1 打开真实消息](../test/evidence/im-desktop-inbound-740/04-phone-read.png)、[M3 收到已读回执](../test/evidence/im-desktop-inbound-740/05-m3-read-receipt.png)。`03-phone-read.*` 是误触“@我”筛选后的中间页，不作为已读证据。

## 服务端与桌面缓存对照

完整桌面同步周期后，用 D1 既有授权会话只读核对：

| 位置 | 当前结果 |
| --- | --- |
| 服务端 bootstrap | HTTP 200；会话 `lastMessageSequence=18`、`lastReadSequence=17`、`unreadCount=1` |
| 服务端消息历史 | HTTP 200；18 条，序号 18 即本轮消息 |
| test01 事件流 | `message.created`，事件序号 2361，目标消息序号 18 |
| test01 真机 SQLite | 18 条，目标消息 1 条；打开前未读 1，打开后服务端未读 0 |
| test03 发送端 | 收到 test01 的 `conversation.read`，recipient-read=18，applied/acked=2364 |
| 当前桌面 SQLite | **仅 15 条**，`last_message_sequence=15`，目标消息 0 条 |
| 桌面事件表 | `collaboration_event_cursors=0`、`collaboration_event_inbox=0` |

服务端请求编号：bootstrap `5a5b4dbe-5a66-4035-8891-150d2c14b368`；同步 `48afec17-a2f7-4e0b-a37f-8560da2ca6ef`；消息历史 `ed9de42c-f459-461e-a051-6091fb50c5c0`；真机打开后的已读同步 `c3143fee-b3d3-4913-ab18-1c06cfa7e529`。

桌面 `latest.log` 在 03:22:23 仍持续写入。最近最多 5000 行的脱敏计数为：connecting 323、retry-wait 324、transport-error 324，connected/event-received/ACK/history-reconcile 均为 0；目标事件 ID、消息 ID 也均未出现。该证据把问题进一步指向桌面事件传输未建立或一直重试，但仍不能只凭关键词计数断言唯一根因。即使 UI 没有刷新，桌面持久缓存也确实缺 16、17、18，因此不是单纯的页面重绘问题。

结构化白名单证据见 [result.json](../test/evidence/im-desktop-inbound-740/result.json)，不包含密码、Token、设备 ID、Cookie、指纹或非 AI-UAT 消息正文。

## 交给桌面端 AI 的提示词

> 继续排查当前正在运行的 Windows v1.0.91（test01）IM 入站同步 P1。不要重启客户端、重登、清库、修改 SQLite 或用打开会话时临时 GET 历史掩盖问题。会话 `2a2ea21f-2ad6-49b3-b3da-407d1e7e4136` 是 direct。本轮 test03 移动端发送 `AI-UAT-20260905-032000-M3-D1-DIRECT`；服务端消息 ID `5815436e-bc6f-40d4-8111-8528169040ff`、clientMessageId `fa46d7c1-6525-4600-9ede-013eb695ea9b`、会话序号 18。test01 服务端事件是 `message.created`，事件 ID `0d0744df-662a-44bd-8187-006115045dc6`、事件序号 2361。服务端 bootstrap/历史均 200，接收前 lastMessageSequence=18、lastReadSequence=17、unreadCount=1、messageCount=18；test01 真机在数秒内收到且 SQLite applied/acked=2361、目标消息唯一、Outbox=0。真机真正打开后，服务端 lastReadSequence=18、unreadCount=0，生成 ReaderId=test01 的 `conversation.read` 事件 ID `8692d9eb-6c9e-4807-918e-f102c1bee6f0`、序号 2363；test03 移动端自然显示已读并落地 recipient-read=18。当前桌面进程 PID 139028 正常响应，但 `collaboration-cache.sqlite3` 仍只有序号 1–15，sync_state=15，目标消息与已读事件均未应用，事件 cursor/inbox 均为空。当前 latest.log 持续写入，最近样本 connecting 323、retry-wait/transport-error 324，connected/event-received/ACK/history-reconcile 为 0。请从实际 v1.0.91 运行代码逐段检查：事件长轮询/网关连接建立、认证头与 device/account scope、重试退避、cursor 初始化、事件反序列化、SQLite 事务、事务成功后的 cursor 更新与 ACK、会话历史缺口 reconcile、前端 store invalidation。必须接收移动端 test03 发给 test01 的事件，也必须处理 ReaderId 为当前账号的 conversation.read；按 server message ID/clientMessageId 幂等合并。不要在 ACK 前前移 cursor，不要以 senderId=currentUserId 过滤，不要把打开会话 GET 50 条当修复。增加真实回归：D1 桌面 test01 保持在线，M3 test03 发序号 19；无需重开会话，桌面列表预览、未读、当前聊天和 SQLite 都出现一次；test01 任一端阅读后，另一端未读清零并显示已读，杀进程重启后不丢不重。输出脱敏的连接建立、事件接收、事务提交、cursor、ACK、UI 发布时间和请求编号。

## 当前移动端处理决定

不修改移动端同步逻辑。当前移动发送、服务端持久化、对方移动接收、事件落库、游标和 ACK 都有一致证据；在移动端增加重复轮询或特殊补丁不能修复桌面事件传输，只会引入重复、额外耗电和协议分叉。等待桌面端修复后再执行序号 19 的端到端回归。
