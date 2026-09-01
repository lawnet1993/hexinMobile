# 603 · 通讯录自动扩展与分类实操

时间：2026-09-01

## 结果

- 组织和好友列表移除“加载更多（已显示/总数）”按钮。
- 保留 30 人窗口化构建，距底部 240dp 时自动扩展下一批 30 人；短列表不足一屏时自动补齐。
- 搜索、切换组织/好友/群聊/新朋友和选择部门时重置联系人窗口并回到顶部，避免复用旧分类位置。
- 没有改写成员在线状态：在线点、在线文本和最近上线时间继续使用服务端 `ImMember` 投影。
- 群聊仍只读取群会话，组织/好友仍只读取成员，未混合两类数据。

## 自动化

- 新增 65 人组织用例：第 65 人首屏不构建，连续上滑后自动出现，尾部提示消失，全程没有“加载更多”。
- `app_smoke_test.dart`：18/18 通过。
- 全量测试：224/224 通过。
- `flutter analyze`：0 项问题。

## 模拟器实操

- 设备：Android 模拟器，1080×2400，隔离 Demo 配置。
- 实际打开组织页，确认四分类、部门树、在线点、在线文字和最近上线时间；UI 树中没有“加载更多”。
- 实际切换好友和群聊：好友页有真实成员且没有群名；群聊页有真实群名且没有直接联系人姓名。
- 应用进程关键错误计数为 0；Debug 首启跳帧不作为性能通过证据。

证据：

- `docs/evidence/603-contacts-auto-window/01-organization.png`
- `docs/evidence/603-contacts-auto-window/01-organization.xml`
- `docs/evidence/603-contacts-auto-window/02-friends.png`
- `docs/evidence/603-contacts-auto-window/02-friends.xml`
- `docs/evidence/603-contacts-auto-window/03-groups.png`
- `docs/evidence/603-contacts-auto-window/03-groups.xml`

## 构建与真机边界

- Production Profile APK：79,660,326 bytes。
- SHA-256：`4147886702CDFBEC580A6E36641740ABE9DFC45A39C8980CB82B6C487AC5DC7F`。
- 已覆盖安装到 realme 真机，设备端 APK 哈希一致。
- 真机仍处于系统锁屏：`Keyguard showing=true / InputRestricted=true`。未绕过锁屏，解锁后需要补真实大通讯录上滑和在线状态刷新复验。
- 群管理的禁言、入群申请、管理员和操作记录页仍有手动分页入口，留在下一轮处理。
