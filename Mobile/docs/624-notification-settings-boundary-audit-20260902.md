# 通知设置与系统推送边界验收

## 结论

- 设置入口与页面标题统一为“通知设置”，不再出现入口和标题名称不一致。
- 页面分为“应用内通知”和“系统推送”两块，避免把通知中心内容、实时同步和操作系统推送混为一个概念。
- 服务不可用时仍展示通知中心来源和同步状态；系统推送单独显示“暂时无法同步推送设置”及重试，不再让整页只剩错误。
- Android 当前没有实际 FCM 或厂商推送服务实现，因此不能宣称系统后台推送已可用。页面保留真实未注册/不可同步状态，没有伪造开关。

## 当前界面

- 应用内通知：通知中心包含消息、审批与公告。
- 同步状态：实时通道不可用时显示“连接恢复后同步”。
- 系统推送：单独承载推送注册、锁屏内容和通道信息；当前离线和加载失败状态都保留紧凑重试行。

## 证据

- 修正前真机：`Mobile/test/evidence/118-notification-settings-before-real.png`
- 修正后真机：`Mobile/test/evidence/119-notification-settings-final-real.png`
- 修正后 Android 16 模拟器：`Mobile/test/evidence/120-notification-settings-final-emulator.png`
- 本轮真机最终状态：`Mobile/test/evidence/profile-audit-20260902/04-notification-final-real.png`
- 本轮 Android 16 模拟器最终状态：`Mobile/test/evidence/profile-audit-20260902/04-notification-final-emulator.png`

## 验证

- 通知相关组件测试：10/10 通过。
- 完整 `flutter test`：280/280 通过。
- `flutter analyze`：通过。
- `flutter build apk --profile`：通过。
- 最新 Profile APK 已覆盖安装到 realme RMX3366 和 Android 16 模拟器。
- 两端重复进入通知设置页后，AndroidRuntime 与 Flutter 关键错误日志均为 0。

## 未完成边界

Android `MainActivity` 已提供推送令牌读取和点击路由桥接，但项目中没有调用 `publishPushToken` 的 FCM/厂商服务，也没有后台消息接收和系统通知展示服务。完成真实系统推送仍需要选择并配置推送提供商、取得平台配置、接入令牌更新和通知展示后，再执行前后台、离线恢复、点击定位及去重验收。
