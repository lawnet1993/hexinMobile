# 移动端通知中心与系统通知语义区分（2026-09-06）

## 结论

首页右上角入口已明确命名为“通知中心”，与“我的 → 通知设置”中的 Android“系统通知”区分。改动只影响提示和无障碍语义，不增加可见说明文字，不改变图标、布局和 44×44 逻辑像素点击热区。

当前 Profile APK 已覆盖安装到四台 AVD；在 `emulator-5556` 真实操作通知页面，并对三台群聊成员数据库和四台登录态做安装后复核：

- 首页铃铛语义为“通知中心”，点击后进入标题为“通知中心”的应用内消息、审批和公告列表。
- “我的 → 通知设置”仍明确显示“系统通知权限 / 系统通知 / 已开启”。
- 通知设置同时显示“通知中心 / 消息、审批与公告”，两个概念和入口职责没有混用。
- 首页截图与改动前保持相同信息密度，铃铛、角标和审批区域没有扩大。
- 四台均未回到登录页；三台群聊成员仍完整保留 324 条、序号 1..324、无重复、Outbox 为 0、SQLite 完整。

## 验证

- `flutter test test/workbench_action_size_test.dart`：2/2 通过。
- 完整 `flutter test`：1406/1406 通过。
- `flutter analyze`：0 error、0 warning；仅 7 条既有花括号风格 info。
- `flutter build apk --profile`：通过。
- APK SHA-256：`1DB548D88E0979009D3F94ABAB119F0AED7846EAD85DC61BFAD6F7A320BBA4B9`。
- 真机语义树中的首页按钮：`content-desc="通知中心"`、可点击，边界约为 44×44 逻辑像素。

## 证据

- [首页当前截图](../test/evidence/notification-center-semantics-20260906-1810/workbench.png)
- [首页当前语义树](../test/evidence/notification-center-semantics-20260906-1810/workbench.xml)
- [通知中心页面截图](../test/evidence/notification-center-semantics-20260906-1810/notification-center.png)
- [通知中心页面语义树](../test/evidence/notification-center-semantics-20260906-1810/notification-center.xml)
- [系统通知设置截图](../test/evidence/notification-center-semantics-20260906-1810/system-notification-settings.png)
- [系统通知设置语义树](../test/evidence/notification-center-semantics-20260906-1810/system-notification-settings.xml)
- [语义区分摘要](../test/evidence/notification-center-semantics-20260906-1810/semantic-distinction.json)
- [四 AVD 当前包与数据保留摘要](../test/evidence/notification-center-semantics-20260906-1810/four-avd-current-apk-preservation.json)
