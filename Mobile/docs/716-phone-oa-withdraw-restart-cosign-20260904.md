# 716 真机 OA 撤回、再次发起与部分会签验收

2026-09-04 23:37–23:45，Asia/Shanghai。结论：**部分通过**。真实流程和持久化核对通过，发现撤回通知原因错误；不代表整个 OA 或完整多端验收通过。

## 环境与范围

- 真机 RMX3366，正常 715 Profile 包，SHA256 `06B38621635F2F20E153B22719C00A487513D36EEDB42F7E381296AD994315D6`；本轮未更改应用源码或安装诊断入口。
- 当前账号 test01 / Test Terminal 01，公司总部。流程预览及真实任务解析到公司总部的 Test Terminal 01、陆炳、宋扬、陆炳002，节点名均“部门负责人审批”，方式会签。没有仅按账号名推断岗位；岗位管理未独立复核。
- 所有创建、提交、同意、撤回、通知阅读均通过真机 UI；API 仅使用当前已登录桌面 test01 会话做只读结果核对，不代表操作过 Windows 窗口。
- 标记 `AI-UAT-20260904-233900-PHONE-WITHDRAW` 写在事由中。当前表单没有独立标题输入，标题由系统生成；未修改正式模板、既有申请或其他账号权限。
- 事假，2026-09-05 23:38 至 09-06 23:39，自动自然日 2 天，表单 v1，预览公司总部流程 v1。独立流程修订号未另行取得，不将申请 version 当成流程版本。

## 真实流转

| 申请 | 时间（本地） | 操作与结果 |
| --- | --- | --- |
| OA-20260904-3B79AE | 23:39:59 | 提交，状态 submitted / 审批中，4 个 pending 任务 |
| 同上 | 23:40:43 | 申请人撤回，状态 withdrawn / 已撤回，4 个任务 canceled |
| OA-20260904-4B57F5 | 23:41:11 | 从原详情“再次发起”，预填原数据，提交生成新 ID 与 clientRequestId |
| 同上 | 23:41:48 | test01 仅同意自己的任务；1 approved、3 pending，申请仍 submitted |
| 同上 | 23:42:24 | 申请人撤回；保留已同意记录，余下 3 个任务 canceled，申请 withdrawn |

原申请 ID `3b79ae54-2b23-422c-9ead-cb8153fdf4a8`，clientRequestId `52ffa163-5454-48c5-9195-9381838e925a`，最终申请版本 2。

新申请 ID `4b57f546-639e-49b7-bc9f-4fbbc69f0496`，clientRequestId `c3c95734-887d-4f3c-af6b-afeaad1eff09`，最终申请版本 3。

两条均保留为已撤回的测试记录，未删除；没有替其他会签人操作，也未把一人同意当成整个流程完成。

## 证据

- [必填校验](../test/evidence/oa-phone-withdraw-20260904/01-required.png)、[完整表单及内联流程](../test/evidence/oa-phone-withdraw-20260904/02-filled.png)。日期、时间、请假类型和审批意见使用底部抽屉，未新增弹窗。
- [提交状态](../test/evidence/oa-phone-withdraw-20260904/03-submitted.png)、[服务端提交结果](../test/evidence/oa-phone-withdraw-20260904/04-server-submitted.json)，详情 GET 200，请求编号 `07444232-c6c6-404a-88cb-0290a0b70541`。
- [撤回抽屉](../test/evidence/oa-phone-withdraw-20260904/05-withdraw-sheet.png)、[首次撤回](../test/evidence/oa-phone-withdraw-20260904/06-withdrawn.png)、[再次发起表单](../test/evidence/oa-phone-withdraw-20260904/07-restart-form.png)、[新申请](../test/evidence/oa-phone-withdraw-20260904/08-restarted.png)。
- [两申请独立存在](../test/evidence/oa-phone-withdraw-20260904/09-server-restarted.json)。原申请仍撤回，新申请审批中。
- [仅一人同意](../test/evidence/oa-phone-withdraw-20260904/10-one-of-four.png)、[服务端部分会签](../test/evidence/oa-phone-withdraw-20260904/11-server-partial.json)。页面提示“当前节点已同意，审批继续流转”，仍显示审批中，当前人的同意/驳回消失，API allowedActions 仅 withdraw/remind。
- [第二次撤回](../test/evidence/oa-phone-withdraw-20260904/12-second-withdrawn.png)、[两条最终状态](../test/evidence/oa-phone-withdraw-20260904/13-server-final.json)，两条 allowedActions 均空，既有同意记录未被撤回改写。
- [通知列表](../test/evidence/oa-phone-withdraw-20260904/14-notifications.png)：提交、待处理、进度和撤回通知实际存在；没有本轮 approval.approved 最终通过通知。
- 阅读第二条撤回通知后，[服务端 isRead=true](../test/evidence/oa-phone-withdraw-20260904/15-server-read.json)，通知 ID `fc6afcf0-881f-4be7-a331-f737a082cf34`，服务端 readAt 23:43:03；[UI 未读 50→49](../test/evidence/oa-phone-withdraw-20260904/17-notification-read.png)。
- [SQLite 回执](../test/evidence/oa-phone-withdraw-20260904/18-local-receipt.json)：该通知 state=sent，游标 541，Outbox=0，当前草稿数=0。只读一致快照，无直接改库、无解密导出业务正文。
- 强停冷启动后，[通知未读仍为 49](../test/evidence/oa-phone-withdraw-20260904/19-cold-notifications.png)、[再次打开新申请仍已撤回](../test/evidence/oa-phone-withdraw-20260904/20-cold-detail.png)，登录无需输入密码。当前进程异常/布局溢出采样均 0。此项不是离线测试或跨令牌到期测试。
- [8/8 证据一致性检查](../test/evidence/oa-phone-withdraw-20260904/21-evidence-checks.json)，可运行 `scripts/verify-oa-phone-withdraw-716.ps1` 复核。它检查已采集证据，不代替重新操作，不代表完整 OA 通过率。

## 问题清单

### P2：撤回取消通知误报由其他处理人完成

复现：test01 提交上述 4 人会签申请 → 未有任何人同意前由申请人撤回 → 打开通知中心。

预期：任务取消通知说明申请已撤回或任务已取消，不能表示别人审批完成。

实际：类型 `approval.task.canceled`、通知 `7f2c5161-242d-4822-90ef-af2357f4bd37` 显示“审批任务已结束”，正文“该节点已由其他处理人完成”。原申请全部任务为 canceled，没有任何 approved 操作。容易让审批人误以为其他人已经完成审批。

来源核对：[服务端正文固定谓词检查](../test/evidence/oa-phone-withdraw-20260904/16-server-cancel-text.json)为 true，撤回谓词为 false；GET `/api/oa/bootstrap` HTTP 200，请求编号 `38840fdc-b1fa-40f8-ba07-52a8cf730271`。移动端读取并展示 body，没有本地生成这句文本。本轮未修复服务端，也未在客户端替换成猜测原因。

### 待优化：自动计算字段必填提示

空表单提交时只读请假天数字段显示“请填写请假天数”（见必填截图），但正常操作依赖起止时间自动计算。建议改为提示先选择起止时间；本轮先记录，未改变后台表单定义或计算规则。

## 未执行与限制

未执行剩余三人会签通过、或签、分级金额分支、跨部门岗位、附件与复杂公式、退回/转交/前后加签、抄送全链、两个审批人并发、断网重连和完整 Windows/多移动端矩阵。电脑 UI 控制运行时仍缺失，桌面会话的只读 API 200 不能替代桌面窗口操作。

本轮只修改了测试核对脚本和报告；应用包仍为 715，其 1267 项测试是上一轮结果，不冒充本轮新增测试。捕获到的请求编号属于核对 GET，不冒充 UI 提交/撤回 POST 的追踪编号。
