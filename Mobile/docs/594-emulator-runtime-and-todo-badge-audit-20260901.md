# 594 模拟器真实交互与待办角标修复

## 当前结论

已在 1080×2400、420 dpi Android 模拟器上安装隔离的 Demo Profile 包并进行真实点击、长按、返回、页面跳转、截图和日志检查。Demo 模式不使用线上账号，也不修改线上数据。

本轮发现并修复一个真实运行问题：待办页“待我处理”为 4 条，但底部待办角标仅统计可处理审批，因此显示 1。现在底部角标统一统计未完成任务与可处理审批，页面和底栏都显示 4。

## 实际操作覆盖

- 工作台：公告、常用应用、审批摘要和五栏底部导航正常；未显示移动端不可用站点或空日程。
- 消息：首页列表明确标识群聊；单聊展示对方真实在线状态。
- 群聊：3 位成员、3 人在线；聊天/文件边界正常；提及成员抽屉展示真实成员和在线点。
- 消息操作：长按群消息显示群置顶；长按单聊消息不显示群置顶。
- 转发：目标抽屉明确标识群聊/单聊，未选择目标。
- 单聊：文件、图片、视频与链接均按各自类型渲染；视频只有播放信息，不重复显示文件名。
- 通讯录：组织、好友、群聊、新朋友分类分离；无黑色分隔线；真实在线和最近上线状态可见。
- 通讯录抽屉：部门选择和添加好友均为紧凑上拉抽屉；未输入账号、未发送好友申请。
- 待办：待处理任务和审批统一列表；新建选择与新建待办编辑器为紧凑上拉抽屉；未创建数据。
- 清空日志后未发现 `FATAL EXCEPTION`、`E/flutter` 或未处理异常。

## 关键证据

- [工作台](evidence/594-emulator-runtime/01-workbench.png)
- [消息列表](evidence/594-emulator-runtime/02-messages.png)
- [群聊](evidence/594-emulator-runtime/03-group-chat.png)
- [提及成员](evidence/594-emulator-runtime/04-mention-picker.png)
- [群消息操作](evidence/594-emulator-runtime/05-group-message-actions.png)
- [转发目标](evidence/594-emulator-runtime/06-forward-targets.png)
- [单聊及媒体渲染](evidence/594-emulator-runtime/07-direct-chat.png)
- [单聊消息操作](evidence/594-emulator-runtime/08-direct-message-actions.png)
- [通讯录与在线状态](evidence/594-emulator-runtime/09-contacts.png)
- [部门选择](evidence/594-emulator-runtime/10-department-picker.png)
- [添加好友](evidence/594-emulator-runtime/11-add-friend-sheet.png)
- [修复前待办角标不一致](evidence/594-emulator-runtime/12-todos.png)
- [修复后工作台底栏角标](evidence/594-emulator-runtime/13-workbench-badge-fixed.png)
- [修复后待办页角标一致](evidence/594-emulator-runtime/14-todos-badge-fixed.png)
- [新建入口](evidence/594-emulator-runtime/15-todo-create-choice.png)
- [新建待办编辑器](evidence/594-emulator-runtime/16-todo-editor.png)

每张 PNG 均有同名 XML 层级文件，可复核可点击元素和控件边界。

## 验证结果

| 项目 | 结果 |
| --- | --- |
| 模拟器真实交互 | 16 组截图/XML 证据 |
| 完整自动化 | 212/212 通过 |
| Golden | 12/12 通过 |
| 静态检查 | `flutter analyze`，0 个问题 |
| 生产 Profile APK | 构建成功，64.0 MB |
| 生产 APK SHA-256 | `873151EE4FED0CD80E5EF8779FD96D2E4494366DCAA7FBAEE7CD83F2302646B1` |
| realme 覆盖安装 | `adb install -r` 成功 |
| 真机状态 | `Keyguard showing=true`、`mInputRestricted=true` |

## 未完成项

生产配置包已经覆盖安装到 realme 真机，但真机仍被系统锁屏限制。解锁后还需在真实账号数据上重复关键只读链路并采集真机截图与日志；默认不发送消息、不提交审批、不添加好友。
