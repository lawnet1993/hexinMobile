# 移动端当前构建四 AVD 并发与及时性回归（2026-09-06）

## 结论

当前 Profile APK 已覆盖安装到四台独立 Android AVD。三台群聊端并发真实发送、第四台保持独立账号在线同步，数据完整性、顺序、去重、Outbox、SQLite 完整性与进程稳定性通过；本轮小样本事件年龄最高约 3.306 秒。

该结果是当前构建的增量回归，不覆盖此前 [792](792-mobile-four-avd-im-latency-read-semantics-20260906.md) 已复现的约 20.259 秒群聊长尾，也不解除服务端错误已读语义的 P1 阻塞。

## 构建与拓扑

- APK：`app-profile.apk`，68.7 MiB。
- SHA-256：`F2F0B74578EE5C7956A66D97EC9A16040959A740515F30EC12D84EC3F58BAD4C`。
- M1 `emulator-5554`：test02，群聊发送/接收。
- M2 `emulator-5556`：test03，群聊发送/接收与时延观察。
- M3 `emulator-5558`：test04，群聊发送/接收。
- M4 `emulator-5560`：test05，独立会话长轮询背景负载。

四台实例保留各自 userdata、安装身份、账号数据库和事件游标。发送只通过真实 UI，消息统一使用 `AI-UAT-POSTOAFIX-20260906-1725-` 前缀；数据库检查为 `run-as` 只读快照。

## 并发结果

M1、M2、M3 同时在 `AI-UAT-MULTIVM-20260906-1100` 群聊中各发送 5 条，共新增 15 条。每次输入稳定等待 750 ms、点击后等待 800 ms，避免把低性能软件渲染器漏消费点击误判成消息丢失。

| 指标 | 基线 | 回归后 | 判定 |
| --- | ---: | ---: | --- |
| 三端累计消息数 | 229 | 244 | 三端一致 |
| test02 / test03 / test04 | 88 / 56 / 85 | 93 / 61 / 90 | 各新增 5 |
| 服务端消息 ID 唯一数 | 229 | 244 | 无重复 |
| 发送者 + `clientMessageId` 唯一键 | 229 | 244 | 无重复 |
| 会话序号 | 1..229 | 1..244 | 严格递增 |
| Outbox | 0 | 0 | 全部确认 |
| SQLite `quick_check` | ok | ok | 三端通过 |
| 事件游标 | applied=acked | applied=acked | 三端通过 |

三台工作器均确认第 5 条消息可见且输入框为空，没有自动重放失败批次。

## 及时性与资源

- M2 设备时钟可用样本中，事件年龄最大约 1.443 秒。
- M3 样本中，事件年龄最大约 3.306 秒。
- M1 与服务端存在约 1–2 秒方向相反的时钟偏差，产生负事件年龄，本轮不把该设备用于绝对时延结论。
- 长轮询自身约 25 秒是无事件时的等待窗口；如果请求在消息到来后立即返回，不能把请求从开始等待到返回的总时长误当成消息延迟。

| 设备 | 回归后 PSS | 进程 | Crash/ANR/OOM 命中 |
| --- | ---: | --- | ---: |
| M1 | 205.8 MiB | 存活 | 0 |
| M2 | 213.8 MiB | 存活 | 0 |
| M3 | 210.9 MiB | 存活 | 0 |
| M4 | 189.2 MiB | 存活 | 0 |

这是四实例同宿主机的 Profile 构建观测值，包含 Android 模拟器软件渲染和当前页面缓存，不作为低内存真机的最终门槛。

## 证据

- [M1 基线](../test/evidence/multivm-post-oa-fix-20260906-1720/emulator-5554-baseline.json)
- [M2 基线](../test/evidence/multivm-post-oa-fix-20260906-1720/emulator-5556-baseline.json)
- [M3 基线](../test/evidence/multivm-post-oa-fix-20260906-1720/emulator-5558-baseline.json)
- [M1 并发发送日志](../test/evidence/multivm-post-oa-fix-20260906-1720/emulator-5554-burst.json)
- [M2 并发发送日志](../test/evidence/multivm-post-oa-fix-20260906-1720/emulator-5556-burst.json)
- [M3 并发发送日志](../test/evidence/multivm-post-oa-fix-20260906-1720/emulator-5558-burst.json)
- [M1 最终数据库快照](../test/evidence/multivm-post-oa-fix-20260906-1720/emulator-5554-after-3s.json)
- [M2 最终数据库快照](../test/evidence/multivm-post-oa-fix-20260906-1720/emulator-5556-after-3s.json)
- [M3 最终数据库快照](../test/evidence/multivm-post-oa-fix-20260906-1720/emulator-5558-after-3s.json)
- [四实例资源与崩溃摘要](../test/evidence/multivm-post-oa-fix-20260906-1720/runtime-health.json)
- [M1 同步阶段日志](../test/evidence/multivm-post-oa-fix-20260906-1720/emulator-5554-sync-stage.log)
- [M2 同步阶段日志](../test/evidence/multivm-post-oa-fix-20260906-1720/emulator-5556-sync-stage.log)
- [M3 同步阶段日志](../test/evidence/multivm-post-oa-fix-20260906-1720/emulator-5558-sync-stage.log)
- [M4 同步阶段日志](../test/evidence/multivm-post-oa-fix-20260906-1720/emulator-5560-sync-stage.log)

## 尚未通过

1. 先前四 AVD 压力中群聊纯接收端出现约 20.259 秒长尾；本次 15 条增量样本较快，不足以宣告长尾消失。
2. 接收端没有打开会话时，服务端仍可能提前推进本人已读游标；服务端修复前跨端已读矩阵保持未通过。
3. GUI 多虚拟机适合端到端一致性和资源回归，不等同于服务端容量压测。服务端最大连接数、每秒消息量和饱和点需要独立压测账户池、限流豁免与监控窗口。
4. AVD 不能替代厂商真机后台冻结、Doze、推送唤醒、低内存回收与弱网切换测试。
