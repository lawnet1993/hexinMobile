# 615 · 真机通讯录在线状态与类型边界回归

时间：2026-09-01

## 结果

- realme 真机在当前生产会话中逐页打开组织、好友、群聊和新朋友四个分类。
- 组织页真实显示 3 名成员：当前 `Codex 测试终端` 为在线，另外两名测试成员为离线；状态与服务端成员投影一致，没有根据页面是否打开伪造在线。
- 好友页只显示 1 位真实好友 `测试-管理员测试`，并保留好友专属更多操作；非好友组织成员没有混入。
- 群聊页只显示真实群会话 `Mobile-Group-20260825`，没有把直接联系人当作群聊。
- 新朋友当前没有待处理申请，使用一行弱化空态；四个分类均无黑色整行分隔线或占满屏幕的大卡片。
- 搜索框保持 34dp；组织/好友搜索姓名、部门或终端账号，群聊搜索群名称或消息，提示文案与数据类型一致。

## 验证

- 使用当前最终 Production Profile APK，SHA-256：`EE0FD38F8FB71155235D194B3D10C31A6C3B62695615EF71CE5182C2F8B71FE3`。
- 真机连续切换四个分类后没有应用崩溃或 `E/flutter`。
- 既有自动化继续覆盖进入页面和下拉刷新会重新请求权威 presence、离线时保留最后一次服务端投影，以及 65 人列表自动扩展。

## 数据边界

- 本轮只读切换通讯录分类，没有搜索账号、发送好友申请、接受/拒绝申请、修改备注、发起单聊或进入群聊。

## 证据

- `docs/evidence/612-real-device-oa-regression/21-contacts-organization.png`
- `docs/evidence/612-real-device-oa-regression/22-contacts-friends.png`
- `docs/evidence/612-real-device-oa-regression/23-contacts-groups.png`
- `docs/evidence/612-real-device-oa-regression/24-contacts-new-friends.png`

