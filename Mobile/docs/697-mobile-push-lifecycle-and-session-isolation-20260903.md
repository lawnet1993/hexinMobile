# 697 推送注册生命周期与会话隔离

日期：2026-09-03，Asia/Shanghai。结论：完成客户端注册竞态修复和正常包回归；**离线推送整体未通过**，真实平台接入及原生安全存储仍有缺口。总 IM/OA 目标保持进行中。

## 已复现并修复

初始六项延迟/并发测试全部失败：[修复前日志](../test/evidence/mobile-push-lifecycle-20260903/red.log)。不是仅凭代码推测。

| 问题 | 原行为/影响 | 修复后 |
| --- | --- | --- |
| P1：退出期间令牌查询尚未返回 | stop 后继续发注册，旧运行周期仍可触发初始通知跳转 | 运行代次检查贯穿查询、请求前后及初始导航；旧代次不再继续 |
| P1：迟到注册或注销结果 | 可能在账号变化后覆盖/清除安全存储中的新令牌 | 操作捕获完整会话，网络绑定原会话；短时安全存储写入使用同一会话锁校验 |
| P1：新登录复用相同推送令牌 | stop 不清注册去重状态，新运行周期可能跳过注册 | stop 清去重状态；成功记录包含会话身份，续期也重新绑定 |
| P2：并发查询同一个令牌 | 可以同时重复发送相同注册 | 同一运行周期串行化，完成后去重；新周期不等待旧周期队列 |
| P2：隐私模式被恢复默认 | 手动选 detail 后，前台恢复/令牌更新重新按 summary 注册 | 运行周期内保留显式选择；新账号运行周期回到保守默认，不继承上个账号的 detail |
| P2：令牌轮换与旧查询乱序 | 旧 native lookup 迟到可覆盖新 token 事件 | native 查询比较 token 事件修订号，放弃旧结果 |
| P2：事件监听中的注册失败 | unawaited Future 可能形成未处理异常 | 后台失败被隔离，后续同步可重试；显式设置调用仍返回失败 |

实现：[mobile_push_registration.dart](../lib/core/notifications/mobile_push_registration.dart)、[请求仓储](../lib/features/collaboration/data/collaboration_repositories.dart)、[会话续期联动](../lib/features/shell/presentation/mobile_shell.dart)。未修改登录协议或服务端推送接口格式。

网络只使用所捕获会话的认证信息；已发往服务器的请求不能被本地代次检查“撤回”，本轮不宣称验证了服务端对在途 PUT/DELETE 的最终排序或补偿。这是本地隔离证明，不是完整推送注销端到端证明。

## 回归证据

- 新增 [生命周期测试](../test/mobile_push_lifecycle_test.dart) 14 项：停止期间的令牌/初始路由查询、迟到成功、同令牌重启、重复请求、隐私、乱序、失败恢复，以及退出/账号切换/同账号续期和安全存储保护。
- 新增 [本地 HTTP 请求测试](../test/mobile_push_session_request_test.dart) 4 项：过期会话在发出 PUT/DELETE 前被拒绝；已经发出的请求仍只带原账号认证信息，迟到注册成功不被当作当前成功。仅使用合成凭据和回环服务器，未向线上注入假推送令牌。
- 首次 HTTP 测试的四项失败来自测试夹具未注入 SQLite factory，发生于 setup，并非产品请求失败；修正 fixture 后重跑。
- 专项 **50/50**：[通过日志](../test/evidence/mobile-push-lifecycle-20260903/targeted-pass.log)；全量 **984/984**：[全量日志](../test/evidence/mobile-push-lifecycle-20260903/full-tests.log)；分析 **0 问题**：[分析日志](../test/evidence/mobile-push-lifecycle-20260903/analyze-final.log)。
- 正常 `lib/main.dart` arm64+x64 Profile 构建成功，93.2 MB：[构建日志](../test/evidence/mobile-push-lifecycle-20260903/build.log)。未启用上传/状态/ACK 诊断入口。
- M3/test03 与 M4/test04 均原地安装正常包，实际 base.apk SHA-256 与本地产物一致：`74510BCF5B531684368B2D25B239FB0E8700D6B8557227C7DFF42E721FBC21C3`。[安装后运行核对](../test/evidence/mobile-push-lifecycle-20260903/normal-runtime-final.json) 中两端网络开启，当前进程异常/溢出及临时诊断匹配均为 0。不是长期稳定性或 Release 性能结论。

## 正常包真实操作

M3、M4 原账号登录均保留：[M3 工作台](../test/evidence/mobile-push-lifecycle-20260903/m3-installed.png)、[M4 工作台](../test/evidence/mobile-push-lifecycle-20260903/m4-installed.png)。

M3 打开消息列表及既有群：[消息列表](../test/evidence/mobile-push-lifecycle-20260903/m3-installed-messages.png)、[群聊](../test/evidence/mobile-push-lifecycle-20260903/m3-installed-group.png)。原 seq1–6 消息和阅读状态仍在，头像与双勾可见；没有新增业务消息。

M4 打开“我的→通知设置”：[我的](../test/evidence/mobile-push-lifecycle-20260903/m4-installed-profile.png)、[通知设置](../test/evidence/mobile-push-lifecycle-20260903/m4-installed-notifications.png)。页面区分“应用内实时同步”与“离线推送未注册”，没有因未取得原生 token 造成崩溃，也没有把未注册说成已送达。

安装前后按账号核对群消息及投影、待发身份、OA 草稿/通知已读/outbox，**12/12**：[数据保留结果](../test/evidence/mobile-push-lifecycle-20260903/retention-checks.json)。M3 两条历史媒体仍 pending，其后台自动重试次数不作为“不变”条件；两条 OA 草稿、10 条通知已读记录保留。没有清除数据库或应用存储。

最终 M3 返回消息列表、M4 返回工作台，真机及其他模拟器未操作。D1 仍只读核对，不能替代桌面 UI 验收：[桌面状态](../test/evidence/mobile-push-lifecycle-20260903/desktop-final.json)。

## 仍需处理的推送缺口

1. **P1：原生推送令牌存在普通偏好存储副本。** [MainActivity.kt](../android/app/src/main/kotlin/com/hexing/zhilian/hexing_terminal_mobile/MainActivity.kt) 的 `publishPushToken/readToken` 使用 `mobile_push` SharedPreferences；本轮保护的是 Flutter 注册阶段安全存储写入，不能据此宣称原生副本满足 KeyStore 要求。下一步需迁移、隔离环境命名空间并核对退出/重装规则；检查不得输出真实令牌。
2. **离线推送实际接入未就绪。** 源码检索仅找到桥接入口，没有找到 `publishPushToken` 的实际 SDK 调用、FirebaseMessaging/MessagingService 实现或构建依赖；实际页面仍未注册。已向用户询问使用的平台及测试配置，不擅自选择第三方服务或上传用户数据。
3. 未验证真实推送唤醒同步、前后台重复事件、点击推送定位消息、令牌轮换及服务端注销补偿。上述合成测试不能代替真实平台投递。
4. 隐私选择目前仅保证当前运行周期不被前台恢复/轮换意外覆盖；跨冷启动的后端配置恢复仍需单独对齐验证。

## 总目标其他未完成项

[695 上传 500](695-im-upload-failure-diagnostics-20260903.md) 等待后端日志，未无依据反复手工重试；[696 多端会话验收](696-mobile-session-switch-and-account-isolation-20260903.md) 仍有 Windows UI、D2 替换 D1、改密会话失效等完整矩阵缺口。高级 OA 分支/会签/或签/公式/附件、真机全页、长期性能与批量同步等继续保留，不能用 984 项测试替代完整业务验收。
