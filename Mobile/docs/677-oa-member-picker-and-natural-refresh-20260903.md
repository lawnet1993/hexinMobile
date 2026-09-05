# 677 选人抽屉空态与正常包自然续期

2026-09-03，Asia/Shanghai。上一轮 676 有修复、真实操作与回归证据，属于 progress。本轮继续推进移动端交互和会话稳定性；整体目标未完成。

## 已验证结论

- 修复转交/加签选人搜索无结果时，整页空态挤出抽屉、文字被键盘遮挡的问题；新提示紧凑并区分无候选与搜索无匹配。
- 5 项新回归通过，全量 **737/737**，静态分析 0 问题，正常 Profile 包构建成功。只安装独立 M3/test03，未操作 M1/M2 或 Windows UI。
- 正常包在 **01:46:30.747** 自然刷新并保存会话成功，HTTP 200。没有注入时钟、改系统时间、重新登录或使用探针入口。续期前打开的旧撤回确认被拦截，未产生撤回事件或 Outbox。
- 同一正常进程跨过原 exp=01:51:13 后，**01:51:28 真实撤回成功**；服务端事件于 01:51:29 创建，未再次刷新或出现登录失效。因此本次自然主动续期及跨原到期边界继续操作通过，不再只停留在 670 的时钟注入证据。

APK 正常入口 `lib/main.dart`，SHA256 `4C284F37356283458E31BA90FCC478B20ABB533CBC2A31A78B524768F32558AB`；[设备文件核对](../test/evidence/oa-member-picker-20260903/apk-check.json) 与构建一致。

## 选人空态复现与修复

在真实新单 OA-20260902-2560AC 的更多 → 转交中输入 `AI-UAT-NOMATCH`。[修复前截图](../test/evidence/oa-member-picker-20260903/07-empty-before.png) 显示大图标及“没有可选成员”被键盘遮挡。对应代码为固定 96dp 列表区域内嵌整页 `EmptyState`，其上下 padding 已占 96dp，还额外放置图标和文字。

[修改前几何测试](../test/evidence/oa-member-picker-20260903/red-layout.log)：普通/键盘场景出现 78px RenderFlex 溢出，小屏和横屏文字底部超出可见边界；不是因为改了文案才得到红测。更早 `red.log` 使用了新文案断言，不作为几何缺陷证据。

[页面改动](../lib/features/todos/presentation/approval_detail_page.dart) 仅将该区域改为 72dp 紧凑、可滚动文字提示，不改变人员来源、权限、请求体或实际处理人。无查询显示“暂无可选成员”，查询无匹配显示“未找到匹配成员”。保留 34dp 搜索框、已有成员行与选中后进入原因抽屉的链路。

真实复验：

| 场景 | 结果 | 证据 |
|---|---|---|
| 无匹配并弹出键盘 | 提示全部位于键盘上方，图标大留白移除 | [14](../test/evidence/oa-member-picker-20260903/14-empty-fixed.png) |
| 清空搜索 | 已有 Test Terminal 01 候选恢复 | [15](../test/evidence/oa-member-picker-20260903/15-cleared.png) |
| 搜索 test01 | 匹配该成员，搜索输入保留 | [16](../test/evidence/oa-member-picker-20260903/16-matched.png) |
| 点击匹配成员 | 正常进入转交原因抽屉；随后取消，未转交 | [17](../test/evidence/oa-member-picker-20260903/17-next-drawer.png) |

[5 项布局回归](../test/evidence/oa-member-picker-20260903/green.log) 覆盖 360×640、320×480、720×360、键盘 inset 和无候选，并验证文字可见边界、搜索尺寸、清空恢复、关闭无异常。完整代码在 [oa_mobile_pages_test.dart](../test/oa_mobile_pages_test.dart)。[全量 737](../test/evidence/oa-member-picker-20260903/full.log)、[分析](../test/evidence/oa-member-picker-20260903/analyze.log)、[构建](../test/evidence/oa-member-picker-20260903/build.log)。未更新 Golden，保留原脏工作区。

## 自然续期与确认隔离

670 的真实探针曾取得 exp=2026-09-02T17:51:13Z 的会话，正常刷新窗口预计为北京时间 01:46:13；那一轮注入调度时钟，不算自然到期验收。本轮正常入口连续运行，没有读取/导出令牌文本，也没有手动触发刷新接口。

- 01:42 的正常进程日志尚无 refresh/auth 诊断：[基线](../test/evidence/oa-member-picker-20260903/session-before.json)。随后安装本轮正常包，仅覆盖 APK，不清数据。
- 01:45:42 前通过真实 UI 打开撤回原因，填入 `AI-UAT-20260903-014000-BEFORE-REFRESH`。到自然窗口后抽屉仍在：[保持中的输入](../test/evidence/oa-member-picker-20260903/20-natural-refresh-held-dialog.png)。
- [正常进程白名单诊断](../test/evidence/oa-member-picker-20260903/session-natural-refresh-corrected.json) 记录 epoch `1788371190.747`，`REFRESH / status=200 / action=accepted`。生产代码只有刷新响应含令牌且安全存储的条件替换成功后才记录 accepted；这比只看没有登录弹窗更强，但不冒充网络抓包或 HTTP 请求编号。
- 点击此前已打开的确认，页面提示“登录状态已更新，请重新打开审批”，申请仍审批中，未错误使用新会话发送旧意图：[21](../test/evidence/oa-member-picker-20260903/21-old-confirm-blocked.png)。正常续期也会要求重新确认，这是当前保守行为，并不等于跨续期编辑体验已经最优。
- [状态对比](../test/evidence/oa-member-picker-20260903/refresh-state-comparison.json)：OA 游标维持 402，事件没有改变，Outbox 0，原两份草稿/四条已读回执不变。
- 续期后“我的”、通讯录、单聊可正常打开。通讯录默认折叠，[展开财顺](../test/evidence/oa-member-picker-20260903/24-department-open.png) 可见当前用户；[消息列表](../test/evidence/oa-member-picker-20260903/25-message-list.png) 与[单聊](../test/evidence/oa-member-picker-20260903/26-direct-after-refresh.png) 都显示对方离线，保留 6 条原消息。文件名 22 带 directory，但实际是“我的”页面，目录证据为 [23](../test/evidence/oa-member-picker-20260903/23-directory-ready.png)，不混用。

新只读助手 [inspect-device-session-events.ps1](../scripts/inspect-device-session-events.ps1) 仅解析指定存活进程的 MOBILE_SESSION 白名单字段，等待不超过 60 秒；进程改变/不存在则停止，不退化为读取全部进程日志。首次解析遗漏 PowerShell JSON 的 Int64 状态码，`session-natural-refresh.json` 的 status 为 null；已修正，以上使用 corrected，不能将解析器问题归因服务端。没有输出原始日志、令牌、密码、设备指纹或附件地址。[语法和整数类型检查](../test/evidence/oa-member-picker-20260903/helper-check.json)。

## 测试数据与边界

本轮仅新建一条 test03 自己发起/自己为实际部门负责人审批的测试借支，金额 100 CNY、其他用途、归还 2026-09-04，说明 `AI-UAT-20260903-014000-MEMBER-PICKER`。由上一轮已撤回单“再次发起”产生新编号 [2560AC](../test/evidence/oa-member-picker-20260903/04-submitted.png)，ID `2560ac24-091b-494f-a8af-5d943edb739a`，未改原单或原草稿。最终已撤回，未留下新审批任务。没有转交、加签、同意、付款、删除数据或修改现有流程。

本轮没有据“候选只有 test01”擅自扩大审批范围。当前页面使用 `imBootstrap.contacts`，实际通讯录显示财顺 1 人、其他联系人 1 人；这能解释当前渲染，不能证明完整审批候选权限/跨部门组织目录已经正确，仍需最新桌面行为和服务端配置核对。

仍保留：P2-675 通知错误文案、全部高级审批终态、真机新版/Windows UI、完整多端替换与未读、后台推送、较大群性能、服务端 IM 投影与媒体问题。此次自然主动刷新与跨原到期边界成功，不等于长时间离线或所有刷新失败场景都已验收。

## 跨原到期边界收尾

[进程观察](../test/evidence/oa-member-picker-20260903/natural-expiry-boundary.json) 证明 01:49:21–01:51:21 同一正常进程 15213 存活。重新打开的撤回抽屉绑定的是续期后的会话，在原令牌 exp 提示之后才点击确认；没有对设备时钟或调度器做更改。

[实际撤回截图](../test/evidence/oa-member-picker-20260903/32-after-old-expiry-withdrawn.png)：已撤回、部门负责人任务已取消，只留一条 `AI-UAT-20260903-014000-AFTER-EXPIRY` 处理记录。此前 BEFORE-REFRESH 意图没有提交。[续期后诊断](../test/evidence/oa-member-picker-20260903/session-after-old-expiry.json) 仍只有一次 REFRESH/200/accepted，未出现 AUTH 失效日志；不据缺失日志单独推导成功，成功同时由真实业务操作与服务端事件证明。

[最终 OA 状态](../test/evidence/oa-member-picker-20260903/final-comparison.json)：原两份草稿及四条回执完全不变，Outbox 空，游标 406。提交事件 399–402，撤回事件 403–406，服务端时间分别为 `17:39:40.568488Z` 与 `17:51:29.191025Z`；撤回 eventId `44db99ca-295c-435a-a95d-d99884e24426`，取消任务 eventId `18c64489-ca02-414d-adfb-bf8fae748627`。事件 ID 不是 HTTP trace ID。撤回事件落库为 17:51:44.524498Z，存在约 15 秒事件同步延迟，不能声称即时通知性能达标。

[最终 IM](../test/evidence/oa-member-picker-20260903/im-final.json)：applied/acked 207、单聊 6 条/已读 6、测试群 11 条/已读 11、空群 0，未读均为 0，Outbox 空。本轮没有发 IM 消息。

[桌面只读核对](../test/evidence/oa-member-picker-20260903/desktop-after-refresh.json)：运行中 Windows 1.0.87/test01 在 M3 续期后仍 IM/OA 200。这不是桌面 UI 操作，也不等于同账号完整多端矩阵。[运行采样](../test/evidence/oa-member-picker-20260903/runtime-final.json)：M3 Wi-Fi/移动数据均 1，正常包当前进程采样 FATAL/E/flutter 均 0。

跨原到期边界后再杀进程冷启动，[首页](../test/evidence/oa-member-picker-20260903/33-cold-after-expiry.png) 自动恢复 test03、通知 20、待处理 0；[新进程诊断](../test/evidence/oa-member-picker-20260903/session-cold-restored.json) 没有额外刷新或失效事件。未输入登录凭据，没有通过重登掩盖持久会话丢失。安装后首次截图 09 只显示加载中的底部导航，不用于首页完成结论；加载完成证据为 10 和冷启动 33。
