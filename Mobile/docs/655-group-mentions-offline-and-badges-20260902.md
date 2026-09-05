# 群聊、@ 提醒、断网补齐与消息角标验收

时间：2026-09-02 20:21–20:40，Asia/Shanghai。结论：**部分通过，整体移动端目标继续进行。**

本轮真实完成两人测试群创建、双向群消息、@ 成员、未读/已读持久化和断网冷启动后的自动补齐；修复本地已读后总角标缺少刷新依赖的问题。群消息事件流缺项、断网恢复延迟、媒体服务 500、完整桌面 UI 与高级 OA 仍未通过，不能将最终一致当作实时同步通过。

## 环境与边界

- M1：真机 `dd00d66d`，Android 14，test01 / Test Terminal 01，公司总部。
- M3：独立 `emulator-5556`，Android 16，test03 / Test Terminal 03，财顺。系统 UTC，截图显示时间比北京时间少 8 小时。
- D1：正在使用的 Windows test01 会话，仅通过其已有授权会话执行 GET 核对；本轮没有可用的桌面控制工具，不能宣称完成桌面窗口操作或观察到桌面角标变化。
- 原 M2 没有安装、点击、切换账号或操作网络。
- 仅创建/操作 `AI-UAT-` 测试群和测试消息，不删除既有数据。M1 热点和网络未改动；M3 网络在测试后恢复 Wi-Fi=1、数据=1、默认网络 106。
- 本轮图标设计交付是独立资产，没有替换应用启动图标。

## 修复：本地已读与总角标的刷新链路

原逻辑：聊天可见区域成功提交已读 → SQLite 更新 → 只失效 `imBootstrapProvider`；`imBadgeSummaryProvider` 不依赖该变化。如果服务端没有产生下一条有效事件，总角标可以继续持有旧值。

修复：总角标订阅本地会话未读合计的变化，变化时重新请求真实 `/api/im/badges`。仍使用服务端汇总，避免将可能不完整的本地会话列表当作全量；好友申请数不被消息数覆盖。仅标题/头像/在线状态或相同数值的 reload 不应重复请求。Riverpod 丢弃已被新一代请求替代的迟到结果。

修改：`lib/features/collaboration/data/collaboration_repositories.dart`；新增 `test/im_badge_refresh_test.dart`。三项测试使用真实仓库、SQLite 和本地 HTTP 服务：

1. 无读事件回声时，真实 markRead 后只触发页面已有的 bootstrap 失效，总角标仍必须 2→0；好友申请 3 保持。
2. 元数据变化、相同未读数反复 reload，不增加 badge 请求。
3. 已读前的 HTTP 结果迟到，不能将 0 改回 2。

修复前第 1、3 项均实际失败（Expected 0 / Actual 2），修复后三项通过。

**证据更正：** 早先对“角标持续为 2”的中间观察不能用留存文件证明。`02-m3-stale-total-before.png/xml` 实际已经是 0；冷启动后的图也为 0。因此不把文件名当证据，不宣称旧包持续不清零已被截图证实。确定的缺陷证据是上述可复现的回归失败，以及当前源码漏掉本地变化依赖；新包行为另由以下真实操作验证。

## 构建与本地检查

正常入口 `lib/main.dart`，Profile 1.0.1+2，arm64+x64，APK 82,544,963 字节。

SHA256：`366F7B01C1B37304515F3310CD630EBCF710C681E6BE98F68A188F942939A050`。

M1/M3 均覆盖安装成功，设备 base.apk 的 SHA256 与产物一致；登录与原数据保留。冷启动 M1 TotalTime=1255 ms、M3=9395 ms。软件渲染模拟器结果不是移动端性能合格结论。

- 全量首跑 405 通过、1 失败：`im_local_store_test.dart:118` 的 `outbox persists failed sends and reconciles by client id`，刚入队后 dueOutbox 实际为空；单独重跑通过。没有删测试、放宽断言或改该实现。
- 全量复跑 **406/406**；[首跑日志](../test/evidence/im-m3-group-20260902/full-tests.log)、[复跑日志](../test/evidence/im-m3-group-20260902/full-tests-rerun.log) 均保留。此偶发失败仍需查明，不用绿灯掩盖。
- `flutter analyze --fatal-infos`：0 问题；[日志](../test/evidence/im-m3-group-20260902/analyze-final.log)。
- `git diff --check`：通过，未清理/回滚已有工作区更改，未更新 golden。
- [构建日志](../test/evidence/im-m3-group-20260902/build.log)：成功；第三方插件 Built-in Kotlin 迁移警告仍存在。
- 20:40 两端当前进程最近 2000 行日志没有命中未处理异常、FATAL 或 RenderFlex overflow；这是有界检查，不代表所有历史日志无异常。

## 真实测试群与四条消息

群名：`AI-UAT-20260902-202100-M1-M3-GROUP`。

群 ID：`bd15cbb6-ab8e-4cf2-9d62-fdb6f37ce90a`。实际成员仅 test01/test03，群头显示 2 位成员，在线时为 2 人在线；群页只有聊天/文件，没有混入单聊任务页。

| 序号 | 方向 / 场景 | 消息标识 | 服务端时间（北京时间） | clientMessageId |
| --- | --- | --- | --- | --- |
| 1 | M1→M3，实际选择 @test03 | AI-UAT-20260902-203300-GROUP-MENTION | 20:33:34.766742 | 2c641f03-f871-4373-8e86-a0d891e9279d |
| 2 | M1→M3，M3 断网，@test03 | AI-UAT-20260902-203600-OFFLINE-GROUP-01 | 20:35:55.674762 | b6494e48-9088-49a0-84c8-6726e2b2d058 |
| 3 | M1→M3，M3 断网，普通文本 | AI-UAT-20260902-203600-OFFLINE-GROUP-02 | 20:36:17.237733 | 54d884ff-18f7-4836-977e-25e0164c896a |
| 4 | M3→M1，群回复 | AI-UAT-20260902-203800-M3-GROUP-REPLY | 20:38:39.965506 | 726ad25b-c1cc-4f2f-b28b-ebbe51ee8242 |

带 @ 的两条通过提及成员抽屉选择 Test Terminal 03，实际服务端 mentionCount 均为 1，不是只键入 @ 字符。普通文本的 mentionCount=0。

### 在线 @ 与角标

- M3 未打开群时：SQLite last=1 / read=0 / unread=1 / mentions=[1]；底部消息角标 1，@我筛选内列出群。
- 打开群、正文真实可见后：SQLite read=1 / unread=0 / mentions=[]；返回列表后 @我筛选清空、底部角标 0，无重启、无手动刷新。
- M1 原消息从“已发送”变“已有接收人已读”，没有再次发送。

证据：[未打开时](../test/evidence/im-m3-group-20260902/05-m3-unopened-group.json)、[@我筛选](../test/evidence/im-m3-group-20260902/06-m3-mention-filter.png)、[阅读后角标](../test/evidence/im-m3-group-20260902/08-m3-read-badge-zero.png)、[阅读后 SQLite](../test/evidence/im-m3-group-20260902/08-m3-read-badge-zero.json)、[发送方回执](../test/evidence/im-m3-group-20260902/09-m1-recipient-read.png)。

### 真实断网、杀进程、恢复

1. 仅关闭 M3 Wi-Fi 和移动数据；确认 `Active default network: none`。force-stop 后正常启动，仍保持 test03 登录与缓存，不因网络失败退出。
2. M1 通过 UI 发送 seq2、seq3。M3 在离线状态下库中仍只有 seq1，read=1/unread=0，证明未提前接收。
3. 20:36:30 恢复 M3 网络，停留工作台，不打开群、不点刷新。早期 `12-*` 检查仍为 seq1；20:37:17 的检查已经自动落齐 seq1–3，read=1/unread=2/mentions=[2]。
4. 此 47 秒是恢复命令到确认补齐的观察上界，并非精确完成耗时；没有秒级持续采样。当前恢复速度仍需优化，不能报“立即补齐”。
5. 此后打开群：两条离线消息顺序正确，read=3/unread=0/mentions=[]；头像和发送者只在连续消息组第一条出现，时间处于气泡内，没有每条重复头像。

证据：[离线快照](../test/evidence/im-m3-group-20260902/11-m3-offline-restart.json)、[恢复后未打开的三条](../test/evidence/im-m3-group-20260902/13-m3-recovered-before-open.json)、[未读 2 截图](../test/evidence/im-m3-group-20260902/13-m3-recovered-before-open.png)、[最终群消息样式](../test/evidence/im-m3-group-20260902/14-m3-recovered-visible.png)。

### 反向群回复与双端一致

- M1 离开群后，M3 通过 UI 发出 seq4。M1 工作台收到后，群 read=3/unread=1；底部角标从原有其他会话的 1 变为 2。
- M1 打开群阅读后，群 read=4/unread=0，总角标回到原有其他会话的 1，未错误清空无关会话。M3 获得真实已读回执，最终消息总角标 0。
- M1/M3 最终各有四条，服务端 ID、clientMessageId、senderId、序号和 sent 状态逐项一致；唯一服务端 ID=4、唯一 clientMessageId=4，无重复。
- 两端目标群均 last=4/read=4/unread=0/mentions=[]。M3 Outbox 空；M1 旧图片 HTTP 500 待发记录仍保留，没有删除或重建。
- D1 既有账号只读核对：M1 未阅读时群 last=4/read=3/unread=1；阅读后 last=4/read=4/unread=0，HTTP 200。证明同账号服务端状态一致，不等于实际观察过桌面界面。

证据：[M1 最终库](../test/evidence/im-m3-group-20260902/20-m1-final.json)、[M3 最终库](../test/evidence/im-m3-group-20260902/20-m3-final.json)、[M1 回到原总数](../test/evidence/im-m3-group-20260902/18-m1-group-read-total-baseline.png)、[M3 回执](../test/evidence/im-m3-group-20260902/19-m3-reply-read.png)、[D1 阅读前](../test/evidence/im-m3-group-20260902/16-desktop-readonly-group-unread.json)、[D1 阅读后](../test/evidence/im-m3-group-20260902/20-desktop-readonly-after-read.json)。

## 未解决问题与下一步

| 优先级 | 问题 / 证据 | 状态 |
| --- | --- | --- |
| P1 | D1 GET `/api/im/sync/events?afterSequence=0&waitSeconds=0&take=500` 为 200，实际 40 条、latestSequence=181。目标群仅有两条 conversation.read，无四条消息对应的 message.created；群历史 GET 为 200 且有完整四条。请求编号响应未提供。 | 事件投递链路仍缺证/有缺项；当前依赖定期会话校对补正文，群实时同步不通过。不能用客户端补偿宣称服务端修复。 |
| P2 | M3 恢复网络后的早期检查未补齐，约 47 秒检查点才确认三条齐全。 | 要进一步区分启动请求超时、重试与 25 秒长轮询/校对等待，优化恢复唤醒并实测。 |
| P2 | 全量测试中 Outbox 入队后立即 due 查询偶发为空，单跑与全量复跑通过。 | 根因未确认；保留失败证据，不能仅以重跑通过关闭。 |
| P3 | @我筛选没有结果时文案仍为“暂无会话”，不够精确。 | 可改为筛选专属空状态并加回归。 |

继续未验收：群内离线发送 Outbox 的独立端到端重放、ACK 前精准崩溃与大批量事件重放、真实系统推送、D1/D2 窗口操作、服务端上传 500 恢复、完整高级 OA 流程/附件/通知矩阵、压力测试和性能指标。本轮不是整体目标完成，保持目标进行中。
