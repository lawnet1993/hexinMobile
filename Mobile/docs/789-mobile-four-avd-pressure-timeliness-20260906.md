# 移动端四虚拟机压力与及时性复验（2026-09-06）

## 测试目标

在现有 3 台独立 Android AVD 之外新增第 4 台独立 AVD，验证多账号并发发送、单聊/群聊接收、断网补偿、去重、顺序、ACK 游标和资源占用。所有写入消息均使用 `AI-UAT-` 前缀。

## 设备与账号

| 逻辑设备 | 测试账号 | 用途 |
| --- | --- | --- |
| M1 | test02 | 群聊发送与接收 |
| M2 | test03 | 群聊纯接收与通讯录观察 |
| M3 | test04 | 群聊发送，同时接收 test05 单聊 |
| M4 | test05 | 新建独立 AVD，单聊发送与断网恢复 |

M4 的 AVD 数据位于 E 盘，拥有独立安装数据和移动端安装身份，没有克隆其他模拟器的 userdata 或设备 ID。压力证据采集后已更新到本轮 Profile APK；重新启动等待 12 秒后确认登录态保留，随后正常关闭，定义和登录数据继续保留。

## 结果摘要

总体为**数据完整性通过、及时性部分通过**。

### 单聊在线连发

- M4→M3 连发 10 条：发送端和接收端均为 10/10。
- 消息序号连续，消息 ID 与发送者 `clientMessageId` 均无重复。
- 双端 Outbox 均为 0，SQLite `quick_check=ok`。
- 双端事件游标均满足 `applied=acked`。
- 接收端结构化同步批次多数约 0.4–2.6 秒完成；设备时钟存在约 0.4 秒偏差，因此不使用负的事件年龄作为网络时延。

### 断网补偿

- M4 同时关闭 Wi-Fi 和移动数据，确认系统无默认网络。
- M3 向 M4 发送 5 条后恢复 M4 网络。
- M4 最终 5/5 落库，序号 16..20 连续，无重复、Outbox=0、SQLite 完整。
- 本地落库时间显示恢复后约 6.9–11.1 秒完成追平；这是包含断网窗口的恢复时间，不是在线单条消息时延。

### 四机并发

- M1 与 M3 同时向 3 人测试群各发送 10 条；M4 同时向 M3 单聊发送 10 条；M2保持接收。
- 群聊累计快照在 M1/M2/M3 三端均为 179/179，发送者计数为 test02=68、test03=41、test04=70。
- 三端群消息序号均为 1..179，179 个服务端消息 ID 唯一，Outbox=0，SQLite 完整，`applied=acked`。
- 并发单聊在 M3/M4 双端均为 10/10，序号 21..30 连续，无重复。
- 四个 App 进程 30 次采样的峰值 PSS 约为 160.3、179.8、203.2、159.7 MiB。
- 4 台并发时宿主机最低观测可用内存约 3.76 GiB；App 日志未发现 FATAL EXCEPTION、App ANR 或 OOM。

## 及时性判定

| 通道 | 结果 | 说明 |
| --- | --- | --- |
| 单聊在线 | 通过 | 并发接收批次大多在 0.4–2.6 秒完成。 |
| 单聊断网补偿 | 通过 | 恢复后 5/5 补齐，无重复、顺序正确。 |
| 群聊数据完整性 | 通过 | 三端 179/179，序号、去重、Outbox、ACK 均正常。 |
| 群聊实时唤醒 | 未通过 | 纯接收端本轮最大事件年龄约 13.683 秒；与前轮 8–14 秒现象一致。 |

群聊未通过点继续指向服务端群事件发布后的等待器唤醒/Gateway 路由，而不是移动端 SQLite 提交或 ACK。移动端提交阶段峰值约 653 ms，但事件到达前已经产生秒级等待。

## 启动与低内存边界

- 当前 Profile 包覆盖安装后的 3 台常驻模拟器稳定态冷启动，共 3 轮：平均约 3.79 秒、4.43 秒、2.19 秒，最大 5.81 秒。
- 这些数据来自 headless Profile AVD，并受到宿主机并发和软件渲染影响，只能作为趋势基线；超过 3 秒的设备继续列为性能观察项。
- M4 以 1 GiB RAM 首次启动 Android 16 时出现一次 System UI 无响应；选择等待后系统恢复，App 登录、在线连发、断网恢复与并发测试均完成。该事件属于低内存模拟器/宿主机压力边界，不能归为 App 通过证据，也没有被隐藏。

## 证据

- [M4 首次在线连发日志](../test/evidence/multivm-pressure-20260906-1420/m4-to-m3-direct-burst.json)
- [M3 单聊接收数据库快照](../test/evidence/multivm-pressure-20260906-1420/m3-receiver-direct-db.json)
- [M4 断网接收数据库快照](../test/evidence/multivm-pressure-20260906-1420/m4-offline-receiver-db.json)
- [四机并发 M1 发送日志](../test/evidence/multivm-pressure-20260906-1420/concurrent-m1.json)
- [四机并发 M3 发送日志](../test/evidence/multivm-pressure-20260906-1420/concurrent-m3.json)
- [四机并发 M4 单聊发送日志](../test/evidence/multivm-pressure-20260906-1420/concurrent-m4-direct.json)
- [M2 群聊接收快照](../test/evidence/multivm-pressure-20260906-1420/group-test03.json)
- [结构化同步指标](../test/evidence/multivm-pressure-20260906-1420/sync-metrics-summary.json)
- [四进程内存采样](../test/evidence/multivm-pressure-20260906-1420/concurrent-memory.json)
- [M4 最终单聊界面](../test/evidence/multivm-pressure-20260906-1420/emulator-5560-after.png)
- [M4 更新当前包后的离线兜底首页](../test/evidence/multivm-pressure-20260906-1420/m4-current-apk-after-update.png)

## 后续修复要求

服务端需要让群聊 `message.created` 在提交后立即唤醒对应账号/设备的长轮询等待器，并补充可观测指标：事件提交时间、目标设备等待器数量、唤醒时间、Gateway 实例和投递结果。验收阈值建议与单聊一致：同区域在线情况下 P95 小于 2 秒，最差不应依赖 25 秒轮询超时。
