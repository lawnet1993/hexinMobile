# 837 · 通讯录进入会话与头像聚合真机复验

时间：2026-09-09（Asia/Shanghai）  
设备：realme Android 真机  
客户端：当前 Profile 构建

## 结论

- 通讯录默认只展示组织；展开公司后才加载成员列表。
- 联系人行不再额外展示聊天图标，点击头像即可进入单聊。
- 从联系人头像进入 Test Terminal 02 单聊，250 ms 取证时已完成页面切换；本次 `gfxinfo` 样本共 2 帧、0 卡顿帧、主要分位耗时 13 ms。
- 修复单聊历史数据因跨设备旧发送者 ID 不同而重复显示头像的问题：同一视觉方向、同一天且相隔不超过 5 分钟的连续消息合并为一组，头像只放在第一条；群聊继续按精确发送者 ID 聚合。
- Profile APK 已覆盖安装且保留登录态；真机复验显示 18:15 首条保留头像，18:17、18:18 连续消息不再重复头像。
- 定向测试 99/99 通过，全量测试 1422/1422 通过，相关静态检查 0 issue。

## 证据

- `Mobile/test/evidence/main-tabs-20260909/real-device-contacts-default-current.png`
- `Mobile/test/evidence/main-tabs-20260909/real-device-contacts-company-expanded-current.png`
- `Mobile/test/evidence/main-tabs-20260909/real-device-contact-to-chat-250ms.png`
- `Mobile/test/evidence/main-tabs-20260909/real-device-contact-to-chat-gfxinfo.txt`
- `Mobile/test/evidence/main-tabs-20260909/real-device-direct-avatar-merged-fixed.png`

## 边界

- 这是当前 Android 真机的联系人、导航与头像聚合证据，不替代 Windows v1.0.105 可见窗口、iOS 真机或服务端多设备长尾验收。
