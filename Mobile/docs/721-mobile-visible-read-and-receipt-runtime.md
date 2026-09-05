# 721 真机与模拟器的可见已读、反向消息与回执

2026-09-05 00:20–00:26，Asia/Shanghai。本轮未修改应用源码、未重新构建；使用现有 718 普通 Profile 包。真机 test01、M3 test03，桌面故障现场未操作。结论：本轮移动单聊接收/回执/本地保留通过，完整多端仍因 720 桌面问题未通过。

- M3 在会话外：会话 latest=12、read=7、unread=5，本地消息 1–12 均存在。点击消息列表后红点仍为 5，未因列表出现而提前清零。
- 点击 Test Terminal 01 会话，序号 8–12 实际位于可见区域；随后 read=12、unread=0、Outbox=0。真机的 recipient.read 同步为 12。
- M3 仅通过真实 UI 发送一次 `AI-UAT-20260905-002300-M3-PHONE-RECEIPT`，实际服务端时间为 `2026-09-04T16:22:00.817674Z`，测试标记不是计时依据。
- 新消息序号 13，ID `dd238a45-8f76-4b80-9ebf-608c4c8dd9c2`，clientMessageId `3f99ef56-a217-4849-bbc2-ea48199d501c`；真机无需切换会话，UI 实际显示，read=13。双方数据库 ID 与 clientMessageId 一致，各一条、Outbox=0。M3 recipient.read=13，截图为双勾。
- 仅强制结束并重新启动 M3，未动真机输入框/网络/热点；新登录会话自动恢复 test03。原序号 1–13 的 ID、顺序和 clientMessageId 全部保留，原测试消息仍只有一条，对方回执仍为 13。
- 冷启动期间会话收到其他新消息：消息列表又出现未读 1；再次进入后最终本地 latest/read=15、unread=0。未把这些新增记录当成重复消息，也未读取或记录其正文。
- 本轮只验证近期有效会话冷启动，不推翻 720 中旧 M3 refresh=401 的证据，也不证明长时续期完成。

## 证据

- [打开前红点 5](../test/evidence/mobile-receipts-721/01-unread-before.png)
- [消息可见后](../test/evidence/mobile-receipts-721/02-visible-read.png)
- [真机收到反向消息](../test/evidence/mobile-receipts-721/03-phone-received.png)
- [发送端双勾](../test/evidence/mobile-receipts-721/04-sender-read.png)
- [冷启动前双方元数据](../test/evidence/mobile-receipts-721/05-before-restart.json)
- [冷启动后 M3 元数据](../test/evidence/mobile-receipts-721/06-after-restart.json)

截图已实际查看。M3 使用不同本地时区，显示时间与手机差 8 小时；跨端比较以相同服务端 UTC 时间及消息 ID 为准。历史图片起初加载中，随后截图已成功展示；头像正确加载、同发送人相邻消息按当前分组规则合并头像。

未执行：本轮未证明每条消息是事件通道而非可见会话对账补偿到达；未实测离线推送、ACK 前崩溃、群聊/@我、完整桌面/UI 替换矩阵。无新增自动化测试结果声明，不将历史全量通过数当作本轮执行。
