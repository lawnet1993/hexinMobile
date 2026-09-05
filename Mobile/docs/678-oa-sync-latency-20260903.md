# 678 OA 同步分段测量与本机操作后追赶

时间：2026-09-03 01:56–02:09（Asia/Shanghai）。结论：本轮本机通知已读追赶和离线补偿通过；整体 IM/OA 对齐目标仍进行中，不能将此解释为跨端性能全部通过。

## 环境与范围

- 当前项目：`E:\SecureAccess-client-source-20260824-151204\Client\Mobile`，保留既有未提交修改。
- 仅操作 M3 `emulator-5556`、Android 16、test03。M1 真机和 M2 未安装、未操作。
- 正常 `lib/main.dart` Profile 包，无测试入口、时钟覆盖、手工令牌注入或数据库改写。
- D1 当前安装版 1.0.87、test01、进程运行，02:04 只读 IM/OA 均 HTTP 200。不是 Windows UI 实测，见 [桌面核对](../test/evidence/oa-sync-latency-20260903/desktop-health.json)。
- 测试 API 为 `api.sfhkh.com`。本轮未新建或处理审批，只打开原 AI-UAT 测试单生成的五条通知，将其标记已读。
- 前一目标工作已完成分段诊断代码及构建测试，本轮通过原句柄终态日志确认完成，没有因句柄缺失而重复启动原任务；随后完成行为改造和新回归。

## 1. 先定位，再修改

677 中撤回事件 created_at 到 applied_at 相差约 15.3 秒，但这不足以归因于 SQLite 或 UI。本轮在成功非空批次记录三个独立 Stopwatch：事件 GET、后续投影读取、本地提交。

只记录耗时、数量、等待参数和时间，不记录账号、事件 ID、业务正文、URL 或凭据。Release 禁用，空轮询不输出。读取助手严格限定当前移动端 PID 和字段白名单。

| 样本 | waitSeconds | 事件请求 ms | 投影读取 ms | 提交 ms | 批次合计 ms | 本机已读意图到 applied_at ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 改造前 seq407 | 20 | 20167 | 518 | 74 | 20759 | 6152.924 |
| 改造前 seq408 | 20 | 20165 | 677 | 56 | 20898 | 9290.619 |
| 改造后 seq409 | 0 | 208 | 790 | 58 | 1056 | 1730.190 |
| 改造后 seq410 | 0 | 227 | 655 | 74 | 956 | 1589.943 |

前两次请求都接近等满 20 秒，新事件在请求途中产生；主要等待在事件请求阶段。投影仍为原顺序读取、SQLite 仍为原事务，本轮没有把次要的约半秒读取当成 15 秒根因去改造。

**测量边界：**批次合计含事件产生前的长轮询等待，不能写成“用户原来每次等 20 秒”。最后一列使用同一设备已读意图与本地 applied_at；它是落库时间戳差值，不是屏幕绘制帧耗时。applied_at 在本地提交准备时取值，提交完成还需表中 commitMs。服务端与设备时钟未经同源校准，跨时钟 created_at 差值仅作核对。以上仅前后各两次通知样本，不是 P95、压测或跨端 SLA。

证据：[前两次分段数据](../test/evidence/oa-sync-latency-20260903/timing-second.json)、[后两次分段数据](../test/evidence/oa-sync-latency-20260903/timing-fixed-second.json)、[逐条 ID 与时间](../test/evidence/oa-sync-latency-20260903/sample-metrics.json)。

采集助手初版将 PowerShell 自动解析的 UTC DateTime 先转字符串，导致显示时区误移，已修正为保留 DateTime Kind。`timing-first.json` 的 recordedAt 不作为时间证据，使用 [修正后的首样本](../test/evidence/oa-sync-latency-20260903/timing-first-corrected.json) 和上述最终文件；耗时数值未改变。

## 2. 实际修改

- `OaSyncCoordinator.catchUpAfterMutation()`：服务器确认本机操作后发出追赶提示，仅取消正在进行的旧长轮询，下一轮 waitSeconds=0；追平后仍回到正常 20 秒长轮询。
- 不制造事件、游标、已读投影或在线状态；仍从服务端获取事件，再将事件、缓存和游标按原规则原子提交。
- 不额外全量刷新工作区，也不因本机写成功闪现“连接中”。重复提示合并；进行中的零等待追赶和启动刷新不反复取消；停止后提示无效。
- 若取消恰好撞上已完成的 SQLite 提交，仍发布该批次变化；否则下一次请求从新游标开始会跳过它的 UI 通知。
- 协调器自身送达 Outbox 后也立即追赶，不先进入长等待。
- 已接入通知单条已读/全部已读、审批提交、审批处理（审核/撤回/转交/加签/退回/催办）和抄送已读成功路径。失败或仅离线入队不会伪造成功追赶。
- 会话、任务版本、权限和取消守卫保留。本轮实际操作覆盖通知单条已读，其他审批动作追赶接入未逐项重新在服务器执行，不能据此声称高级流程已验收。

涉及源文件：

- [协调器](../lib/features/collaboration/application/oa_catalog_sync_coordinator.dart)
- [分段诊断](../lib/features/collaboration/data/oa_sync_timing.dart) 与 [仓库计时调用](../lib/features/collaboration/data/collaboration_repositories.dart)
- [通知](../lib/features/notifications/presentation/notifications_page.dart)、[审批详情](../lib/features/todos/presentation/approval_detail_page.dart)、[审批发起](../lib/features/todos/presentation/approval_request_page.dart)
- [只读计时采集助手](../scripts/inspect-device-oa-sync-timing.ps1)

## 3. M3 真实操作

正常改造前计时包哈希 `34F0675D3FEEE8D221F6C34C55B51A9BD127990AF1A8E0544F1E0B0FCA68A754`；最终正常包 SHA-256 `33CB4C5EA8DC8EC1A057C59091EA5CDCB83FF4366B55D9FDE290ABDBB2C2B340`，本机与安装后 base.apk 一致，见 [安装校验](../test/evidence/oa-sync-latency-20260903/installed-final.json)。

1. 基线通知总数26、未读20、OA游标406。
2. 计时包打开 OA-20260902-2560AC 的撤回和任务结束通知，产生407/408，未读20→19→18。
3. 新包打开同一单的待审批和提交通知。详情均显示真实终态“已撤回”，没有将旧通知当作当前可审批任务。产生409/410，未读18→17→16。
4. 关闭 M3 Wi-Fi 与移动数据；打开 OA-20260902-2DDF00 的任务结束通知。缓存详情显示已撤回及“当前显示本机审批快照”，无可提交操作；新增已读回执 pending，游标保持410。
5. 断网强制停止再启动，自动恢复 test03，无需输入凭据；通知未读15，明确显示“1条已读状态待同步”，回执保留。
6. 02:08:13 恢复 M3 网络，没有点击重试。新进程自动发送原回执，state=sent、attempts=1、read_at不变，获取真实 seq411 并持久化，待同步提示消失。此补偿批次 waitSeconds=0、1660ms。
7. 最终首页未读15、待办0，Wi-Fi/移动数据恢复1/1。当前 PID 范围日志中 FATAL EXCEPTION 和 E/flutter 均0，不是整段设备日志的无崩溃保证。

关键截图：

- [原通知与19未读](../test/evidence/oa-sync-latency-20260903/06-first-read-list.png)
- [修复后单据详情](../test/evidence/oa-sync-latency-20260903/11-fixed-read-first.png)
- [修复后16未读](../test/evidence/oa-sync-latency-20260903/14-fixed-second-list.png)
- [离线详情](../test/evidence/oa-sync-latency-20260903/16-offline-read.png)
- [离线冷启动待同步](../test/evidence/oa-sync-latency-20260903/19-offline-cold-notifications.png)
- [联网自动清除待同步](../test/evidence/oa-sync-latency-20260903/20-reconnected-notifications.png)
- [最终首页](../test/evidence/oa-sync-latency-20260903/21-final-home.png)

部分首次启动抓取（02/08/17）未取得 UI hierarchy，助手按失败退出，未复用旧截图。后续03/09/18才有实际页面证据。本轮未建立冷启动完成时间指标，不能以重试抓到页面证明启动性能达标；离线初始首页仍曾显示“同步中”，后续通知页面明确显示待同步回执。

## 4. 数据保留与可复现记录

- 两条原草稿 ID/更新时间完全不变，原四条已读回执完全不变。
- 新增五条已读回执，总数9，最终全部sent；OA Outbox空，OA游标411。
- 新事件407–411均为`oa.notification.read`，逐个ID见 [保留核对](../test/evidence/oa-sync-latency-20260903/preservation-check.json)，事件ID不是HTTP请求编号。
- IM applied/acked仍207；单聊6条、read6、未读0；目标群11条、read11、未读0；原空群0条。消息账本及游标前后完全相同，IM Outbox空。
- [离线回执](../test/evidence/oa-sync-latency-20260903/oa-offline-pending.json)、[冷启动回执](../test/evidence/oa-sync-latency-20260903/oa-offline-cold.json)、[联网落库](../test/evidence/oa-sync-latency-20260903/oa-reconnected.json)、[补偿计时](../test/evidence/oa-sync-latency-20260903/timing-reconnected.json)、[最终运行状态](../test/evidence/oa-sync-latency-20260903/runtime-final.json)。

复现时使用独立测试账号和其 AI-UAT 通知：安装正常 Profile 包→保存本机 OA 基线→等待普通事件轮询→UI 打开未读测试通知→采集当前PID计时与SQLite只读元数据→返回核对未读。再次断网打开另一通知→确认pending后杀进程→离线恢复→联网不点击→核对原回执sent和唯一新事件。不得操作“全部已读”代替逐条样本，不得打印原始日志或解密业务缓存。

## 5. 自动回归

- 新增9项：2项诊断字段/空批次测试，7项本机追赶、重复提示、启动、停止、无事件不造游标、通知成功/失败真实本地HTTP接入测试。
- 同步/会话/计时专项 **55/55**，见 [专项日志](../test/evidence/oa-sync-latency-20260903/focused-final.log)。
- 含审批交互守卫和通知导航的专项 **60/60**（先于补入两项通知接入测试运行），见 [交互日志](../test/evidence/oa-sync-latency-20260903/wakeup-tests.log)。
- 最终全量 **746/746**，见 [全量日志](../test/evidence/oa-sync-latency-20260903/full-final.log)；[analyze](../test/evidence/oa-sync-latency-20260903/analyze-final.log) 0问题；[正常包构建](../test/evidence/oa-sync-latency-20260903/build-final.log)成功。原进程句柄均取得exit0。
- 未更新 Golden，无安装到M1/M2，无提交/推送代码，无服务端或数据库修改。

## 6. 未完成与问题

- **P2-678-01：服务端事件请求约等满20秒。** 本机写成功后已主动追赶，远端写入、网关缓冲/服务端通知唤醒具体原因仍需对应服务证据。没有修改整体轮询频率，也没有证明跨端新事件立即可见。不能将本轮优化当成该问题全修复。
- **P2-675-01仍在：** 本人撤回后的任务取消通知正文仍写“该节点已由其他处理人完成”。本轮又可见该现象，没有擅自按标题猜测改写服务端语义。
- 真机/Windows UI、同账号多端替换与密码失效矩阵、跨端已读、完整高级OA节点/表单/附件/条件分支、原生推送、长离线续期失败和整机性能仍未完成。
- 后续重点：远端事件唤醒与桌面多端真实操作；当前测试成员可选范围、冷启动等待和此前媒体/群事件服务端问题继续保留。目标保持 active。
