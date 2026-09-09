# 765 · 多模拟器 IM 并发与及时性追加复验

日期：2026-09-06，Asia/Shanghai。

结论：**服务端前台事件流本轮通过，锁屏真机后台接收未通过。** test02、test03 两台 Android 模拟器通过真实聊天输入框向 test01 发送，服务端对追加的 30 条目标消息返回 30/30 个 `message.created` 事件；一次严格对齐的单条样本从 UI 点击到桌面 test01 长轮询收到匹配事件约 512 ms。与此同时，锁屏真机的本地游标仍停在 3764，新增两路各 0/10，必须在解锁回前台后继续验证追赶。

后续同日已扩展为三模拟器 60 条在线并发、30 条离线补偿和通知首启权限复验；移动端通过，Windows 未打开会话的后台同步与真机锁屏通知仍未通过，见 [767](767-mobile-multivm-permission-offline-followup-20260906.md)。后续样本开始前真机曾在锁屏状态追到 3897，但新增单条锁屏消息后仍停在 3897，不能继续沿用本页 3764 作为当前游标。

## 拓扑与资源边界

- 发送端：`emulator-5554`（test02）、`emulator-5556`（test03），均为当前 Profile 包和真实 UI。
- 接收核对：Windows 当前 test01 已有授权会话的只读事件流；realme RMX3366 真机 test01 的只读 SQLite 快照。
- 本轮开始时宿主机 31.73 GB 内存只剩约 3.55 GB；两个 QEMU 工作集约 3.44 GB 和 3.45 GB。此时再启动完整 AVD 会进入换页区，因此没有重复启动第三台模拟器。
- 之前已完成三模拟器加一真机的 90 条测试，见 [758](758-mobile-four-device-im-load-background-timing-20260906.md)。本轮不把宿主机内存压力伪装成客户端或服务端延迟。

## 单条有效唤醒

- 会话：test02 → test01 单聊，固定会话 ID 与事件载荷一致。
- 长轮询开始后 14.456 ms 执行真实发送按钮点击；526.428 ms 时收到目标事件，换算 UI 点击到事件返回约 **511.972 ms**。
- HTTP 200，请求编号 `45249e29-ad0f-4742-99cb-4e2d5ac0c2ed`；返回 1 个事件、匹配 1 个事件，服务端游标从 3764 推进到 3802。
- 前两次探针分别在 14.579 s 和 6.671 s 返回空事件且游标不变。第一次因软键盘弹起后测试脚本点击了旧坐标，文本仍在输入框；第二次没有触发消息。两次只证明服务端存在空唤醒，不能计入消息投递延迟。

## 两模拟器真实 UI 突发

- test02 先单路发送 10 条，随后 test02/test03 并行各发送 10 条；所有测试内容均使用 `AI-UAT-` 前缀。
- 服务端从游标 3802 读取到目标事件 30/30，最终游标 3871。
- test02 单路 10 条：事件序号 3804..3822。
- test02 并发 10 条：事件序号 3833..3863。
- test03 并发 10 条：事件序号 3835..3871。
- 两个并发发送端的事件序号交错推进，没有出现整路缺失。UI 工作器均确认第 10 条可见、输入框已清空。
- 压测后最终 Profile 包已保留数据覆盖安装到两台模拟器和真机；test02/test03 登录态均保留并回到工作台。包 SHA-256 为 `606A464D4CA1F23CFE90CE9F8025EF3BC07C14553004CBD2FA75851F624344E3`。

## 锁屏真机边界

- 服务端已经存在两路并发事件后，真机 test01 的一致性只读快照仍为 `applied=acked=3764`。
- 对本轮 test02/test03 两个会话分别核对，均为 0/10；SQLite `quick_check=ok`、Outbox 为 0。
- 真机当时处于系统锁屏，不能据此判定前台同步回归；但它足以证明“锁屏/进程不可前台时及时接收”当前没有通过。
- 后续必须解锁并回到 App，验证游标追到至少 3871、两路各 10/10、无重复且会话序号连续。厂商推送仍只标记为未完成，不能用前台 HTTP 长轮询替代。

## 第三台模拟器与同账号替换

- 最终测试和构建结束、停止本项目 Gradle daemon 后，宿主机可用内存从低位恢复到 7.34 GB；随后启动 E 盘 `SecureAccess_UAT_M3` 无头模拟器并安装同一最终 Profile 包。
- 三个 QEMU 工作集约 3.38 GB、3.44 GB、3.06 GB，新增实例运行后宿主机仍有约 4.07 GB 可用内存，没有进入上一轮的 0.57 GB 换页区。
- 第三台使用系统安全存储中已有的 test03 凭据重新登录后，原 `emulator-5556` 在下一次心跳收到 `409 session_replaced` 并回到登录页；原设备重新登录后，第三台也收到替换并退出。两次均只出现一次终止提示。
- 该结果验证了不同移动安装 ID 的同账号互斥。桌面当前是 test01，不是同账号 test03，因此本轮不能把它写成“同账号桌面保持在线”的证据。
- 因第三台保存的是 test03，而不是独立 test04，本轮没有让同一账号作为两个并发发送端。完成双向替换验收后仅关闭本轮新增的无头实例，可用内存恢复到 7.42 GB；原两台模拟器和真机保持连接。

## 证据

- [单条有效长轮询](../test/evidence/multi-device-latency-20260906/im-long-poll-t02-to-t01-03.json)
- [第一次空唤醒](../test/evidence/multi-device-latency-20260906/im-long-poll-t02-to-t01-01.json)
- [第二次空唤醒](../test/evidence/multi-device-latency-20260906/im-long-poll-t02-to-t01-02.json)
- [test02 并发发送日志](../test/evidence/multi-device-latency-20260906/burst-lat3-t02-10.json)
- [test03 并发发送日志](../test/evidence/multi-device-latency-20260906/burst-lat3-t03-10.json)
- [服务端 30 条事件顺序](../test/evidence/multi-device-latency-20260906/burst-server-order.json)
- [真机 test02 未追赶快照](../test/evidence/multi-device-latency-20260906/physical-lat3-t02.json)
- [真机 test03 未追赶快照](../test/evidence/multi-device-latency-20260906/physical-lat3-t03.json)
- [原 test03 被第三台替换](../test/evidence/multi-device-latency-20260906/emulator-5556-session-replace.xml)
- [第三台被原 test03 反向替换](../test/evidence/multi-device-latency-20260906/emulator-5558-session-reverse3.xml)
