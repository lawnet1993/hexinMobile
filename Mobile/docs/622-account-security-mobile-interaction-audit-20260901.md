# 账户与安全移动端交互验收

## 结论

- 账户页不再向普通用户展示内部设备 ID，改为真实设备名称与系统版本。
- 原“已验证·状态未知”改为“已登录·同步中断”，明确区分本地会话仍在与实时服务暂不可用。
- 修改密码不再常驻展开三个输入框；页面只保留“修改登录密码”入口，点击后使用向上展开的底部抽屉。
- 密码框改为 40dp 内的填充式输入，不使用聚焦后悬浮在边框上的标签；三个显隐按钮保持独立。
- 确认按钮保持 118×36dp，三个字段未填写完整时保持禁用；抽屉支持键盘避让和内容滚动。
- 修改成功后客户端保留当前操作会话，只提示其他设备重新登录；不再主动清理当前令牌，符合“除当前操作会话外均失效”的验收规则。
- 请求失败使用抽屉内的单条错误信息，保留三个输入值，并设置 12 秒超时，避免无响应或重复弹出提示。

## 真机与模拟器证据

- 2026-09-02 真机账户页：`Mobile/test/evidence/account-security-audit-20260902/01-account-security-final-real.png`
- 2026-09-02 Android 16 模拟器账户页：`Mobile/test/evidence/account-security-audit-20260902/01-account-security-final-emulator.png`
- 2026-09-02 真机密码抽屉：`Mobile/test/evidence/account-security-audit-20260902/02-change-password-sheet-final-real.png`
- 2026-09-02 Android 16 模拟器密码抽屉：`Mobile/test/evidence/account-security-audit-20260902/02-change-password-sheet-final-emulator.png`
- 真机账户页：`Mobile/test/evidence/114-account-security-final-real.png`
- 真机密码抽屉禁用态：`Mobile/test/evidence/115-change-password-disabled-final-real.png`
- Android 16 模拟器输入聚焦态：`Mobile/test/evidence/117-change-password-keyboard-final-emulator.png`
- 真机断网失败态：`Mobile/test/evidence/106-change-password-offline-error-real.png`

真机显示当前设备 `realme RMX3366 · Android 14`；模拟器显示 `Android 模拟器 · Android 16`。两端账号与设备信息保持各自会话隔离。截图和报告不包含设备 UUID、令牌、密码或设备指纹。

## 自动验证

- `flutter test`：281/281 通过。
- `flutter test test/account_security_page_test.dart`：通过。
- `flutter analyze`：通过。
- `flutter build apk --profile`：通过。
- 最新 profile APK 已覆盖安装到真机和模拟器，SHA-256：`AF6D086E0F98F426966E15E8E66D56996F668D6B4F161ECF27D3FC5F3B87FA40`。
- 清空日志后重复打开账户页、密码抽屉并操作密码显隐，`AndroidRuntime` 与 Flutter 错误日志均为空。

## 未执行项

2026-09-02 复查测试服务仍在 5 秒内无响应，因此没有提交真实密码修改，也没有把任何测试账号强制退出。客户端已通过模拟 `204` 响应验证“当前会话保留”，待服务恢复后再使用两个以上真实会话验证其他桌面端和移动端会话失效。
