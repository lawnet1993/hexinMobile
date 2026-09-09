# 783 · IM 事件投影一致性与双模拟器实测

> 日期：2026-09-06  
> 结论：真实并发测试发现并修复“消息已经落库，但会话列表预览、最后消息序号和未读状态仍等待会话索引刷新”的问题。修复后两台模拟器在发送结束后的首个一致性快照中均达到 95/95，消息表、会话投影、已读游标和事件 ACK 一致；数据可靠性通过，端到端及时性仍因一次 5.558 秒长轮询批次判定为部分通过。

## 真实发现

沿用 `AI-UAT-MULTIVM-20260906-1100` 三成员测试群：

- emulator-5556：test03；
- emulator-5558：test04；
- 基线为 65 条，test02/test03/test04 分别为 25/25/15，ID 和 `clientMessageId` 均唯一，序号 1..65 连续。

两端通过真实 Flutter 输入框并发各发送 10 条后，消息数据达到 85/85。但 emulator-5558 的第一次一致性快照出现：消息最大 sequence=85、lastReadSequence=85，`lastMessageSequence` 却仍为 80。12 秒后的下一次快照才自行修正到 85。

这不是消息丢失，而是会话列表投影延迟；用户可能已经在聊天页看到新消息，但会话列表仍显示旧预览和旧排序。

## 根因与修正

事件同步此前存在两个耦合问题：

1. 每个含事件批次都会用本地缓存 bootstrap 删除并重写整份成员和会话投影；缓存本身不是最新会话状态。
2. `message.created` 只写入消息表，不在同一事务推进会话预览、`lastMessageSequence`、未读和 @我序号，需要等待最长约 25 秒的会话索引校准。

现在改为：

- 已存在 bootstrap 缓存时，事件批次不再重复全表替换；首次无缓存恢复仍保留安全初始化路径。
- `message.created` 与消息去重、会话预览、最后消息序号、未读重算和 @我序号在同一 SQLite 事务完成。
- 重放同一事件通过消息表重算未读，不会重复累加。
- 同账号桌面发送的事件仍更新移动端预览，但不会增加当前账号自己的未读。
- 后台会话索引校准继续保留，作为漏事件与元数据差异的兜底，而不是正常消息显示的必经路径。

## 修复后双模拟器复验

覆盖安装新 Profile 包并保留账号、数据库后，两端再次通过真实输入框并发各发送 5 条：

| 项目 | emulator-5556 / test03 | emulator-5558 / test04 |
| --- | ---: | ---: |
| 最终消息 | 95/95 | 95/95 |
| 发送者分布 | 25/40/30 | 25/40/30 |
| ID 唯一数 | 95 | 95 |
| sender + clientMessageId 唯一数 | 95 | 95 |
| 消息序号 | 1..95 连续 | 1..95 连续 |
| lastMessageSequence | 95 | 95 |
| lastReadSequence | 95 | 95 |
| Outbox | 0 | 0 |
| SQLite quick_check | ok | ok |
| applied / ACK | 4689 / 4689 | 4688 / 4688 |

发送工作器结束后立即执行的两端一致性快照命令总耗时 1169 ms；两端首个快照已经一致，不再等待下一轮 25 秒校准。

### 未打开会话的未读与可见区域已读

1. test04 返回会话列表，确认测试群未读为 0；test03 保持群聊前台。
2. test03 通过真实输入框发送 `AI-UAT-UNREAD-20260906-1300-M2-001`。
3. 发送完成后的首个 test04 一致性快照命令耗时 990 ms，结果已经是：消息 96、`lastMessageSequence=96`、`lastReadSequence=95`、未读 1、事件游标 applied/ACK=4690/4690。
4. test04 会话列表同步显示最新预览、时间 12:56 和红色角标 1；底部消息入口也显示 1。
5. test04 点击进入群聊后，3323 ms 观测上界内持久状态变为 `lastReadSequence=96`、未读 0、applied/ACK=4691/4691。
6. test03 对应消息随后显示“已有接收人已读”，没有产生重复消息或额外未读。

该时延包含 ADB 点击和只读数据库快照，不是纯网络延迟。它证明了真实未打开会话下的投影、未读、打开后已读和发送方回执闭环。

## 性能结果

同一宿主机、同一会话和同两台模拟器的阶段日志显示：

| 本地提交 | 修复前 P50 / P95 / 最大 | 修复后 P50 / P95 / 最大 |
| --- | --- | --- |
| emulator-5556 | 262 / 374.9 / 415 ms | 38 / 254.2 / 259 ms |
| emulator-5558 | 114 / 196.8 / 220 ms | 51 / 85.6 / 94 ms |

该结果证明移除重复 bootstrap 全表重写降低了事件事务成本，但不是严格实验室 A/B：两轮事件批次数不同。

端到端同步总耗时不能只报改善部分：修复后 emulator-5558 的含事件批次 P95=3576.8 ms、最大=5558 ms，主要时间在长轮询请求返回前，本地提交最大只有 94 ms。因此本轮仍把“实时及时性”判为部分通过，不把客户端 SQLite 优化冒充服务端投递 SLA 已达标。

## 自动化与构建

- IM 定向回归：43/43 通过。
- Flutter 全量测试：1406/1406 通过。
- `flutter analyze --no-fatal-infos`：0 error、0 warning，保留 7 条已有样式 info。
- Profile APK：111,236,918 字节。
- SHA-256：`C31AAD0029F83EA55F5010ED073A2319A90ED39B8DFBEE84CCAE436742663ADA`。

## 证据

- [结构化前后对照](../test/evidence/multivm-liveopt-20260906-1245/result.json)
- [test03 真实发送记录](../test/evidence/multivm-liveopt-20260906-1245/m2-projection-send.json)
- [test04 真实发送记录](../test/evidence/multivm-liveopt-20260906-1245/m3-projection-send.json)
- [test03 最终聊天页面](../test/evidence/multivm-liveopt-20260906-1245/m2-final-95.png)
- [test04 最终聊天页面](../test/evidence/multivm-liveopt-20260906-1245/m3-final-95.png)
- [test04 会话列表真实未读 1](../test/evidence/multivm-liveopt-20260906-1245/m3-list-unread-1.png)
- [test04 打开后可见区域已读](../test/evidence/multivm-liveopt-20260906-1245/m3-opened-read-96.png)
- [test03 接收人已读回执](../test/evidence/multivm-liveopt-20260906-1245/m2-sender-read-receipt.png)

## 仍未通过

- 5.558 秒长轮询慢批次需要继续结合服务端请求指标与移动端网络时间线定位。
- Windows 当前桌面端与移动端的同账号发送、未读和会话排序仍需在可控桌面窗口上复验；本轮用自动化测试覆盖协议语义，但没有用单元测试替代真实桌面证据。
- Android 虚拟机系统回收后的自动登录、增量追平和可见区域已读已在 [791](791-mobile-im-process-death-recovery-20260906.md) 通过；realme 锁屏、深度 Doze、厂商推送唤醒与真机进程回收仍未通过。
