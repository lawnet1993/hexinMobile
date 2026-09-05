# “我的”与登录设备空态真机验收

## 结论

- “我的”首页继续保持紧凑分组：头像卡不暴露账号，账户安全、通知、网络、设备和通用设置边界清晰。
- 个人资料页在服务不可达时先显示同步中，超时后切换为“当前显示本机资料 + 重新同步”，昵称、签名和头像仍可读取本地账号隔离数据。
- 登录设备无缓存且同步失败时，不再显示误导性的“已授权设备”标题；只保留“暂时无法同步设备”和“重试”。
- 当确实存在服务端或本机设备投影时，“已授权设备”标题仍正常显示，不影响设备列表语义。

## 真机步骤

1. 打开“我的”：通过。头像、姓名和部门正确，未显示登录账号或内部设备 ID。
2. 打开个人资料：通过。同步中和离线本机资料状态转换正确，输入区保持 40/72dp，未修改资料。
3. 打开登录设备：通过。连接中仅显示“正在同步设备”，无虚假的授权列表标题。
4. 等待网络超时：通过。显示“暂时无法同步设备 + 重试”，仍无“已授权设备”标题。
5. Android 16 模拟器复验：通过。空态结构与真机一致。

## 证据

- `Mobile/test/evidence/profile-settings-current-audit-20260902/01-profile-current.png`
- `Mobile/test/evidence/profile-settings-current-audit-20260902/04-profile-edit-stable.png`
- 修正前：`Mobile/test/evidence/profile-settings-current-audit-20260902/03-login-devices-current.png`
- 真机修正后：`Mobile/test/evidence/profile-settings-current-audit-20260902/06-login-devices-offline-final.png`
- 模拟器修正后：`Mobile/test/evidence/profile-settings-current-audit-20260902/07-login-devices-emulator-final.png`

## 验证结果

- 登录设备定向测试：9/9 通过。
- `flutter analyze`：0 问题。
- `flutter test`：302/302 通过。
- 干净 Profile APK：69,428,260 bytes。
- SHA-256：`BAEE66113B49005DCF1F6D72AC4BFEB2B0F3B687410F05B48D031F5A6F419CF8`。
- 已覆盖安装 realme RMX3366 与 Android 16 模拟器。

## 未覆盖边界

- 测试服务仍不可达，无法取得当前服务端已授权设备列表，也未执行撤销授权。
- 服务恢复后需要验证真实多设备列表、当前设备标识、最后活动时间和撤销后的会话失效。
