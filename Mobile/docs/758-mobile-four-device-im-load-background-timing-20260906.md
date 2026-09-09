# 758 · 移动端四端 IM 压测、后台恢复与事件流及时性

> 2026-09-06 当前环境复核：本文记录的是当时服务端事件游标停在 3309 的真实现场，但早期消息“延迟”同时使用了会被对账重写的 `updated_at`，不能单独代表首次投递时点。当前服务端事件流已推进到 3764，真实长轮询可在发送后约 419 ms 唤醒，最新结论见 [761](761-mobile-three-device-im-load-latency-20260906.md)。历史故障证据保留，不覆盖为当前状态。

日期：2026-09-06，Asia/Shanghai。

结论：**完整性通过，前台实时性部分通过，Android 后台实时性不通过**。本轮同时运行三台 Android 模拟器和一台 Android 真机，通过真实 UI 发送 90 条 `AI-UAT-` 测试消息；90/90 最终落库，消息 ID 与 `senderId + clientMessageId` 均唯一，会话序号连续，Outbox 为 0，SQLite `quick_check=ok`。但是前台单聊仍出现 18.333 秒和 27.011 秒长尾；真机进入系统桌面后，20 条单聊在进程仍存活的情况下超过一个长轮询周期仍未落库，恢复前台后约 4.2 秒批量补齐，端到端最大延迟 113.037 秒。

## 测试拓扑与资源边界

- 真机接收端：realme RMX3366，`dd00d66d`，test01。
- 模拟器 1：`emulator-5554`，test02，向 test01 单聊发送。
- 模拟器 2：`emulator-5556`，test03，向 test01 单聊发送，并接收 test04 群聊。
- 模拟器 3：`emulator-5558`，test04，向既有两人 AI-UAT 群聊发送。
- 第三台 AVD 使用 E 盘独立数据目录、无窗口和 1,024 MB 配置启动。停止三个遗留 Gradle daemon 后，主机可用内存由 2.55 GB 回升到 7.28 GB，第三台完成冷启动后基线仍有 4.16 GB；测试结束为 3.99 GB。
- 三个 QEMU 最终工作集分别约 3.43、3.76、3.44 GB，主机内存占用约 87.4%。这已是当前主机可复现的四端功能压力拓扑，不代表服务端容量或最大在线数。

## 第一轮：三路前台并发 20×3

三台模拟器同时在真实聊天页面输入并发送 20 条，真机停留消息列表；test03 虽停留在与 test01 的单聊页，仍同时接收 test04 群聊事件。

| 路径 | 结果 | 序号 | P50 | P95 | 最大 |
| --- | --- | --- | ---: | ---: | ---: |
| test02 → test01 单聊 | 20/20，唯一、连续 | 69–88 | 5.818 s | 17.136 s | 18.333 s |
| test03 → test01 单聊 | 20/20，唯一、连续 | 120–139 | 0.711 s | 24.110 s | 27.011 s |
| test04 → test03 群聊 | 20/20，唯一、连续 | 615–634 | 0.215 s | 1.910 s | 2.735 s |

本轮 60 条全部到达，但两个单聊会话出现接近一次 25 秒长轮询周期的长尾，和 [756](756-mobile-multi-emulator-im-load-timing-20260906.md) 的 test03 十秒级长尾一致，因此不能判定前台实时性完全通过。群聊样本存在 2 个轻微负延迟值，范围小于 0.5 秒，是模拟器与服务端时钟偏差；原始值保留，未伪造为 0。

## 第二轮：真机后台 10×3

真机切到 Android Launcher 后 PID 始终为 `26447`，移动端进程没有被杀。三台模拟器再次并发发送 10 条：

| 路径 | 后台期间 | 最终结果 | P50 | P95 | 最大 |
| --- | --- | --- | --- | ---: | ---: | ---: |
| test02 → test01 单聊 | 0/10 | 恢复前台后 10/10 | 106.242 s | 112.373 s | 113.037 s |
| test03 → test01 单聊 | 0/10 | 恢复前台后 10/10 | 98.376 s | 110.474 s | 111.831 s |
| test04 → test03 群聊 | 10/10 | 10/10 | 0.299 s | 1.066 s | 1.213 s |

- 真机后台超过 25 秒后仍为 0/20；恢复前台的 `am start -W` 为 HOT，调用返回后约 4 秒，20 条在 04:35:01 一次性落库。
- 补偿后两个单聊序号分别为 89–98、140–149，双重唯一性通过，Outbox 为 0，说明没有丢失或重复。
- test03 打开群聊后可连续渲染本轮 30 条，test04 随后收到“已有接收人已读”状态，群聊加载与跨端已读通过。

## 服务端事件流根因证据

test01 真机补齐消息后，本地事件游标仍停在 `applied=acked=3309`；继续等待一个完整长轮询周期仍没有推进。随后使用当前桌面 test01 的已有授权会话做只读核对：

- `GET /api/im/sync/events?afterSequence=3309&waitSeconds=0&take=500`
- HTTP 200，请求编号 `e1496e67-4ccb-43e1-9fb3-fef8e5a4ffb0`
- `latestSequence=3309`、`events=[]`
- 同一时刻会话接口已经显示 test02 会话 `lastMessageSequence=98`、test03 会话 `lastMessageSequence=149`，并能读取到本轮测试消息。

因此这不是仅由移动端渲染或 SQLite 写入造成：**消息本体已存在，但 test01 的 `message.created` 事件没有进入可拉取事件流**。移动端恢复前台后依靠会话索引和缺口修复补齐；Windows 本地缓存稍后也通过对账到达序号 149，但不能据此判定实时同步通过。

## 稳定性

| 设备 | 基线 PSS | 结束 PSS | 变化 |
| --- | ---: | ---: | ---: |
| 真机 test01 | 243,050 KB | 242,581 KB | -469 KB |
| test02 模拟器 | 180,874 KB | 184,633 KB | +3,759 KB |
| test03 模拟器 | 182,836 KB | 181,291 KB | -1,545 KB |
| test04 模拟器 | 176,027 KB | 183,141 KB | +7,114 KB |

四个 App 进程均存活，日志中 `FATAL EXCEPTION`、`Unhandled Exception`、`OutOfMemoryError`、`RenderFlex overflowed` 均为 0。本轮没有观察到随消息数持续增长的 PSS 趋势。

测试完成后仅关闭本轮新增的 test04 无头模拟器，AVD 保留以便复测；宿主机可用内存由约 3.99 GB 回升至 7.96 GB，其余真机与两台原有模拟器保持连接。

## 必须修改与验收清单

### 服务端 P1：补齐每个接收账号的持久事件

1. 消息事务成功后，必须为每个目标账号写入可持久拉取的 `message.created` 事件；不能只更新消息表和会话最后序号。
2. `/api/im/sync/events` 的 `latestSequence` 必须随该账号新事件增长，并立即唤醒对应长轮询；不要等到 25 秒超时或依赖客户端会话索引轮询。
3. 排查请求编号 `e1496e67-4ccb-43e1-9fb3-fef8e5a4ffb0` 前后的事件发布、账号 fan-out、网关节点、队列提交与事务边界。
4. 回归至少覆盖：三发送端并发单聊/群聊、同账号桌面与移动端、接收端离线、事件落库后 ACK 前崩溃、重复事件和重复 ACK。
5. 验收条件：消息、会话索引和事件流三者序号一致；前台 P95 建议不高于 2 秒，不能再出现接近 25 秒的周期性长尾。

### 移动端 P1：厂商推送通道仍未完成

1. 当前服务端推送能力可以接入，但厂商推送令牌注册、后台回调和真实设备通道仍应保持“未完成”。
2. 推送只负责唤醒同步；回调后仍按事件游标/会话索引补拉，不能把推送正文直接写成最终消息。
3. 应上报不含敏感信息的同步健康：模式、最后事件时间、事件游标、会话索引序号、缺口修复次数和事件滞后量。
4. App 回到前台立即同步已经生效，本轮 HOT 恢复约 4 秒补齐；仍需在服务端事件发布修复后复测后台推送及时性。

### Windows 桌面端 P1：保留索引兜底并暴露同步健康

1. 桌面端不能只等待事件流；启动、恢复、网络重连和周期巡检时必须对比会话 `lastMessageSequence` 与本地序号并补拉缺口。
2. 会话索引兜底不能掩盖事件丢失，应记录安全的 `eventCursor`、`indexSequence`、补拉数量和耗时，禁止记录 Token、消息正文和附件地址。
3. 服务端修复前，桌面端“手机发出的消息不能实时显示”保持未通过；本轮只确认本地缓存最终到达 149，未把延迟补偿当成实时通过。

## 证据

- [四端基线资源](../test/evidence/oa-action-boundaries-20260906/continuation-20260906/load-round-20260906/four-device-20260906-042800/00-baseline-resource.json)
- [test02 前台单聊指标](../test/evidence/oa-action-boundaries-20260906/continuation-20260906/load-round-20260906/four-device-20260906-042800/20-test02-to-test01-metrics.json)
- [test03 前台单聊指标](../test/evidence/oa-action-boundaries-20260906/continuation-20260906/load-round-20260906/four-device-20260906-042800/21-test03-to-test01-metrics.json)
- [test04 前台群聊指标](../test/evidence/oa-action-boundaries-20260906/continuation-20260906/load-round-20260906/four-device-20260906-042800/22-test04-group-to-test03-metrics.json)
- [真机后台状态](../test/evidence/oa-action-boundaries-20260906/continuation-20260906/load-round-20260906/four-device-20260906-042800/30-physical-background-state.json)
- [后台等待后仍未落库](../test/evidence/oa-action-boundaries-20260906/continuation-20260906/load-round-20260906/four-device-20260906-042800/43-background-before-resume-summary.json)
- [真机恢复时点](../test/evidence/oa-action-boundaries-20260906/continuation-20260906/load-round-20260906/four-device-20260906-042800/46-physical-resume.json)
- [test02 后台补偿最终指标](../test/evidence/oa-action-boundaries-20260906/continuation-20260906/load-round-20260906/four-device-20260906-042800/49-test02-post-resume-final.json)
- [test03 后台补偿最终指标](../test/evidence/oa-action-boundaries-20260906/continuation-20260906/load-round-20260906/four-device-20260906-042800/50-test03-post-resume-final.json)
- [服务端事件流与会话序号矛盾](../test/evidence/oa-action-boundaries-20260906/continuation-20260906/load-round-20260906/four-device-20260906-042800/72-desktop-service-events-after-3309.json)
- [Windows 本地缓存延迟对账](../test/evidence/oa-action-boundaries-20260906/continuation-20260906/load-round-20260906/four-device-20260906-042800/73-desktop-cache-late-reconcile.json)
- [真机恢复后消息列表](../test/evidence/oa-action-boundaries-20260906/continuation-20260906/load-round-20260906/four-device-20260906-042800/60-physical-recovered-message-list.png)
- [test03 群消息连续渲染](../test/evidence/oa-action-boundaries-20260906/continuation-20260906/load-round-20260906/four-device-20260906-042800/61-test03-group-rendered.png)
- [test04 已读回执](../test/evidence/oa-action-boundaries-20260906/continuation-20260906/load-round-20260906/four-device-20260906-042800/62-test04-read-receipts.png)
- [结束资源与错误计数](../test/evidence/oa-action-boundaries-20260906/continuation-20260906/load-round-20260906/four-device-20260906-042800/70-final-resource-stability.json)
- [新增模拟器测试后释放资源](../test/evidence/oa-action-boundaries-20260906/continuation-20260906/load-round-20260906/four-device-20260906-042800/80-third-avd-post-test-stop.json)
