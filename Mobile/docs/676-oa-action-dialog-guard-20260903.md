# 676 审批确认抽屉的会话、任务与网络守卫

时间：2026-09-03，Asia/Shanghai；正常包实际操作 01:30–01:36。续接已运行的构建与全量回归，原进程均正常退出，没有因观察超时重启任务。本轮有代码修复、回归和真实业务证据，属于 progress；整体对齐目标仍进行中。

## 结论与范围

**本专项通过：旧确认抽屉不再使用新登录身份发送审批动作；任务变化、断网和连点得到拦截。真实 M3 撤回确认前断网 → 恢复后重新操作 → 冷启动保留终态通过。**

本结论不等于全部 OA/IM 验收通过。切号、任务变更和并发连点以组件及本地 HTTP 回归证明；本次真实线上执行的是新建、选择后取消、断网确认与在线撤回，没有把模拟测试描述成真实多端业务证据。

仅安装、操作独立 M3（emulator-5556 / Android 16 / test03）。M1 真机、M2 未操作。当前已安装 Windows 1.0.87 / test01 仅作只读核对，不依据旧桌面源码。正常入口 `lib/main.dart`、Profile APK，SHA256：

`6A218AEF864BA3ADBB685A2726C246DC02C49F8BEAE9B0E0CC3DE08225A1F382`

[运行与安装核对](../test/evidence/oa-action-dialog-20260903/runtime-final.json)：设备 APK 与构建哈希一致，Wi-Fi/移动数据均已恢复，应用存活，采样日志 FATAL EXCEPTION 与 E/flutter 均为 0；这只是本次日志窗口，不代表全历史无异常。

## 问题及修复

原页面在打开菜单、选人、填写说明后继续使用此前捕获的申请/任务，而 Repository 在最终调用时才读取当前登录。抽屉期间切号、重新登录或任务变化，存在旧操作意图使用新会话发送的风险。修复前的有效本地回归是 [28 个负例失败、1 个正常对照通过](../test/evidence/oa-action-dialog-20260903/red-matrix.log)，负例实际进入本地 HTTP 服务，不是只检测按钮状态。

- 从第一次打开菜单或审批意见抽屉起，捕获完整会话；账号、设备与 access token 一致性在后续阶段复核。
- 选人后、加签方式后以及最终发送前重新核对当前请求、允许动作、任务 ID/版本/处理人及可处理状态；连接不可用则明确提示并停止。
- Repository 新增可选 `expectedSession`，页面将捕获会话一直传到底层，利用已有发送前/建客户端后/响应后检查，关闭 UI 检查与实际读取凭证之间的竞态。
- 交互锁覆盖整个抽屉链路；快速连点不会叠两个流程，取消后恢复按钮。提交等待和交互锁分开，不在选择人员时显示网络提交动画。
- 旧会话的成功/失败结果不再通知新登录界面；保持现有 API 方法、请求体、任务版本和幂等字段，没有数据库迁移。

改动：[页面](../lib/features/todos/presentation/approval_detail_page.dart)、[Repository](../lib/features/collaboration/data/collaboration_repositories.dart)。合法的自动 token 轮换也会使打开中的旧确认失效，需要重新确认；本轮没有证明跨续期保留编辑体验。服务端仍须执行权限与任务版本校验。

## 自动回归

| 范围 | 结果 | 证据 |
|---|---|---|
| 新增抽屉守卫 | 42 项：7 动作 × 5 状态变化，连点、菜单/选人/方式中途变化、任务版本、正常对照 | [组件测试](../test/oa_action_dialog_guard_test.dart) |
| 新增绑定会话的 Repository 测试 | 18 项：6 方法 × 切号/重登/退出，验证未发送及缓存不串号 | [会话隔离测试](../test/oa_action_session_isolation_test.dart) |
| OA/UI 专项 | 161/161 | [日志](../test/evidence/oa-action-dialog-20260903/focused.log) |
| 最终全量 | 732/732 | [日志](../test/evidence/oa-action-dialog-20260903/full-final.log) |
| 最终静态分析 | 0 issues | [日志](../test/evidence/oa-action-dialog-20260903/analyze-final.log) |
| 正常 Profile 构建 | 成功 | [日志](../test/evidence/oa-action-dialog-20260903/build.log) |

构建仍提示 secure_tunnel 的 Kotlin Gradle Plugin 将来兼容性警告，不是本次构建失败。早期 `red.log`、`red-behavior.log`、`red-confirmed.log` 和 `control-*` 是测试夹具建立/修正过程，不用于产品通过结论；有效修复前证据为 `red-matrix.log`。首次全量后 9 项分析提示已修复，以上引用最终重新执行结果。没有更新 Golden 来掩盖失败。

## 真实操作与结果

新单 **OA-20260902-2DDF00**，ID `2ddf0071-0276-4001-a061-b5466a082391`。从原撤回单 8928DD 的“再次发起”进入，金额 100、CNY、用途其他、预计归还 2026-09-04；说明替换为 `AI-UAT-20260903-013000-DIALOG-GUARD`。申请人及流程实际解析的财顺部门负责人均为 Test Terminal 03，来自页面预览与实际任务，不按账号名称猜角色。表单/流程页面显示 v1，未读取完整发布版本 ID。

| 实际步骤 | 观察结果 | 截图证据 |
|---|---|---|
| 原单再次发起、修改说明、提交 | 新编号，审批中，待 test03 处理；没有提前通过 | [表单](../test/evidence/oa-action-dialog-20260903/08-form-ready.png)、[新单](../test/evidence/oa-action-dialog-20260903/09-submitted.png) |
| 更多 → 转交 → 选 Test Terminal 01 → 取消原因抽屉 | 返回原申请，仍由 test03 处理；未真实转交 | [选人](../test/evidence/oa-action-dialog-20260903/11-transfer-picker.png)、[说明](../test/evidence/oa-action-dialog-20260903/12-transfer-reason.png)、[取消后](../test/evidence/oa-action-dialog-20260903/13-after-cancel.png) |
| 更多 → 加签 → 选 Test Terminal 01 → 前加签 → 取消说明 | 选人、方式、说明依次向上展开；取消无新任务 | [方式](../test/evidence/oa-action-dialog-20260903/16-addsign-mode.png)、[说明](../test/evidence/oa-action-dialog-20260903/17-addsign-reason.png) |
| 打开撤回原因，输入 `AI-UAT-20260903-013000-OFFLINE`，关闭 M3 Wi-Fi 与移动数据 | 抽屉保持，输入存在 | [断网抽屉](../test/evidence/oa-action-dialog-20260903/20-offline-dialog.png) |
| 断网后点击确认 | 明确提示“当前连接不可用，请联网后重新操作”，仍审批中，显示本机快照；未写入待同步撤回 | [拦截提示](../test/evidence/oa-action-dialog-20260903/21-offline-confirmed.png)、[本地元数据](../test/evidence/oa-action-dialog-20260903/oa-offline-confirmed.json) |
| 恢复网络，不点击重新同步 | 自动恢复在线详情和操作按钮；申请仍审批中，未自动补发 OFFLINE 意图 | [恢复后](../test/evidence/oa-action-dialog-20260903/22-reconnecting.png)、[恢复元数据](../test/evidence/oa-action-dialog-20260903/oa-reconnected.json) |
| 重新打开撤回，输入 `AI-UAT-20260903-013000-ONLINE` 并确认 | 撤回成功、任务已取消，记录只有该 ONLINE 原因 | [在线撤回](../test/evidence/oa-action-dialog-20260903/25-online-withdraw.png) |
| 杀进程冷启动，再打开新单 | 待我处理 0；撤回终态及唯一处理记录保留，仅有再次发起 | [冷启动首页](../test/evidence/oa-action-dialog-20260903/26-cold-home.png)、[重开详情](../test/evidence/oa-action-dialog-20260903/28-cold-withdrawn.png) |

以上 8 个限定 UI 检查点全部通过；不能外推为 8 条完整高级审批流程。没有转交给真机用户或触发其新待办，没有同意、付款或放款操作。新单最终已撤回，没有留下可操作的新增审批任务；新增通知保留。

服务端事件提交时间 `2026-09-02T17:31:42.546023Z`（北京时间 01:31:42），撤回时间 `17:34:36.482198Z`（北京时间 01:34:36）。设备页面与电脑时区展示不同，未改设备时钟，编号原样记录。截图 JSON 带独立采集时间。

## 持久状态与桌面核对

[对比结果](../test/evidence/oa-action-dialog-20260903/comparison.json) / [最终 OA 元数据](../test/evidence/oa-action-dialog-20260903/oa-final.json)：

- OA 游标 390 → 提交后 394；断网确认及恢复后仍 394；在线撤回后 398。事件 391 为 submitted，393 为 task.created，395 为 withdrawn，397 为 task.canceled，其余四条为 notification.created。
- 撤回事件 ID `2ac0d896-9ecf-498c-8726-dd76e3a80e8f`；任务取消 ID `c22fda06-f8df-4216-b974-683c3e6e3d79`。它们是事件编号，**不是 HTTP 请求编号**；本轮 UI 写请求未抓原始响应，不能提供 HTTP trace ID 或据此声称网络抓包证明。
- 断网、恢复、最终 OA Outbox 均为空。两份原有草稿 ID/修改时间与四条原有已读回执完全一致。页面通知数 12 → 16，与新建/撤回产生四条通知相符；本轮未打开读取新通知。
- [IM 元数据](../test/evidence/oa-action-dialog-20260903/im-final.json)：应用/ACK 游标仍 207，单聊 6 条/已读 6/未读 0，测试群 11 条/已读 11/未读 0，空群 0，Outbox 空；未发送任何 IM 消息。
- [Windows 只读检查](../test/evidence/oa-action-dialog-20260903/desktop-health.json)：01:34 运行中的 1.0.87/test01，IM/OA GET 均 200，读取 test03 新单为 404。会话文件 01:28:58 已更新；Token 时间字段仅为未验签提示，不单独作为登录正常依据。404 仅证明此请求未返回该他人资源，不代表完整权限矩阵通过。

启动瞬间首次 UI dump 失败，脚本拒绝复用旧 dump，因此没有 `02-installed` 截图；实际安装后证据从 [03](../test/evidence/oa-action-dialog-20260903/03-installed-ready.png) 开始。所有使用的 UI 证据均为独立新 dump。

## 保留问题与未执行项

- P2-675-01：撤回后的任务取消通知误写“其他处理人完成”仍未修复，本轮不伪造服务端含义。
- 实际转交、前后加签、退回、跨部门/多分支/会签或签/抄送/办理付款及附件公式仍需真实终态验证，本次仅走选择与取消。
- 选人沿用现有已加载目录，当前候选仅 Test Terminal 01；不能据此认为全组织人员搜索和权限范围已经对齐，需要最新服务端/桌面行为核对。
- 会话/任务中途改变的线上双端操作、自然续期与打开抽屉时 token 轮换的完整 UX 仍未实测。
- M1/M2 所有权未确认，Windows 图形控制能力未恢复，本轮不操作这些界面；只读 HTTP 检查不是 UI 替代验收。
- 真机更新、完整跨端未读/替换登录/密码变更失效、原生推送、大群与帧性能，以及已记录的服务端 IM 投影/媒体问题仍保留。

以上均维持原目标，不将本次 732 项通过或单模拟器通过等同于核心流程全部可验收。
