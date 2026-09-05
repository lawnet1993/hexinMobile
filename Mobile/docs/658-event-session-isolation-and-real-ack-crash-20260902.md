# 同步响应归属与真实 ACK 前杀进程验收

时间：2026-09-02 21:09–21:21，Asia/Shanghai。结论：**本轮断点场景通过，整体移动端仍部分通过**。

## 修复：旧会话的事件响应不得继续提交

检查同步链路时发现，`pullEvents` 开始时捕获旧 session，但随后 `_fetchBootstrap` 会重新读取当前 session；切换账号或同账号重新登录期间到达的旧响应仍可能落库、推进旧游标并发送 ACK。其他已有接口的隔离措施不能证明该路径安全。

新增 `im_event_session_isolation_test.dart`：在真实本地 HTTP 服务分别于 events/后续 bootstrap 响应阶段切换账号或更换同账号会话，四项在修复前均失败（应丢弃却返回 changed=true）。修复后四项通过。

修复范围仅 IM 事件拉取路径：Dio 和后续 bootstrap 均绑定最初 session；待确认 ACK 处理后、事件响应后、bootstrap 响应后和事务完成后的 ACK 前再次校验会话。过期结果不再进入后续落库/ACK。已在切换前成功提交的旧账号数据仍归属原账号，不删除；不同账号不共享缓存。并不声称已穷尽其他所有仓库方法的会话竞争。

[修复前](../test/evidence/im-ack-crash-20260902/session-before.log)、[修复后](../test/evidence/im-ack-crash-20260902/session-after.log)。

## 本地 ACK 恢复回归

新增 `im_ack_recovery_test.dart` 的三个测试，使用真实本地 HTTP、AES-GCM SQLite 缓存和关闭后重新打开的数据库：

1. 事件与消息事务提交后、ACK 前抛出模拟崩溃：已落库序号保持，确认序号不动；重开后先补 ACK 再拉取。
2. ACK 返回 500：仍保留已提交内容，重开后补 ACK。模拟服务故意再次返回同一事件，事件和消息各只一条。
3. 事务已提交、ACK 前切换账号：不向旧会话继续确认，不写入新账号；恢复原账号后可补 ACK，另一设备游标仍独立。

此处模拟异常与强制重复事件是本地测试，下节才是真实设备杀进程；两者不混淆。

## 真实测试准备与中途会话失效

- M1：真机 `dd00d66d` / test01；M3：独立 `emulator-5556` / test03，系统 UTC。M2 没有操作。
- D1：现有 Windows test01 会话只用于 GET 核对；没有可用桌面控制工具，不能视为本轮桌面 UI 实测。
- 21:14:08 M1 的 `managed_commands` 返回 401，日志 action=terminated，UI 提示登录已失效/到期。[日志](../test/evidence/im-ack-crash-20260902/05-m1-session-auth.log)、[UI](../test/evidence/im-ack-crash-20260902/04-m1-direct.xml)。使用登录页已安全保存的凭据直接恢复 test01，未打印或重新存储密码。M3 保持 test03，D1 随后核对仍 200。
- 该 401 来自当前安装的上一正常包，不是本轮断点造成；但**不能仅凭提示确定为正常 12 小时到期**。命令鉴权与会话有效期原因继续待查，不通过忽略所有 401 来绕过。

## 精准落库后 / ACK 前强制杀进程

测试入口 `test_driver/im_ack_checkpoint.dart` 不由正常 main 引入。它只允许指定环境的已有 test03 会话和明确的 AI-UAT 消息标识；拦在生产仓库真实事务成功之后、真实 ACK 之前。只暂停指定 message.created，记录数字游标，等待外部结束进程；不伪造事件、不改游标、不注入消息。

断点包仅装 M3，正常 UI、真实服务、Profile x64，SHA256 `0946C9D6C196EC62312E8CD21D407BF24B5CFDFC86E8D3985FFEA1E795AC8BC6`。开关标识 `AI-UAT-20260902-211500-ACK-CRASH`，没有密码或 Token。

真实单聊 ID `2a2ea21f-2ad6-49b3-b3da-407d1e7e4136`，对应 test01/test03；不是沿用群聊标题当单聊。

1. M3 初始已有 seq1–3，read=3/unread=0，已落库游标=195、已确认=195。
2. M1 在真实聊天输入框输入并发送一次 `AI-UAT-20260902-211500-ACK-CRASH`，未通过 API 创建。
3. M3 停留首页。21:16:40.588 命中断点，`eventSequence=200`、`messageSequence=4`、`appliedCursor=200`、`ackedCursor=195`、copies=1。
4. 先用只读 SQLite+WAL 快照确认上述状态，再于 21:16:56.688 `am force-stop`；确认 PID 22649 已不存在。不是仅模拟抛错、返回后台或关闭页面。
5. 进程停止后再次只读快照，仍 applied=200、acked=195、消息 4 条、read=3/unread=1，证明事务数据跨进程死亡保留。
6. 覆盖安装**正常 main、无断点**的最终包并冷启动，不打开单聊。ACK 自动补到 200，消息仍 4 条、原 ID 不变、read=3/unread=1。没有清数据、改本地游标或重发消息。
7. 随后打开单聊，真实正文可见且只一条，返回列表后未读清零；最终 M3 read=4/unread=0，事件/ACK 为 202（增加本人读事件）。M1 事件/ACK 为 201。不同账号收到的事件序号不同，不能用数值相等来判断双端一致。

| 标识 | 值 |
| --- | --- |
| 服务端消息 ID | 114d4ea8-4124-4a5d-9f8a-8994a2a79fe7 |
| clientMessageId | 4174eccd-f9e9-4aec-ba0e-f602ce084107 |
| 单聊消息序号 | 4 |
| 服务端 UTC 时间 | 2026-09-02T13:16:40.263138Z |
| M3 真实 message.created 事件 | ffa97caa-f2f1-48c3-b4a2-c2341ddcb0c8 / seq200 |

证据：[初始快照](../test/evidence/im-ack-crash-20260902/01-baseline.json)、[M1 输入框](../test/evidence/im-ack-crash-20260902/09-m1-composer.xml)、[断点日志](../test/evidence/im-ack-crash-20260902/11-checkpoint.log)、[落库未确认](../test/evidence/im-ack-crash-20260902/11-committed-not-acked.json)、[进程死亡后](../test/evidence/im-ack-crash-20260902/12-after-process-death.json)、[正常包自动恢复](../test/evidence/im-ack-crash-20260902/13-normal-recovery.json)、[未读 1 列表](../test/evidence/im-ack-crash-20260902/14-recovered-list.png)、[正文真实可见](../test/evidence/im-ack-crash-20260902/15-message-visible.png)、[阅读后列表](../test/evidence/im-ack-crash-20260902/16-after-visible-read.png)。

## 双端与服务端核对

M1/M3 最终单聊各 4 条，服务端 ID、clientMessageId、senderId、seq、sent 状态逐项一致，唯一 ID 各 4；目标消息没有重复。两端该单聊 read=4/unread=0。

D1 现有桌面会话 GET bootstrap / events / 目标单聊历史均 200，目标消息唯一，真实 read 事件的 ReaderId=test03、sequence=4。请求编号响应未提供；记录事件/消息 ID 用于追踪。D1 的事件序号 199 对应此次 message.created、201 对应 test03 阅读，不能把 M3 的 seq200 套用到 D1。

[M1 最终](../test/evidence/im-ack-crash-20260902/18-m1-final.json)、[M3 最终](../test/evidence/im-ack-crash-20260902/18-m3-final.json)、[D1 GET 核对](../test/evidence/im-ack-crash-20260902/17-desktop-readonly.json)。

**验收边界：** 真实设备证明一次单聊 message.created 的“事务提交后、ACK 前”死亡恢复及自动补 ACK；服务端重启后按 afterSequence=200 拉取，不代表服务端实际重复投递过该消息。强制重复事件/重复 ACK 的幂等性由本地测试验证。群事件、500/1000 条积压、其他崩溃窗口和系统推送不能据此判定通过。

## 最终构建与保留事项

- 全量 **423/423**、分析 0 问题；[测试](../test/evidence/im-ack-crash-20260902/full-tests.log)、[分析](../test/evidence/im-ack-crash-20260902/analyze-final.log)、[正常构建](../test/evidence/im-ack-crash-20260902/build-final.log)。最初 analyze 的初始化参数/花括号提示已修正，没有删测试或更新 golden。
- 正常 Profile 1.0.1+2，`lib/main.dart`、arm64+x64；71,207,235 字节，SHA256 `18634FA2196C8D4ACEAD465623941C716EB3FA3945994AB7F201C6CD46626104`。APK 实际检查两种 ABI 均有 libapp.so/libflutter.so。M1/M3 均覆盖安装成功、base.apk 哈希一致，断点入口已移除。正常包冷启动 M1=1050 ms、M3=6824 ms，不据此宣称整体性能达标。
- M1 旧图片 500 和同会话后排文本保留，没有清理用户数据；M3 Outbox 空。M1 热点/网络未改，M2 未改，M3 网络保持可用。
- 21:21 最终有界检查：两端进程均在运行；各自最近 2000 行无 FATAL/Unhandled/RenderFlex overflow、无断点输出和新会话失败日志。M1 默认网络 107（Wi-Fi=0/数据=1）；M3 默认网络 112（Wi-Fi=1/数据=1）。这不是无限期稳定性保证。
- 保留 P1：657 的未打开群读状态被服务端投影提前推进；本轮 managed_commands 401 原因尚未追溯；群 message.created 缺项、上传/附件 500、真实桌面窗口/D2、12 小时到期/改密完整矩阵、高级 OA 流程、系统推送及压力性能仍需继续验收。整个目标保持进行中。
