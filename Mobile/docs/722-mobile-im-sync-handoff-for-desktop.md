# 给桌面端排查 AI：移动端实际 IM 同步实现

核对日期：2026-09-05。以下来自当前 Mobile 源码，不代表 Windows v1.0.91 的 Push Gateway 契约。请用于对照排查，不要未经协议确认把桌面直接改成移动端的传输方式。

## 1. 主通道是 HTTP 长轮询，不是已经验收的新 Push Gateway

当前登录响应提供 imApiUrl，客户端归一化 origin，避免重复拼接 `/api/im`。请求携带现有会话 Authorization、X-Device-Id、X-Terminal-Device-Id 和 X-Terminal-Account-Id；诊断不得记录实际凭据。

```text
GET /api/im/sync/events?afterSequence=<本设备已应用游标>&waitSeconds=25&take=500
POST /api/im/sync/ack
{"eventSequence": <已事务提交的最大事件序号>}
```

25 秒是服务端长轮询等待上限，不是客户端固定睡眠 25 秒。有事件时请求可以提前返回；收满 500 条，下一次 waitSeconds=0 立即继续追赶。正常请求 receiveTimeout=30 秒、connectTimeout=15 秒。网络异常延迟 3 秒再试，不直接登出；401/明确 session_replaced 交会话控制器处理。

源码：`lib/core/network/collaboration_client.dart:27`、`lib/features/collaboration/application/im_sync_coordinator.dart:174`、`lib/features/collaboration/data/collaboration_repositories.dart:5291`。

## 2. 本地游标与 ACK 分开，事务成功后才确认

本地状态按 accountId 与设备安装标识隔离。syncDeviceId 优先 installationId，否则 deviceId；网络请求头使用服务端会话的 deviceId，不要盲目把两者混为一个字段。设备状态键后缀经转换，不输出原标识。

pullEvents 的实际顺序：

1. 读取 applied 与 acked；若 applied > acked，先补 ACK 已经提交的那部分。
2. 请求事件；检查响应仍属于相同会话，旧账号/旧令牌的迟到响应不能写入新会话。
3. 非空事件批次拉取 bootstrap。
4. applySyncBatch 在一个 SQLite 事务中更新 bootstrap、事件 inbox、消息/已读投影和 applied 游标。
5. 723 修正：事务成功且仍是当前会话时，立即通知受影响的会话消息、列表和角标刷新，不等待 ACK 网络返回。
6. 再 POST ACK，成功后单调更新 acked；失败仍按原路径重试或处理会话失效，不回滚已提交的消息、不伪造确认成功。ACK 成功不会重复通知同一批 UI。

注：本说明最初整理时，718 包仍先等 ACK 再刷新。后续专项真实本机 HTTP + SQLite 测试确认，这会在 ACK 阻塞时延迟显示已提交内容，因此在 723 中拆开 UI 发布和 ACK。此项修复不能解释或修复 720 中桌面本地根本缺记录的问题。

提交后 ACK 前崩溃，重启允许重放/补确认。不会只因为服务器返回 latestSequence 就把本地游标跳到未处理事件之后。

源码：`im_local_store.dart:1767`、`:1809`，同目录 `collaboration_repositories.dart:5291`。

## 3. 不过滤当前账号自己发送的消息

`message.created` 一律交 `_upsertMessage`，没有 `senderId == currentAccount` 就 return 的过滤。同账号另一设备发出的消息也要落到本机。

服务端消息以 accountId + messageId 定位；相同 accountId + senderId + clientMessageId 的临时/重复身份先归并，再写服务端记录，避免发送响应与同步事件产生两份气泡。未读从真实会话投影/已读状态维护，不简单按“收到事件就加一”。

源码：`im_local_store.dart:1871`、`:2051`。

## 4. 还有独立补偿，因此“能收到”不等于已证明推送通道正常

- 事件积压追平后，检查 `/api/im/conversations` 的序号和摘要；同会话 index 请求合并，通常 25 秒节流。比较序号，不只看未读总数。
- 检查会话宣布的消息范围与本地历史覆盖，执行 `repairAnnouncedMessageGaps` 补正文缺口；不会靠把最大序号改大冒充历史完整。
- 当前可见聊天页面还有 12 秒间隔的最近 50 条消息对账。`reconcileLatestMessages` 仅在快照有差异时合并并刷新，不每次都重建未变化的消息列表。
- 返回前台、网络恢复会唤醒同步并请求会话对账，取消旧长轮询；停止/重启有 generation 与 CancelToken 防止旧循环复活。

所以，本轮确实验证手机收到桌面消息，但未逐条记录它究竟经事件通道还是 12 秒补偿到达，不能宣称每条均是即时 Push Gateway 推送。

源码：`collaboration_repositories.dart:3152`、`:3617`；`im_sync_coordinator.dart:77`、`:230`；`lib/features/messages/presentation/chat_page.dart:290`。

## 5. 自己的已读与对方回执是两种状态

当前可见且处于前台的聊天页面，在布局后检测消息与视口相交范围，仅提交真正可见的最大消息序号：

```text
POST /api/im/conversations/<conversationId>/read
{"sequence": <visibleSequence>}
```

`conversation.read` 的 ReaderId 是当前账号时也处理：单调推进本账号已读、未读/@我相关投影。ReaderId 是其他成员时，推进 recipient.read，而不是把本人的阅读误认为对方已读。两类状态均落 SQLite。

源码：`chat_page.dart:722`、`collaboration_repositories.dart:5372`、`im_local_store.dart:1875`。

## 6. 实测对照与桌面检查建议

test01 手机与桌面同账号；模拟器 test03。原手机消息序号 8、clientMessageId `c1bee507-132e-4e5f-addc-98f5c7581cf5` 在服务端和手机均存在，桌面缓存缺 8、10，详见 720 报告。

本轮移动验证：test03 打开前未读 5/read 7；真正显示消息后未读 0/read 12，test01 手机持久保存 recipient.read=12。test03 再实际 UI 发送一条测试消息（序号 13），手机真实显示并已读，双方 ID/clientMessageId 一致，test03 持久回执到 13；双方 Outbox=0。这些不代替 Windows 接收验收。

请桌面侧逐层核对：事件是否生成 → 当前桌面设备是否被投递 → 连接是否真的收到 → 是否过滤同账号 → 事务是否落库 → 是否先 ACK 后处理 → 缺口是否触发补偿 → UI 是否读取新投影。即使主通道故障，也需要确认为什么本机已经出现 7→9、9→11 的缺口却没有补齐。

现有移动链路不是完美性能基准：非空事件批次还会抓取 bootstrap，当前补偿有额外请求，后续仍需性能评估；不要照搬为每条消息全量刷新通讯录或全量重绘页面。
