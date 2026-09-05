# 691：消息列表真实在线状态刷新

日期：2026-09-03，约 05:21–05:38（Asia/Shanghai）。结论：**部分通过**。整体目标仍为 IM/OA 与当前安装桌面端对齐，不能据本轮局部修复判定整体通过。

后续：[692 同步采集来源时序](692-presence-source-comparison-20260903.md) 已补两轮移动端响应/投影/列表与资料查询证据。未复现新离线响应被旧在线覆盖，也未证明不同接口在同一时刻冲突；本篇保留原始观测，根因判断请结合 692，离线及时性仍开放。

## 缺陷与修复范围

上一轮 690 已实测：两台模拟器均在线，消息列表静置后联系人变为“状态未知”，必须进入单聊才恢复在线。本轮改动前再次确认 [M3 列表未知](../test/evidence/message-list-presence-refresh-20260903/01-m3-before.png)。原因是共享 presence 观测 60 秒后到期，原 MessagesPage 只读缓存投影，没有前台补取机制。

新增 [MessageListPresence](../lib/features/messages/presentation/message_list_presence.dart)，由 [MessagesPage](../lib/features/messages/presentation/messages_page.dart) 集中管理可见单聊状态：

- 根据实际 RenderBox 与列表视口相交情况选择目标，列表缓存区和屏幕外的行不请求，群聊不当成个人状态查询。
- 复用现有 `/api/im/conversations/{id}/presence` 接口，**不是新造批量 API**。页面统一调度，最多两个并发，30 秒周期；滚动合并 120ms，同一会话两次尝试间隔至少 25 秒，避免重建控件触发重复请求。
- 不重新加载整个通讯录、消息账本或 bootstrap；结果进入已有共享 presence 投影，保持不同页面的真实状态来源一致。
- 离开页面、被抽屉覆盖、切后台、退出或更新登录会话时取消请求；回来立即刷新。不会把旧会话的迟到结果发布给新会话。
- 单个查询失败只将该行降级为未知，下一周期重试，不清令牌、不弹循环错误、不伪造离线/在线；错误身份或群统计响应不能标记单聊用户在线。
- [仓储](../lib/features/collaboration/data/collaboration_repositories.dart) 的 presence 请求接受 CancelToken，并在写共享成员观测前再次检查取消状态。

未扩大为服务器修改，未改变群/单聊成员解析、已读规则、消息内容、OA 业务流程或密码。

## 自动化证据

新增 [列表刷新测试](../test/message_list_presence_test.dart) 10 项及 [仓储取消测试](../test/im_member_presence_repository_test.dart) 1 项，覆盖：

1. 2000 会话中初始只查询视口内 6 个单聊；跳到第 50 行后只增加 7 个，累计 13 次，不查询缓存行和群，最大并发 2。
2. 真实 MessagesPage 接线：只轮询 direct 行，不取 group 在线总数。
3. 连续 90 秒模拟时间每轮得到新观测，不因 60 秒到期停止刷新。
4. 后台取消、回前台即取新状态，旧请求迟到不会覆盖。
5. Offstage Tab 停止及恢复。
6. 登录令牌轮换隔离。
7. 失败限频、局部未知及恢复，仍保留登录。
8. 群响应不得标为个人在线。
9. 实际底部抽屉覆盖时停止，关闭后恢复。
10. 退出登录取消且不继续请求。
11. 真实本地 HTTP 取消后不得发布迟到成员状态。

原 presence 投影测试继续保留过期、乱序、跨登录和缓存不可直接证明在线的断言；仅显式关闭该测试夹具的网络轮询，并在测试结束释放外部 ProviderContainer 的计时器。初次运行发现测试夹具的 60 秒观测计时器尚未释放，修正清理后通过，不把测试清理问题记为产品缺陷。

[专项 47/47](../test/evidence/message-list-presence-refresh-20260903/targeted-final.log)、[全量 899/899](../test/evidence/message-list-presence-refresh-20260903/full-tests.log)、[分析 0 问题](../test/evidence/message-list-presence-refresh-20260903/analyze.log)。这些不是 2000 人实机 FPS 或完整线上用例通过率。

## 安装与真实设备验收

独立 M3/test03（财顺）与 M4/test04（合盈），Android 16。正常 profile arm64+x64 包已覆盖安装两台，没有清数据、复制身份或更换账号；M1 真机和 M2 未操作。

APK SHA-256：`D9944AB568C74A987C6D260805F278BE01540CA63CB0BCEAFB9B1A692CDAE55C`。两次完成构建哈希一致；最终包 93.2MB。[构建](../test/evidence/message-list-presence-refresh-20260903/build.log)、[串行复核构建](../test/evidence/message-list-presence-refresh-20260903/build-final.log)、[M3 安装](../test/evidence/message-list-presence-refresh-20260903/install-5556.json)、[M4 安装](../test/evidence/message-list-presence-refresh-20260903/install-5558.json)。Activity 计时 3678ms/7452ms，不作为 Flutter 页面可用耗时。包体较上一轮 80.6MB 增大，尚未定位 dex/打包差异，不宣称包体性能通过。

初次进入消息列表，即自动显示 Test Terminal 04 在线、Test Terminal 01 离线，没有打开会话或手动下拉，[列表初始状态](../test/evidence/message-list-presence-refresh-20260903/04-m3-list-initial.png)。

通过 [uat-message-list-presence.ps1](../scripts/uat-message-list-presence.ps1)，M3 始终停留消息列表，不打开单聊、不下拉刷新。先观察约 101 秒，再仅断开 M4 网络、观察离线变化，finally 恢复 M4 原网络后观察重连。[运行时间线](../test/evidence/message-list-presence-refresh-20260903/presence-run.json) 已结束；采样名中的 30/60/90 是计划等待时长，不是精确网络延迟。

| 主机时间（+08:00） | 实际动作/状态 | 证据 |
| --- | --- | --- |
| 05:30:11 → 05:31:50 | 不操作列表，四次采样均在线，覆盖 60 秒观测有效期 | [约 101 秒仍在线](../test/evidence/message-list-presence-refresh-20260903/baseline-90.png) |
| 05:31:51 | M4 确认无默认网络，Wi-Fi/数据均关闭 | 运行时间线 |
| 05:32:24 / 05:32:57 / 05:33:30 / 05:34:02 | M3 列表仍显示对方在线 | [关闭网络约 131 秒时](../test/evidence/message-list-presence-refresh-20260903/peer-offline-120.png) |
| 05:34:35 | M3 列表自行变为离线，距断网约 164 秒 | [自动离线](../test/evidence/message-list-presence-refresh-20260903/peer-offline-150.png) |
| 05:34:35 → 05:35:08 | M4 原网络恢复 1/1，约 33 秒后的采样中列表自行恢复在线 | [自动恢复](../test/evidence/message-list-presence-refresh-20260903/peer-reconnected-30.png) |

结论：**静置后过期为未知的列表补取问题已在此路径修复；断网最终转离线和重连转在线有真实证据，但离线及时性不能判通过**。

### P2 待查：资料接口与列表的离线判定时间不一致

M4 仍断网时，使用已安装 Windows/test01 的现有会话只读请求 test04 资料，`GET /api/im/members/{test04Id}/profile` 在 **05:33:48** 返回 HTTP 200、`isOnline=false`、`lastSeenAt=2026-09-02T21:31:34.4697Z`。M3 在 **05:34:02** 仍显示在线，直到 **05:34:35** 才显示离线。

预期：列表应及时反映权威状态，同一成员在不同入口使用一致口径；不可通过延长旧缓存寿命掩盖差异。实际：至少有上述接口与 UI 时间样本不一致，用户可能向已断网联系人发起实时联系。M4 重连后资料接口与列表均恢复在线。

[离线时资料响应摘要](../test/evidence/message-list-presence-refresh-20260903/desktop-peer-offline-check.json)、[重连时资料摘要](../test/evidence/message-list-presence-refresh-20260903/desktop-peer-reconnected-check.json)。请求编号响应未提供，明确记为 null；没有虚构请求 ID。新增 [受限只读入口](../scripts/inspect-desktop-im-uat.ps1) 的 `-InspectTestMember` 仅允许 test03/test04，输出状态白名单，不输出令牌、设备 ID、原始响应或附件地址。

本轮没有捕获 M3 会话 presence 接口在该时刻的原始响应，因此**尚不能断言是服务端 TTL、网关缓存、接口口径还是客户端投影覆盖**。不把约 164 秒当作已验证的服务端配置值，不为通过测试伪造在线/离线。下一步应在受控测试包中仅采集 presence 白名单字段，与资料接口同时对照定位。

### 本机断网：未知、保留登录、恢复

继续使用 [本机断网脚本](../scripts/uat-message-list-observer-offline.ps1)，M3 保持同一消息列表，05:35:54 断开本机 Wi-Fi/数据并确认无默认网络，M4 保持在线。05:36:36 采样为“状态未知”，头像不再显示绿色在线点，消息列表仍保留，未跳登录、未抹去数据、未出现循环弹窗。网络在 finally 恢复为原 1/1；05:37:16 采样自行恢复在线。

[本机断网时间线](../test/evidence/message-list-presence-refresh-20260903/observer-offline-run.json)、[断网未知](../test/evidence/message-list-presence-refresh-20260903/observer-offline-40.png)、[联网恢复](../test/evidence/message-list-presence-refresh-20260903/observer-reconnected-35.png)。只证明这些采样时刻的状态，不把等待 40 秒当作瞬时离线检测能力，也不宣称期间每一帧都已记录。

## 保留数据与最终检查

- 本轮没有发送新消息、创建新群、提交新审批或更改密码。M3/M4 既有测试群三条消息 ID/序号/本地状态完全不变，所有会话数量、最新序号、已读与未读元数据均保留。
- M3 原两个待发媒体的 ID、会话、类型和创建时间保留；未宣称媒体服务端错误修复。M4 没有新增 Outbox 项。
- M3 OA 两条草稿、十个已读回执和 OA Outbox 完全保留。
- [九项数据比对](../test/evidence/message-list-presence-refresh-20260903/verification.json) 全为 true；[M3 最终 SQLite](../test/evidence/message-list-presence-refresh-20260903/m3-after.json)、[M4 最终 SQLite](../test/evidence/message-list-presence-refresh-20260903/m4-after.json)、[OA 最终快照](../test/evidence/message-list-presence-refresh-20260903/m3-oa-after.json)。
- 最终两台 Wi-Fi/数据均为 1/1，当前 app PID 范围未发现 Unhandled Exception / RenderFlex overflow / FATAL EXCEPTION，[检查摘要](../test/evidence/message-list-presence-refresh-20260903/runtime-final.json)。不输出原始日志，不据短期计数声称长期稳定。
- 安装 Windows 1.0.87/test01 仍运行，05:31:39 只读 IM/OA 均 HTTP 200，[桌面检查](../test/evidence/message-list-presence-refresh-20260903/desktop-after.json)。当前工具未提供 Windows 实际控制入口；本轮的桌面证据明确限于已安装程序会话与只读状态，不用旧桌面源码替代窗口验收。

## 未完成项

- P2 离线判定延迟与资料接口/消息列表口径差异：仍需同时采集直接 presence 响应定位，尚未关闭。
- 本轮 profile 包体为 93.2MB，较上一轮增大；发布包体与 dex 差异尚未定位，不能作为性能通过。
- 同账号 Windows/移动互不替换、第二设备同平台替换、本人跨端已读、密码更改会话失效。
- Windows 窗口实操、真机和大通讯录/大群实机性能。
- 退群重入、移除成员后权限、超过 500 条补拉、ACK 前杀进程重放、推送唤醒和长时间稳定性。
- 高级 OA 分支、跨部门审批、会签/或签/办理/付款/抄送及双公式线上验收。
- 先前服务端媒体 500 等缺陷保持未关闭；本轮未重发或删除原待发媒体。
