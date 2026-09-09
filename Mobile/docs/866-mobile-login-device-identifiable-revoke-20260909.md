# 866 · 移动端同名登录设备可识别撤销验证

时间：2026-09-09（Asia/Shanghai）  
设备：Android 16 模拟器 `emulator-5556`  
账号：Test Terminal 03

## 结论

通过。登录设备页存在三个显示名称相同的 Windows 历史设备时，撤销确认不再只显示设备名称，而会同时显示对应的最近活动时间。用户可以在不暴露完整设备 ID 的前提下确认具体目标。

本次只打开并取消确认抽屉，没有调用撤销接口，也没有改变任何现有桌面会话。

## 真实页面证据

- 当前 Android 设备显示“当前”，没有撤销入口。
- 三个 Windows 设备分别显示不同的最近活动时间。
- 点击第一条 Windows 设备的“撤销”后，确认内容为“设备名称 + 最近活动时间 + 重新登录影响”；确认内容与列表统一显示“Windows 设备”，不再回退为服务端原始英文名称 `Windows device`。
- 完整设备 ID 未出现在列表、确认内容或截图中。
- 最终构建截图：[login-device-revoke-identifiable-current-20260909.png](../test/evidence/login-device-revoke-identifiable-current-20260909.png)

## 自动化覆盖

- `mobile_device_authorization_test.dart` 新增同名设备撤销识别用例。
- 专项测试：10/10 通过。
- 最终构建对应代码的全量 Flutter 测试：1436/1436 通过，耗时约 1 分 15 秒。
- `flutter analyze`：0 issue。

## 安装一致性

- Profile APK 已覆盖安装到 `dd00d66d`、`emulator-5554`、`emulator-5556`、`emulator-5560`，四台均返回 `Success`。
- 当时验证 APK SHA-256：`18422DD9AE29F5B5A9CDAEA2B319FC552FD469FD48100DAF2608D56E7019986C`；后续上传识别改造产生的新基线见 [869](869-mobile-extensionless-image-local-processing-20260909.md)。

## 尚未声明通过

- 本次没有真实撤销 Windows 会话；该操作会改变用户现有登录状态，需要独立安排多端验收。
- M2 替换 M1、改密后的多会话失效仍需真实多端证据。
