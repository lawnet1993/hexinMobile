# 690：独立双端群聊同步与创建抽屉键盘修复

日期：2026-09-03，主机 Asia/Shanghai 约 05:06–05:21。结论：**部分通过，整体目标继续**。本轮新增真实群聊、@、离线补拉和持久已读证据，修复新建群聊按钮被键盘遮挡；另外确认消息列表的在线状态刷新仍存在缺口。

## 范围与环境

- M3：`emulator-5556` / test03 / Test Terminal 03 / 财顺；M4：`emulator-5558` / test04 / Test Terminal 04 / 合盈。均为独立 Android 16 模拟器，账号和名称以当前 UI、SQLite 为准。
- API 测试环境 `http://api.sfhkh.com`。仅新建一个带 AI-UAT 前缀的两人群并发送三条测试消息；不修改其他群、账号、部门或正式流程，不提交新 OA 申请。
- M1 真机与 M2 未操作、未重登。Windows 安装版 1.0.87/test01 仍运行，结束时只读 IM/OA GET 均为 200，见 [桌面会话核对](../test/evidence/im-m3-m4-group-20260903/desktop-after.json)。这不是桌面窗口实操或同账号多端验收证据。
- 未修改系统时间；消息 UTC 时间、模拟器显示时间和主机时间分别保留，不据跨时钟截图计算同步延迟。

## 新建群聊与角色边界

真实路径：M3 消息 → 发起会话 → 群聊 → 输入名称 → 仅选择 Test Terminal 04 → 创建一次。群名 `AI-UAT-20260903-050600-M3-M4-GROUP`，ID `95e704ae-0e34-4f56-87db-038526796d6c`。

M3 群详情显示 2 位成员，M3 为群主、M4 为成员；M4 未手动刷新即在消息列表收到新群。群页显示聊天/文件及群详情、提及成员入口；既有单聊仍显示聊天/文件/任务和个人资料，没有变为群聊。

证据：[创建成功](../test/evidence/im-m3-m4-group-20260903/11-m3-create-result.png)、[M4 自动出现新群](../test/evidence/im-m3-m4-group-20260903/13-m4-group-arrived.png)、[成员及群主](../test/evidence/im-m3-m4-group-20260903/20-m3-group-details.png)、[既有单聊](../test/evidence/im-m3-m4-group-20260903/39-m3-direct-presence-refresh.png)。

## 三条消息与真实状态变化

| 序号 | 方向与场景 | 正文标记（提及由实际成员选择器插入） | clientMessageId |
| --- | --- | --- | --- |
| 1 | M3 → M4，在线 @ | AI-UAT-20260903-051200-M3-M4-GROUP-MENTION | 44021622-4bca-4278-a9c7-3ce85add654f |
| 2 | M4 → 离线 M3，普通群消息 | AI-UAT-20260903-051400-M4-M3-GROUP-OFFLINE-01 | 137d9123-ea63-459b-ae1a-3d3617542710 |
| 3 | M4 → 离线 M3，@ | AI-UAT-20260903-051400-M4-M3-GROUP-OFFLINE-02 | 936374ac-08c1-4ac1-b3aa-949f6713a1df |

### 在线 @ 与可见后标读

1. M3 点击“提及成员”，从真实成员列表选择 Test Terminal 04，而非仅输入同名文本。发送前截图保留实际 @ 和标记，见 [选择器](../test/evidence/im-m3-m4-group-20260903/12-m3-mention-picker.png)、[发送前](../test/evidence/im-m3-m4-group-20260903/15-m3-mention-ready.png)。
2. M4 停留列表时，SQLite 为 lastMessage=1、lastRead=0、unread=1、unreadMentionSequences=[1]；列表和底部角标均为 1，且“@我”筛选能找到该群。见 [未读快照](../test/evidence/im-m3-m4-group-20260903/m4-mention-unread.json)、[@我列表](../test/evidence/im-m3-m4-group-20260903/17-m4-mention-filter.png)。
3. M4 实际打开群聊、正文进入可见区域后，SQLite 变为 lastRead=1、unread=0、mention=[]。M3 不重开会话即显示接收人已读。见 [已读快照](../test/evidence/im-m3-m4-group-20260903/m4-mention-read.json)、[发送端回执](../test/evidence/im-m3-m4-group-20260903/19-m3-group-receipt.png)。

### 离线冷启动、补拉与顺序

通过 [受限 UI 测试脚本](../scripts/uat-m3-offline-group-m4.ps1)，仅关闭 M3 Wi-Fi/移动数据，确认 `Active default network: none`，强制结束并冷启动 M3。M4 在真实输入框依次发送序号 2、3，其中第二条通过提及选择器选择 Test Terminal 03。

脚本在发送前后记录点击，存在运行记录时拒绝再次发送；不把点击等同服务端确认。`finally` 恢复 M3 原网络 1/1，M4 网络始终未关闭。见 [操作时间线](../test/evidence/im-m3-m4-group-20260903/offline-group-run.json)、[离线工作台](../test/evidence/im-m3-m4-group-20260903/21-m3-group-offline-home.png)。

- 离线期间 M3 账本仍仅 seq1、lastRead=1、unread=0；[离线快照](../test/evidence/im-m3-m4-group-20260903/m3-group-offline-before-reconnect.json)。
- 联网后 M3 仍在工作台、未打开群聊，自动落库 seq1–3，lastRead=1、unread=2、mention=[3]；[打开前快照](../test/evidence/im-m3-m4-group-20260903/m3-group-reconnected-before-open.json)、[未读列表](../test/evidence/im-m3-m4-group-20260903/23-m3-group-offline-unread.png)。
- 实际打开群聊后 lastRead=3、unread=0、mention=[]；M4 两条发送消息均自动显示已读。见 [M3 阅读](../test/evidence/im-m3-m4-group-20260903/24-m3-group-offline-read.png)、[M4 回执](../test/evidence/im-m3-m4-group-20260903/25-m4-group-read-receipts.png)。
- 两端三条服务端 ID、clientMessageId、发送者、序号、创建时间和状态完全相同，无重复；连续两条同发送者仅首条显示头像/姓名。该结论仅覆盖这三条及本轮恢复路径，不代表所有重放、500 条批次或 ACK 前崩溃矩阵已验收。

## P2 已修复：创建群聊按钮被键盘遮挡

复现：消息 → 发起会话 → 群聊 → 输入群名，保持软键盘显示。原抽屉没有消耗键盘 viewInsets，创建按钮仍位于屏幕底部。原生 [修复前截图](../test/evidence/im-m3-m4-group-20260903/06-m3-group-name-keyboard.png) 中按钮被遮挡；用户必须先收起键盘才可提交。

在 [messages_page.dart](../lib/features/messages/presentation/messages_page.dart) 的底部抽屉构建器添加当前键盘高度的底部 Padding。保留原成员懒构建列表、38dp 提交按钮及群名/选择状态，让系统约束缩小内容可用区域，而不是放大控件或强制隐藏键盘。

新增 [三组回归测试](../test/new_conversation_keyboard_test.dart)：390×844、320×568、390×844/1.3 倍文字。均验证按钮在键盘上方、仍可用、键盘收起后群名和成员选择不丢失、无布局异常。旧实现 **0/3**，修复后 **3/3**，见 [红测](../test/evidence/im-m3-m4-group-20260903/keyboard-red.log)、[绿测](../test/evidence/im-m3-m4-group-20260903/keyboard-green.log)。

最终普通安装包在两台设备重新打开群聊创建表单，选择对方、输入 AI-UAT-KEYBOARD-CANCEL 标记，**没有提交第二个群**。软键盘实际显示时，按钮 enabled=true，边界为 y=1391–1491，截图确认完整位于键盘上方。验证后按系统返回收起键盘、再返回取消抽屉；标题/选择不落成远端业务数据。中间证据 `32-m3-draft-cancelled` 文件名不代表成功取消：当次仅点到拖动条，实际仍为表单；真正取消证据为 `34`。

证据：[M3 修复后](../test/evidence/im-m3-m4-group-20260903/31-m3-fixed-keyboard-ready.png)、[M4 修复后](../test/evidence/im-m3-m4-group-20260903/37-m4-fixed-keyboard-ready.png)、[M3 键盘状态](../test/evidence/im-m3-m4-group-20260903/keyboard-native-m3.json)、[M4 键盘状态](../test/evidence/im-m3-m4-group-20260903/keyboard-native-m4.json)、[M3 真正取消后](../test/evidence/im-m3-m4-group-20260903/34-m3-draft-dismissed.png)、[M4 取消后](../test/evidence/im-m3-m4-group-20260903/38-m4-draft-dismissed.png)。

## 构建、安装及保留数据

- 全量 **888/888**，[测试日志](../test/evidence/im-m3-m4-group-20260903/full-tests.log)；[静态分析](../test/evidence/im-m3-m4-group-20260903/analyze.log) 0 问题。
- 正常 profile/arm64+x64 APK 构建成功，Gradle 53.0 秒，[构建日志](../test/evidence/im-m3-m4-group-20260903/build.log)。SHA-256：`C63BFAB0E135187A7512F47452CD341F47C47C068E1FD310C70882EF984DCD1A`。
- 使用 `install -r` 覆盖 M3/M4，均与本地 APK 哈希一致，未清应用数据。系统 Activity 启动耗时分别 3154ms、8808ms，仅为 Activity 计时，不作为 Flutter 首屏或性能通过依据。[M3 安装](../test/evidence/im-m3-m4-group-20260903/install-5556.json)、[M4 安装](../test/evidence/im-m3-m4-group-20260903/install-5558.json)。
- 业务收发测试在原 689 包执行；最终 690 包真实复测键盘与重开群聊，三条消息、头像合并、回执均仍显示。[M3 最终群页](../test/evidence/im-m3-m4-group-20260903/41-m3-final-group.png)、[M4 最终群页](../test/evidence/im-m3-m4-group-20260903/42-m4-final-group.png)。
- [M3 最终 SQLite](../test/evidence/im-m3-m4-group-20260903/m3-group-postinstall.json)、[M4 最终 SQLite](../test/evidence/im-m3-m4-group-20260903/m4-group-postinstall.json)：三条 ID/顺序/已读重启保持；两台都只增加本轮一个群，原单聊三条账本完全不变。
- M3 原有两个待发媒体的 clientMessageId、目标会话、类型和创建时间不变，未宣称先前媒体 500 已解决；M4 Outbox=0。M3 OA 两草稿、十个通知回执及 OA Outbox 保留，未因安装清空。[OA 快照](../test/evidence/im-m3-m4-group-20260903/m3-oa-postinstall.json)、[18 项元数据比对](../test/evidence/im-m3-m4-group-20260903/verification.json)。
- 最终 M3/M4 网络均 1/1。限定当前 app PID 的日志计数无 Unhandled Exception / RenderFlex overflow / FATAL EXCEPTION；未输出原始日志，不据此宣称长时稳定。[运行检查](../test/evidence/im-m3-m4-group-20260903/runtime-final.json)。

## P2 未修复：消息列表静置后在线状态刷新缺口

复现：M3/M4 均在前台且连接有效，安装后停留消息列表/创建抽屉，再返回列表。Test Terminal 04 显示“状态未知”；进入其单聊立即显示“在线”，返回列表也恢复“对方在线”。

预期：前台可见列表应按有限批次持续核对真实状态；网络不可靠时保留未知，不使用缓存伪造在线。实际：当前观测过期后，列表不能自行获取新的状态。影响：用户不能仅从消息列表可靠判断联系人在线。

证据：[列表未知](../test/evidence/im-m3-m4-group-20260903/34-m3-draft-dismissed.png)、[会话在线](../test/evidence/im-m3-m4-group-20260903/39-m3-direct-presence-refresh.png)、[返回后恢复](../test/evidence/im-m3-m4-group-20260903/40-m3-list-presence-refreshed.png)。代码核对显示 presence 观测有 60 秒有效期，MessagesPage 只读取投影，页面内没有刷新机制；这里只定位前台补取缺口，未证明所有未知状态都由此产生。本轮没有为解决未知而伪造在线值。下一轮应补可见成员批量刷新、前后台取消和迟到请求隔离，并真实静置回归。

## 尚未执行或不能判通过

- 同账号桌面/移动互不替换、第二设备同平台替换、跨端本人已读与密码修改会话失效；本轮是两个不同账号。
- Windows 窗口真实操作、真机验收与性能量测；本轮只控制独立 M3/M4，不接管 M1/M2。
- 退群/重新入群、踢人后的权限与历史边界、多人或 2000 人群、超过 500 条补拉、事件落库后 ACK 前强杀重放、推送唤醒定位、并发幂等和长时间性能。
- 高级 OA 条件分支、跨部门会签/或签/办理/付款/抄送及公式全链路；先前服务端媒体 500 和其他已记录问题仍保留。
- 全量 888 是本地自动化数量，不是完整线上验收用例通过率；本轮真实流程的通过不能覆盖上述未执行项，因此不结束总目标。
