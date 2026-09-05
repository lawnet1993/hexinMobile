# 719 新版桌面基准下的移动单聊回归与协议缺口

2026-09-05 00:06–00:09，Asia/Shanghai。结论：本轮单聊发送及冷启动持久化检查通过；**不是统一 Push Gateway 或完整双端验收通过**。

后续反例：[720 桌面入站同步缺口](720-desktop-inbound-sync-gap-20260905.md) 已确认手机发送后桌面 UI 与本地缓存缺消息。当前双端同步不通过；不得将下述单端结果当作双端通过。

## 基准与协议发现

- 用户已提供桌面运行界面 v1.0.91 截图，当前账号 test01；不再以旧 EXE 元数据否定更新，也未重复安装桌面端。
- 线上公开管理端入口返回脚本 `/assets/index-glXwUBJD.js`。脚本声明版本管理页面 `ClientVersionManagementView-DPFS-Uwu.js` 和只读发布列表 `GET /api/control-plane/client-versions`，未调用该受保护管理接口，也未登录管理后台或修改版本记录。
- `http://api.sfhkh.com/swagger/v1/swagger.json` 与 `/openapi/v1.json` 都返回 HTTP 200 / text/html，不是可用 JSON 契约。
- 已缓存的 `terminal-1.0.91.exe` 存在，大小 252095283；未执行、提取或再次下载。当前没有浏览器/Windows 控制运行时，不把静态资源查询称为 UI 验收。
- 仓库仍通过 `/api/im/sync/events`、`/api/im/sync/ack` 等处理同步；公开管理端主脚本没有提供统一 Push Gateway 的连接/事件/ACK 契约。已向用户询问新版接口文档或最新客户端源码，未猜测协议、更改同步流程。

## 真机实际操作

- RMX3366，普通 718 Profile APK，SHA256 `8BEA8D5F70FD04F0CAD0A7F554EE40EC8568B92D6367EA6ACC39649E8D5CF50E`。
- test01 打开单聊 Test Terminal 03。对方显示离线，最近上线 09-03 18:03，与用户桌面截图的对象/状态相符；文件页签 1，历史图片和文字正常呈现。
- 仅通过真机 UI 发送一次 `AI-UAT-20260905-000800-MOBILE-D91`。标记是测试标识，真实服务器创建时间为本地 00:07:38，不以标记字符串代替时间证据。
- 手机显示已发送（单勾），并未把离线接收人标成已读。没有代表 test03 回复或切换其他账号。
- 强制关闭手机应用再启动，自动恢复登录；重新进入相同会话，新测试消息仅显示一次，仍为已发送。没有清数据、退出账号或切换手机网络/热点。

## 服务端与 SQLite 只读核对

- 使用现有桌面 test01 会话只读 GET，未通过 API 发送消息；这不证明 Windows 窗口已实时渲染该消息。
- 会话 `2a2ea21f-2ad6-49b3-b3da-407d1e7e4136`，类型 direct。
- 服务端消息 ID `4d277f77-b799-45ac-a1a7-6d6c375ebcc6`，clientMessageId `c1bee507-132e-4e5f-addc-98f5c7581cf5`，sequence 8。
- 服务端创建时间 `2026-09-04T16:07:38.002343Z`；消息 GET HTTP 200，请求编号 `78191808-6a0f-416c-8326-c326277a8ac4`。
- 服务端和本地各有 8 条历史；新消息服务端/本地 ID 相同、clientMessageId 相同，本地状态 sent、Outbox 0。
- 自己的 lastMessageSequence / lastReadSequence 均为 8，unreadCount 0。
- 冷启动前后 8 条历史消息 ID 和顺序保持一致，未多出临时消息；SQLite quick_check=ok。
- 事件 applied / acked 均为 2302；本轮是 ACK 已完成后的冷启动，**没有模拟“落库后、ACK 前”崩溃**。

## 证据及复现

- [发送后真机截图](../test/evidence/im-d91-runtime-719/01-sent.png)、[冷启动后截图](../test/evidence/im-d91-runtime-719/04-cold-chat.png)。
- [服务端消息摘要](../test/evidence/im-d91-runtime-719/02-server-message.json)、[冷启动前本地元数据](../test/evidence/im-d91-runtime-719/03-local-before.json)、[冷启动后元数据](../test/evidence/im-d91-runtime-719/05-local-after.json)、[8 项交叉检查](../test/evidence/im-d91-runtime-719/06-checks.json)。不含令牌、设备 ID、附件地址或非测试消息正文。
- 可复用 `scripts/inspect-desktop-im-uat.ps1 -ConversationId 2a2ea21f-2ad6-49b3-b3da-407d1e7e4136`，以及 `scripts/inspect-device-im-outbox.py --serial dd00d66d --conversation-id 2a2ea21f-2ad6-49b3-b3da-407d1e7e4136 --client-message-id c1bee507-132e-4e5f-addc-98f5c7581cf5 --message-ledger` 做只读复核。
- 脚本新增 `-ListTestDirects`，仅列名称严格匹配 Test Terminal 01–10 的单聊元数据，用于定位当前真实测试会话。

## 未执行

新版 Windows UI 收发、移动接收桌面新消息、M2/D2 替换、统一 Gateway 协议、ACK 前崩溃、多端并发、离线群聊/@我和长时会话到期未在本轮执行。新消息作为测试记录保留，未删除或修改已有消息。
