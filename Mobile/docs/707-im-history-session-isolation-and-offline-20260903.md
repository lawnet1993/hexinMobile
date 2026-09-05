# 707：历史读取会话隔离与断网回归

日期：2026-09-03。结论：本轮历史读取安全修复及模拟器回归通过，完整移动端 IM/OA 目标仍未完成。

## 本轮发现与改动

检查首条未读定位所依赖的历史加载链路时，发现读取操作没有始终保留原始登录：

1. `loadOlderMessages` 先取得账号 A，再异步读本地缓存；网络分支重新调用未指定会话的 `forIm()`，期间切到 B 时可能以 B 请求、却按 A 落库。
2. `refreshMessages` / `reconcileLatestMessages` 收到迟到成功响应后未检查登录是否已改变；旧请求可以继续写原账号缓存或通知调用方更新。
3. `messagesCacheFirst` 以及历史缓存命中/空结果直接返回；账号变化或同账号重新登录时，旧缓存结果没有及时失效。
4. 旧 HTTP 401/409/500 仍按当前操作错误抛出，缺少“该操作已属于上一登录”的区分。

[实现](../lib/features/collaboration/data/collaboration_repositories.dart)现在对上述路径保留同一个 `MobileSession`：本地读/解码前后、HTTP 前后及错误分支检查会话；缓存为空继续用原会话刷新；短会话锁内完成写入，网络与纯缓存解码不持锁。迟到结果统一为 `SessionChangedException`，不会因旧请求改动新的令牌或把新账号响应写回旧分区。消息查询仍为既有 take50 / beforeSequence+take80，不新增服务端接口。

当前登录下真实 401/409/500 仍作为请求错误交给既有调用链；本修复没有改动心跳的失效/替换处理，也没有让单个历史读取函数自行清除登录。读取历史不提交已读，本轮未改已读业务协议。

## 可复现本地证据

新增 [79 项真实 localhost HTTP + SQLite 回归](../test/im_history_session_isolation_test.dart)，全部使用隔离合成数据和测试安全存储，无线上账号口令。

- 48 项：刷新、最新核对、历史补拉、缓存缺失四条路径 × 切账号/同账号重登/退出 × 200/401/409/500，检查原请求身份、旧结果丢弃、双方 SQLite 无污染、新登录保持。
- 12 项：缓存命中、相邻历史、自动推算游标、核对最新四条路径，解码期间切账号/重登/退出，禁止返回旧结果或继续请求。
- 2 项：数据库首次打开期间换账号，缓存缺失与空游标不得启动新账号请求或返回旧操作结果。
- 16 项：四条路径正常成功及 401/409/500，验证原请求参数、账号分区、未读游标不被历史读取修改。
- 1 项：未变化的最新消息核对不重新写入，继续复用相同消息对象。

[修复前](../test/evidence/im-history-session-20260903/red.log)为 17 通过、62 失败；[修复后](../test/evidence/im-history-session-20260903/first-green.log)79/79。红测示例为切账号后仍返回旧消息列表，或仍抛原 Dio 错误而不是失效操作；同时测试覆盖 HTTP 等待中能完成保存新登录，避免把网络等待放进会话锁造成死锁。

- [全量 1123/1123](../test/evidence/im-history-session-20260903/full-test.log)。
- [静态分析 0 问题](../test/evidence/im-history-session-20260903/analyze.log)。
- [正常入口构建成功](../test/evidence/im-history-session-20260903/build.log)：`lib/main.dart`、profile、arm64+x64。既有 secure_tunnel 未来 Kotlin 插件迁移警告尚待独立处理。

## 真实模拟器回归

保留数据更新 M3（test03）和 M4（test04）。[实际安装记录](../test/evidence/im-history-session-20260903/install.json)中的 base.apk SHA256 均为：

`BA2BA61A347FD48DC0A6CDE9B620F4D65E060FD4D3110AABEA7CB9CEBD7F3BEB`

正常包：`test/evidence/im-history-session-20260903/normal-707.apk`。使用参数化的[保留数据安装脚本](../scripts/install-normal-706.ps1)，未卸载/清空，未安装观察入口。M3 PID5007、M4 PID28293 在整个回归中未变。

升级后的 [M3 工作台](../test/evidence/im-history-session-20260903/emulator-5556-installed.png) / [M4 工作台](../test/evidence/im-history-session-20260903/emulator-5558-installed.png)仍显示原用户。通过真实点击进入既有群 `AI-UAT-20260903-IM-BATCH-701`，没有重发其 510 条历史消息。

[断网操作脚本](../scripts/uat-im-history-offline-707.ps1)与[原始操作记录](../test/evidence/im-history-session-20260903/offline-history.json)：

- 先记录 Wi-Fi/数据 1/1，再关闭两者；Android connectivity 明确为 `Active default network: none`，不是只模拟一个错误提示。
- 24 次同向上滑，从最新 510 到 [第 1 条](../test/evidence/im-history-session-20260903/m3-offline-history-06.png)，首条头像/姓名正常合并，无“加载更多”点击。
- 断网期间返回消息列表并[重新进入](../test/evidence/im-history-session-20260903/m3-offline-reopened.png)，最新 510 正常显示，没有跳登录页。
- finally 恢复原 1/1；[系统网络恢复核对](../test/evidence/im-history-session-20260903/online-restored.json)有 active default network。[恢复后界面](../test/evidence/im-history-session-20260903/m3-online-restored.png)显示最新消息及 2 人在线；断网时截图只显示成员数，没有拿旧在线数冒充实时状态。
- [M4 最新消息/双勾](../test/evidence/im-history-session-20260903/m4-group-latest.png)保留。

[最终证据核对 8/8](../test/evidence/im-history-session-20260903/verification.json)，由[只读脚本](../scripts/verify-im-history-session-707.mjs)执行：双方 510 条唯一消息账本、会话元数据、read510/unread0、对方已读投影不变；M3 原 2 条媒体 Outbox、2 份 OA 草稿、10 条通知回执保留。对自动重试记录只比身份，不把 attempt 计数正常增长认作数据损坏。

[运行核对](../test/evidence/im-history-session-20260903/runtime.json)未见当前进程 FATAL、未处理异常、RenderFlex 溢出或旧观察入口日志；两端 Wi-Fi/数据最终均为 1/1。原生回归没有切换账号；精确请求竞态发生于上述本地 HTTP + SQLite 测试，不能替代线上多设备会话替换矩阵。

## 首条未读及其他未完成项

**首条未读定位本轮未实现。** 当前模型有 `firstUnreadSequence`，但 ChatPage 没有使用它建立定位；初次进入仍定位最新消息。现有可见区域最高序号会按服务端累计已读协议提交，因此“显示了最新消息”不能被描述为“逐条阅读了所有历史”。后续需要未读起点定位、较长未读区间的分页/前后连续性、定位期间禁止中途布局触发已读，以及跨端已读变化后的正确更新，不能只加一个未读数字按钮。

真机[已授权但仍锁屏](../test/evidence/im-history-session-20260903/physical-device-state.json)，本轮未操作；当前无可调用 Windows UI 控制接口，未完成最新桌面窗口真实对照。首条未读、增量窗口/锚点与真实帧率、完整多端/密码矩阵、真实推送与 iOS 安全存储、媒体上传 500、高级 OA 条件分支/会签/或签/多人办理付款/公式附件和全过程通知仍继续。整体目标保持活动，不将本次历史读取修复视为全面验收通过。
