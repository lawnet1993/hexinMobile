# 移动端“我的”与个人资料离线验收

## 结论

- “我的”首页移除无业务价值的自状态文案；实时通道不可用时不再展示“状态未知”。
- 设置入口将“消息通知”明确为“通知设置”，避免与 OA 通知列表混淆。
- 个人资料页改为缓存优先：进入后立即展示当前成员的本地资料，远端同步只占用 34dp 紧凑状态行。
- 服务不可达时保留头像、姓名、账号等本地信息，并提供重试；编辑、头像上传和保存保持禁用，避免用不完整缓存覆盖服务端资料。
- 远端资料请求增加 5 秒页面级超时，不再出现整页无限转圈。

## 真机证据

- `Mobile/test/evidence/76-profile-home-after-real.png`
- `Mobile/test/evidence/77-profile-edit-syncing-real.png`
- `Mobile/test/evidence/79-profile-edit-offline-final-real.png`

真机：realme RMX3366。测试时 `43.198.199.162:80` 连接超时，以上证据覆盖真实断网/服务不可达路径。

## 模拟器交叉验证

- `Mobile/test/evidence/82-emulator-profile-home.png`
- `Mobile/test/evidence/83-emulator-profile-offline.png`

模拟器为 1080×2400、420dpi。真机缓存身份为“老王 / 集团总部”，模拟器缓存身份为“林川 / 外站”；两端头像、姓名、部门和账号均保持各自账户作用域，没有串用另一个账号的数据。模拟器当前进程保持存活，清空日志后重新进入“我的”和个人资料页，`AndroidRuntime` 与 Flutter 错误日志均为空。

## 自动验证

- `flutter analyze`：通过。
- `flutter test test/profile_edit_page_test.dart test/account_security_page_test.dart`：通过。
- `flutter test test/design_golden_test.dart --update-goldens --plain-name "09-profile matches the approved mobile composition"`：通过并更新视觉基准。
- `flutter build apk --profile`：通过并安装真机。

发布构建未执行成功：项目要求外部注入构件签名公钥；本次未输出、猜测或写入任何签名材料，改用 profile 包完成真机验收。
