# 692：在线状态来源与离线延迟实测

日期：2026-09-03，约 05:39–05:52（Asia/Shanghai）。结论：**部分通过；离线及时性仍未验收通过**。本轮收敛 691 的原因排查，不宣称完成整体 IM/OA 对齐。

## 结论与证据边界

两轮真实断网中，会话 presence 的新离线响应进入移动端后，共享成员状态和列表构建决策都随即变为离线，没有复现“新接口已返回离线、列表仍保持在线”。字段解析后的诊断点到离线构建决策分别为约 **17ms / 40ms**；这是同一设备内的日志时差，不是屏幕绘制耗时或 FPS。后续原生截图确认灰色离线点。

第一轮约 **140 秒**、第二轮约 **126 秒**后的截图首次显示对端离线，均从主机记录的物理断网时刻计算。这些是采样上界，不是连续逐帧测得的精确切换时刻。

第二轮缩短采样间隔后，资料接口首次离线时，列表仍使用约 10 秒前的在线响应；下一次 30 秒周期的新 presence 请求返回离线，列表立即采用它。**没有证据证明两个接口在同一观测时刻给出互相冲突的状态**，也不能据“资料先离线、列表后离线”直接断言缓存覆盖错误。

数据与“服务端按最近活动时间保留一段在线窗口，再叠加客户端最多一个查询周期”相符。资料转换发生在最后活动约两分钟附近，但**这只是实测推断，不是已读取或确认的服务端 TTL 配置**。当前没有调整 TTL、硬编码离线阈值、伪造状态或增加常驻高频轮询。

## 实测对象与方法

- M3：独立模拟器 emulator-5556，test03；M4：独立模拟器 emulator-5558，test04。M1 真机、M2 未操作。
- M3 保持真实消息列表，不打开会话、不下拉刷新；仅关闭 M4 Wi-Fi/移动数据，并通过系统网络状态确认无默认网络。两轮均用 finally 恢复原有双网络。
- 使用已有单聊 `e51db063-4ed2-4a43-b7ff-bfbf32b1806d`，没有创建或发送消息，也未改变已有业务数据。
- 移动端真实请求为 `GET /api/im/conversations/{id}/presence`，日志确认 host 为 `api.sfhkh.com`、响应为 200。
- 桌面 1.0.87/test01 的现有授权会话只读调用 `GET /api/im/members/{test04成员ID}/profile`，用于对照；[安装端配置只读核对](../test/evidence/presence-source-comparison-20260903/desktop-origin.json) 确认同为 `api.sfhkh.com`。**这不是 Windows 界面操作证据**。
- [实验脚本](../scripts/uat-presence-source-comparison.ps1)：第一轮等待间隔 25 秒；第二轮为 5 秒，加上抓图/接口耗时，实际相邻截图约 8 秒。文件名里的秒数不是实际断网时长。
- 每次截图与 XML 都使用新设备路径，不复用旧截图。主机时间用于事件时间线；设备、服务端时间仅在各自时钟域内解释，未改系统时间。

## 第一轮：定位离线响应到页面的路径

[完整时间线与白名单诊断](../test/evidence/presence-source-comparison-20260903/source-comparison.json)，[计算摘要](../test/evidence/presence-source-comparison-20260903/first-run-summary.json)。

| 主机时间 +08:00 | 实际结果 |
| --- | --- |
| 05:43:48 | 列表、会话响应、桌面资料均在线 |
| 05:43:50 | M4 确认无默认网络 |
| 05:45:42 | 资料已离线；列表仍在线，使用设备 21:45:35Z 的旧在线样本 |
| 05:46:10 | 截图首次离线；对应设备 21:46:05.280759Z 离线响应，21:46:05.297770Z 构建决策离线 |
| 05:46:10 | M4 双网络恢复 |
| 05:46:38 | 列表与资料均在线 |

[旧在线样本仍展示](../test/evidence/presence-source-comparison-20260903/source-offline-100.png)、[新离线状态已展示](../test/evidence/presence-source-comparison-20260903/source-offline-125.png)、[恢复在线](../test/evidence/presence-source-comparison-20260903/source-restored-25.png)。这些截图已实际查看。

## 第二轮：缩短采样，排除不同观测时刻的误判

[完整细采样](../test/evidence/presence-source-comparison-20260903/precise-comparison.json)，[计算摘要](../test/evidence/presence-source-comparison-20260903/precise-run-summary.json)。

| 主机采样时间 +08:00 | 桌面资料 | 移动端最近 presence / 列表 |
| --- | --- | --- |
| 05:47:02 | — | M4 断网；最后活动字段为 21:46:43.944475Z |
| 05:48:36 | 在线 | 21:48:35.269391Z 响应在线，列表在线 |
| 05:48:45 | 首次观测离线 | 仍是上一条在线响应，不是此刻新请求 |
| 05:48:52 / 05:49:00 | 离线 | 仍使用同一条 21:48:35Z 样本 |
| 05:49:08 | 离线 | 新响应 21:49:05.269553Z 离线；21:49:05.309577Z 构建决策离线 |
| 05:49:09 | — | M4 双网络恢复 |
| 05:49:16 | 在线 | 列表已采用更高 order 的共享成员在线观测 |

资料首次离线后、恢复网络前，**没有新的 presence 在线响应**。[旧样本仍在线](../test/evidence/presence-source-comparison-20260903/precise-offline-65.png)、[下一周期离线](../test/evidence/presence-source-comparison-20260903/precise-offline-80.png)、[自动恢复](../test/evidence/presence-source-comparison-20260903/precise-restored-5.png)。

恢复后最后一次会话 presence 仍为离线，但共享成员已经有更新的在线观测，列表因此在线，资料也确认在线。这不是“旧在线覆盖新离线”：新观测具有更高 order 和恢复后的 lastSeenAt。不能要求不同来源在不同时间采集的最后一条记录始终相同。

另做了一次桌面配置网关的只读资料查询，未取得 HTTP 响应，只得到受控 MethodInvocationException。[失败记录](../test/evidence/presence-source-comparison-20260903/gateway-probe-failure.json)。未用它推断状态或根因；主要对照走同一 API 主机。

## 本轮代码与安全约束

新增 [ImPresenceDiagnostics](../lib/features/collaboration/data/im_presence_diagnostics.dart)，在 [仓储](../lib/features/collaboration/data/collaboration_repositories.dart) 和 [列表](../lib/features/messages/presentation/messages_page.dart) 记录状态来源。

- 默认关闭，仅显式 `MOBILE_IM_PRESENCE_DIAGNOSTICS=true` 的 profile/debug 用于本次排查；release 有代码层硬禁用。
- 只允许会话 ID、在线布尔值、样本时间、HTTP 状态、主机名及投影 order/fresh 等字段。没有日志输出密码、Token、Cookie、设备指纹、设备 ID、消息正文或附件地址。
- 脚本只读当前 M3 PID 的 logcat，在内存中提取固定前缀，再按字段白名单保存；原始 logcat 不落盘。
- 不新增业务请求、不更改在线判定/轮询频率、不改数据库内容。本轮诊断包仅安装 M3，采集结束后已恢复两台正常包。

[3 项诊断测试](../test/im_presence_diagnostics_test.dart) 覆盖默认关闭、响应字段白名单以及 unknown/多来源状态不被混淆；[专项 26/26](../test/evidence/presence-source-comparison-20260903/targeted.log)、[全量 902/902](../test/evidence/presence-source-comparison-20260903/full-test.log)、[分析 0 问题](../test/evidence/presence-source-comparison-20260903/analyze.log)。自动化通过率不代表完整线上验收通过率。

## 正常包回装与数据核对

[正常构建](../test/evidence/presence-source-comparison-20260903/normal-build.log)，93.2MB，SHA-256：`24A60B082004A4088E0BCF0F04D2D86455661143C191D754CA1325049ADD1157`。

[M3 安装与哈希](../test/evidence/presence-source-comparison-20260903/normal-install-emulator-5556.json)、[M4 安装与哈希](../test/evidence/presence-source-comparison-20260903/normal-install-emulator-5558.json)，均 install -r 保留数据，不清登录。临时诊断包记录另存于 [诊断安装](../test/evidence/presence-source-comparison-20260903/diagnostic-install.json)，不作为最终交付包。

[M3 正常首页](../test/evidence/presence-source-comparison-20260903/m3-normal-home.png)、[M4 正常首页](../test/evidence/presence-source-comparison-20260903/m4-normal-home.png)、[M3 正常消息列表](../test/evidence/presence-source-comparison-20260903/m3-normal-list.png) 的原生节点确认仍为 test03/test04，M3 中 Test04 在线。

[正常包静置复核](../test/evidence/presence-source-comparison-20260903/m3-normal-stable-list.png)：05:52:41 采集仍在线，距首次正常列表采集超过两分钟，未再次降级成过期未知。

[9 项数据保留检查](../test/evidence/presence-source-comparison-20260903/preservation.json) 全部通过：两台目标群的 3 条消息账本不变，所有会话的序号/已读/未读等元数据不变，Outbox 消息 ID/会话/类型/创建时间不变；M3 原 2 条待发媒体仍保留，OA 2 份草稿、10 条回执及 OA Outbox 不变。未将重试次数计为业务身份变化，也不把元数据核对描述为所有消息正文校验。

原始只读快照：[M3 前](../test/evidence/presence-source-comparison-20260903/m3-before.json)、[M3 后](../test/evidence/presence-source-comparison-20260903/m3-after.json)、[M4 前](../test/evidence/presence-source-comparison-20260903/m4-before.json)、[M4 后](../test/evidence/presence-source-comparison-20260903/m4-after.json)、[OA 前](../test/evidence/presence-source-comparison-20260903/oa-before.json)、[OA 后](../test/evidence/presence-source-comparison-20260903/oa-after.json)。

[运行检查](../test/evidence/presence-source-comparison-20260903/normal-runtime.json)：两台 Wi-Fi/移动数据均 1/1；正常包当前 PID 的诊断记录均为 0，Unhandled/RenderFlex overflow/FATAL 均为 0，仅代表此观测窗口。[桌面授权只读健康](../test/evidence/presence-source-comparison-20260903/desktop-health.json)：Windows 1.0.87/test01 运行，IM/OA 均 200。

## 待完成项与下一步

- **P2 离线及时性**仍开放：后台需确认各状态接口的在线超时定义、心跳/实时连接判定和期望时效；本轮不能确认具体 TTL 或承诺对端断网立刻离线。
- 691 的“列表过期后不再补取”已有修复；692 未观察到新的客户端状态覆盖缺陷。后续不应基于旧截图盲目追加清缓存或猜测性离线逻辑。
- 包体从 80.6MB 增至 93.2MB 的原因仍未定位；未证明性能验收通过。
- 两条历史媒体仍待发，不能把保留它们当成上传/发送成功。
- 同账号桌面+移动互不踢线、同平台替换、跨端已读、ACK 前崩溃、推送、真实大目录/大群性能、高级 OA 分支/多人处理、Windows UI 和授权真机全矩阵仍未完成，持续沿原目标推进。
