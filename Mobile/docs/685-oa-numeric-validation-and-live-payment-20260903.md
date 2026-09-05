# 685 · OA 数值校验、错误恢复与真实请款

## 结论与范围

**部分通过，整体目标继续。** 2026-09-03 03:48–04:02（北京时间），仅操作独立 M3/test03 的正常应用。发现并修复两项实际表单问题，新增 20 项回归，全量 **829/829**、静态分析 0 问题；通过真实页面完成一条 100.25 的请款、审批、结果通知阅读和断网冷启动恢复。

当前安装 Windows 1.0.87/test01 进程存在，当前保存会话只读 IM/OA GET 均 200：[会话核对](../test/evidence/oa-live-continuation-20260903/desktop-session.json)。这不是桌面窗口交互证据。电脑控制入口不可用；M1 真机接管问题仍未收到确认，未操作 M1/M2，也没有新建或复制设备、改变身份或直接修改数据库。

## 本轮修复

### P2-685-01：数字和金额漏检非有限值

复现：当前财顺部门请款表单填金额 `NaN`、测试说明，类型和日期留空，点击提交。原页面只提示类型、日期必填，金额无错误：[原始实际页面](../test/evidence/oa-live-continuation-20260903/06-invalid-amount-validation-before.png)。这是客户端校验漏检，不代表服务端已接受该金额；缺失必填项阻止了实际申请，原 OA 游标 449、Outbox 0。

原因是输入框与提交前整份表单校验都只判断 `num.tryParse != null`。现在两层均要求 `isFinite`，拦截 NaN、正负 Infinity 和指数溢出。金额原有大于零规则、数字字段负数、普通小数、科学记数法以及可选空值保持。

[修复前 12 项有效红测](../test/evidence/oa-live-continuation-20260903/red-numeric-verified.log)覆盖两种字段和恢复的可选字段。初次 `red-numeric.log` 是测试夹具缺少参数造成的编译失败，不算缺陷复现。

最终正常包真实恢复草稿后，其他必填项全部填写，仅把金额改为 NaN，提交仍被明确拦截：[最终拦截](../test/evidence/oa-live-continuation-20260903/19-final-nan-validation.png)。没有发出无效金额申请。

### P2-685-02：输入修正后仍显示旧错误

实际把金额改为 100.25、类型选其他、日期选 2026-09-04 后，旧错误仍留在三处：[修复前](../test/evidence/oa-live-continuation-20260903/15-filled-with-stale-errors.png)。用户需要再次提交才能清除，容易误以为正确输入仍不合法。

修复为首次提交尝试后，字段使用最新值重新校验，并刷新跨字段计算错误。首次进入/首次填写不提前显示必填错误；服务端字段错误仍保留至对应字段修改。仅在外层 Form 设置自动校验不足以刷新子字段捕获的旧错误，初次尝试仍红，最终改为字段级校验。

[两项纠错红测](../test/evidence/oa-live-continuation-20260903/red-correction.log)、[纠错绿测](../test/evidence/oa-live-continuation-20260903/green-correction.log)。另外覆盖下拉/日期错误清除和除零依赖修正。最终 M3 将 NaN 改回 100.25，**没有再次点击提交**，错误立即消失：[真实修正结果](../test/evidence/oa-live-continuation-20260903/20-corrected-no-resubmit.png)。

源文件：[表单](../lib/features/todos/presentation/approval_request_page.dart)、[回归](../test/oa_mobile_pages_test.dart)。没有修改后台模板、计算表达式、审批人员、流程规则或消息同步协议，没有批量格式化或覆盖其他未提交改动。

## 真实请款记录

- 编号：**OA-20260902-2C342E**；ID `2c342eb7-ef37-40de-89a7-ba4d3e27e1e3`。
- 测试说明：`AI-UAT-20260903-035000-NUMERIC`；审批意见追加 `-APPROVED`。
- 表单：M3 当前财顺部门请款 v1，模板 ID `5d8b964d-37f5-4cdd-8516-96faa4d8a516`，应用 `finance.payment_request`。
- 实际金额 100.25、类型其他、期望付款日期 2026-09-04，无附件。当前模板没有显示币种字段，不擅自标成 CNY。
- 申请人与实际审批人均为 **Test Terminal 03 / test03 / 财顺**；节点显示“部门负责人审批”。节点名称不替代岗位/负责人组织配置证明。本轮是单节点自审批，不是跨账号验收、付款操作或多金额分支验收。
- 本轮没有独立取得流程版本、任务 ID、clientRequestId 或写请求 HTTP 请求编号，不冒充已经核对。

| 实际操作 | 页面及持久证据 |
| --- | --- |
| 真实提交 | [申请内容与审批中](../test/evidence/oa-live-continuation-20260903/22-submitted-stable.png)，金额保持 100.25；本地事件 452 `approval.submitted`、454 `approval.task.created` |
| 打开同意抽屉、填写测试意见、确认 | [最终确认](../test/evidence/oa-live-continuation-20260903/24-approve-confirm.png)；[通过结果](../test/evidence/oa-live-continuation-20260903/25-approved.png)，此时才显示“审批已通过”，无继续同意/驳回入口 |
| 结果通知 | [通知列表](../test/evidence/oa-live-continuation-20260903/27-result-notifications.png)，申请已提交、待审批和最终结果分别为独立事件；结果正文“审批已通过” |
| 打开结果通知 | [定位同一终态详情](../test/evidence/oa-live-continuation-20260903/28-result-opens-final-detail.png)，[返回未读 32→31](../test/evidence/oa-live-continuation-20260903/29-result-read.png) |
| 断网、强停、正常冷启动 | [通知未读仍 31](../test/evidence/oa-live-continuation-20260903/31-offline-notifications.png)，[本机终态快照](../test/evidence/oa-live-continuation-20260903/32-offline-final-detail.png)，保留金额、日期、意见、已通过且无操作入口，没有退出登录 |
| 恢复网络，不点击重试 | [自动恢复在线详情](../test/evidence/oa-live-continuation-20260903/33-online-recovered.png)，离线快照提示消失，值和终态不变 |

事件原始 UTC：提交事件 2026-09-02 19:59:51.007868，审批更新/结果通知 20:00:30.759396，通知已读事件 20:01:05.134280。Android 状态栏、主机时区与服务端存在显示差异，本地 applied_at 还略早于事件 created_at；没有修改时钟或用跨时钟相减推导延迟。

最终 [SQLite 元数据](../test/evidence/oa-live-continuation-20260903/oa-final.json)：OA 游标 458；结果回执 `a9f79aea-59a9-47ec-b4f5-061ed5aa046a` 为 sent、attempts 0；对应 `oa.notification.read` 事件序号 458。与[断网冷启动快照](../test/evidence/oa-live-continuation-20260903/oa-offline-cold.json)一致，不只是 UI 数字改变。

D1/test01 对新申请的只读详情 GET 返回 404，bootstrap/page 为 200：[其他账号读取](../test/evidence/oa-live-continuation-20260903/desktop-other-account.json)。证明本次无关账号不能读取这一申请，不证明所有权限组合，也不能拿 404 当最终状态核对。

## 构建、回归与数据保护

- 新增 20 项：12 异常数值/恢复，4 合法值/可选空值，2 错误纠正，1 下拉日期，1 计算依赖纠正；[OA 页面 84/84](../test/evidence/oa-live-continuation-20260903/green-final2-oa-pages.log)。
- [全量 829/829](../test/evidence/oa-live-continuation-20260903/full-final.log)、[分析 0](../test/evidence/oa-live-continuation-20260903/analyze-final.log)、[正常 Profile 构建](../test/evidence/oa-live-continuation-20260903/build-final.log)。未更新 Golden。旧 Kotlin 插件迁移警告仍存在，未误报为构建失败。
- 入口 `lib/main.dart`，最终 APK SHA256 **83540B186C77AE95A122096DBDA75F0262FBD6D9D8E5E26AF6339EBB06F15999**；[本地与 M3 安装哈希一致](../test/evidence/oa-live-continuation-20260903/installed-final.json)。仅 M3 覆盖安装，保留数据。
- [保护对比](../test/evidence/oa-live-continuation-20260903/preservation-final.json)：IM 单聊账本和群消息未变，IM applied/acked 236；原两份 OA 草稿和 9 条回执不变。本轮草稿 `8d43e91a-965e-4a34-91b4-2c8a37e7ab13` 正常提交后被消费，只新增已通过测试申请和对应通知/回执。
- 两条既有图片/视频 Outbox 仍在，最近失败仍 HTTP 500；没有删除或换 ID。Wi-Fi/移动数据均恢复到原值 1：[网络状态](../test/evidence/oa-live-continuation-20260903/network-restored.json)。
- [当前 PID 15398 错误计数](../test/evidence/oa-live-continuation-20260903/runtime-errors.json)：Unhandled、RenderFlex overflow、FATAL 匹配均 0，仅为有限日志检查。
- 证据名 `11-valid-amount` 实际是快捷键未全选导致的 `NaN100.25`，不作为合法值证据；`18-final-nan-only-blocked` 没有捕获到按钮生效，最终阻止证据使用 19。未隐藏这些自动操作中间状态，也未将它们算通过。

## 未完成项

当前 M3 本部门模板仅有普通请款字段和单节点流程，不具备双公式、业务部门跨选和分级金额分支，不能把本轮当成复杂请款矩阵通过。转交/前后加签接收人实际处理仍待真机接管确认；当前选人列表只出现 test01，不等于完整审批权限范围已证明。桌面窗口逐项对照、多端/推送/大群性能，以及既有服务端媒体 500、群事件/读投影和高级 OA 终态问题继续保留。整体目标不完成。
