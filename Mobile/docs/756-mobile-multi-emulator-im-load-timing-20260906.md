# 756 · 移动端多模拟器 IM 并发与及时性实测

> 2026-09-06 复核说明：本文早期“延迟”使用本地 `im_messages.updated_at - created_at` 计算；`updated_at` 会被后续会话对账重写，因此 10–36 秒长尾不能继续解释为首次投递延迟。最新 Profile 事件年龄、长轮询唤醒和三设备并发结果见 [761](761-mobile-three-device-im-load-latency-20260906.md)。本文的消息完整性、唯一性、顺序和当时环境现象仍有效。

日期：2026-09-06，Asia/Shanghai。结论：**投递完整性通过，及时性部分通过**。两台 Android 模拟器同时向一台 Android 真机发送消息，原六轮 94 条加上 App 后台 10+10 突发，累计 114 条目标记录，未发现丢失、重复或会话内序号断裂；但首轮 test03 会话出现 36.435 秒长尾，后台复测同一发送端仍有 15.566 秒长尾，因此实时及时性不能判定完全通过。

## 拓扑与边界

- 接收端：realme RMX3366，test01，ARM64 Profile 包。
- 发送端 1：`emulator-5554`，test02，x86_64 Profile 包。
- 发送端 2：`emulator-5556`，test03，x86_64 Profile 包。
- 三端同时在线，使用真实 UI 输入、真实发送接口、真机 SQLite 落库和截图核对。
- 两个模拟器进程合计常驻约 7.6 GB；本轮结束时主机只剩约 1.9 GB 可用内存。没有再启动第三台模拟器，避免主机换页和软件渲染把环境噪声混入产品结论。
- 本轮是客户端多实例并发、及时性和完整性测试，不是服务端容量、最大在线数或饱和吞吐压测。ADB 逐条输入本身约需 1 秒/条，不能用发送命令持续时间推导服务端 TPS。

## 结果总览

| 场景 | 新增落库 | 唯一性与顺序 | `createdAt` 到真机提交延迟 |
| --- | ---: | --- | --- |
| 首轮 25+25，真机停留审批详情“更多操作”层 | 52/52，含 2 条输入校准消息和 50 条有效突发消息 | 两会话各 26 条；消息 ID 与 `senderId + clientMessageId` 均唯一；序号分别连续 | 有效 50 条 P50 3.575 s、P90 28.999 s、P95 33.514 s、最大 36.435 s |
| 前台单条 1+1 | 2/2 | 两会话各新增 1 条 | test02 363.531 ms；test03 951.448 ms |
| 消息列表前台 10+10 | 20/20 | 两会话各 10 条，序号连续、双重 ID 唯一 | P50 4.023 s、P95 11.266 s、最大 12.369 s |
| 同源最新包覆盖后 5+5 | 10/10 | 两会话各 5 条，序号连续、双重 ID 唯一 | P50 2.706 s、P95/最大 6.543 s |
| 真机停留 OA 待办页 3+3 | 6/6 | 两会话各 3 条，序号连续、双重 ID 唯一 | P50 417.692 ms、P95/最大 765.503 ms |
| 真机停留同一审批详情“更多操作”层 2+2 | 4/4 | 两会话各 2 条，序号连续、双重 ID 唯一 | P50 583.132 ms、P95/最大 1.991 s |
| App 后台、系统 Office 打开器前台 10+10 | 20/20 | 两会话各 10 条，序号连续、双重 ID 唯一 | P50 933.006 ms、P95 13.987 s、最大 15.566 s |

原六轮合计恰好新增 94 条，追加后台轮次 20 条，累计 114 条目标消息；没有删除旧消息。真机消息列表同时显示 test02 和 test03 的最新消息与未读数；进入 test03 会话后，突发消息能够按序渲染并继续上滑查看历史。

## 首轮延迟异常

首轮 50 条有效突发消息中：

- test02 会话 25 条：P50 1.223 s、P95 4.029 s、最大 4.718 s。
- test03 会话 25 条：P50 18.008 s、P95 35.027 s、最大 36.435 s。
- test03 的较早消息集中在约 19:08:17Z 被提交，表现更像实时事件未及时唤醒、随后由长轮询/会话索引对账批量补回，而不是客户端丢消息。

后续把真机放在消息列表、聊天页和 OA 待办页复测，两个会话都能渐进落库；OA 待办页 3+3 的最大延迟只有 765.503 ms。再返回与首轮相同的审批详情“更多操作”层执行 2+2，四条全部落库，最大 1.991 秒。因此没有证据证明“打开 OA 或更多操作层就停止 IM 同步”，首轮 36 秒长尾更像一次瞬时服务端事件/长轮询异常；但长尾真实存在，仍需服务端按事件 ID、账号、网关节点和发布时间排查。

## 安装架构与恢复

- 为统一源码版本，第一次覆盖模拟器时误用了 ARM64 包，x86_64 模拟器启动立即报 `EM_AARCH64 instead of EM_X86_64`。这是测试包架构使用错误，不是产品崩溃。
- 随后使用项目既有 Gradle 缓存重新构建 `android-x64` Profile 包并保留数据覆盖安装，两台模拟器均恢复，test02/test03 登录态和历史消息保留。
- 最终安装状态：真机 ARM64 SHA-256 `4007EF04E67DDA18D5B2080B1F0DDC2776BB406ACE839536F6FF3C01C754C700`；两台模拟器 x86_64 SHA-256 `EC39189A05131FA299BE1E481251AF0A99D6AADFE375C79F5B9247080FEEC4EF`。架构不同所以哈希不同，源码与版本号相同。
- 本轮结束后重新生成 ARM64 交付产物，大小 69,497,080 字节，SHA-256 仍为 `4007EF04E67DDA18D5B2080B1F0DDC2776BB406ACE839536F6FF3C01C754C700`。

## 稳定性与资源

- 三端最终 Activity 均为移动端 `MainActivity`；日志未发现新的 `FATAL EXCEPTION`、`Unhandled Exception` 或 `RenderFlex overflowed`。
- 真机 PSS：20 条前约 260,854 KB，接收后约 239,727 KB，打开并往返滚动突发会话后约 245,646 KB；本样本未出现持续增长。
- 该 realme 系统本轮 `dumpsys gfxinfo` 返回 0 个有效帧，不能据此宣称 0% Jank。此前 808 帧样本仍以 [754](754-mobile-oa-boundary-multi-device-real-device-20260906.md) 为准。

### 第三台 AVD 资源边界

- 追加创建了放在 E 盘的独立 `SecureAccess_Load_03`，以 1,024 MB 内存、无窗口模式启动为 `emulator-5558`。
- 冷启动时该 QEMU 工作集仍达到约 2.20 GB，宿主机可用物理内存由 2.58 GB 降至 0.57 GB，实例尚处于 `offline`。继续等待会进入明显换页区，所得延迟不能代表移动端或服务端。
- 随即只终止本轮新增实例，宿主机可用内存恢复到 2.97 GB；真机、`emulator-5554`、`emulator-5556` 保持在线。AVD 定义保留在 E 盘，后续释放宿主机内存后可复用。
- 因此当前主机的可靠 GUI 验收上限仍是两模拟器加一真机。更高并发应使用协议级虚拟用户，同时保留少量真实设备验证 UI、生命周期和本地数据库语义。

### App 后台时 10+10 突发复测

- test01 真机停留在 Android Office 附件打开器，移动端 App 处于后台；test02 与 test03 分别向 test01 单聊发送 10 条 `AI-UAT-MV3-20260906-035100-*`。
- 真机数据库最终恰好新增 20 条目标记录；消息 ID 20/20 唯一，`senderId + clientMessageId` 20/20 唯一，两会话序号分别为 59–68、110–119，均连续。
- test02 的 10 条接收延迟为 374.007–933.006 ms；test03 为 2.609–15.566 s。合并 P50 933.006 ms、P95 13.987 s、最大 15.566 s。
- 这些记录的 `updatedAt` 均早于 19:53:41Z 的 App 前台恢复动作，证明本轮确实在 App 后台落库，不是回前台后才补偿。返回消息列表后可见最新 `T02-10` 与 `T03-10`。
- 结论仍是完整性通过、及时性部分通过：后台同步没有丢失或重复，但 test03 再次出现十秒级长尾，需要结合服务端事件发布/长轮询唤醒日志定位。

## 证据

- [首轮接收端增量、唯一性和延迟](../test/evidence/oa-action-boundaries-20260906/multi-vm-im-20260906/receiver-added-metrics.json)
- [前台单条采样时间线](../test/evidence/oa-action-boundaries-20260906/multi-vm-im-20260906/foreground-probe.json)
- [消息列表 20 条采样](../test/evidence/oa-action-boundaries-20260906/multi-vm-im-20260906/foreground-burst20.json)
- [消息列表 20 条落库指标](../test/evidence/oa-action-boundaries-20260906/multi-vm-im-20260906/foreground-burst20-metrics.json)
- [同源最新包 10 条落库指标](../test/evidence/oa-action-boundaries-20260906/multi-vm-im-20260906/post-upgrade-burst10-metrics.json)
- [OA 页面 6 条采样](../test/evidence/oa-action-boundaries-20260906/multi-vm-im-20260906/oa-page-burst6.json)
- [OA 页面 6 条落库指标](../test/evidence/oa-action-boundaries-20260906/multi-vm-im-20260906/oa-page-burst6-metrics.json)
- [审批详情更多操作层 4 条采样](../test/evidence/oa-action-boundaries-20260906/multi-vm-im-20260906/oa-detail-more-burst4.json)
- [审批详情更多操作层 4 条落库指标](../test/evidence/oa-action-boundaries-20260906/multi-vm-im-20260906/oa-detail-more-burst4-metrics.json)
- [审批详情更多操作层测试画面](../test/evidence/oa-action-boundaries-20260906/multi-vm-im-20260906/physical-oa-detail-more-before-probe.png)
- [真机两会话同时收到突发消息](../test/evidence/oa-action-boundaries-20260906/multi-vm-im-20260906/physical-messages-before-probe.png)
- [真机突发会话渲染与历史滚动](../test/evidence/oa-action-boundaries-20260906/multi-vm-im-20260906/physical-chat-after-burst.png)
- [两台模拟器最终安装哈希](../test/evidence/oa-action-boundaries-20260906/multi-vm-im-20260906/installed-artifacts.json)
- [test02 覆盖安装后登录保留](../test/evidence/oa-action-boundaries-20260906/multi-vm-im-20260906/emulator-5554-x64-restored.png)
- [test03 覆盖安装后登录保留](../test/evidence/oa-action-boundaries-20260906/multi-vm-im-20260906/emulator-5556-x64-restored.png)
- [第三台 AVD 资源边界](../test/evidence/oa-action-boundaries-20260906/continuation-20260906/load-round-20260906/third-avd-resource-boundary.json)
- [后台 10+10 突发指标](../test/evidence/oa-action-boundaries-20260906/continuation-20260906/load-round-20260906/background-burst20-metrics.json)
- [test02 发送端结果](../test/evidence/oa-action-boundaries-20260906/continuation-20260906/load-round-20260906/emulator-5554-after-corrected-send.png)
- [test03 发送端结果](../test/evidence/oa-action-boundaries-20260906/continuation-20260906/load-round-20260906/emulator-5556-after-send.png)
- [真机后台接收后消息列表](../test/evidence/oa-action-boundaries-20260906/continuation-20260906/load-round-20260906/physical-messages-after-load.png)

## 后续验收

1. 服务端按首轮 test03 的消息创建时间和会话序号 64–88 排查事件发布、长轮询唤醒和网关节点日志；在原因明确前，IM 实时及时性保持“部分通过”。
2. 服务端容量压测应改用独立虚拟用户脚本，并同时采集网关连接数、事件队列积压、HTTP/gRPC 延迟、数据库连接池和错误率；GUI 模拟器只保留端到端行为验收。
3. 催办接收人的在线通知、App 强制停止后的离线恢复、刷新后单事件去重，以及桌面会话与真机同时处理同一审批任务的乐观并发冲突均已补齐。

## 追加四端阶梯复测

停止遗留 Gradle daemon 释放宿主机内存后，`SecureAccess_Load_03` 已作为 `emulator-5558` 完成冷启动并登录 test04，形成三模拟器加一真机拓扑。两轮共发送 90 条，完整性、唯一性、会话序号、群聊渲染和跨端已读通过；但前台单聊最大延迟 27.011 秒，真机进入 Launcher 后消息直到恢复前台才补齐，最大延迟 113.037 秒。服务端只读核对进一步证明会话序号已经推进，而 test01 的事件流仍停在 3309。详见 [758 · 移动端四端 IM 压测、后台恢复与事件流及时性](758-mobile-four-device-im-load-background-timing-20260906.md)。
