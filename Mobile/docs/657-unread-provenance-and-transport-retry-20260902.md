# 未读来源定位与断网重连待发恢复

时间：2026-09-02，Asia/Shanghai。结论：**部分通过，仍有 P1 服务端读状态问题**。本轮不是全部 IM/OA 验收通过。

## P1：服务端摘要推进未打开会话的已读游标

沿用两人测试群 `AI-UAT-20260902-202100-M1-M3-GROUP`，群 ID `bd15cbb6-ab8e-4cf2-9d62-fdb6f37ce90a`。M1=test01，M3 独立模拟器=test03。没有操作 M2。前轮现象和旧库升级见 [656](656-outbox-clock-migration-and-network-recovery-20260902.md)。

### 取证方法

新增可选 `IM_READ_DIAGNOSTICS=true`，只在非 release 可启用。仅记录来源、HTTP 状态、消息/已读序号、未读数和是否本人读事件；会话标识为 SHA256 前 12 位，不记录真实身份、正文、Token、请求头、附件地址。相同摘要去重，缓存上限 512。默认关闭；不新增网络请求、不修改同步内容、不改读状态。

临时诊断包为正常 `lib/main.dart` 入口，仅安装 M3；SHA256 `2AFA256749D8EDCEDD3EAE06366CCE955AC8CB67E3055597CAAAB7494A6D698A`。同进程日志来源覆盖 `/api/im/bootstrap`、`/api/im/conversations`、收到的 conversation.read，以及主动 `/read` 和 active 请求。两项测试验证白名单输出/关闭无输出，正文与身份不进入日志。

### 真实复现

1. M3 打开原群，原记录读到 7；关闭 Wi-Fi/数据，确认默认网络 none。
2. 真实 UI 输入并发送 `AI-UAT-20260902-210100-READ-OUTBOX`，呈现“发送中”，随后 force-stop。
3. M1 真实 UI 发出 `AI-UAT-20260902-210100-READ-INCOMING`。M3 断网冷启动停留首页，不打开会话。
4. 21:00:48.522 恢复 M3 网络，队列自动发送；不点击刷新或重试。进程 PID 19087 的整个复现窗口没有 visible_read_request、active_enter_request。
5. 下列远端响应先后出现，本地最终 read=9/unread=0；不是界面单独把数字改成 0。

| 手机日志时间 UTC | 来源 | last | read | unread |
| --- | --- | --- | --- | --- |
| 13:00:53.286 | GET conversations，200 | 8 | 7 | 1 |
| 13:01:02.134 | GET bootstrap，200 | 9 | 9 | 0 |
| 13:01:28.073 | GET conversations，200 | 9 | 9 | 0 |

13:01:02.135 同批读事件在 M3 的事件序号 195、消息序号 9，`isSelf=false`。因此未读变化的已证实来源是**服务端自身返回的会话投影**，并非 M3 把另一成员读事件当成本人读，也不是页面提前主动 POST `/read`。服务端内部究竟是发送隐式已读、active 会话残留，还是其他处理推进游标，尚需服务端链路进一步排查，不能宣称已确定具体服务端代码行或已经修复。

M1 同账号的 D1 只读核对 200，目标群 9 条；最后一条读事件为 test01 读 9（D1 事件序号 196，各接收端事件序号不同，不按其数值做跨账号对齐）。M1 当时在群页实际可见，正常；没有看到 test03 读到 9 的对应事件。D1 检查不能代替桌面窗口操作。

| 消息 | clientMessageId | 服务端 ID | 服务端 UTC |
| --- | --- | --- | --- |
| 8：新来、未打开 | 16e25a70-6113-47d2-ac43-5bc0b0a4cad1 | 934b0b8f-e1ce-4641-9302-38d2554b6e2e | 13:00:32.138009 |
| 9：M3 排队补发 | f430dbb7-a56b-42f4-8a4b-71475eb54ef0 | d62fc735-fcbe-4252-855c-94610cc4b44c | 13:00:59.487918 |

证据：[脱敏来源日志](../test/evidence/im-read-provenance-20260902/11-read-provenance.log)、[断网队列](../test/evidence/im-read-provenance-20260902/09-m3-offline.json)、[恢复后 SQLite](../test/evidence/im-read-provenance-20260902/10-m3-recovered.json)、[仍停首页](../test/evidence/im-read-provenance-20260902/11-m3-home-unopened.png)、[D1 GET 核对](../test/evidence/im-read-provenance-20260902/12-desktop-corroboration.json)。响应未提供请求编号。未通过忽略同账号 read 或拒绝服务端更高读游标来掩盖问题，跨端已读仍按原协议处理。

## 客户端改进：只提前恢复传输失败的待发消息

上轮断网后已有指数退避造成联网仍等约 61 秒。现将无 HTTP 响应的 Dio 连接/连接超时/发送超时/接收超时记录为传输失败，标记与队列失败一起事务落库；使用现有按账号隔离的 sync_state，不改 schema13、不迁移业务数据。不能通过错误文案猜测旧记录原因。

- 网络接口变化或冷启动成功连接后，消耗该标记，将目标下一次重试时间提前到当前时间；不直接发送假成功，不改 clientMessageId、消息正文、附件、重试次数或会话 FIFO。
- 同一标记只消耗一次，重复网络通知不重复触发。新失败仍按原退避再标记。
- HTTP 429/408/5xx、认证错误、本地文件错误、取消及未知类型，不因该唤醒跳过退避；后续 HTTP 错误会清除旧传输标记。
- 正常发送确认清除对应标记；账号间隔离。旧包没有分类的待发继续原退避，不能批量重试所有上传 500。
- 三项新增测试验证冷重开持久化/FIFO/账号隔离/一次性消费、后续 503 清除旧标记、错误类型白名单。扩展原网络恢复测试，用真实本地 HTTP 服务证明接口恢复打断长轮询后，原客户端 ID 自动发送一次、正文持久化、未读保留、重复接口通知不重复发送。

## 检查与验收边界

本轮先完成诊断版本 **413/413**；加入重连恢复后的全量 **416/416**，分析 0 问题。首次新增诊断测试漏传必填 nullable 字段导致编译失败，补齐后重跑通过；首次 analyze 的 null-aware 风格提示已修正，不删除断言。

日志：[全量最终测试](../test/evidence/im-read-provenance-20260902/full-tests-final.log)、[静态分析](../test/evidence/im-read-provenance-20260902/analyze-final.log)、[重连定向回归](../test/evidence/im-read-provenance-20260902/reconnect-tests.log)。未更新 golden、未清理原工作区。

### 最终正常包与真实重连复验

正常 Profile 1.0.1+2、`lib/main.dart`、arm64+x64，不带诊断开关。构建时间 21:05:01，82,676,035 字节；SHA256 `E8D0596F740E159674E708FB2396082464596A905E770371AC702F71874EF33C`。M1/M3 覆盖安装 Success，设备 base.apk 均核对为该哈希；冷启动 1458 ms / 8286 ms。诊断输出已关闭，两端当前进程最近 2000 行均没有 MOBILE_IM_READ。模拟器启动数值仍非性能通过结论。[构建日志](../test/evidence/im-read-provenance-20260902/build-final.log)。

M3 再次真实断网（默认网络 none），通过 UI 连续发送两条 `AI-UAT-20260902-210600-RECONNECT-FIFO-01/02`，随后 force-stop、离线冷启动停在首页。第一条 attempts=3、next_retry_at=`13:07:48.266848Z`、retry_on_connection_change=1；第二条 attempts=0，仍在同会话后排。两条在重启后保留原 ID 和正文。

21:07:24.670 开启网络，未开会话、未点刷新/重试；21:07:34.573 的检查已 Outbox 空、两条确认。因此约 10 秒为已观察到完成的上界，且早于原 21:07:48 的调度时间；不把设备/服务端时间差当精确端到端延迟。单次受控结果也不代替压力测试或 P95。

| seq | clientMessageId | 服务端 ID | 服务端 UTC |
| --- | --- | --- | --- |
| 10，FIFO-01 | b4432b00-e62a-4d25-a81a-45487294a32d | 8c905368-96de-48a2-a12a-78708058a138 | 13:07:30.378417 |
| 11，FIFO-02 | 37f01073-a3fe-4139-8f3a-930ae916b2fd | 6091711f-6378-4243-86cc-a0510485d511 | 13:07:30.621124 |

- M1 停留首页自动收到两条，目标群 last=11/read=9/unread=2，首页底部消息角标 2；没有为了证明接收而手动刷新或进入会话。
- M1/M3 共 11 条的服务端 ID、clientMessageId、senderId、序号、sent 状态逐项完全一致，唯一服务端 ID 各 11 个。发送端随后打开群，两条显示“已发送”，没有把未读的 M1 伪造为已读；连续两条只在第一条显示头像，输入区与文件/聊天分界正常。
- 本次发送端没有新来的未读消息，因此不用于关闭前述 P1。前述有未读的诊断复现仍不通过。
- M1 原有图片 HTTP 500（clientMessageId `901c6844-5dde-48f5-87c4-1768742d0e18`）及其后原待发文本 `7fc6e1e1-c95f-41f8-bbd6-10020739349b` 保留，两者传输恢复标记为 0；没有删除、重建或越过同会话 FIFO。
- 结束：M1 Wi-Fi=0、数据=1、默认网络 107，原热点未动；M3 Wi-Fi=1、数据=1、默认网络 112，网络已恢复。M2 未动。两端当前进程最近 2000 行没有命中 FATAL/Unhandled Exception/RenderFlex overflow/EXCEPTION CAUGHT；仅是有界检查。

证据：[离线排队截图](../test/evidence/im-read-provenance-20260902/19-two-queued.png)、[重启后排队及未来到期时间](../test/evidence/im-read-provenance-20260902/20-final-offline-restarted.json)、[自动提前发出](../test/evidence/im-read-provenance-20260902/21-final-recovered.json)、[M1 自动接收持久化](../test/evidence/im-read-provenance-20260902/22-m1-auto-received.json)、[M1 首页未读 2](../test/evidence/im-read-provenance-20260902/22-m1-auto-received.png)、[发送完成与连续头像](../test/evidence/im-read-provenance-20260902/24-final-sent-visible.png)。

保留未完成：服务端未读 P1、群 message.created 缺项、媒体/附件 500、桌面窗口与 D2、精准 ACK 前崩溃、系统推送、12 小时到期/改密完整矩阵、高级 OA 流程及压力性能指标。继续原目标。
