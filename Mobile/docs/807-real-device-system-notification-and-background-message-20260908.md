# 真机系统通知与后台消息到达验证（2026-09-08）

## 结论

本轮判定为**部分通过**：系统通知权限引导、系统设置跳转、返回状态刷新、有效消息发送和恢复前台后的自动追平通过；应用在后台时没有产生系统通知，因此后台推送仍未通过。当前桌面端功能基准按用户现场确认使用 **v1.0.105**。

## 已通过

- realme 真机初始 `POST_NOTIFICATIONS` 为拒绝状态，移动端“通知设置”正确显示“已关闭”。
- 点击“去设置”能够打开当前应用的系统通知设置页。
- 开启通知权限并返回后，页面立即显示“已开启”。
- 返回后的同步状态曾短暂显示“连接恢复后同步”，随后自动恢复为“实时同步”，没有要求重新登录。
- 页面明确标识“服务端推送能力已接入，厂商推送通道待接入”，没有把厂商通道误报为完成。

## 无效样本与纠正

发送端 Test Terminal 02 向后台中的 Test Terminal 01 发送：

`AI-UAT-NOTIFY-20260908-2045`

复核结果：

1. 发送端截图清楚显示目标文本仍在底部输入框，而不是消息气泡。
2. 强制停止发送端后，只读检查其两套 IM SQLite：目标文本不在 `im_messages` 和 `im_outbox`，与“尚未点击发送”的事实一致。
3. 接收端没有系统通知、列表更新或会话消息不能作为失败证据，因为服务端根本没有收到这次样本。

因此撤回此前关于“发送端假成功”的判断。后台通知与前台追平必须用重新发送、且发送端已经出现消息气泡或持久化记录的有效样本复测。

## 有效后台样本

重新由 Test Terminal 02 向后台中的 Test Terminal 01 发送：

`AI-UAT-NOTIFY-20260908-VALID-01`

结果：

1. 发送端输入框清空，消息进入正式气泡并显示已发送标识，样本成立。
2. 接收端保持后台约 12 秒，通知栏没有出现合兴智联通知，目标文本也不在活动通知记录中。
3. 启动接收端后，无需手动刷新，约 15 秒内在原会话中显示目标消息。
4. 返回会话列表后，Test Terminal 02 行的摘要同步更新为目标消息。

结论：服务端事件及移动端前台补偿同步有效；当前未闭环项集中在应用后台/锁屏时的系统推送通道。由于页面已经明确标记厂商推送通道待接入，本轮不把它误报成移动端完整推送能力已完成。

## 证据

- `Mobile/test/evidence/real-device-main-pages-20260908/notification-settings-denied-current.png`
- `Mobile/test/evidence/real-device-main-pages-20260908/system-notification-settings-opened.png`
- `Mobile/test/evidence/real-device-main-pages-20260908/notification-settings-granted-after-return.png`
- `Mobile/test/evidence/real-device-main-pages-20260908/notification-shade-after-test-message.png`
- `Mobile/test/evidence/real-device-main-pages-20260908/notification-test-sender-state.png`
- `Mobile/test/evidence/real-device-main-pages-20260908/message-chat-after-background-catchup-30s.png`
- `Mobile/test/evidence/real-device-main-pages-20260908/notification-valid-sender-confirmed-ui.png`
- `Mobile/test/evidence/real-device-main-pages-20260908/notification-valid-message-shade.png`
- `Mobile/test/evidence/real-device-main-pages-20260908/notification-valid-recipient-foreground.png`
- `Mobile/test/evidence/real-device-main-pages-20260908/notification-valid-conversation-preview.png`

本地数据库仅作目标消息存在性、状态及 Outbox 核对；未输出账号密钥、Token、Cookie、设备指纹或其他消息内容。

## 后续通过门槛

1. 有效测试消息必须在接收端后台产生系统通知；当前厂商通道未接入，继续标记为未完成。
2. 接入通道后再执行锁屏、Doze、通知点击后先同步再定位消息的真机验证。
3. 保持当前已通过的恢复前台自动追平、会话历史与列表摘要一致性回归。
