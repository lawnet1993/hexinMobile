# 787 · 三 AVD 群聊压力与及时性追加实测

> 日期：2026-09-06，Asia/Shanghai。结论：修复连续发送队列后，test02 与 test04 通过真实 Flutter 输入框并发追加 20+10 条，三端 159/159 完整一致、无重复、无乱序、无 Outbox 残留或崩溃。test03 未打开群聊时再次出现 13.87 秒事件年龄长尾，因此完整性通过、群聊实时性未通过。

## 拓扑与动作

- `emulator-5554 / test02`：群内发送 20 条。
- `emulator-5556 / test03`：保持 App 前台，但停留在会话列表，不打开被测群。
- `emulator-5558 / test04`：群内发送 10 条。
- 两个发送 worker 同时运行，所有消息均使用 `AI-UAT-PRESSURE-20260906-1355-` 前缀。
- 本轮是三 GUI 客户端端到端压力样本，不是服务端容量上限测试。

## 三端稳定快照

| 项目 | test02 | test03 | test04 |
| --- | ---: | ---: | ---: |
| 群消息总数 | 159 | 159 | 159 |
| test02 / test03 / test04 | 58 / 41 / 60 | 58 / 41 / 60 | 58 / 41 / 60 |
| ID 唯一 | 159 | 159 | 159 |
| sender+client ID 唯一 | 159 | 159 | 159 |
| 序号 | 1..159 | 1..159 | 1..159 |
| Outbox | 0 | 0 | 0 |
| SQLite quick_check | ok | ok | ok |
| applied / acked | 4861 / 4861 | 4860 / 4860 | 4862 / 4862 |
| 未读 | 0 | 63 | 0 |

test03 的群会话 `lastReadSequence=96`、`lastMessageSequence=159`，未读 63 与序号差一致。截图中的会话预览、末条内容和未读角标均已刷新，不是仅数据库追平。

## 性能与稳定性

| 设备 | 含事件批次 / 事件 | commit P95 | total 最大 | oldest event age 最大 | PSS |
| --- | ---: | ---: | ---: | ---: | ---: |
| test02 | 21 / 33 | 193 ms | 2,292 ms | 806 ms | 156.2 MiB |
| test03 | 5 / 30 | 330 ms | 14,831 ms | 13,874 ms | 162.4 MiB |
| test04 | 22 / 38 | 140 ms | 4,919 ms | 3,066 ms | 199.9 MiB |

- 三台进程均存活；日志没有 FATAL、ANR 或 OOM。
- test02 的 20 次 UI 发送约 30.23 秒，test04 的 10 次约 16.79 秒。该速度包含逐条 ADB 输入和 UI 采样，不代表接口吞吐。
- test03 只用 5 个含事件批次收齐 30 个本轮事件，说明事件可以批量补齐；但 13.87 秒长尾再次复现 [786](786-im-long-poll-direct-group-wakeup-20260906.md) 的群成员长轮询唤醒问题。

## 判定

- 连续发送队列：通过。
- 三端最终一致、幂等、顺序、未读和游标：通过。
- 当前模拟器负载下的进程稳定性：通过。
- 群聊前台接收实时性：未通过，等待服务端/Gateway 修复后复跑。
- 第四台本地 AVD：本轮未启动。当前三台已覆盖双发送+独立接收；继续堆 GUI 实例会把宿主机内存和虚拟化调度噪声误当成产品容量指标。

## 证据

- [结构化结果](../test/evidence/multivm-pressure-20260906-1355/result.json)
- [test02 发送 journal](../test/evidence/multivm-pressure-20260906-1355/m1.json)
- [test04 发送 journal](../test/evidence/multivm-pressure-20260906-1355/m3.json)
- [test02 末条与空输入框](../test/evidence/multivm-pressure-20260906-1355/test02-after.png)
- [test03 未打开群聊、未读 63](../test/evidence/multivm-pressure-20260906-1355/test03-unopened-group.png)
- [test04 末条与空输入框](../test/evidence/multivm-pressure-20260906-1355/test04-after.png)
- 三台 Profile 日志：`emulator-5554-logcat.txt`、`emulator-5556-logcat.txt`、`emulator-5558-logcat.txt`。
