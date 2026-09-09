# 761 · 移动端三设备 IM 并发、及时性与同步热点复测

> 追加复核：当前服务端在两模拟器 30 条真实 UI 消息中返回 30/30 个事件，单条 UI 点击到长轮询返回约 512 ms；但锁屏真机未追赶，见 [765](765-mobile-multi-emulator-timeliness-followup-20260906.md)。前台事件流通过不等同于后台推送通过。

日期：2026-09-06，Asia/Shanghai。

结论：**三设备真实 UI 并发下，消息完整性、唯一性、会话内顺序和真机事件游标均通过；当前前台/后台存活进程的事件拉取及时性通过本轮小规模验收。** 两台模拟器向一台真机累计发送 190 条 `AI-UAT-` 消息，真机 190/190 落库，无重复、无会话序号断裂，Outbox 为 0，SQLite `quick_check=ok`。Profile 事件年龄诊断的 20 条收口样本中，中位数 244 ms、最慢 1,844 ms。

## 拓扑与测试边界

- 接收端：realme RMX3366 真机，test01，ARM64 Profile。
- 发送端：`emulator-5554`（test02）和 `emulator-5556`（test03），x86_64 Profile。
- 三端均保留各自稳定安装 ID 和独立本地游标；发送通过真实聊天输入框和发送按钮完成，不直接调用消息发送 API。
- 本轮开始时主机只有约 5.16 GB 可用内存，因此没有再启动第三台 AVD。此前第三台实例已证明会将当前主机推入明显内存压力区；本轮选择两个既有模拟器加一台真机，避免把宿主机换页误判为产品延迟。
- 这是客户端多实例、生命周期和同步正确性压力测试，不是服务端最大连接数或饱和 TPS 容量测试。

## 负载结果

| 轮次 | 负载 | 接收结果 | 用途 |
| --- | ---: | --- | --- |
| 单发送端 | test02 30 条 | 30/30，唯一、连续 | 后台接收基线 |
| 双发送端 | test02/test03 各 30 条 | 60/60，唯一、连续 | 未优化并发基线 |
| Profile 双发送端 | 各 20 条 | 40/40，唯一、连续 | 定位同步阶段耗时 |
| Bootstrap 缓存优化后 | 各 20 条 | 40/40，唯一、连续 | 验证优化不损害 ACK/落库语义 |
| 事件年龄诊断包 | 各 10 条 | 20/20，唯一、连续 | 以事件生成时间直接核对及时性 |

所有轮次合计 190 条。真机最终事件游标 `applied=acked=3764`，最后一轮服务端事件序号为 `3726..3764`；服务端只读核对返回 20 个目标事件，test02/test03 的事件交错递增，没有出现游标跳过。

## 及时性结论与测量修正

早期脚本把 `im_messages.updated_at - created_at` 当成投递延迟。复核本地表定义后确认，`updated_at` 会被后续会话历史对账再次覆盖，因此它只能表示“最近一次本地写入年龄”，不能证明消息首次到达时点。相关取证脚本已改名输出为 `createdToLocalUpdateAgeMs`，并明确标注不能作为网络投递延迟。

本轮改用两类有效证据：

1. 在桌面 test01 的既有授权会话上建立长轮询，再由 test02 真实 UI 发送。消息点击后约 419 ms，长轮询返回目标事件；HTTP 200，请求编号 `c7b06e8a-2f81-4610-a471-2e99dd59b8e0`。
2. Profile 包在收到事件页时记录事件年龄、序号范围和各同步阶段耗时，不记录消息正文、账号、Token、设备 ID 或附件地址。最后 20 条并发样本共 17 个批次，事件年龄中位数 244 ms、最大 1,844 ms；仅一个 -12 ms 样本，属于服务端和真机的轻微时钟偏差。

因此，旧报告中的 10–36 秒 `updated_at` 长尾不能继续当作实时投递结论。当前服务端事件流在本轮已能随消息推进并唤醒长轮询；[758](758-mobile-four-device-im-load-background-timing-20260906.md) 记录的旧服务端 `latestSequence=3309` 不推进问题，需视为当时环境证据，不能替代本轮现状。

## 客户端同步热点与修复

未优化 Profile 样本中，真机每个小事件批次都会重新请求 `/api/im/bootstrap`：

- 26 个有效批次、40 个事件；Bootstrap 平均 240.54 ms，最大 402 ms。
- 事件批次整体平均 1,486.27 ms；在两个发送端持续输入时容易形成短时队列。

修复后，事件循环优先读取启动阶段已持久化的账号级 Bootstrap，仅在首次运行或缓存缺失时回退到网络：

- 最后 17 个有效批次、20 个事件；Bootstrap 阶段平均 48.29 ms，最大 71 ms，平均耗时下降约 79.9%。
- 保持顺序不变：事件先在 SQLite 事务中落地并更新设备游标，事务成功后才 ACK；崩溃前未 ACK 仍允许幂等重放。
- ACK 仍有 1,595 ms 的单次长尾，当前不影响完整性，但应在更高负载测试中继续观察服务端 ACK 延迟。

## 资源与稳定性

- 优化后 40 条并发轮次前后，真机 PSS 约增加 17.4 MiB；两个模拟器分别约增加 1.0 MiB 和 2.8 MiB。样本包含消息缓存增长，未观察到崩溃或持续线性增长证据。
- 模拟器软件渲染的 `gfxinfo` 样本帧数过少，不用于宣称真实 UI 帧率；性能判断以真机同步阶段和落库完整性为主。
- 三端均保留登录态，最终包能够在 ARM64 真机和 x86_64 模拟器运行。

## 构建与自动化

- 最终三端诊断 Profile APK：106.1 MB，SHA-256 `5F8C636D2EAA77063F94928D79D09911036A6FB5633F895273886CDFAFB0C5E2`。
- `flutter test`：1396/1396 通过。
- 全量测试曾暴露一个 OA 外部打开失败清理用例与真实文件 I/O 的竞态；产品代码会清理失败文件，测试已改为有界等待真实 I/O，隔离和全量复跑均通过。
- `flutter analyze`：0 error、0 warning；保留 7 条既有大括号风格 info。

## 证据

- [单发送端 30 条发送记录](../test/evidence/im-multidevice-load-20260906/emulator-5554-send-30.json)
- [双发送端 30+30 服务端事件](../test/evidence/im-multidevice-load-20260906/server-events-after-concurrent.json)
- [有效长轮询唤醒](../test/evidence/im-multidevice-load-20260906/long-poll-wakeup-live.json)
- [优化后 test02 真机完整性](../test/evidence/im-multidevice-load-20260906/optimized-physical-receive-test02-20.json)
- [优化后 test03 真机完整性](../test/evidence/im-multidevice-load-20260906/optimized-physical-receive-test03-20.json)
- [最终事件年龄与阶段汇总](../test/evidence/im-multidevice-load-20260906/age-sync-summary.json)
- [最终服务端事件交错顺序](../test/evidence/im-multidevice-load-20260906/age-server-event-order.json)
- [最终全量测试](../test/evidence/im-multidevice-load-20260906/full-flutter-test-final.log)
- [最终静态检查](../test/evidence/im-multidevice-load-20260906/flutter-analyze-final.log)

## 尚未通过或需继续观察

1. Android 厂商推送通道仍未完成；本轮验证的是 App 进程存活时的 HTTP 长轮询及前台/后台同步，不等同于进程被系统杀死后的推送到达。
2. 服务端 ACK 偶发 1.4–1.6 秒长尾；需要协议级虚拟用户配合服务端队列、数据库和网关指标做更高阶容量测试。
3. Windows 当前实际运行文件和卸载注册信息仍为 1.0.87，不能用更新弹窗显示的 1.0.93/1.0.94 代替已安装版本证据；桌面端修复要求见 [762](762-windows-update-path-and-cross-client-sync-prompt-20260906.md)。
