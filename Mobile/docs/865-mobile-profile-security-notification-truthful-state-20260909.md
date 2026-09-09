# 865 · 我的、账户安全与通知状态真实性复验

时间：2026-09-09（Asia/Shanghai）  
设备：Android 16 模拟器 `emulator-5556`

## 结论

- “我的”只保留个人资料、账户与安全、通知设置、登录设备、外观与语言、帮助、关于和退出登录，没有重新暴露仅供站点使用的隧道或“网络与安全”。
- 账户与安全页只展示账号、当前移动设备及登录状态，不展示完整设备 ID、设备指纹、Token 或隧道状态。
- 修改密码使用底部抽屉；三个密码框物理高度 105 px（当前 3x 密度下约 35 dp），确认按钮约 32 dp。键盘弹出后抽屉整体上移，三个输入框、说明和确认按钮仍在可见区域。
- 修改密码最终提交没有执行，未修改测试账号数据。
- 通知设置把前台事件长轮询显示为“应用内实时同步”，不再笼统显示“实时同步”；厂商推送仍明确为“待接入”，避免把尚未通过的锁屏/后台通知冒充为已完成。
- Android 16 模拟器真实撤销系统通知权限后，页面显示“已关闭”和紧凑的“去设置”；应用内同步仍独立显示正常。点击后准确进入合兴智联的系统通知设置页。恢复权限并重启应用后页面自动回到“已开启”，登录态没有丢失。
- 追加按真实用户路径验证：在系统通知设置页直接打开总开关并返回应用，不重启进程，生命周期恢复后页面立即由“已关闭”刷新为“已开启”；包权限同时确认 `POST_NOTIFICATIONS granted=true`。
- 追加前台断网/恢复：同时关闭模拟器 Wi-Fi 与移动数据后，通知页只将同步状态改为“连接恢复后同步”，系统通知权限仍显示“已开启”，登录态没有失效；恢复网络约 12 秒后自动回到“应用内实时同步”。

## 验证

- 通知设置定向用例：6/6 通过。
- 修改密码抽屉、账户安全与通知页面既有覆盖继续纳入全量回归。
- 当前全量 Flutter 回归：1435/1435 通过。
- `flutter analyze`：0 issue。
- Profile APK SHA-256：`DC632549F707A61DAB1434004D5583F9ED2A506AAF31F7F3BADEE70B2643310C`。
- APK 已覆盖安装至 3 台 Android 模拟器和 1 台 realme 真机。

## 截图

- `test/evidence/profile-current-20260909.png`
- `test/evidence/account-security-current-20260909.png`
- `test/evidence/change-password-current-20260909.png`
- `test/evidence/change-password-keyboard-20260909.png`
- `test/evidence/notification-settings-honest-sync-20260909.png`
- `test/evidence/notification-permission-denied-20260909.png`
- `test/evidence/notification-system-settings-20260909.png`
- `test/evidence/notification-permission-restored-20260909.png`
- `test/evidence/notification-permission-return-refresh-20260909.png`
- `test/evidence/notification-offline-20260909.png`
- `test/evidence/notification-online-restored-20260909.png`

## 未通过边界

- realme 真机仍处于锁屏/Doze，本轮未绕过锁屏重复操作这些页面。
- 厂商推送通道、锁屏通知和 Doze 后通知点击定位仍未通过。
- iOS Keychain、通知权限、键盘和 VoiceOver 尚未真机验收。
