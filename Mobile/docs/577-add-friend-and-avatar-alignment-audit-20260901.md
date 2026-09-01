# 577 添加好友链路与预设头像真机对齐审计

## 结论

- 当前已登录桌面端的“添加好友”采用完整终端账号精确查找，结果只展示一个成员，并由服务端能力决定显示“发消息”或“申请好友”。
- 移动端已移除“点击整行立即进入下一步”的错误交互，改为底部抽屉、单结果卡片和显式操作按钮。
- 动作不再根据 `isFriend` 猜测，而是严格读取 `canStartDirect`：可直接会话时显示“发消息”，否则显示“申请好友”。
- 当前账号即使被接口返回也会被过滤，结果按桌面端显示“未找到该终端账号”，不会创建自聊。
- 搜索完成后输入账号保持可见；成员名称、终端账号、部门和真实在线/离线状态保持在一条紧凑结果卡片内。
- 移动端已识别桌面端 `person/work/badge/support/security` 五种预设头像键，并接入通讯录、好友申请、消息列表、群成员、会话详情、联系人名片、审批人员和个人资料。

## 当前运行桌面端只读核对

| 查询 | 桌面端结果 | 操作 |
| --- | --- | --- |
| `test02` | Test Terminal 02 | 发消息 |
| `test03` | Test Terminal 03 | 发消息 |
| 当前桌面账号 | 未找到该终端账号 | 无 |

桌面端当前账号具备对上述企业成员发起直接会话的能力。核对只执行查找，没有点击“发消息”。

## realme 真机验收

- 设备：realme RMX3366，Android 14，序列号 `dd00d66d`。
- 登录身份：Codex 测试终端。
- 路径：通讯录 → 添加好友 → 输入 `test03` → 查找。
- 真实结果：Test Terminal 03，集团总部，离线，操作为“申请好友”。这说明当前移动账号的服务端 `canStartDirect=false`，与桌面账号权限不同，界面没有再错误显示“发消息”。
- 输入框在结果返回后仍显示 `test03`；预设 `person` 头像已正确显示，不再退化为首字母。
- 未点击“申请好友”，未发送申请、消息或创建新会话，未修改线上业务数据。

## 自动化与构建

- `flutter analyze`：0 问题。
- `flutter test`：207/207 通过。
- 新增覆盖：精确账号载荷、搜索结果显式操作、直接会话/好友申请能力分支、自身账号过滤、搜索文本保持、部门与状态渲染、预设头像与未知键回退。
- Profile APK：`build/app/outputs/flutter-apk/app-profile.apk`。
- SHA-256：`218F0CD076B62B5DEA7E091C42C64D930394233219B3F4CBF5D3BE2066107D51`。
- 真机覆盖安装：成功。

## 证据

- `docs/device-acceptance/577-add-friend-avatar-final.png`
- `docs/device-acceptance/577-add-friend-avatar-final.xml`
- `docs/device-acceptance/577-add-friend-final.png`
- `docs/device-acceptance/577-add-friend-final.xml`
- `docs/device-acceptance/577-add-friend-empty.png`
- `docs/device-acceptance/577-add-friend-empty.xml`

