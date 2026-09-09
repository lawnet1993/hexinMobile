# 767 · 三模拟器并发、离线追平与通知首启追加复验

日期：2026-09-06，Asia/Shanghai。

结论：**移动端三模拟器在线并发、离线补偿、账号隔离和通知首启询问通过；Windows 后台会话同步、真机锁屏通知和厂商推送仍未通过。** 本轮全部消息经真实 Flutter 输入框发送，使用 `AI-UAT-` 前缀；没有直接写数据库或调用发送 API。

## 当前安装包

- Profile APK：111,236,918 B。
- SHA-256：`AE698B1090BEC2BF0320916701361289F67B2BD1F2C21CA50D44D914E7C0FBFE`。
- 已逐台核对 `base.apk`：`emulator-5554`、`emulator-5556`、`emulator-5558`、realme RMX3366 真机均与上述摘要一致。
- `flutter test --concurrency=1`：1,405/1,405 通过。
- `flutter analyze`：0 error、0 warning；保留 7 条既有花括号风格 info。

## 通知权限首启链路

- 修复前真机 `POST_NOTIFICATIONS` 为未授权，AppOps 为 ignore；锁屏发送 `AI-UAT-LOCKBG-20260906-073800-001` 后等待约 20 秒，本地游标仍为 3897，收到 0/1。
- 移动端 Shell 现在只在权限状态为 `notDetermined` 时主动发起一次系统授权；拒绝、已允许、平台不支持时均不重复询问，也不阻塞 IM/OA 启动。
- Android 16 模拟器真实出现系统通知授权框；点击允许后权限为 granted，强停重启没有再次弹出，test03 登录态保留。
- 同一行为在 test02 模拟器再次通过。真机已安装相同 APK，但当前仍锁屏且权限未授予，不能用 ADB 代替用户点击。

证据：

- [首次系统授权框](../test/evidence/lockscreen-background-20260906/05-permission-prompt.png)
- [允许后的工作台](../test/evidence/lockscreen-background-20260906/06-after-permission-allow.png)
- [重启后不重复询问](../test/evidence/lockscreen-background-20260906/07-relaunch-no-reprompt.png)
- [test04 独立设备工作台](../test/evidence/lockscreen-background-20260906/09-m3-test04-home.png)
- [权限与真机安装摘要](../test/evidence/lockscreen-background-20260906/permission-result.json)

## 三模拟器在线并发

拓扑：M1=`emulator-5554/test02`，M2=`emulator-5556/test03`，M3=`emulator-5558/test04`，Windows 当前账号=test01。

- M1、M2 分别向 test01 单聊发送 20 条；M3 向 test03/test04 专用群发送 20 条，共 60/60 条 UI 点击成功，三路末条可见且输入框为空。
- test02→test01 服务端 20/20，消息 ID 与 `clientMessageId` 各 20 个唯一值；点击到服务端落库平均 1,304.0 ms，P95 1,352.4 ms，最大 1,402.5 ms。
- test03→test01 服务端 20/20 且唯一；平均 2,168.9 ms，P95 4,730.2 ms，最大 8,296.6 ms。峰值偏高，暂不判为丢失，但应继续在稳定宿主负载下复测。
- 三台当前账号 SQLite 均 `quick_check=ok`、Outbox=0、消息 ID/客户端消息 ID 无重复，游标 applied=acked。
- 移动端含事件批次的完整同步阶段：M1 P95 964 ms、M2 P95 1,868 ms、M3 P95 1,414 ms；单进程 PSS 分别约 210.2、189.1、158.0 MiB。
- test04 AVD 中同时保留 test03 与 test04 两个账号域的数据，同一群分别为 644/664 条；按 `account_id` 核算后各账号内部无重复，证明账号隔离不是重复消息。

证据：

- [M1 发送 journal](../test/evidence/im-multivm-20260906-080452/m1.json)
- [M2 发送 journal](../test/evidence/im-multivm-20260906-080452/m2.json)
- [M3 发送 journal](../test/evidence/im-multivm-20260906-080452/m3.json)
- [并发结果摘要](../test/evidence/im-multivm-20260906-080452/result.json)

## 离线补偿

- test03 同时关闭 Wi-Fi/移动数据并强停 App，确认默认网络为 none。
- test04 在专用群真实发送 30 条；发送端最终序号 694、Outbox=0。
- test03 恢复网络并冷启动后 7,255.3 ms 从序号 664 追到 694。
- 接收端 694 条，缺失 0、重复 ID 0、重复 `clientMessageId` 0、序号断点 0、Outbox=0、applied=acked=4099、SQLite 完整性正常。
- 测试结束已恢复 test03 原网络状态。

证据：

- [离线期间发送 journal](../test/evidence/im-offline-multivm-20260906-081014/m3-sender.json)
- [追平结果摘要](../test/evidence/im-offline-multivm-20260906-081014/result.json)

## Windows 桌面端未通过项

- test03→test01 会话当时正显示在桌面：服务端末序号 261，桌面缓存窗口也到 261，200 条窗口内无重复。
- test02→test01 会话未打开：服务端末序号已到 252，但桌面缓存和 `im_conversation_sync_state` 均仍停在 10。
- 桌面 `collaboration_event_cursors` 与 `collaboration_event_inbox` 对 test01 均为 0 行。这说明桌面当前可通过打开会话补历史，但没有证据证明全局后台事件流在运行；未打开会话不会及时更新。
- 本轮电脑控制插件没有暴露可调用的运行入口，因此缺少桌面窗口截图；SQLite 使用当前运行客户端的数据库、只读事务和 WAL 一致性快照，完整性为 ok。

交给 Windows 端 AI 的复现提示词：

```text
请只修复 Windows 桌面端，不修改移动端或服务端。当前桌面 test01 已登录。复现证据：
1. 移动 test02 向 test01 会话 a164a0c0-4cad-44b0-9ece-e095371b2f91 真实发送 20 条，服务端 lastMessageSequence=252，20 个消息 ID 和 clientMessageId 均唯一；Windows collaboration-cache.sqlite3 仍只有序号 1..10，im_conversation_sync_state.last_message_sequence=10。
2. 同时移动 test03 向 test01 会话 2a2ea21f-2ad6-49b3-b3da-407d1e7e4136 发送 20 条；该会话当时处于桌面当前打开状态，Windows 缓存已到 261。
3. Windows collaboration_event_cursors 和 collaboration_event_inbox 对当前账号均为 0 行。

请检查 v1.0.94 当前运行版本实际下发的 Gateway 地址、gRPC/事件连接建立、全局事件循环生命周期、前后台恢复、ACK/游标持久化，以及是否错误地只对当前打开会话拉历史。要求未打开的单聊/群聊也实时更新预览和未读；事件先事务落库、再推进游标、最后 ACK；重复事件幂等；不要以发送者或当前会话过滤事件。新增自动化覆盖“当前打开会话收到、另一个未打开会话同时收到、重启后追平、事件落库后 ACK 前崩溃”。输出连接端点、连接状态、事件序号和请求编号，但不得输出 Token、Cookie、设备 ID、消息正文或附件地址。
```

## 仍未通过

1. realme 真机解锁后手动允许通知，再锁屏发送单聊、群聊、@我和 OA 通知；要求系统通知、点击定位、游标追平、无重复都有证据。
2. 厂商推送 Provider/Token 通道仍未接入，系统通知权限通过不等于进程被杀后的离线推送通过。
3. Windows 未打开会话的后台同步需修复并补 UI 截图、游标和重启恢复证据。
4. iOS 真机通知、后台唤醒、附件和离线补偿未执行。
5. OA `return` 仍缺服务端 `allowedActions=return` 的真实候选；不能用无权限流程代替。
