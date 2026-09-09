# 移动端“我的”、账户安全与通知设置真机验收

> 验收日期：2026-09-09  
> 设备：Android 真机  
> 账号：测试账号（报告不记录密码、令牌或完整设备标识）

## 结论

本轮范围通过。

- “我的”保持移动端两级信息结构，入口包括账户与安全、通知设置、登录设备、外观与语言、帮助反馈和关于；未展示移动端不需要的站点、隧道或“网络与安全”入口。
- 个人卡片只展示姓名与部门，不在主页暴露登录账号。
- 账户安全页仅在账户本人范围展示账号，当前设备显示真实机型与 Android 平台；不展示完整设备 ID、指纹或令牌。
- 登录状态显示为“已登录”，没有把 TUN、站点或瞬时同步探测结果混入登录状态。
- 登录设备页把当前 Android 设备与 Windows 设备分开，当前设备不可撤销，其他设备提供独立撤销操作；页面不展示完整设备 ID。
- 通知设置明确区分应用内通知中心、事件同步、Android 系统通知权限和推送通道状态。
- 服务端推送注册显示已接入，厂商推送通道保持“待接入”，没有将未完成能力标记为完成。

## 真机证据

- `test/evidence/main-tabs-20260909/real-device-profile-current.png`
- `test/evidence/main-tabs-20260909/real-device-profile-current.xml`
- `test/evidence/main-tabs-20260909/real-device-account-security-recheck.png`
- `test/evidence/main-tabs-20260909/real-device-account-security-recheck.xml`
- `test/evidence/main-tabs-20260909/real-device-notification-settings-current.png`
- `test/evidence/main-tabs-20260909/real-device-notification-settings-current.xml`
- `test/evidence/main-tabs-20260909/real-device-login-devices-current.png`
- `test/evidence/main-tabs-20260909/real-device-login-devices-current.xml`

## 自动化回归

```text
flutter test test/app_smoke_test.dart
```

结果：28/28 通过。

```text
flutter test test/account_security_page_test.dart test/mobile_device_authorization_test.dart test/password_change_safety_test.dart
```

结果：28/28 通过。

## 尚未宣称通过的边界

- 本轮没有执行设备撤销，避免主动使正在使用的 Windows 测试会话失效。
- 厂商推送通道仍明确为未完成；服务端注册成功不等于后台/Doze 场景下的最终厂商推送验收。
- iOS 真机尚未验收。
