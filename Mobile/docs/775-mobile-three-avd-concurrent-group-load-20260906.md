# 775 · 三 AVD 同群并发与离线追赶实测

> 日期：2026-09-06  
> 结论：数据可靠性通过；三模拟器高负载下的实时性和恢复稳定性部分通过，不作为真机性能 SLA。

## 拓扑与范围

- M1：Android AVD / `test02`。
- M2：Android AVD / `test03`。
- M3：Android AVD / `test04`。
- 三端进入同一 `AI-UAT-` 测试群，均使用独立账号域、安装身份、SQLite 和事件游标。
- 消息全部通过真实 Flutter 输入框发送；只读取脱敏后的计数、序号、游标和完整性，不记录消息正文、凭据、Token、设备标识或附件地址。
- 本轮是客户端并发、同步与恢复验收，不是服务端容量压测；只有三个客户端样本，不能外推服务器 QPS 上限。

## 在线三端并发

M1、M2、M3 同时各发送 15 条，共 45 条。

| 项目 | M1 | M2 | M3 |
| --- | ---: | ---: | ---: |
| UI 发送总耗时 | 16.87 s | 42.84 s | 19.57 s |
| 最终消息数 | 45/45 | 45/45 | 45/45 |
| 发送者分布 | 15/15/15 | 15/15/15 | 15/15/15 |
| 消息 ID 唯一数 | 45 | 45 | 45 |
| 发送者 + clientMessageId 唯一数 | 45 | 45 | 45 |
| 序号 | 1..45 严格递增 | 1..45 严格递增 | 1..45 严格递增 |
| Outbox | 0 | 0 | 0 |
| SQLite quick_check | ok | ok | ok |
| 最终游标 | applied=acked | applied=acked | applied=acked |

M2 的真实 UI 自动化吞吐明显低于另外两台；该耗时包含 ADB 输入、Flutter 重绘和模拟器调度，不能当作服务端发送时延，但能够复现宿主机压力下的交互退化。

同步阶段按含事件的批次统计，批次混有消息、已读、成员和在线状态事件：

| 指标 | M1 | M2 | M3 |
| --- | ---: | ---: | ---: |
| 含事件批次数 | 26 | 13 | 24 |
| 本地提交 P50 / P95 / 最大 | 106 / 158.8 / 160 ms | 403 / 635 / 761 ms | 112 / 203.4 / 228 ms |
| ACK P50 / P95 / 最大 | 109 / 141.5 / 181 ms | 227 / 514.6 / 844 ms | 112.5 / 135.7 / 139 ms |
| 同步阶段总耗时 P50 / P95 / 最大 | 497.5 / 8914.2 / 11580 ms | 1244 / 3855.8 / 5156 ms | 620.5 / 8299.5 / 8957 ms |
| 最大临时 pending ACK | 0 | 11 | 6 |
| 最终健康状态 | healthy | healthy | healthy |

长轮询等待会进入同步阶段总耗时，设备时钟也有偏差，所以不能把表中 P95 直接解释为纯消息投递 P95。可以确定的是：三 AVD 同时运行时出现数秒级批次和临时 ACK 积压，最终均自行追平，没有形成游标停滞。

## 强停离线与一次启动追赶

1. 对 M3 执行严格 `force-stop` 并确认进程不存在。
2. M1、M2 同时各发送 10 条；在线两端先达到 65/65。
3. M3 停止期间保持 45 条，证明没有后台进程偷跑。
4. 只启动 M3 一次，从启动到 SQLite 达到 65/65 的观测上界为 4775 ms。

追赶完成后的 M3：

- 三个发送者分别为 25、25、15 条，总计 65 条。
- 消息 ID 65 个唯一，发送者 + `clientMessageId` 65 个唯一。
- 序号 1..65 严格递增，Outbox=0，SQLite `quick_check=ok`。
- `lastMessageSequence=65`，事件游标 `applied=acked`。
- `lastReadSequence=45`、未读 20；同步落库没有错误地把离线消息标成已读。

证据：[追赶计时](../test/evidence/multivm-offline-catchup-20260906-1130/m3-catchup-timing.json)、[M3 最终数据库摘要](../test/evidence/multivm-offline-catchup-20260906-1130/m3-final-db.json)、[恢复后的未读 20](../test/evidence/multivm-offline-catchup-20260906-1130/m3-after-catchup.png)。

## 稳定性与资源

- 每台模拟器追加 24 次聊天记录上下滚动，三路操作均完成。
- 三端日志均未发现应用 FATAL、ANR、OutOfMemoryError 或未处理异常。
- 应用 PSS 约 157–176 MiB；三套 QEMU 工作集合计约 10 GiB，采样时宿主机可用内存约 3.2 GiB。
- 证据采集完成后已正常关闭轮换用的 M1 AVD，数据盘保留；M2/M3 继续运行，宿主机可用内存恢复到约 5.2 GiB。
- Android `gfxinfo` 对 Flutter `SurfaceView` 本轮返回 0 个应用帧，因此不能据此给出掉帧通过结论；结构化结果明确标为不支持，未用伪造的 4950 ms 分位数替代真实帧数据。
- M2 此前在三 AVD 常驻时恢复到前台曾停留在空白工作台加载状态超过 35 秒，整机重启后恢复。该问题仍按“并发恢复稳定性未完全通过”保留。

证据：[运行稳定性摘要](../test/evidence/multivm-offline-catchup-20260906-1130/runtime-stability.json)、[在线同步阶段摘要](../test/evidence/multivm-concurrent-20260906-1100/sync-stage-summary.json)。

## 判定与后续

- 三端同群并发落库、去重、顺序、Outbox、SQLite 完整性：**通过**。
- 强停期间积压 20 条、一次启动追赶、未读语义：**通过**。
- 三 AVD 压力下即时性：**部分通过**。无丢失，但存在约 5–12 秒最慢同步批次，M2 输入/提交/ACK 明显偏慢。
- 崩溃、ANR、OOM：**本轮未发现**。
- 帧流畅度：**未判定**。需要真机 Profile/Release 的 Flutter DevTools frame timeline 或 Perfetto 采样。
- 服务端修改：当前证据不足以归因服务端，不创建服务端修复项。
- 移动端后续：对同步循环、SQLite 事务和列表增量渲染做 Profile/Perfetto 采样；复测 M2 恢复前台卡住问题。
