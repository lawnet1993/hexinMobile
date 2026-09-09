# 777 · “我的”与登录设备信息密度实机审查

> 日期：2026-09-06  
> 结论：移动端“我的”、账户安全、修改密码、通知设置和全部应用的结构符合当前移动端范围；设备摘要的重复平台和中英文混排已修正并在模拟器验证。

## 真实页面检查

- “我的”首页只显示真实姓名、部门、账户与安全、通知设置、登录设备、外观与语言、帮助、关于和退出；普通页面不展示登录账号、设备 ID、网络隧道或站点状态。
- 账号只在“账户与安全”内按需显示；当前设备显示设备名称和操作系统，不显示设备 ID。
- 修改密码采用底部抽屉，三个紧凑密码框分别控制可见性；没有执行密码修改。
- 通知设置明确区分应用内通知、系统通知权限和系统推送；服务端注册为已接入，厂商通道仍显示待接入，没有冒充完成。
- “全部应用”只展示服务端可视化 OA 应用目录：考勤、费用、财务、采购、行政。没有出现移动端不需要的常用站点、网络诊断或隧道开关。

修正前截图：[我的](../test/evidence/profile-alignment-20260906-1330/01-profile.png)、[账户与安全](../test/evidence/profile-alignment-20260906-1330/02-account-security.png)、[修改密码抽屉](../test/evidence/profile-alignment-20260906-1330/03-change-password.png)、[通知设置](../test/evidence/profile-alignment-20260906-1330/05-notification-settings.png)、[全部应用](../test/evidence/profile-alignment-20260906-1330/06-all-apps.png)。

## 本轮修正

- 个人页设备摘要从“Android 模拟器 · android”压缩为“Android 模拟器”。
- 服务端返回的通用名称“Windows device”在展示层规范为“Windows 设备”；服务端原始设备身份不变。
- 平台名统一为 Android、iOS、Windows、macOS、Linux。
- 当设备名称已经包含平台时，副标题不再重复平台，只保留最近活动；真实机型名称不包含平台时仍保留平台信息。

实测结果：[修正后的个人页](../test/evidence/profile-alignment-20260906-1330/07-profile-after-density-fix.png)、[修正后的登录设备](../test/evidence/profile-alignment-20260906-1330/08-login-devices-after-density-fix.png)。

## 回归

- `mobile_device_authorization_test.dart`、`account_security_page_test.dart`、`app_smoke_test.dart`：45/45 通过。
- 定向 `flutter analyze`：0 问题。
- Profile arm64+x64 APK 构建成功，M2/test03 与 M3/test04 均保留数据覆盖安装成功。
- M3 实际登录设备页显示当前 Android 模拟器和四条 Windows 授权记录；没有执行撤销操作。

## 边界

- Windows 窗口控制能力本轮没有暴露可调用入口，因此桌面设置页没有新增 UI 截图；不把旧截图或源码冒充当前桌面观察。
- 模拟器系统时区为 UTC，所以页面时间与宿主机上海时区相差 8 小时；应用使用设备本地时区，真机仍需在正确系统时区下复验。
- 真机处于锁屏/熄屏状态，本轮没有执行覆盖安装或 UI 点击。

