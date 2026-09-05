# 679 · OA 转交、前后加签真实续验

## 结论与边界

**部分通过，完整目标继续。** 2026-09-03 02:12–02:35（北京时间）在 M3/test03 正常应用页面新建并操作三条借支申请；D1 当前 test01 会话仅用 GET 核对实际任务、权限、通知与终态。没有通过接口代替点击来发起/处理业务，没有修改数据库或既有业务数据。

转交、前加签暂停原任务、后加签先等待再激活的中间状态有真实证据。三单均已撤回、无可操作待审批任务，但前加签原任务在服务端仍为 `waiting`，终态一致性不通过。接收人没有实际点击同意，因此不能称转交、前加签回到原节点、后加签最终通过等完整链路已验收。

发现并修复移动端历史记录泄漏 `add_signed`：新正常包显示“加签”，保留人员、意见与时间。新增 4 项回归，全量 **750/750**，静态分析 0 问题；仅更新 M3，未接管 M1/M2，未替换 Windows 安装包。

上一目标轮已经完成真实业务操作、红绿测试和安装，属于有进展；本次恢复先核对磁盘证据与存活设备，再补齐只读终态、升级保留检查及报告，未因观察中断重复构建或重复提交。

## 环境与身份

| 对象 | 本轮实际证据 | 限制 |
| --- | --- | --- |
| M3 / emulator-5556 | Android 16、1080×2400、density 420；test03；页面真实操作、截图、SQLite 元数据 | 独立测试模拟器 |
| D1 / test01 | 当前安装 Windows 1.0.87 的安全保存会话；OA bootstrap/page/detail/events GET 200 | 不是桌面 UI 操作证据；未改变登录或刷新凭据 |
| M1 / dd00d66d | ADB 已授权；转交后只读 OA 缓存仍为游标 343、更新时间 2026-09-02T13:43:22.172071Z | 接管问题尚无回复，没有重开、安装或点击；不能据此断言在线同步故障 |
| M2 / emulator-5554 | ADB 设备存在 | 操作来源未确认，本轮未操作 |
| 测试控制面 | `http://api.sfhkh.com` | 不使用已经删除的旧服务器 |

真实申请人及原审批任务处理人均为 **Test Terminal 03 / test03 / 财顺**；实际选择的转交、加签人均为 **Test Terminal 01 / test01 / 公司总部**。原节点名称为“部门负责人审批”，新增节点为“部门负责人审批（加签）”。这些来自页面与返回任务，不是按用户名猜测角色。

账号 ID：test03 `c404c59a-6dc3-4e6b-a1dc-d5d0c20786cc`；test01 `63bb07f7-89dc-449e-9e49-4b528f5215b7`。具体岗位、外号、负责人组织配置未完整获取，**不能把节点名等同于岗位证明**。候选抽屉实际只有 Test Terminal 01，本轮没有绕过服务端扩大候选范围。

主机、Android 状态栏和业务时间显示不同：以下流转时间均按服务器原始 **UTC** 记录，北京时间为 +8 小时；不跨时钟相减推导精确点击延迟，也未修改设备时钟。

## 申请与版本

共同表单值：借支金额 100、币种 CNY（通过选择器实际选择）、用途“其他”、预计归还日期 2026-09-04、无附件。CNY 是本次选择值，不代表所有业务固定该单位。

三单 `templateVersion=1`，`workflowKey=system.default.finance.advance-request`。只读证据没有单独确认工作流版本号；下面的 requestVersion 是申请修订号，**不冒充流程版本**。

| 申请编号 | 唯一业务说明 | 申请 ID | clientRequestId | 最终修订号 |
| --- | --- | --- | --- | --- |
| OA-20260902-E5F097 | AI-UAT-20260903-021200-TRANSFER | e5f0977a-c8c0-46a0-baff-aeecea59094c | 14442de9-9efd-46fb-82cc-a165732832ed | 3 |
| OA-20260902-8B87B0 | AI-UAT-20260903-021600-FRONTSIGN | 8b87b0c1-486c-41fe-9e1a-1fd98495d7eb | 7ddcbbc3-d6e0-4157-8e35-463fc0f21af1 | 3 |
| OA-20260902-5303A3 | AI-UAT-20260903-022400-BACKSIGN | 5303a348-ddea-40e0-938a-3ed2b7fd3486 | 58725c23-076c-4f9e-9a82-526d32a5abdf | 4 |

8B87B0、5303A3 分别从上一条已撤回申请的“再次发起”进入，修改测试说明后提交；新 ID 与原单不同，最终 GET 仍能分别读取原单终态，没有覆盖原申请。

## 真实流转记录

### 转交 E5F097

| UTC 时间（2026-09-02） | 实际动作及处理人 | 结果 |
| --- | --- | --- |
| 18:13:37.072238 | test03 提交 | 原任务 test03 pending |
| 18:14:45.659688 | test03 转交给 test01；意见 AI-UAT-20260903-021200-TRANSFER-TO-TEST01 | 原任务 transferred，新任务 pending；整单仍 submitted |
| 18:15:49.803210 | test03 以申请人身份撤回；意见 AI-UAT-20260903-021200-TRANSFER-WITHDRAW | 整单 withdrawn，新任务 canceled，原 transferred 历史保留 |

原任务 `d9f33c2b-4687-4ae3-866c-e292cefe00e5`；新任务 `e45129a1-8058-4215-8417-60954e44cdb1`。转交后 M3 的同意、驳回入口消失；D1/test01 同一申请由转交前 404 变为 200，获得 approve/reject/transfer/add_sign。撤回后两任务均不可操作、allowedActions 为空。

证据：[提交前表单](../test/evidence/oa-transfer-real-20260903/10-final-form.png)、[已提交](../test/evidence/oa-transfer-real-20260903/12-submitted-ready.png)、[转交确认](../test/evidence/oa-transfer-real-20260903/16-transfer-confirm.png)、[转交后](../test/evidence/oa-transfer-real-20260903/17-transferred.png)、[撤回后](../test/evidence/oa-transfer-real-20260903/21-withdrawn.png)、[D1 转交前](../test/evidence/oa-transfer-real-20260903/desktop-before-transfer.json)、[D1 转交后](../test/evidence/oa-transfer-real-20260903/desktop-transferred.json)。

### 前加签 8B87B0

| UTC 时间（2026-09-02） | 实际动作及处理人 | 结果 |
| --- | --- | --- |
| 18:16:38.058148 | test03 提交 | 原任务 test03 pending |
| 18:22:47.832555 | test03 选择 test01、前加签；意见 AI-UAT-20260903-021600-BEFORE-TEST01 | 原任务 waiting，新任务 pending；原处理按钮移除 |
| 18:23:49.249038 | test03 撤回；意见 AI-UAT-20260903-021600-FRONTSIGN-WITHDRAW | 整单 withdrawn，新任务 canceled；**原任务仍 waiting**，均不可操作 |

原任务 `6e079f8c-5cc8-46d2-bae7-9a125662bd30`；新任务 `5c4ffaee-046c-476c-8bbb-5fae346425aa`。加签后 D1/test01 新任务可操作。未操作 test01 同意，所以“新增人员先处理，之后回到当前节点”的后半段未执行。

证据：[提交表单](../test/evidence/oa-transfer-real-20260903/24-frontsign-final-form.png)、[前后方式抽屉](../test/evidence/oa-transfer-real-20260903/28-frontsign-mode.png)、[前加签确认](../test/evidence/oa-transfer-real-20260903/30-frontsign-confirm.png)、[稳定中间态](../test/evidence/oa-transfer-real-20260903/32-frontsign-stable.png)、[撤回异常](../test/evidence/oa-transfer-real-20260903/36-frontsign-withdrawn.png)、[D1 中间态](../test/evidence/oa-transfer-real-20260903/desktop-frontsign-stable.json)、[D1 终态](../test/evidence/oa-transfer-real-20260903/desktop-frontsign-withdrawn.json)。

### 后加签 5303A3

| UTC 时间（2026-09-02） | 实际动作及处理人 | 结果 |
| --- | --- | --- |
| 18:25:27.604471 | test03 提交 | 原任务 test03 pending |
| 18:27:18.396058 | test03 选择 test01、后加签；意见 AI-UAT-20260903-022400-AFTER-TEST01 | 原任务继续 pending，新任务 waiting；D1 可以查看，但无操作权限 |
| 18:28:13.187009 | test03 真正点击原节点同意；意见 AI-UAT-20260903-022400-APPROVE-ORIGINAL | 原任务 approved，新任务 pending 且 D1 可操作；整单仍 submitted |
| 18:28:59.841046 | test03 撤回；意见 AI-UAT-20260903-022400-BACKSIGN-WITHDRAW | 整单 withdrawn，原 approved 历史保留，新增任务 canceled |

原任务 `e812f16f-a2d8-4d04-986f-335dcc51e1c9`；新任务 `5b7c27f8-3b00-44b5-bf44-9dcf8ab6f6e5`。原节点同意后的实际提示为 **“当前节点已同意，审批继续流转”**，没有提前提示整单通过；新增任务由 waiting/v1 → pending/v2 → canceled/v3。未操作 test01 最终审批。

证据：[提交表单](../test/evidence/oa-transfer-real-20260903/39-backsign-final-form.png)、[后加签确认](../test/evidence/oa-transfer-real-20260903/45-backsign-confirm.png)、[稳定等待态](../test/evidence/oa-transfer-real-20260903/47-backsign-stable.png)、[原节点同意及提示](../test/evidence/oa-transfer-real-20260903/51-backsign-original-approved.png)、[撤回](../test/evidence/oa-transfer-real-20260903/55-backsign-withdrawn.png)、[D1 等待态](../test/evidence/oa-transfer-real-20260903/desktop-backsign-added.json)、[D1 激活态](../test/evidence/oa-transfer-real-20260903/desktop-backsign-activated.json)。

各 `canOperate` 都相对于发起 GET 的 **D1/test01**：例如后加签原 test03 任务 pending 而 D1 返回 false，不表示 M3/test03 被禁止处理。

## 通知、同步与权限证据

| 申请 | test01 新任务通知 ID（实际未读） | test01 取消任务通知 ID（实际未读） | 筛选到的新任务通知事件序号 |
| --- | --- | --- | --- |
| E5F097 | b6cbcb6a-2eed-4a1e-9dfe-1ee3932d230a | 9424ef77-57f5-4e77-8d49-ee081bcb9ca4 | 419 |
| 8B87B0 | 1f4cd96b-4b2a-4661-a494-3eb89a496b70 | ec7a680c-d0d6-4ec4-9c11-4836e66d2a57 | 431 |
| 5303A3 | 69deea1f-4d23-45c2-a635-d6b09d54b6f8 | 5e67d0ef-1428-41c4-b510-b80eceeb8295 | 445 |

这些为 D1 会话读取到的持久通知，不等于 Windows 弹窗、系统推送或真机实时到达已经通过。本轮未打开通知，未改变其已读状态。前加签第一份立即查询 bootstrap 早于动作完成、notifications 为空，稳定复查已存在通知；不把该临时采样当丢通知缺陷。

[七组状态摘要](../test/evidence/oa-transfer-real-20260903/server-flow-summary.json) 与 [02:33 最终只读核对](../test/evidence/oa-transfer-real-20260903/desktop-final.json) 显示三单 detail HTTP 200、withdrawn、allowedActions=[]，任务均 canOperate=false。响应没有返回可用 HTTP 关联请求编号，原样记录 null；申请 ID、任务 ID、事件 ID 可用于服务端追溯，不能伪造 request-id。

M3 OA 游标 411 → 449；首页未读通知显示 29、待我处理 0。正常应用白名单计时：提交后零等待批次 total 3660ms（请求 2777、投影 734、提交 149）；转交后 total 878ms（231/573/74），各 4 个事件。见 [计时](../test/evidence/oa-transfer-real-20260903/m3-action-timing.json)。这是批处理耗时，不是完整点击到界面响应耗时，也不证明跨端远端事件延迟达标。

只读助手新增显式申请 ID、afterSequence 与业务标记复核：无匹配只输出 ID/HTTP/标记结果，拒绝重定向、非测试域和非测试账号。已用 404→匹配 200 及 [不匹配遮蔽样本](../test/evidence/oa-transfer-real-20260903/helper-marker-redaction.json) 验证。事件只筛选已匹配申请，不能将其结果当作所有嵌套任务事件的完整审计。

## 问题清单

### P2-679-02 · 前加签撤回后原等待任务未终结（未修复）

- 复现：M3 提交 8B87B0 → 选择 test01 前加签 → 原任务 waiting → 申请人撤回 → 升级后重开详情，并用 D1 GET 核对同一 ID。
- 预期：整单撤回后未完成的等待任务进入取消等终态；已结束流程不继续展示“等待中”。
- 实际：整单 withdrawn、test01 新任务 canceled，但 test03 原任务 waiting/v2、completedAt=null；页面如实显示“等待中”。两任务均不可操作，尚无越权或继续执行证据。
- 影响：审批轨迹与整单状态矛盾，用户可能误以为仍需审批；可能影响等待任务统计，后者尚未验证。
- 定位证据：[撤回原图](../test/evidence/oa-transfer-real-20260903/36-frontsign-withdrawn.png)、[升级后复验](../test/evidence/oa-transfer-real-20260903/61-frontsign-after-update.png)、[服务端终态](../test/evidence/oa-transfer-real-20260903/desktop-final.json)。GET `/api/oa/approval-requests/8b87b0c1-486c-41fe-9e1a-1fd98495d7eb` 返回 200；关联头为空，原任务 ID 见前文。
- 处理：保留真实服务端状态，不修改数据库，不用 UI 假取消掩盖；需服务端核对撤回对 waiting 任务的收束规则，完整后端根因未确定。

### P2-679-01 · 加签历史显示原始动作代码（已修复）

- 复现：执行任一前/后加签，展开处理记录。
- 预期：显示中文“加签”，保留实际处理人、意见和时间。
- 实际：服务端 action=`add_signed`，旧移动端只识别 `add_sign`，于是原样显示原始代码；见 [修复前](../test/evidence/oa-transfer-real-20260903/55-backsign-withdrawn.png)。
- 影响：业务历史不可读；未发现它改变实际流转结果。
- 修复：`approval_detail_page.dart` 同时识别 `add_sign` / `add_signed`，沿用不区分大小写映射；不从备注猜测前后加签类型。
- 验证：[后加签新包实图](../test/evidence/oa-transfer-real-20260903/58-history-label-fixed.png)、[前加签新包实图](../test/evidence/oa-transfer-real-20260903/61-frontsign-after-update.png)，4 个真实 Widget 回归覆盖新代码、大小写、旧代码、系统空意见。

既有 P2-675 撤回取消通知正文误写“其他处理人完成”、678 远端事件等待延迟，以及更早 IM 服务端 P1、媒体上传失败等仍保留；本轮未复现全部，不视为已修复。

## 本轮门禁（不替代整体验收率）

| 检查项 | 结果与范围 |
| --- | --- |
| 转交后的原/新任务及权限迁移 | 通过：M3 页面 + D1 只读 |
| 前加签原任务等待、新任务可处理 | 通过：仅中间态 |
| 后加签新增任务初始等待 | 通过：尚不可处理 |
| 原节点同意激活后加签、提示不提前通过 | 通过：真实 M3 点击 + D1 只读 |
| 三单撤回且无可操作任务 | 通过 |
| 撤回后所有未完成任务均进入终态 | **不通过：前加签原任务 waiting** |
| 接收人的持久新任务/取消通知 | 通过：GET 证据；非推送显示 |
| 再次发起保留原单、新编号独立 | 通过 |
| 加签历史中文与元信息保留 | 修复后通过 |
| 升级后原草稿/已读/IM 元数据保留 | 通过，比较范围见下节 |
| 正常包构建、安装一致与本地回归 | 通过 |

本轮 11 个明确检查项，最终 10 通过、1 不通过（90.9%）。三类接收人最终处理链路均未完整执行，**不能借此 90.9% 或 750 个单测宣称总体验收通过**。

## 构建、回归与数据保留

- 有效红测：[history-label-red-final.log](../test/evidence/oa-transfer-real-20260903/history-label-red-final.log) 为 1 通过 / 3 预期失败；前两次记录含夹具缺字段和时区期望问题，不作为功能红测证据。
- 专项：[focused-final.log](../test/evidence/oa-transfer-real-20260903/focused-final.log)，106/106；全量：[full-final.log](../test/evidence/oa-transfer-real-20260903/full-final.log)，750/750；[analyze-final.log](../test/evidence/oa-transfer-real-20260903/analyze-final.log)，0 问题。
- 正常入口 `lib/main.dart`，Profile、android-arm64/android-x64；[构建日志](../test/evidence/oa-transfer-real-20260903/build-final.log)，80.5MB，构建成功；插件 Kotlin 迁移提示仍在日志，不属于本轮编译失败。
- 02:29:27 覆盖安装 M3，APK 与安装后 base.apk SHA-256 均为 `9A79F29C001B0789722236F89FBEE5DC7DBFBC33D0219049091BD632B55079E2`；见 [安装校验](../test/evidence/oa-transfer-real-20260903/installed-final.json)。业务流转操作在前一正常包完成，新包复核两种历史和终态；没有声称全新包重新执行过全部三单。
- [preservation-check.json](../test/evidence/oa-transfer-real-20260903/preservation-check.json)：test03 不变；2 份原草稿 ID/更新时间完全一致；9 个已有已读回执及状态完全一致；OA/IM Outbox 均空；IM applied/acked=207、11 条群消息 ID/clientMessageId/序号账本和所有会话元数据未变，单聊条数仍 6、群聊 11、未读 0。不是整个解密数据库逐字节相等验证。
- [runtime-final.json](../test/evidence/oa-transfer-real-20260903/runtime-final.json)：检查时 PID 25928、Wi-Fi/数据开关均 1、该进程可用日志未见 fatal/Flutter error；不是长期稳定性结论。
- 新包实测回到首页仍待我处理 0，见 [最终首页](../test/evidence/oa-transfer-real-20260903/62-home-after-detail.png)；再实际切回“待我处理”显示 [暂无审批事项](../test/evidence/oa-transfer-real-20260903/63-pending-zero-final.png)。报告 40 个原始本地证据链接全部存在，新补充的第 41 个截图亦已采集；当前 APK 哈希再次核对一致，相关已跟踪变更 `git diff --check` 无空白错误。未修改密码、解绑设备或删除测试证据，未提交 Git。

截图 11 是加载中；31、46 是动作后立即采样的旧帧，应采用 12、32、47 的稳定页面，不拿旧帧当最终状态。全部截图未经编辑，每次采集使用独立文件。

## 未执行项与下一步

1. 接收人真实同意转交任务；前加签处理后原节点恢复；后加签最终审批。当前仅有独立 M3 可安全操作，M1 接管待答复，M2 操作来源未确认；不通过登录同账号新设备来绕过可能替换现有会话。
2. Windows 当前窗口真实点击与双端页面对照：当前工具搜索仍无可调用的电脑 UI/Node REPL；未用旧源码或只读接口冒充当前窗口验收。
3. 真实岗位、负责人配置和完整候选资格、工作流版本；复杂金额分支、公式、双人会签/或签、办理/付款/抄送、退回与附件完整链路尚待合适配置和可操作接收端。
4. M1/M2 更新、完整 D1/M1/M2/D2 会话替换与密码失效矩阵、推送与离线恢复、跨端 IM 全路径及性能持续验收；677 自然续期已通过的局部证据不倒退为未测，但长离线与完整矩阵仍未完成。
5. 将 waiting 终态和已有服务端缺陷作为修复后复测门禁；继续保留本目标全范围，不缩减成上述单测或本轮三个案例。
