# 通知中心相对时间真机验收

## 结论

- 通知中心与消息列表已共用同一移动端时间格式器，不再分别维护日期规则。
- 列表右侧统一为：今天显示 `HH:mm`、昨天显示“昨天”、本周显示“周一…周日”、同年更早显示 `MM/dd`、跨年显示 `yyyy/MM/dd`。
- 通知正文中的业务日期保持原文，例如考勤摘要仍显示 `2026-09-01`，没有被列表时间格式错误替换。
- 群聊、单聊、审批和考勤仍使用各自图标与类型标签，未因本次重构混线。

## 真机步骤

1. 覆盖安装最新 Profile APK 并冷启动：通过。
2. 从工作台点击通知入口：通过，恢复账号隔离的本地通知投影。
3. 核对 2026-09-01 通知：通过，右侧显示“昨天”。
4. 核对 2026-08-31 通知：通过，右侧显示“周一”。
5. 核对未读点、类型标签和正文：通过，布局无挤压，业务日期未改变。

## 证据

- 修正前：`Mobile/test/evidence/notification-time-audit-20260902/01-notification-current.png`
- 修正后：`Mobile/test/evidence/notification-time-audit-20260902/02-notification-relative-time-final.png`
- Android 16 模拟器覆盖安装与启动：`Mobile/test/evidence/notification-time-audit-20260902/03-emulator-post-install.png`
- 同目录 XML 保存可访问性节点和时间文本。

## 验证结果

- `flutter test test/messages_page_type_test.dart`：9/9 通过。
- 通知中心定向用例：1/1 通过。
- `flutter analyze`：0 问题。
- `flutter test`：301/301 通过。
- 干净 Profile APK：69,428,260 bytes。
- SHA-256：`88A58101245B4DFFC4E647FD2B7F3015C78CC033B17BB89E2B4D8AB3A5726745`。
- 已覆盖安装 realme RMX3366 与 Android 16 模拟器。

## 未覆盖边界

- 测试服务仍不可达，本轮使用既有账号隔离的 SQLite 通知投影完成视觉与交互验收。
- 服务恢复后仍需验证当天实时新通知的 `HH:mm`、正式推送唤醒同步和跨端已读。
