# 733 当前包双向单聊与桌面入站缺口复验

时间：2026-09-05 02:08–02:11（Asia/Shanghai）。移动端双向链路通过；当前运行的 Windows v1.0.91 入站同步仍不通过。

## 实际参与端

- M1：realme 真机，Test Terminal 01 / test01。
- M3：Android 16 模拟器，Test Terminal 03 / test03。
- D1：用户当前运行中的 Windows 客户端进程 139028，启动于 2026-09-04 23:52:54，既有会话 test01。
- 会话 `2a2ea21f-2ad6-49b3-b3da-407d1e7e4136`；服务端与两个移动端均确认类型为 `direct`，没有以群聊接口或群成员语义替代。

## 真实消息结果

1. M1 输入值经 UI 树逐字核对后发送 `AI-UAT-20260905-021500-M1-M3-DIRECT`。M3 可见 UI 在发送操作后约 3.8 秒发现消息；服务端分配消息序号 16。
2. M3 同样经 UI 输入并发送 `AI-UAT-20260905-021600-M3-M1-DIRECT`。M1 可见 UI 在发送操作后约 3.0 秒发现消息；服务端分配序号 17。
3. 两端 SQLite 中 16/17 的服务端 ID、`clientMessageId`、发送人、顺序完全一致，各只有一条，状态均为 sent，Outbox 均为空。
4. 两端该会话都为 `lastMessageSequence=17`、`lastReadSequence=17`、`unreadCount=0`、`localMessageCount=17`。M1 保存对方已读 16；M3 保存对方已读 17，与双方 UI 双勾一致。
5. 双端强制停止、冷启动后均自动恢复原账号；17 条记录、已读游标、0 未读、0 Outbox 全部保持。M3 既有 614 条群聊仍为 group/614/已读614，未被这两条单聊污染。
6. 两端当前进程范围 FATAL、Unhandled Exception、RenderFlex overflow 均为 0。

## 服务端与桌面端对照

- D1 现有授权会话只读 GET 成功：bootstrap HTTP 200；会话摘要为 direct、`lastMessageSequence=17`、`lastReadSequence=17`、`messageCount=17`。
- 同一事件流明确包含：2332 `message.created` / 消息16，2334 `conversation.read` / test03读到16，2336 `message.created` / 消息17，2338 `conversation.read` / test01读到17。
- 但当前 Windows 进程使用的 `collaboration-cache.sqlite3` 在02:11仍只有序号1–15，`last_message_sequence=15`，没有16/17；数据库完整性为ok。
- 这证明移动发送、服务端持久化、移动接收及已读均正常，桌面端缺的是入站事件/历史对账后的本地发布。没有重启、重登、清库或手工插入桌面缓存来掩盖现场。
- 与730相比，桌面缓存后来通过某条路径补齐了旧的8/10/13，但实时路径仍没有让本轮16/17进入当前缓存，说明“偶尔历史补齐”不能替代持续同步修复。

## 给桌面端 AI 的增量提示词

> 继续检查当前运行的 Windows v1.0.91（test01）IM 入站同步。不要重启客户端、重登、清库或修改数据库。会话 `2a2ea21f-2ad6-49b3-b3da-407d1e7e4136` 是 direct。服务端 bootstrap/会话消息已确认 lastMessageSequence=17、lastReadSequence=17、messageCount=17；事件流包含2332 message.created（会话序号16，test01发送）、2334 conversation.read（test03读16）、2336 message.created（会话序号17，test03发送）、2338 conversation.read（test01读17）。两个移动端 SQLite 都有相同服务端消息 ID/clientMessageId/sequence，且重启后仍为17/已读17/未读0。但桌面 `collaboration-cache.sqlite3` 只有1–15，sync_state也是15。旧缺失8/10/13后来能被历史路径补齐，说明服务器有数据，当前实时/定时对账发布链仍会停住。请沿当前进程实际使用的事件长轮询、cursor/ACK、会话历史 reconcile、SQLite事务提交和前端 store invalidation 逐段加脱敏诊断，确认在哪一段停止。必须处理自己账号从移动端发送的 message.created，也必须处理对方消息和 ReaderId 为当前账号的 conversation.read；以 server message ID/clientMessageId 幂等合并。增加“桌面D1+移动M1同账号、对方test03”真实链路测试：16/17无须重开会话就出现，未读和双向已读同步，杀进程重启不重复。不要只在打开会话时 GET 50 条作为临时补丁，不要过滤 senderId=currentUserId，也不要在 ACK 前更新游标。修复后请提供事件接收、事务落库、ACK、UI发布时间与请求ID的脱敏证据。

## 证据

- `test/evidence/im-direct-733/01-phone-bidirectional.png`：真机同一单聊中的16/17及双方头像、双勾。
- `test/evidence/im-direct-733/02-m3-bidirectional.png`：M3同一单聊中的16/17、真实在线状态和双勾。
- 移动端状态由 `scripts/inspect-device-im-outbox.py` 使用账号隔离 SQLite、DB+WAL 一致性快照只读取得；未读取正文密文。
- 桌面缓存由 `scripts/inspect-desktop-im-cache.py` 使用只读事务取得；服务端由 `scripts/inspect-desktop-im-uat.ps1` 使用现有测试会话仅GET核对。

## 边界

- 本轮是两个不同员工账号的单聊，不代表群聊、离线积压、媒体或桌面端已通过。
- 延迟是 ADB 发出点击后到UI树首次检出的大致端到端值，不是严格网络基准。
- 没有改移动端生产代码或重打APK；当前已安装包已完成这条链路。全量自动化仍为本轮此前验证的1361/1361。
