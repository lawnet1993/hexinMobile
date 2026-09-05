# 675 真实撤回、再次发起与驳回验收

时间：2026-09-03 01:06–01:15，Asia/Shanghai。上一轮 674 有实际修复与回归，本轮补齐其断网恢复收尾，并继续正常包的真实 OA 操作，属于 progress。整体目标仍进行中。

## 结论与范围

**本轮部分通过：撤回→再次发起→驳回、数据独立性和断网恢复通过；发现一处任务取消通知文案错误，未自行改写服务端业务含义。**

仅操作独立 M3（emulator-5556/test03），版本仍是 674 正常 `lib/main.dart` Profile 包，SHA256 `AD0B64E93A90EA378959043026943D011264EBD5439359FA98C279E51CBCEA86`。未重新编译或安装，未操作 M1/M2。当前已安装 Windows 1.0.87/test01 只用于只读会话/权限核对，不声称完成 Windows UI 验收。

所有新业务标记以 `AI-UAT-20260903-010600` 开头。当前借支表单不提供独立标题输入，自动标题是“Test Terminal 03的借支审批”，标记写在借支说明及处理原因。无付款、放款或删除操作；两条新申请最终均为终态。

## 实际身份与表单

- 申请人、实际解析的部门负责人均为 Test Terminal 03 / 财顺；来自当前表单的流程预览和实际任务，不是根据 test03 名称猜测。
- 借支表单和财顺流程在 UI 显示 v1；未获取独立的流程发布 ID、服务端请求 version，不能将 UI 的 v1 等同于全部版本字段。
- 金额、CNY、其他用途、2026-09-04 预计归还日期和说明均通过真实页面填写；下拉与日期均为底部抽屉。未上传附件。
- 先查看加班入口时恢复了原有草稿，因此退出，改用没有草稿的借支入口。两份原有草稿未编辑，最终 ID 和修改时间不变。

## 流转记录

| 申请 | ID | 提交操作时间（北京时间） | 金额 | 实际路径与最终状态 |
|---|---|---|---:|---|
| OA-20260902-8928DD | `8928dded-2c49-4cbb-8eed-2e5808ab7cf7` | 01:06:23 | 100 | 申请人提交 → 财顺部门负责人待处理 → 01:07:17 申请人撤回，原任务取消 |
| OA-20260902-0FE47E | `0fe47e22-a5d3-4daa-ae3e-05d27741c021` | 01:08:46 | 101 | 原单再次发起 → 财顺部门负责人待处理 → 01:09:30 Test Terminal 03 驳回 |

表中时间是操作前的本机记录，不冒充服务端精确完成时间。服务端事件 UTC 时间可见 [最终 OA 元数据](../test/evidence/oa-withdraw-resubmit-20260903/oa-final.json)：撤回和任务取消为 `2026-09-02T17:07:18.551928Z`，新提交为 `17:08:46.709636Z`，驳回对应更新为 `17:09:31.6776Z`。应用中的日期格式与电脑时区不同，申请编号原样保留，未修改设备时间。

- [原单提交后](../test/evidence/oa-withdraw-resubmit-20260903/12-submitted.png)：审批中、待你处理，没有提前提示通过。
- [撤回后](../test/evidence/oa-withdraw-resubmit-20260903/16-withdrawn.png)：已撤回、任务已取消，记录 `AI-UAT-20260903-010600-WITHDRAW-ORIGINAL`，仅可再次发起。
- [再次发起表单](../test/evidence/oa-withdraw-resubmit-20260903/17-resubmit-form.png)：原金额、币种、用途、日期和说明正确带入；随后仅将新金额改为 101，说明增加 `-REISSUED`，从 UI 提交。
- [新单](../test/evidence/oa-withdraw-resubmit-20260903/23-new-stable.png) 与 [新单驳回后](../test/evidence/oa-withdraw-resubmit-20260903/26-rejected.png)：新编号、101 元，原因 `AI-UAT-20260903-010600-REJECT-REISSUED`，显示处理人/节点/时间，操作按钮移除。
- [发起列表](../test/evidence/oa-withdraw-resubmit-20260903/29-initiated.png) 同时保留两单；[重新打开原单](../test/evidence/oa-withdraw-resubmit-20260903/30-original-final.png) 仍是 100 元、原说明、撤回原因，未被新申请覆盖。
- 撤回和驳回后“待我处理”均为空，[待办 XML](../test/evidence/oa-withdraw-resubmit-20260903/28-todo-return.xml)；历史通知仍存在，不等同于仍有可操作任务。

## 通知与持久化

[通知中心](../test/evidence/oa-withdraw-resubmit-20260903/33-notifications.png) 实际出现两单的提交/待审批、撤回、任务取消及驳回结果通知；驳回结果正文为“审批已被驳回”。打开结果通知进入 0FE47E，打开撤回通知进入 8928DD，未混用申请。

未读数依次 **14 → 13 → 12**：[读取驳回结果后](../test/evidence/oa-withdraw-resubmit-20260903/35-notification-read.png) / [读取撤回通知后](../test/evidence/oa-withdraw-resubmit-20260903/37-read-before-offline.png)。本地回执新增：

- 驳回结果 `dbf04aea-c91a-4e0b-b9cd-ccf3b1bf7828`，`read_at=2026-09-02T17:11:17.712551Z`，sent。
- 撤回结果 `1ff0307a-d840-4da6-bd3b-fc93cd1bfb12`，`read_at=2026-09-02T17:11:57.780402Z`，sent。
- 两个 `oa.notification.read` 事件 seq389/390 均已落库；OA 游标到 390，Outbox 为空。通知正文没有当成消息直接插入 IM。

关闭 M3 WiFi 和移动数据并杀进程后正常启动：[通知未读仍为 12](../test/evidence/oa-withdraw-resubmit-20260903/40-cold-notifications.png)，[新单驳回状态](../test/evidence/oa-withdraw-resubmit-20260903/41-cold-rejected.png) / [原单撤回状态](../test/evidence/oa-withdraw-resubmit-20260903/43-cold-withdrawn.png) 均保留，详情显示本机快照且不提供在线动作。01:13:58 恢复网络，没有点击重试；01:14:14 捕获时快照提示已自动消失，[恢复后的原单](../test/evidence/oa-withdraw-resubmit-20260903/45-auto-recovered.png)。约 16 秒是观察间隔上界，不是精确恢复延迟。

[数据对比](../test/evidence/oa-withdraw-resubmit-20260903/data-checks.json) 所有检查为 true：两份原有草稿、断网前后四条已读回执、IM 全部消息元数据与群 11/单聊 6 条、已读和 applied/acked207 均不变。无本轮遗留待发送审批。

## 只读桌面核对与限制

01:11，已安装桌面客户端进程运行，当前保存的 test01 会话 IM/OA bootstrap 均为 HTTP 200。用该会话 GET 两条 test03 申请详情均返回 **404**：[当前桌面会话与请求状态](../test/evidence/oa-withdraw-resubmit-20260903/desktop-approval-access.json)。这两次样本未泄露申请，不代表所有角色、租户和操作接口的权限矩阵已通过；也不能仅凭 404 断言服务器的内部权限实现。

移动端提交/撤回/驳回的 POST HTTP 状态和关联请求头未采集，不编造请求编号。上述请求 ID 是业务申请 ID，不是 HTTP Request-ID。未用 API 替代任何业务写操作，未解密并导出移动端缓存正文或令牌。

## 本轮用例汇总

仅统计本轮 12 项检查，不是整个 IM/OA 目标通过率：**11/12（91.7%）**。

| 检查 | 结果 |
|---|---|
| 提交显示审批中而非提前通过 | 通过 |
| 撤回后原任务取消、不可继续审批 | 通过 |
| 撤回原因、人员和时间展示 | 通过 |
| 再次发起正确带入业务字段 | 通过 |
| 新 ID、改值独立、原申请未覆盖 | 通过 |
| 驳回状态、节点、人员、时间与原因 | 通过 |
| 驳回/撤回结果通知定位正确申请 | 通过 |
| 未读 14→13→12 且回执/事件落库 | 通过 |
| 断网杀进程保留两单与已读、恢复自动同步 | 通过 |
| 两份旧草稿和 IM 消息、游标、队列未受影响 | 通过 |
| 桌面 test01 两次只读请求未获得其他账号详情 | 通过（有限样本） |
| 任务取消通知准确描述取消原因 | **不通过 P2** |

### P2-675-01：撤回后任务通知错误声称由他人完成

1. 以 test03 在财顺借支流程提交 8928DD，当前待审批人也是 test03。
2. 同一申请人撤回，详情正确显示任务已取消。
3. 打开通知中心，17:07 的“审批任务已结束”通知写着“该节点已由其他处理人完成”。[截图](../test/evidence/oa-withdraw-resubmit-20260903/33-notifications.png)。

预期：说明申请被撤回、当前任务取消；实际：暗示其他人已处理完成，与详情冲突。影响：用户可能误解为或签抢先完成或他人已审批。相关申请 `8928dded-2c49-4cbb-8eed-2e5808ab7cf7`；本地事件 seq379 为 `approval.withdrawn`、381 为 `approval.task.canceled`，同批通知 seq380/382。未取得通知原始 HTTP 关联编号，不猜测两条通知与事件的精确映射。

移动端通知模型从 `body` 读取并原样展示，未找到该文案的本地硬编码；目前按通知内容来源问题记录，尚未在线抓取原始响应完成最终根因归属，也未修改服务器或在客户端擅自替换原因。

## 工具、证据质量与未执行项

- 增加安全截图助手 `scripts/capture-device-uat.ps1`：每次使用唯一设备文件，dump 失败不回收旧截图；限制项目证据子目录、不覆盖旧证据。真实调用正常，重复文件/越界目录/不存在设备的保护及两个脚本语法检查通过：[助手检查](../test/evidence/oa-withdraw-resubmit-20260903/helper-checks.json)。桌面只读助手新增显式业务申请 ID 状态核对，不输出响应正文或凭据。
- `38-cold-start.xml` 来自旧脚本在启动过渡期 dump 失败后拉取的旧文件，**不作为冷启动证据**；改用新助手的 39–45。`27-original-unchanged` 实际是返回后的应用目录，亦不作为原单证据；正确原单证据为 30。
- 编辑新单说明时，ADB 的行尾/组合键没有按预期替换全文；通过页面长按→全选纠正，21 的最终表单与 23 的服务端详情一致。中间 18/19 不是提交值。
- 本轮没有修改 Flutter 生产代码；沿用 674 的全量 672/672、分析 0 和已安装包，**没有把此前测试说成本轮新跑**。没有删除业务数据、原草稿、历史消息或证据。
- 01:16 收尾重新核对设备 base.apk 哈希仍与 674 一致，WiFi/移动数据开启，应用运行；该进程最近 2000 条日志的 FATAL EXCEPTION / E/flutter 计数均为 0，仅记录计数。[收尾运行检查](../test/evidence/oa-withdraw-resubmit-20260903/runtime-final.json)。
- 仍未执行：真机新版、Windows UI 与同账号真实跨端矩阵、自然到期、前后加签/转交/退回、金额多分支/会签/或签/办理付款/抄送、附件失败恢复、并发及大群性能、原生推送。后端既有 IM 群读/事件/媒体问题继续保留；完整目标不能判定通过。
