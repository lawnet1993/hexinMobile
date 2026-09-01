# IM 已读状态右置与占位压缩验收

日期：2026-09-01

## 结论

通过。自己发送的消息现在按“气泡 → 双勾 → 自己头像”排列；双勾只保留 16 × 22dp 的可见占位，不显示“回执”文字，也不会单独换行。

## 真实运行证据

- [用户反馈的原始间距](evidence/618-two-device-direct-sync-and-chat-density/01-user-reported-receipt-spacing.png)
- [模拟器真实会话](evidence/618-two-device-direct-sync-and-chat-density/02-emulator-compact-receipt.png)
- [realme 真机真实会话](evidence/618-two-device-direct-sync-and-chat-density/03-real-device-compact-receipt.png)
- [真机已读详情 1/1](evidence/618-two-device-direct-sync-and-chat-density/04-real-device-read-detail.png)
- [调整前后局部同屏对照](evidence/618-two-device-direct-sync-and-chat-density/05-receipt-spacing-before-after.png)

林川与青山的双向测试消息在覆盖安装和强制重启后仍存在。林川端会话列表只显示对方“青山”，青山端只显示对方“林川”，没有把单聊标题拼成两个人名，也没有混入群聊标识。

## 自动化与构建

- 新增几何约束：已读入口必须位于消息气泡右侧，宽度不超过 18dp，并与气泡保持同一视觉行。
- 完整测试：242/242 通过。
- 静态检查：0 issue。
- Profile APK SHA-256：`8A013FB5F8E6187868FCCD29905766BEACACE0AC92D815D486D63F54172DE872`。
- 模拟器与 realme 真机均覆盖安装成功。
- 两台设备当前进程日志关键异常均为 0。

## 验收边界

本报告覆盖已读状态位置、密度、点击详情、真实双向消息持久化和单聊身份显示。群聊并发、离线补偿和大规模历史消息性能仍按总目标继续逐项验收。
