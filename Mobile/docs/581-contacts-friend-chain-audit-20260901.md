# 581 通讯录与添加好友真机验收

## 结论

本轮通过。通讯录四分类保持真实数据边界，在线状态、头像、单聊和群聊没有混用。“添加好友”已从精确账号查找完成到真实好友申请提交，不再把“允许直接单聊”误当成“已是好友”。

## 环境

- 设备：realme RMX3366，Android 14，1080×2400
- 应用：`com.hexing.zhilian.hexing_terminal_mobile` 1.0.1（Profile）
- APK SHA-256：`1B418CBA9C4BC5212F5BC8945B394038829F569DD2B65EA62AF0C32875DB412C`
- 验收日期：2026-09-01

## 实际验收

1. 组织：当前账号真实显示在线，其他测试成员显示离线；头像正常，无黑色分隔线。
2. 好友：只显示真实好友，提供发消息和修改备注操作。
3. 群聊：只显示真实群会话 `Mobile-Group-20260825`，没有混入单聊联系人。
4. 新朋友：当前无新的入站申请，显示明确空态。
5. 添加好友：精确查找非好友测试成员后显示“申请好友”；点击后服务端成功接收，终端显示“好友申请已发送”。
6. 移动交互：添加好友、联系人操作、修改备注均为紧凑底部抽屉；抽屉覆盖 Shell 底部 Tab，输入框约 34–36dp，软键盘弹出时内容整体上移。

## 修正点

- 主操作由 `canStartDirect` 判断改为 `isFriend` 判断。
- 组织成员允许直接聊天时，仍可从组织通讯录发起单聊，但不会破坏好友关系语义。
- 添加好友和部门选择抽屉改用根导航，不再停留在 Shell 内。
- 添加好友抽屉压缩为 240–290dp，并根据系统键盘 `viewInsets` 上移。

## 证据

- 组织、好友、群聊、新朋友：`docs/device-acceptance/581-contacts-organization.png`、`581-contacts-friends.png`、`581-contacts-groups.png`、`581-contacts-new-friends.png`
- 修正后查找与主操作：`docs/device-acceptance/581-add-friend-keyboard-fixed.png`、`581-add-friend-action-fixed.png`
- 真实提交结果：`docs/device-acceptance/581-add-friend-submitted.png`
- 联系人操作和备注：`docs/device-acceptance/581-friend-actions-sheet.png`、`581-friend-remark-sheet.png`

## 自动化与运行日志

- `flutter analyze`：0 问题。
- `flutter test`：209/209 通过。
- Profile APK 构建、覆盖安装和冷启动成功。
- 清空旧日志后重放通讯录分类、联系人操作和添加好友抽屉：Flutter/Android 关键异常 0 条。

## 未执行

- 未登录申请接收方点击接受；本轮验证范围为移动端发起链路和界面行为。
- 未修改现有好友备注；只打开并取消输入抽屉。
