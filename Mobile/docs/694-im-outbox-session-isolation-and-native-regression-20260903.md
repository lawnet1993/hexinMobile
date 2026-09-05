# 694：IM 待发队列会话隔离与真实发送回归

2026-09-03，Asia/Shanghai。**总体结论：部分通过。** 本轮修复了可复现的跨账号发送风险；新包双模拟器文字群聊、未读与回执通过。原图片和视频重试仍 HTTP 500，媒体跨端链路没有通过。整体 IM/OA 目标继续，不以本轮专项替代完整验收。

## 1. 本轮范围与环境

- M3：emulator-5556/test03，财顺，Test Terminal 03；M4：emulator-5558/test04，合盈，Test Terminal 04。两台 Android 16，保留原安装数据及身份。
- 安装正常 `lib/main.dart` profile 包，没有测试断点入口、在线会话切换注入或诊断开关。未操作 M1 真机和 M2。
- 当前运行 Windows 为 1.0.87/test01；已安装客户端的只读 IM/OA GET 均 200，见 [桌面健康记录](../test/evidence/im-outbox-session-20260903/desktop-health.json)。这是会话/接口证据，不是 Windows UI 验收。本轮工具发现没有可调用的 Windows 电脑控制工具，不以旧桌面源码替代实际窗口。
- 原生操作由 ADB 驱动真实 Android UI，接口及 SQLite 只核对状态；未直接写业务数据库。仅新增一条带 AI-UAT 前缀群消息，原媒体分别点击一次重试。
- 主机时间约 06:13–06:24；Android 状态栏及消息时间存在不同钟域，未调整任何时钟，不拿截图时间推算端到端延迟。

## 2. P1：待发消息可能使用切换后的账号身份（已修复）

### 复现与证据

1. 账号 A 创建待发消息；让队列读取在异步边界暂停。
2. 保存账号 B 的会话，再恢复队列读取与发送。
3. 原实现提取 A 队列，但 `_post*` 内重新调用无 `forSession` 的 `forIm()`；请求使用 B 的账号头和令牌。
4. 另验证请求已经发出后切换账号、同账号重新登录、退出登录，再返回 200/503/401/409；原实现仍处理旧结果、改变待发记录或继续发送后续项目。

测试使用本地回环 HTTP、合成身份、临时 SQLite 和加密附件文件，不在线上制造跨账号误发。[修复前日志](../test/evidence/im-outbox-session-20260903/before.log)中原 26 项全部失败，前六项分别观察到文本、名片、文件、图片、音频、视频使用 B 身份发送。

预期：排队消息只能属于原账号；登录状态变化后，旧批次停止，不得影响新会话或伪造失败/成功。影响包括消息身份混用、旧队列被错误清理及媒体多步上传继续执行。

### 改动

[IM Repository](../lib/features/collaboration/data/collaboration_repositories.dart) 中：

- 批次捕获完整原会话，所有发送方法显式 `forIm(forSession: session)`，附件始终按原账号读取。
- 发送前、媒体上传与封面上传之间、最终媒体消息发送前核对原会话。
- SQLite 成功/失败写入通过会话锁与登录切换串行，锁内不执行网络请求。
- 迟到响应遇到账号/设备/令牌变化时，停止批次，不增加失败次数，不删除原待发消息和附件，不向新页面发布旧会话刷新结果。
- 当前会话的 401 或 `409 session_replaced` 交给现有会话失效处理；支持与协调器一致的 `code`/`Code`。业务 403/409 保持单条失败，5xx 保持重试，不当成退出登录。
- 封面普通失败仍可发送视频，但封面阶段的会话失效不再被“可选封面”分支吞掉。

边界：已经发到服务器的原账号请求无法撤回；会话变化后保留稳定 clientMessageId，原账号恢复时重放。服务端去重在本地 HTTP fixture 中受控验证，本轮没有在线制造该危险竞态，也不能据此宣称所有重登/换机矩阵完成。

## 3. 自动回归与正常安装

[新增测试](../test/im_outbox_session_isolation_test.dart)共 39 项：六种消息在队列读取处换账号、三类会话变化与四类迟到状态、视频/封面中途变化、当前 401/409、错误码拼写兼容、业务失败、可选封面 503，以及各媒体迟到成功后的稳定 ID 重放。另结合已有附件与队列回归。

| 验证 | 结果 | 证据 |
| --- | --- | --- |
| 隔离、队列和媒体专项 | 47/47 | [专项日志](../test/evidence/im-outbox-session-20260903/after-targeted.log) |
| 全量 Flutter 测试 | 954/954 | [全量日志](../test/evidence/im-outbox-session-20260903/full-test.log) |
| 静态分析 | 0 问题 | [分析日志](../test/evidence/im-outbox-session-20260903/analyze.log) |
| 正常 profile APK | 成功，93.2 MB，Gradle 52.8s | [构建日志](../test/evidence/im-outbox-session-20260903/build.log) |
| M3/M4 保留数据安装 | 两台成功，设备上 base.apk 哈希相同 | [安装与哈希](../test/evidence/im-outbox-session-20260903/installed-build.json) |

APK SHA256：`B9C67ACBA57785CFB643B62A9579CFF518B3305B0EB62FE27E78427F5DC49376`。

## 4. 真实群聊发送、接收、阅读与重启

使用已有两人群 `AI-UAT-20260903-050600-M3-M4-GROUP`，ID `95e704ae-0e34-4f56-87db-038526796d6c`，原 seq1–4 保留。

1. 两台安装后均恢复各自首页；M4 不进入会话。
2. M3 打开该群输入 `AI-UAT-20260903-061900-SESSION-GUARD`，[发送前截图](../test/evidence/im-outbox-session-20260903/m3-group-ready.png)和[唯一点击日志](../test/evidence/im-outbox-session-20260903/group-send-once.json)证明使用原生输入与一次发送。
3. M3 显示[已发送](../test/evidence/im-outbox-session-20260903/m3-group-sent.png)。M4 仍在[首页显示未读 1](../test/evidence/im-outbox-session-20260903/m4-home-unread.png)，随后[列表仍为未读 1](../test/evidence/im-outbox-session-20260903/m4-list-unread.png)。只读 [SQLite 快照](../test/evidence/im-outbox-session-20260903/m4-im-unread.json)为 lastMessage=5、lastRead=4、unread=1，未提前阅读。
4. M4 [实际进入群聊并看到正文](../test/evidence/im-outbox-session-20260903/m4-group-read.png)后 read=5、unread=0；M3 未刷新或重新打开会话，[回执自动变为已读](../test/evidence/im-outbox-session-20260903/m3-group-read-receipt.png)。
5. 两台正常强制停止并冷启动，再读数据库。原四条与新消息均唯一，双方 read=5/unread=0 持久保留；M3 applied/acked=296，M4=295，各自对齐，不要求不同账号的事件序号相等。

新消息账本：

| 字段 | 实值 |
| --- | --- |
| 服务端消息 ID | `323012c0-5d62-4aaf-b13b-64944248e617` |
| clientMessageId | `22dd2ad4-e15d-464c-9445-56d2dbcd573e` |
| 群内序号 | 5 |
| 发件成员 | `c404c59a-6dc3-4e6b-a1dc-d5d0c20786cc`（test03） |
| 服务端创建时间 | `2026-09-02T22:19:50.969346Z` |
| 两端最终本地状态 | sent，各一条 |

证据：[M3 最终账本](../test/evidence/im-outbox-session-20260903/m3-im-final.json)、[M4 最终账本](../test/evidence/im-outbox-session-20260903/m4-im-final.json)。这证明两个不同账号的本轮群聊发送/阅读，不替代同账号桌面与手机双端验收。

## 5. P1：媒体 HTTP 500 仍未解决

未重新选择附件或创建第二条媒体消息，只对已有记录分别点击一次“立即重试”。

| 旧记录 | 原生重试与持久结果 | 请求路径（由客户端发送实现核对） |
| --- | --- | --- |
| 单聊图片，clientMessageId `13dc7539-f758-450e-a45d-ae151c846e14` | attempts 46→47，seq0/pending，HTTP 500 | `POST /api/im/conversations/2a2ea21f-2ad6-49b3-b3da-407d1e7e4136/images` |
| 群聊视频，clientMessageId `4bd94d7a-d990-44d8-9b72-4edc3fc4925c` | attempts 46→47，seq0/pending，HTTP 500 | `POST /api/im/upload/video` |

图片：[唯一重试日志](../test/evidence/im-outbox-session-20260903/image-retry-once.json)、[重试前账本](../test/evidence/im-outbox-session-20260903/image-im-before-retry.json)、[重试后账本](../test/evidence/im-outbox-session-20260903/image-im-after-retry.json)、[实际错误抽屉](../test/evidence/im-outbox-session-20260903/m3-image-retry-result.png)。

视频：[唯一重试日志](../test/evidence/im-outbox-session-20260903/video-retry-once.json)、[重试前账本](../test/evidence/im-outbox-session-20260903/video-im-before-retry.json)、[重试后账本](../test/evidence/im-outbox-session-20260903/video-im-after-retry.json)、[实际错误抽屉](../test/evidence/im-outbox-session-20260903/m3-video-retry-result.png)。

预期：上传成功后原临时消息替换成服务端确认记录，对端收到可预览媒体。实际：上传/图片发送失败，未到确认阶段。影响：图片和视频不能送达。现有自动重试仍保留，页面没有伪报成功；不是“新会话隔离修复后媒体已解决”。没有获得响应请求编号或经过安全处理的响应正文，不猜测存储服务、反代或后端根因。下一步需要安全采集这些响应信息并与当前服务端上传协议/日志核对。

## 6. 数据保留与取证质量

- [22 项最终元数据核对](../test/evidence/im-outbox-session-20260903/final-checks.json)全部通过：原群消息、其他会话元数据、原两条待发 ID、M4 空队列，以及 M3 两草稿、十条 OA 阅读回执均保留。
- OA [变更前](../test/evidence/im-outbox-session-20260903/m3-oa-before.json)/[变更后](../test/evidence/im-outbox-session-20260903/m3-oa-final.json)一致，没有提交新审批。
- [重启后运行状态](../test/evidence/im-outbox-session-20260903/runtime-final.json)：M3 PID12400，M4 PID27079，Wi-Fi/移动数据均 1/1；本次当前进程日志未发现 Unhandled/FATAL/RenderFlex overflow，诊断标记为 0。这不代表长时间性能或所有崩溃路径验收。
- 最终 M3 停在[消息全部列表](../test/evidence/im-outbox-session-20260903/m3-final-list.png)，M4 停在[工作台](../test/evidence/im-outbox-session-20260903/m4-cold-home.png)。
- 本轮发现截图脚本未拒绝同名 JSON，初次 `m3-before.json`/`m4-before.json` 被截图元数据覆盖。安装前重新以 `m3-im-before.json`/`m4-im-before.json` 采集；核对使用重采快照，不使用被覆盖文件作为数据库证据。已修复 [抓图脚本](../scripts/capture-device-uat.ps1)，[仅 JSON 重名保护测试](../test/evidence/im-outbox-session-20260903/capture-collision-check.json)确认拒绝覆盖。

## 7. 仍未完成

媒体 500 根因与真实送达；同账号 D1/M1、M2/D2 替换及改密失效矩阵；Windows 原生 UI 与真机完整回归；大型离线批量、500 条追平、多崩溃窗口、推送注册/唤醒、真实大目录与长期性能；高级 OA 分支/角色/会签/或签与已有服务端问题。沿用 [总对齐清单](DESKTOP-MOBILE-FUNCTION-ALIGNMENT.md)，不缩减原目标。本轮无提交、推送或服务端改动。
