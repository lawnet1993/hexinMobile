# “我的”与 IM 当前版本运行复核

日期：2026-09-02  
设备：realme RMX3366、Android 16 模拟器  
环境状态：测试服务不可用，使用两个账号各自已有的本地加密投影只读复核

## 结论

- “我的”主页在真机和模拟器上均保持紧凑设置页结构，头像、姓名和部门按账号隔离，没有串号或暴露账号字段。
- 消息列表中的群聊与单聊边界正确：群聊使用群组标识，单聊使用真实成员头像和 Presence 状态。
- 群聊与单聊连续消息均按发送人和五分钟时间窗口合并；头像、昵称只放在消息组首，不在每条消息旁重复。
- 会话热重开直接复用本地窗口。真机 50 ms 截图已显示标题、历史消息、头像和输入区，150 ms 状态稳定；本次采样 2 帧、卡顿帧 0、P99 12 ms。
- 当前运行结果没有发现需要修改 IM 渲染代码的新问题。

## 运行步骤与结果

### 1. “我的”主页：通过

- 真机显示“老王 / 集团总部”，模拟器显示“林川 / 外站”。
- 两端头像、姓名、部门及设置状态未互相串用。
- 内部账号不在主页资料卡重复显示。

证据：

- `test/evidence/profile-main-audit-20260902/01-profile-main-real.png`
- `test/evidence/profile-main-audit-20260902/01-profile-main-emulator.png`

### 2. 消息列表：通过

- 群聊行有明确群组标识；单聊行显示成员头像。
- 群聊和单聊入口、标题及详情没有混用。
- 服务不可用时单聊状态显示“状态未知”，没有使用旧缓存伪造在线。

证据：

- `test/evidence/im-current-audit-20260902/01-messages-current-real.png`
- `test/evidence/im-current-audit-20260902/01-messages-current-emulator.png`

### 3. 群聊消息渲染：通过

- 对方连续消息仅在组首显示一次昵称和头像。
- 自己发送的连续消息同样只在组首保留头像。
- 已读入口保持气泡同行双勾，没有重新出现“回执”文字。

证据：

- `test/evidence/im-current-audit-20260902/02-group-current-real.png`
- `test/evidence/im-current-audit-20260902/02-group-current-emulator.png`

### 4. 单聊消息渲染：通过

- UI 语义树确认同一发送人在连续时间窗口内只创建一个组首头像。
- 时间间隔超过五分钟时重新创建消息组，避免把不连续历史错误合并。
- 临时只读检查过模拟器加密 SQLite 中的发送人和时间序列；检查副本已立即删除，没有保留消息数据库、明文、令牌或设备标识。

证据：

- `test/evidence/im-current-audit-20260902/03-direct-current-real.png`
- `test/evidence/im-current-audit-20260902/03-direct-current-emulator.png`

### 5. 会话热重开：通过

- 50 ms：标题、历史消息、头像和输入区已出现。
- 150 ms：页面完全稳定，无二次空白渲染。
- `dumpsys gfxinfo`：总渲染帧 2，Janky 0，P50/P90/P95/P99 均为 12 ms；Missed Vsync、High input latency、Slow UI thread 和 Frame deadline missed 均为 0。

证据：

- `test/evidence/im-current-audit-20260902/04-direct-hot-reopen-50ms-real.png`
- `test/evidence/im-current-audit-20260902/05-direct-hot-reopen-150ms-real.png`
- `test/evidence/im-current-audit-20260902/direct-hot-reopen-framestats-real.txt`

## 实现边界

- 消息窗口离开页面后保留 30 分钟。
- 最近 32 个会话有界保存已扩展窗口和“历史已到底”状态。
- 历史消息由上滑接近顶部自动加载，不需要手动按钮。
- 列表使用懒构建、稳定消息 Key 和滚动锚点；重复最新消息核对会合并请求。

## 自动化与构建基线

- `flutter analyze`：通过，0 问题。
- `flutter test`：284/284 通过。
- Profile APK SHA-256：`09C7646130BC437C9F3E247FB768306F75960BB7037B2802DF0BC9E108E64904`。
- 同一 APK 已安装真机和 Android 16 模拟器，关键崩溃日志为 0。

## 未完成

测试服务仍不可用，本轮不能创建新消息、验证实时跨端同步、读取最新 Presence 或提交在线已读回执；这些项目继续保留在总体验收矩阵中，不能由本地缓存复核替代。
