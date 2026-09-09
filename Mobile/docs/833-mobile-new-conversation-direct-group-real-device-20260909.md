# 移动端发起会话单聊/群聊真机验收

> 验收日期：2026-09-09  
> 设备：Android 真机  
> 范围：消息页、发起会话抽屉、单聊/群聊边界

## 结论

本轮通过。

- 消息页通过独立筛选展示全部、未读、@我和群组，会话行明确区分单聊与群聊。
- 发起会话使用移动端底部抽屉，不使用桌面弹窗。
- 单聊模式仅选择一位联系人并进入单聊，不显示群名称和多人提交动作。
- 群聊模式显示独立群名称、成员多选框与带人数的创建动作，不会误走单聊链路。
- 联系人展示姓名和部门，未在列表正文中暴露登录账号；账号仍可作为搜索条件使用。
- 键盘展开与关闭时，群聊创建动作均位于可操作区域；关闭键盘后列表可继续滚动，底部动作未被安全区遮挡。

## 真机证据

- `test/evidence/main-tabs-20260909/real-device-messages-current.png`
- `test/evidence/main-tabs-20260909/real-device-new-conversation-current.png`
- `test/evidence/main-tabs-20260909/real-device-new-group-current.png`
- `test/evidence/main-tabs-20260909/real-device-new-group-current.xml`
- `test/evidence/main-tabs-20260909/real-device-new-group-keyboard-closed.png`
- `test/evidence/main-tabs-20260909/real-device-new-group-keyboard-closed.xml`

## 自动化回归

执行：

```text
flutter test test/messages_page_type_test.dart test/new_conversation_keyboard_test.dart test/messages_empty_state_test.dart
```

结果：22/22 通过。

覆盖单聊名称解析、群名称保留、账号搜索但不展示、44dp 顶部入口、单聊/群聊流程隔离、不同屏幕与文字缩放下键盘避让，以及无消息与搜索无结果的不同空状态。

## 尚未宣称通过的边界

- 本轮未真实提交新群聊，避免生成不必要的远端业务数据；创建后的服务端成员关系与跨端到达仍沿用既有 IM 专项证据，不由本轮截图单独证明。
- iOS 真机仍未验收。
