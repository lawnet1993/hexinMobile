# 移动端系统通知权限验收

> 日期：2026-09-06  
> 范围：Android 系统通知权限与应用内通知/厂商推送状态分层

## 结论

- Android 13 及以上已声明并按需申请 `POST_NOTIFICATIONS`。
- 登录成功或恢复有效会话进入主 Shell 时，如果权限仍是首次未决定状态，会主动申请一次；拒绝、已允许或不可用时不重复弹出。
- “通知设置”现在分别展示：
  - 应用内通知：通知中心来源与实时同步状态；
  - 系统通知权限：未开启、已关闭、已开启；
  - 系统推送：服务端注册能力和厂商通道状态。
- 首次未授权点击“开启”会显示系统原生授权框。
- 用户拒绝或在系统中关闭后，点击“去设置”会进入当前应用的系统通知设置页；部分厂商 ROM 不支持该页面时回退到应用详情页。
- 从系统设置返回后会重新读取真实权限，不以应用内开关冒充系统权限。
- 厂商推送通道仍明确标记“待接入”，本次没有将其错误判定为完成。

## 通知设置状态表达复验

三台 Android 16 模拟器覆盖安装同一 profile APK 后，登录态均被保留。“我的”页、账号与安全页以及修改密码底部抽屉已做真实 UI 检查：页面不再暴露隧道/TUN 状态，账号与设备信息没有混用，操作控件保持移动端紧凑尺寸。

通知设置原来把“厂商推送通道待接入”和“服务端注册接口已接入”挤在同一行，容易误解为同一个能力。本轮已拆成两个独立状态行：

- `服务端推送注册 / 已接入`：表示客户端已经具备调用服务端注册接口的能力；
- `厂商推送通道 / 待接入`：表示离线厂商 SDK 与令牌通道仍未完成。

改造前后截图：

- `test/evidence/profile-multivm-20260906-083000/emulator-5556-notification-settings.png`
- `test/evidence/profile-multivm-20260906-083000/emulator-5556-notification-settings-fixed.png`
- `test/evidence/profile-multivm-20260906-083000/emulator-5554-account-security.png`
- `test/evidence/profile-multivm-20260906-083000/emulator-5554-password-sheet.png`

## 实机化运行证据

本轮在 Android 16 模拟器 `emulator-5554`、账号 `test02` 上覆盖安装 profile 包并操作真实系统权限：

1. 初始 AppOps 为 `POST_NOTIFICATION: ignore`，应用显示“系统通知：未开启”。
2. 点击“开启”，出现 Android 原生 `Allow 合兴智联 to send you notifications?` 授权框。
3. 允许后 AppOps 为 `allow`，应用立即显示“系统通知：已开启”。
4. 通过系统撤销权限后重启应用，应用显示“系统通知：已关闭 / 去设置”。
5. 点击“去设置”，前台 Activity 为 `Settings$AppNotificationSettingsActivity`，页面显示 `All 合兴智联 notifications`。
6. 恢复权限并返回应用，生命周期恢复时重新查询，页面显示“系统通知：已开启”。

截图：

- `test/evidence/goal-continuation-20260906/emulator-5554-notification-permission-before.png`
- `test/evidence/goal-continuation-20260906/emulator-5554-notification-system-dialog.png`
- `test/evidence/goal-continuation-20260906/emulator-5554-notification-permission-denied.png`
- `test/evidence/goal-continuation-20260906/emulator-5554-notification-system-settings-fixed.png`
- `test/evidence/goal-continuation-20260906/emulator-5554-notification-permission-restored-fixed.png`

## 包与自动化

- profile APK：`build/app/outputs/flutter-apk/app-profile.apk`
- 大小：`111236918` bytes
- 当前 Profile APK SHA-256：`0BBC94F4D56FF1D86A8420909AA9CB46410BC6E325472E0738E51B4D404DA544`。
- 安装覆盖：`emulator-5554`、`emulator-5556`、`emulator-5558` 与物理设备 `dd00d66d` 均安装成功；三模拟器已启动并保留原登录态，物理设备因锁屏未继续操作。
- 定向组件测试：首次授权、拒绝后跳设置、紧凑行高均通过。
- Android 原生契约测试：权限声明、查询、请求、系统设置跳转均通过。
- 全量 Flutter 测试：`1405/1405` 通过。
- `flutter analyze --no-fatal-infos`：`0` error、`0` warning；保留 `7` 条既有花括号风格 info。

## 未完成边界

- 厂商推送 SDK/令牌通道仍待接入，因此本轮只证明系统权限与设置恢复链路，不证明离线厂商通知已经送达。
- 真机锁屏期间的新消息等待 45 秒未落库，显式启动后通过离线补偿在 924 ms 内追平且只落一条；见 [772](772-mobile-locked-device-session-catchup-20260906.md)。这进一步证明“服务端注册已接入”不能替代厂商推送唤醒。
- iOS 已补齐权限查询、申请和跳转设置桥接，但当前 Windows 环境没有 iOS 真机，未做 iOS 运行验收。
- 本轮物理 Android 真机仍处于锁屏，未替用户解锁；同一改造尚待在真机上重复一次系统授权与拒绝恢复操作。
- Shell 自动询问、三模拟器和最新真机安装摘要见 [767](767-mobile-multivm-permission-offline-followup-20260906.md)。
