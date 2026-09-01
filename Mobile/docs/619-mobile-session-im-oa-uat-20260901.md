# 移动端会话、IM 与 OA 真机验收记录（2026-09-01）

## 结论

当前结论为**部分通过**。

- 最新 profile APK 已在 realme RMX3366 真机和 Android 16 模拟器覆盖安装并稳定运行。
- `laowang` 已在真机登录，跨过多个 30 秒心跳周期后仍保持工作台状态。
- 同一账号在 M2 登录后，M1 立即退出到登录页；M1 恢复登录后，M2 在一个心跳周期内退出，移动端会话互斥已取得双向真实证据。
- IM 移动端发送、服务端确认、临时消息原位替换、本地去重、双设备实时到达和跨端已读均已获得真实证据。
- OA 请假申请已真实提交，并完成当前用户的会签任务；流程保持“审批中”，没有错误提示整条流程已通过。
- 自动化测试 268/268 通过，`flutter analyze --fatal-infos` 通过。
- 桌面端进程仍在响应，但其 IM/OA 实时连接持续处于传输失败重试，Windows 到测试环境的 HTTP 与 gRPC 端口当前均超时；因此 D1 当前并非可用在线状态，桌面回复与跨端已读清零不能判定通过。

## 环境与产物

- 测试时间：2026-09-01 18:01–22:16（Asia/Shanghai）
- 控制面：线上测试环境
- 移动设备 M1：realme RMX3366，账号 `laowang`（老王，集团总部）
- 移动设备 M2：Android 16 模拟器，先使用林川验证双端消息，后切换为 `laowang` 验证同账号会话互斥
- APK：`build/app/outputs/flutter-apk/app-profile.apk`
- APK SHA-256：`0D02B8C72E5E1DE008B3AD01027B8E546B8CE9A777DADDB2B32D4F3F817882CC`
- APK 大小：78,480,678 bytes
- 证据目录：`docs/evidence/619-mobile-protocol-upgrade-20260901`

报告与证据中未记录密码、Token、Cookie、设备 UUID、设备指纹或附件私有地址。

## 本轮修正

### 设备身份与心跳

首次真机登录出现“登录已失效或已到期”。无凭据连通性检查显示主机和真机均能访问测试服务器，应用进程 PID 未变化，系统 crash 缓冲区为空，因此排除断网和崩溃。

根因是移动端把稳定安装 UUID 直接当成了后续接口的鉴权设备记录 ID，而线上服务与桌面端都要求使用登录响应中的 `device.id`。现已拆分：

- 稳定安装 ID：安全存储、登录请求、账号+设备 IM 游标隔离。
- 服务端设备记录 ID：鉴权请求头、心跳、设备授权、隧道和推送接口。

修正后 `laowang` 登录成功，并跨过多个心跳周期保持在线。

### 会话与 IM 协议

- 登录请求固定 `clientPlatform=mobile`，携带系统、设备、指纹和版本字段。
- 登录、恢复登录、前台恢复立即心跳，之后每 30 秒心跳。
- 401 清理会话，409 `session_replaced` 停止同步并一次性提示；网络错误和 5xx 仅重试。
- IM 游标按账号+稳定安装 ID 隔离；事件先事务落库和更新游标，再 ACK。
- 500 条拉满时立即继续；重复事件、ACK 前崩溃重放和当前账号发送事件均按幂等逻辑处理。
- 已读只在消息真实进入可见区域后上报，并持久化 `conversation.read`。
- Outbox 按序重试，稳定 `clientMessageId`，服务端确认后替换临时消息。
- 推送仅唤醒同步，Token 使用安全存储，退出登录注销推送并停止循环。

## 真实执行记录

### 登录与设备

1. 覆盖安装 profile APK，应用进程正常启动。
2. 真机登录 `laowang`，进入工作台，页面显示“晚上好，老王”。
3. 等待多个 30 秒心跳周期，仍保持工作台，PID 不变，无会话失效提示。
4. “登录设备”显示 realme RMX3366 为当前设备，并保留多条 Windows 设备记录；移动登录没有替换桌面设备记录。

证据：

- `laowang-login-08s.png`
- `laowang-after-heartbeat.png`
- `laowang-login-devices.png`

### IM

- 会话类型：单聊（Codex 测试终端）。
- 测试消息：`AI-UAT-IM-SYNC-M1-20260901-181705`。
- 结果：消息发送成功；输入框清空；服务端确认后只保留一个气泡；显示紧凑双勾状态；会话列表只出现一条最新消息，无重复插入。

证据：

- `laowang-messages-list.png`
- `laowang-mobile-sent-confirmed.png`
- `laowang-mobile-sent-confirmed.xml`

### 双移动端实时消息与已读

- 方向：M2 林川 → M1 老王。
- 会话类型：单聊；两端标题、在线状态和会话列表语义均保持单聊，没有出现群成员数、群聊标签或 `@` 输入入口。
- 测试消息：`AI-UAT-IM-M2-M1-20260901-192000`。
- M2 发送结果：服务端确认后仅保留一个气泡，并显示发送成功状态。
- M1 到达结果：约一个长轮询周期后进入消息列表首位，显示林川、消息原文和未读 `1`；底部总未读由 `1` 增至 `2`。
- 打开前回执：M2 已读详情为 `0/1`，没有把发送成功误报为已读。
- 打开后回执：M1 打开消息进入可见区后，M2 已读详情变为 `1/1`，并显示老王及读取时间。
- M1 返回列表后，林川会话不再显示未读数，底部总未读由 `2` 降至 `1`；剩余 `1` 来自另一条既有未读消息。

证据：

- `m2-sent-to-m1.png`
- `m1-check.png`
- `m1-received-from-m2-unread.xml`
- `m2-receipt-before-m1-read.png`
- `m2-receipt-before-m1-read.xml`
- `m1-opened-m2-chat-read.png`
- `m1-opened-m2-chat-read.xml`
- `m2-receipt-after-m1-read-1of1.png`
- `m2-receipt-after-m1-read-second.xml`
- `m1-list-after-reading-m2.png`
- `m1-list-after-reading-m2.xml`

### 聊天头像回归

- 问题：接收方头像可显示真实图片，但发送方气泡只传递 `avatarDataUrl`，未传递当前成员的 `avatarKey`，因此部分账号退化为姓名首字。
- 修正：发送方消息头像同时使用当前成员的 `avatarKey` 与 `avatarDataUrl`；同一自然日内、未被其他发送者打断的连续消息形成一个身份组，组首同时显示一次昵称和头像。五分钟规则只负责压缩相邻消息间距，不再决定是否重复身份。
- 真机结果：老王与林川两侧均使用真实人物头像；林川从 18:41 到 20:00 的连续消息只在第一条显示一次昵称和头像，后续不重复，较长时间间隔仍保留正常留白。
- 模拟器结果：林川与老王两侧真实头像均正常，历史消息按相同分组规则合并头像。
- 20:16 复查发现模拟器仍停留在 11:54 安装的旧包，而真机已经是 19:54 的最新包；旧包中存在个别群消息头像缺失。覆盖安装同一最新 APK 并冷启动后，模拟器单聊历史消息及双方新消息头像均正常。
- 定向回归 `consecutive sender keeps one avatar on the first message` 与 `outgoing messages keep the current member avatar key` 均通过，保证连续消息不重复头像，并把唯一头像固定在组首。
- 群成员分页接口不可用时，聊天页现在先合并 SQLite 成员缓存和通讯录联系人；分页恢复后逐页合并，不会因某一页到达而删掉其他已缓存成员。
- 20:51 真机在服务端成员分页仍不可用的条件下复验：群聊中林川历史消息左侧显示真实人物头像，老王发送消息右侧也显示真实头像；成员数未知时不再误显示“0 位成员”。
- 会话热缓存保留时间由 5 分钟延长到 30 分钟。真机首次进入等待本地窗口读取，随后返回并重新打开时，120 ms 截图已直接显示历史消息和真实头像，没有重新空白渲染。

证据：

- `avatar-key-fix-real-chat.png`
- `avatar-key-fix-real-chat.xml`
- `avatar-key-fix-emulator-own-chat.png`
- `group-avatar-first-real.png`
- `group-avatar-first-real.xml`
- `avatar-key-fix-emulator-chat.xml`
- `chat-direct-current.png`
- `chat-group-avatar-after-send.png`
- `m2-chat-after-update.png`
- `group-offline-contact-avatar-final.png`
- `group-avatar-final.png`
- `group-avatar-final.xml`
- `group-avatar-hot-reopen-120ms.png`
- `group-cluster-final.png`
- `group-cluster-final.xml`

### 实时在线状态失联降级

- 问题：测试环境不可达后，SQLite 中最近一次在线状态仍可能渲染绿色圆点，容易把历史缓存误当成实时在线。
- 修正：新增 IM 实时可用性状态；只有 bootstrap、事件拉取或 presence 请求成功时才允许显示在线/离线。连接中、网络超时、断网、5xx、会话失效或同步停止时统一隐藏绿点，并显示“状态未知”或已有的“最后在线”时间。
- 覆盖入口：消息列表、单聊标题、通讯录成员、个人页、联系人搜索、`@` 成员选择、单聊详情、群详情、群成员目录、群管理和群发助手。
- 真机结果：目标服务不可达时，消息列表语义为“单聊，状态未知”，林川单聊标题、通讯录展开成员及个人页状态均显示“状态未知”，没有残留绿色在线点；本地消息和真实头像仍可正常展示。

证据：

- `messages-offline-presence-final.png`
- `messages-offline-presence-final.xml`
- `chat-offline-presence-final.png`
- `chat-offline-presence-final.xml`
- `contacts-offline-presence-expanded.png`
- `contacts-offline-presence-expanded.xml`
- `profile-offline-presence-final.png`
- `profile-offline-presence-final.xml`

### 断网状态与加载收口

- 工作台、消息、通讯录、待办、通知、会话详情和 OA 页面统一把连接失败、超时、5xx、401/403 等映射成简短用户文案，不再把接口地址、异常堆栈或传输细节直接显示在界面。
- 审批人解析请求按当前表单指纹去重；字段未变化时不重复创建请求，字段变化或用户主动重试时才重新解析。
- 审批人解析最长等待 12 秒。断网时先显示紧凑加载态，超时后原位切换为“网络不可用，表单与草稿已保留”，保留完整表单、保存草稿和提交入口，并提供单个重试按钮。
- debug 真机冷启动复现出 `MobileShell.initState` 在构建阶段修改 Riverpod 状态的红屏；已把连接态更新延后到首帧之后。最终 profile APK 在 realme RMX3366 与 Android 16 x86_64 模拟器均冷启动成功。
- 真机 profile 复验：进入请假审批后 2 秒仍显示“正在解析审批人…”，13 秒后加载态消失、断网提示和重试入口出现，页面字段未被清空。
- 真机继续复核发现“登录设备”在协作连接持续 `connecting` 时永久显示加载：个人页摘要一直为“正在同步设备”，详情页超过 30 秒仍是大号转圈。现已在实时连接尚未可用时立即显示“暂时无法同步”，有缓存则保留缓存设备；无缓存使用紧凑离线行和重试，重试最长 12 秒后恢复可操作状态。

证据：

- `profile-real-startup-final.png`
- `profile-real-startup-final.xml`
- `profile-emulator-startup-final.png`
- `profile-emulator-startup-final.xml`
- `oa-offline-profile-initial.xml`
- `oa-offline-profile-final.png`
- `oa-offline-profile-final.xml`
- `profile-device-offline-final.png`
- `profile-device-offline-final.xml`
- `login-devices-offline-final.png`
- `login-devices-offline-final.xml`
- `login-devices-offline-retry.png`
- `login-devices-offline-retry-settled.png`

### 群聊与 `@我` 漏事件补偿

- 原始缺陷：M2 在 2000 人工作群发送 `@老王 AI-UAT-IM-GROUP-M2-M1-20260901-192500` 后，M1 的事件收件箱没有对应 `message.created`；消息列表、群未读与 `@我` 保持旧状态，手动打开群聊后才通过消息接口取得正文。
- 客户端修正：空长轮询后只请求轻量 `/api/im/badges`；仅当服务端未读总数与 SQLite 会话投影不一致时才刷新 bootstrap。应用回前台和推送打开也请求该核对；普通打开会话不触发全量 bootstrap。
- 当前会话性能边界：聊天页每 12 秒只核对当前会话最新 50 条，且本地快照一致时不写库、不使消息窗口失效。
- 真实复验：M2 发送 `@老王 AI-UAT-IM-GROUP-RECONCILE-20260901-194100` 后，M1 始终停留消息列表，35 秒内自动出现 19:41 新预览、群未读 `1`，底部总未读由 `1` 增至 `2`。
- `@我` 复验：M1 未打开群聊前，`@我` 标签仅显示该群；打开消息进入可见区后返回，`@我` 清空，底部总未读由 `2` 降至 `1`。
- 服务端缺陷仍需保留：群消息事件未投递给目标移动设备；当前通过客户端低成本投影补偿避免用户侧丢消息。

证据：

- `group-reconcile-m1-before.png`
- `group-reconcile-m1-before.xml`
- `group-reconcile-m2-sent.png`
- `group-reconcile-m2-sent.xml`
- `group-reconcile-m1-after-35s.png`
- `group-reconcile-m1-after-35s.xml`
- `group-reconcile-m1-at-me.png`
- `group-reconcile-m1-at-me.xml`
- `group-reconcile-m1-open-read.png`
- `group-reconcile-m1-open-read.xml`
- `group-reconcile-m1-after-read.png`
- `group-reconcile-m1-after-read.xml`

### 同账号移动设备会话互斥与恢复

- 初始状态：M1 真机登录老王，M2 模拟器登录林川。
- M2 切换登录为老王后，M1 立即回到登录页，之前的工作台和消息内容不再可操作，证明旧移动会话已被替换。
- M1 使用记住的账号恢复登录后重新进入工作台；M2 最迟在下一次心跳检查内（实测不超过 35 秒）回到登录页，证明反向替换同样生效。
- M1 恢复后消息列表、群聊预览、未读数、联系人真实头像及本地会话数据仍正常，未出现登录恢复后空列表、头像丢失或跨账号数据串用。
- 本轮捕获到了两端被替换后的登录页，但一次性提示消失较快，未获得提示文案的稳定截图，因此仅判定会话终止与跳转行为通过，不把提示文案计为已验收。
- 桌面 D1 是否在两次移动替换期间保持在线仍缺桌面页面证据，不能随移动端互斥一并判定通过。

证据：

- `m2-profile-before-replace.xml`
- `m2-logout-sheet.xml`
- `m2-laowang-login-result.png`
- `m1-after-m2-login-immediate.png`
- `m1-after-m2-login-immediate.xml`
- `m1-relogin-replaces-m2.png`
- `m2-after-m1-relogin.png`
- `m2-after-m1-relogin-35s.png`
- `m2-after-m1-relogin-35s.xml`
- `m1-restored-message-list.png`
- `m1-restored-message-list.xml`

### 通讯录进入已有单聊的响应优化

- 通讯录默认只展示真实组织树，部门展开后才渲染其中人员；人员行不再保留独立聊天图标，头像和整行均可直接进入单聊。
- 原始路径即使本地已经存在该单聊，也会先等待“创建/获取单聊”网络请求。真机证据显示点击后 120ms 仍停留通讯录，约 620ms 才显示聊天页，造成明显的无响应感。
- 修正后先从当前账号的本地会话投影匹配已有单聊；匹配唯一时立即打开，只有首次会话或同名匹配不唯一时才调用服务端接口，避免误开其他人员会话。
- 同一真机复验中，点击头像后 120ms 截图已经完整显示聊天页、历史消息和双方真实头像；620ms 页面保持稳定，没有二次插入或闪烁。

证据：

- `contacts-default.png`
- `contacts-expanded.png`
- `contact-avatar-to-chat-120ms.png`
- `contact-avatar-to-chat-620ms.png`
- `contact-avatar-cached-chat-120ms.png`
- `contact-avatar-cached-chat-620ms.png`
- `contact-avatar-cached-chat.xml`

### 离线多条单聊、群聊与 `@我` 补偿

- M1 真机停留在消息列表，并关闭 Wi-Fi 与移动数据；M2 模拟器保持在线，使用林川账号向老王连续发送三条带序号单聊消息。
- M2 随后在 2000 人工作群通过“提及成员”抽屉真实选择老王并提交两次群消息。两次提交正文相同，但发送时间不同，属于两个真实用户操作，不是同步重复。
- M1 离线期间没有打开任何会话；恢复移动数据后，在一个长轮询/心跳窗口内自动恢复：林川单聊未读 `3`、群聊未读 `2`、底部总未读由原有 `1` 增至 `6`，`@我` 仅出现目标群。
- M1 本地 SQLite 核对显示五条新消息均有不同的服务端消息 ID 和 `clientMessageId`；单聊序号连续为 `2/3/4`，群聊序号连续为 `20846/20847`，落库状态均为 `sent`，没有同一事件重复落库。
- 打开单聊后，正文严格按 `01 → 02 → 03` 展示且各一条；打开群聊后，两条真实提交按 19:59、20:00 排列。读取后 `@我` 空状态为“暂无会话”，底部未读恢复为原有 `1`。

证据：

- `m1-offline-before-restore.png`
- `m2-offline-direct-sent3.png`
- `m2-offline-direct-sent3.xml`
- `m2-group-mention-sheet.png`
- `m2-offline-group-compose.png`
- `m2-offline-group-sent-final.png`
- `m2-offline-group-sent-final.xml`
- `m1-offline-after-restore.png`
- `m1-offline-after-restore.xml`
- `m1-offline-atme.png`
- `m1-offline-group-open.png`
- `m1-offline-group-open.xml`
- `m1-offline-direct-open.png`
- `m1-offline-direct-open.xml`
- `m1-offline-atme-cleared.png`
- `m1-offline-atme-cleared.xml`

### OA

- 流程：请假审批 v1。
- 申请编号：`OA-20260901-4F9A4A`。
- 申请人：老王（集团总部）。
- 请假类型：事假。
- 时间：2026-09-02 18:20 至 2026-09-02 19:22。
- 自动计算天数：1。
- 事由：`AI-UAT-LEAVE-20260901-182300`。
- 初始状态：审批中。
- 当前用户处理：老王的“部门负责人审批”由“待你处理”变为“已同意”。
- 处理后状态：仍为审批中；其他会签人员保持待处理。

验证结果：

- 下拉、日期、时间、审批动作均使用移动端向上抽屉。
- 表单由服务端 schema 渲染；自动计算字段显示业务值 `1`，没有把 schema 配置对象当成业务文本。
- 中间节点同意后未提示整条流程已通过。
- 离线 IM 验收结束后再次进入待办，标签、搜索与筛选仍保持紧凑；“我发起的”正确加载本申请及既有撤回申请。
- 重新打开详情后，动态表单业务值、多人会签节点和“审批中”状态保持一致；“更多”操作以底部抽屉显示催办、撤回，没有使用居中弹窗。
- 21:23 在服务端不可达条件下重新打开缓存表单，申请人、部门、版本及服务端 schema 字段仍正常；请假类型和日期继续使用底部抽屉，输入框、附件按钮、保存草稿与提交按钮保持移动端紧凑高度。

证据：

- `laowang-leave-form.png`
- `laowang-leave-start-picker.png`
- `laowang-leave-ready.png`
- `laowang-leave-submit-result.png`
- `laowang-leave-approved-node.png`
- `oa-current-recheck.png`
- `oa-current-recheck.xml`
- `leave-request-current-audit.png`
- `leave-request-current-audit.xml`
- `leave-type-sheet-audit.png`
- `leave-type-sheet-audit.xml`
- `leave-date-sheet-audit.png`
- `leave-date-sheet-audit.xml`
- `oa-initiated-recheck.png`
- `oa-initiated-recheck.xml`
- `oa-detail-recheck.png`
- `oa-detail-recheck.xml`
- `oa-more-sheet-recheck.png`
- `oa-more-sheet-recheck.xml`

### 运行中桌面端与移动端并行状态

- Windows 桌面进程自 18:07 启动后始终存在并可响应，但“进程存在”不能代表 IM/OA 会话在线。
- 移动端“登录设备”在 20:19 复查时，最新 Windows 设备记录最后活动仍停在 19:47；记录没有被撤销，但没有继续更新活动时间。
- 桌面日志可见区间 19:57:42–20:17:58 内，IM 仅在 `connecting` 与 `retry-wait` 间循环，重试从 191 增至 221；OA 重试从 186 增至 220。两者原因均为 `transport error`，没有出现一次 `ready`。
- 桌面本地 `collaboration_event_cursors` 与 `collaboration_event_inbox` 均为 0；19:58 离线补偿消息以及 20:14/20:15 头像复验消息在桌面消息缓存中的匹配数均为 0。
- 桌面配置的控制面 HTTP 为 80 端口、IM/OA gRPC 为 9080 端口。20:21 Windows 对两端口的直连都超时，而同机访问公共 HTTP 站点返回 200，属于测试环境目标路径异常，不是 Windows 整体断网。
- 20:22 M1 再发送 `AI-UAT-DESKTOP-NETCHECK-20260901-2022` 时，消息最终进入失败状态且 M2 未收到。这说明当时移动端到测试环境也已异常，因此不能把桌面掉线直接归因于移动端登录替换；必须在测试环境恢复后重新执行同一矩阵。

证据：

- `login-devices-2019.png`
- `login-devices-2019.xml`
- `m1-netcheck-after-wait.png`
- `m1-netcheck-after-wait.xml`
- `m2-netcheck-after-wait.png`

## 验收矩阵

| 项目 | 状态 | 证据/说明 |
| --- | --- | --- |
| 移动登录携带最新设备字段 | 通过 | 合同测试 + 真机登录 |
| 稳定安装 ID 与服务端设备 ID 分离 | 通过 | 存储测试 + 真机心跳 |
| 登录后立即心跳、30 秒周期心跳 | 通过 | 真机跨多周期保持在线 |
| 401/409/网络错误分类处理 | 通过（自动化） | 协议合同测试 |
| 账号+设备事件游标 | 通过（自动化） | SQLite 测试 |
| 事务落库后 ACK、重放幂等 | 通过（自动化） | SQLite 与同步测试 |
| 移动发送确认后原位替换、无重复 | 通过 | 真机消息证据 |
| 另一移动账号发送、M1 实时出现 | 通过 | M2→M1 真实发送、未读和气泡证据 |
| M1 阅读后发送端回执同步 | 通过 | 回执由 0/1 变为 1/1，M1 未读持久清零 |
| 聊天双方真实头像正确显示 | 通过 | 真机与模拟器均验证收发两侧；群成员分页离线时仍可从通讯录和成员缓存恢复 |
| 连续消息昵称与头像合并 | 通过 | 同一自然日内连续同发送者为一组，组首同时显示昵称和单头像；真机群聊 18:41–20:00 历史验证 |
| 在线状态仅在实时通道可用时显示 | 通过 | 失联时消息、单聊、通讯录及成员选择入口均隐藏缓存绿点并显示状态未知 |
| 冷启动不在构建期修改 Provider | 通过 | debug 捕获调用栈并修正；最终 profile 真机与 x86_64 模拟器均冷启动成功 |
| OA 断网加载超时、表单保留与重试 | 通过 | 真机 profile 从加载态切换到断网态；表单仍在原页，重试入口可见 |
| 登录设备断网状态与重试收口 | 通过 | 真机入口即时显示断网摘要；详情页不再永久转圈，重试 12 秒内恢复 |
| 群聊漏事件后自动补偿 | 通过（客户端补偿） | 消息列表未打开群聊，35 秒内恢复预览与未读 |
| `@我` 投影与阅读清除 | 通过 | `@我` 标签出现目标群，阅读后自动清空 |
| 桌面 D1 + 移动 M1 同时在线 | 未通过（当前环境） | D1 进程存在但实时通道持续传输失败，Windows 设备活动停在 19:47 |
| 桌面发送、移动实时出现 | 未执行 | D1 当前离线，且缺桌面 UI 控制运行时 |
| 移动已读后桌面未读立即清零 | 未执行 | D1 未接收本轮消息，无法形成有效前置状态 |
| M2 替换 M1、D1 保持在线 | 无法判定 | D1 掉线与移动替换时间接近，但随后确认测试环境目标路径异常，证据不足以归因 |
| M1 恢复登录后反向替换 M2 | 通过 | M2 在一次心跳周期内退出登录，实测不超过 35 秒 |
| 移动会话恢复后的本地数据隔离 | 通过 | M1 消息、未读、群预览和头像均恢复正常，无空列表或串号 |
| 通讯录已有联系人进入单聊 | 通过 | 本地复用已有会话；真机 120ms 截图已进入聊天页 |
| D2 替换 D1、M1 保持在线 | 未执行 | 当前仅一个可操作桌面实例 |
| 离线多条单聊/群聊/@我补偿 | 通过 | 真机断网恢复；5 条消息无丢失、无事件重复、序号与展示顺序正确 |
| 事件落库后、ACK 前强杀 | 通过（自动化），真机未执行 | 幂等测试通过 |
| 密码修改使其他会话失效 | 未执行 | 需至少两个可控终端会话 |
| OA 动态表单、抽屉、真实提交 | 通过 | 真实申请与截图 |
| OA 中间节点同意后继续流转 | 通过 | 申请仍为审批中 |

## 未完成与阻塞

1. 当前 Codex 任务未暴露 `computer-use` 所需的 `node_repl` 运行时；按安全规则不能改用 PowerShell/SendKeys 冒充桌面 UI 验收。
2. 运行中的桌面 WebView2 未开启 remote-debugging 端口，不能通过浏览器调试协议安全接管。
3. 同账号移动互斥已完成真实双向验证，但 `session_replaced` 的一次性提示文案未被稳定截图，仍需在可控录屏条件下复验提示次数与文本。
4. 项目根下 `.git` 目录当前为空，无法生成可信的 `git diff/status`；本轮未重建或覆盖版本库元数据。
5. 服务端事件接口未向 M1 返回本轮首条群聊 `message.created`；客户端已通过未读投影差异自动恢复，但服务端事件投递仍需修正。
6. 20:21 后 Windows 到测试环境 80/9080 均超时，21:14 复查仍分别在约 3 秒后超时；测试环境恢复后需原样重跑桌面 D1 + 移动 M1 在线、桌面发送和跨端已读三项。

## 自动化结果

- `flutter analyze --fatal-infos`：通过，无问题。
- `flutter test`：268/268 通过。
- `flutter build apk --profile`：通过。
