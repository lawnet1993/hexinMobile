# 754 · 移动端 OA 边界、多设备及时性与断网恢复实测

日期：2026-09-06，Asia/Shanghai。环境为线上测试环境，只创建或处理 `AI-UAT-` 测试数据。结论为**部分通过**：本轮补齐了真实跨账号审批、多端通知、催办在线/离线恢复与去重、IM 突发消息、大附件断网恢复，以及 DOCX/XLSX/PPTX 服务端往返与真机下载证据；退回、双设备同时处理同一任务和服务端容量上限仍不能判定通过。

## 测试拓扑

- Android 真机：realme RMX3366，test01，作为审批发起/处理端和 IM 接收端。
- Android 模拟器 1：`emulator-5554`，test02，作为转交接收人。
- Android 模拟器 2：`emulator-5556`，test03，作为加签接收人和 IM 发送端。
- 三端同时在线。两台模拟器合计占用约 7.3 GB 主机内存，测试时主机可用内存约 2.5–3.2 GB，因此没有启动第三台模拟器。继续增加实例会把主机换页与 Android 软件渲染噪声混入产品指标。

## OA 操作边界

| 边界 | 真实结果 | 判定 |
| --- | --- | --- |
| 驳回 | `OA-20260906-78DA79` 由 test01 填写原因并确认；详情变为“已驳回”，其他并行节点取消，显示一次处理记录 | 通过 |
| 转交 | `OA-20260906-7BE44E` 从 test01 转给 test02；test02 待办只出现一条，详情显示原处理人“已转交”、test02“待你处理”；test02 同意后显示一次处理记录 | 通过 |
| 前加签 | `OA-20260906-0BE73F` 加签 test03；test01 先变为“等待中”，test03 同意后 test01 恢复“待处理”，真机待办数同步增加 | 通过 |
| 后加签 | `OA-20260906-EF19C3` test01 同意后流转给 test03；test03 同意后流程继续 | 通过 |
| 快速重复确认 | test03 在后加签确认页 60 ms 间隔点击两次；最终只存在一条 `同意 · AI-UAT-AFTERSIGN-TEST03-DOUBLE-TAP` 处理记录 | 客户端防重复通过；不等同于双设备并发幂等通过 |
| 撤回 | `OA-20260906-0F96FF` 撤回后详情状态为“已撤回”，原审批历史保留，可再次发起 | 通过 |
| 催办 | test02 对包含 test01 的会签申请分别完成在线和离线催办；在线通知即时出现一次，test01 被强制停止后发送的第二条催办在冷启动后恢复，刷新后仍恰好一条；短时间重复催办被服务端冷却规则拒绝 | 通过 |
| 退回 | 后续已专门新建并发布允许“退回”的 `AI-UAT-退回验收-20260906-103600`，真实负责人待办仍未包含 `return`，移动端按权限只显示“转交、加签” | 未通过：后台配置到运行实例权限的链路不一致，详见 [774](774-mobile-oa-return-published-flow-live-verification-20260906.md) |

### 桌面与移动并发处理补测

- 使用当前已安装桌面 test01 会话与 test01 真机，针对同一待办 `fe90a4a7-5438-4d23-88db-a4e19972b538`、同一任务 `bd98b373-ad9a-4ebf-9718-27916c9c657a` 发起近同时处理。
- 服务端只接受一次有效动作；桌面请求以 `expectedTaskVersion=1` 返回 HTTP 200，结果版本推进为 2，请求编号 `572e23e2-cd3b-4fa5-8f79-c675ab57c74e`。最终详情只有一条处理结果，没有重复流转。
- 随后明确重放旧版本 1，服务端返回 HTTP 409，提示 `The record has changed. Refresh and retry.`，请求编号 `7734a56b-b6db-4ca6-b333-0f701593d1f3`。
- 判定：同任务乐观并发冲突和旧版本拒绝通过；这补齐了此前“只做单端双击”的服务端边界。当前样本没有授权 `return`，退回仍保持未通过。

移动端操作入口严格以服务端 `allowedActions` 渲染；`return` 的客户端处理代码存在，但本轮测试流程没有获得该权限。这说明当前阻塞不是按钮漏画，也不能据此证明服务端退回语义可用。

随后又逐条检查 test01 当前全部 4 条真实待办：`OA-20260906-0BE73F`、`OA-20260906-24DD3C`、`OA-20260904-FE90A4`、`OA-20260902-9F62B5`。四条详情均只有“驳回/同意”以及“转交、加签、催办、撤回”，仍没有“退回”。这进一步确认当前测试数据没有服务端授权的退回样本，不应由移动端自行显示或绕过权限调用。

## 通知与未读

- test03 收到前加签和后加签两条“待你审批”通知，能够分别定位到对应审批详情。
- 打开其中一条前，通知中心为“未读 61”；打开详情再返回后为“未读 60”，该条蓝点消失。
- 这证明本轮跨账号通知可达、点击路由正确且未读状态能够持久更新。
- `OA-20260906-507E72` 在线催办 `AI-UAT-REMIND-ONLINE-20260906-0357` 在 test01 通知中心即时出现，刷新后精确计数仍为 1。
- test01 被 `force-stop`、进程确认不存在后，test02 在新申请 `OA-20260905-4FEE3F` 成功提交 `AI-UAT-REMIND-OFFLINE-0405`；test01 冷启动后从持久通知恢复，通知中心精确计数为 1，再次下拉刷新仍为 1。
- 同一申请短时间内再次催办时，服务端返回 `Please wait before sending another reminder.`，申请状态未改变，也没有产生第二条通知。

## 多端 IM 及时性与突发消息

### 单条及时性

- test03 模拟器向 test01 真机发送 `AI-UAT-PERF-PROBE`。
- 真机第一次 UI 采样即已看到消息；从发送操作到采样命中的上界为 3091 ms。
- 该数字包含 ADB 输入和 `uiautomator` 采样开销，只能作为端到端上界，不能当作网络纯延迟。

### 突发与去重

- test03 连续发送 20 条 `AI-UAT-PERF-20260906-BURST-001..020`，真机按序显示到最后一条。
- 另发送 10 条 `BURST2-001..010`；真机当前账号 SQLite 消息数从 189 增至 199，消息 ID 去重计数和 `clientMessageId` 去重计数也均从 189 增至 199。
- 因此这 10 条在本轮接收端表现为：恰好新增 10、无重复落库、顺序可见。
- 20 条 ADB 驱动发送耗时 19.905 s，约 995 ms/条；主要受逐条 UI 输入限制，不能代表服务端吞吐上限。

### 性能样本

| 设备 | 帧样本 | Janky | P50 / P90 / P95 / P99 | PSS |
| --- | ---: | ---: | --- | ---: |
| 真机 RMX3366 | 808 | 27（3.34%） | 6 / 13 / 16 / 23 ms | 约 247 MB |
| emulator-5554 | 58 | 17（29.31%） | 17 / 34 / 65 / 150 ms | 约 147 MB |
| emulator-5556 | 147 | 48（32.65%） | 20 / 57 / 85 / 500 ms | 约 166 MB |

模拟器采用软件渲染且主机内存紧张，模拟器 Jank 只能用于发现明显回归，不能替代真机性能结论。本轮属于三端并发冒烟和小规模突发测试，**不是**服务端容量、最大在线数或饱和吞吐压测。

进一步的两模拟器并发结果见 [756 多模拟器并发与及时性实测](756-mobile-multi-emulator-im-load-timing-20260906.md)：原六轮共 94 条，加上 App 在系统附件打开器后台时的 10+10 突发，共 114 条目标消息均无丢失、无重复、会话序号连续；但首轮一个会话 P95 35.027 秒，后台复测 test03 最大 15.566 秒，故实时及时性仍为部分通过。第三台 1 GB 无窗口 AVD 启动时宿主机可用内存降至 0.57 GB，已停止该实例，避免把宿主机换页当成产品延迟。

通讯录头像进入会话的 Profile 真机与模拟器结果见 [757 通讯录进入会话与热打开性能实测](757-mobile-contact-chat-open-profile-real-device-20260906.md)：真机消息窗口可用 P95 为 118.602 ms，最新消息布局的适用样本最大 194.034 ms；模拟器热打开 10/10 命中 58 条保留窗口。当前包未发现每次打开会话都全量下载历史。

## 12 MiB 附件断网与恢复

- 对象：`AI-UAT-20260906-large-attachment.bin`，12,582,912 字节。
- 下载开始后关闭移动数据，客户端提示“附件打开失败，请稍后重试”，检查时没有遗留 `.part` 半文件。
- 恢复移动数据并重试后进入 Android 系统“打开方式”页面。
- 重试文件大小仍为 12,582,912 字节，SHA-256 为 `cfadd44a103cbd6d5726fa07b27d7aad2f67ed3930ff96901c486a5beaf7e723`，与上传原件一致。
- 结论：文件流下载、进度态、失败清理、网络恢复重试和完整性校验通过。未知格式的 `.bin` 交给系统选择打开器是预期行为，不代表内容渲染通过。

## Office 三格式服务端往返

- test02 在 AOSP 模拟器发起 `OA-20260906-507E72`，一次上传有效 DOCX、XLSX、PPTX；test01 真机工作台实时出现对应待办。
- 真机下载三种附件时分别显示进度态，完成后均以正确标准 MIME 拉起 Android 系统打开器。
- 从真机应用私有缓存导出的三份回下载文件与上传原件逐字节一致，大小和 SHA-256 均匹配；详细值、OEM DocumentsUI 故障与系统查看器隐私边界见 [755 Office 真机验证](755-mobile-office-mime-local-render-real-device-20260906.md)。

## 自动化回归

- 审批动作保护、会话隔离、附件流存储和 OA 页面定向测试：237/237 通过。
- 当时完整移动端测试集为 1393/1393；补齐 Office MIME 后最新完整测试为 1395/1395，通过结果见 [755 Office 真机验证](755-mobile-office-mime-local-render-real-device-20260906.md)。
- `flutter analyze`：0 error、0 warning；保留 7 条仓库已有的 `curly_braces_in_flow_control_structures` info。

## 证据索引

- [转交接收人详情](../test/evidence/oa-action-boundaries-20260906/06-test02-transfer-detail.png)
- [转交接收人同意结果](../test/evidence/oa-action-boundaries-20260906/08-test02-transfer-agree-result.png)
- [前加签接收人同意结果](../test/evidence/oa-action-boundaries-20260906/16-test03-before-sign-agree-result.png)
- [前加签后原处理人恢复待办](../test/evidence/oa-action-boundaries-20260906/18-test01-restored-pending.png)
- [后加签快速重复确认结果](../test/evidence/oa-action-boundaries-20260906/23-after-sign-double-confirm-result.png)
- [驳回结果](../test/evidence/oa-action-boundaries-20260906/reject-result-06.png)
- [跨账号通知](../test/evidence/oa-action-boundaries-20260906/19-test03-notifications.png)
- [通知已读减一](../test/evidence/oa-action-boundaries-20260906/21-test03-notification-marked-read.png)
- [IM 单条及时性接收](../test/evidence/oa-action-boundaries-20260906/24-im-perf-probe-receiver.png)
- [IM 20 条突发接收](../test/evidence/oa-action-boundaries-20260906/25-im-burst-receiver.png)
- [当前 4 条待办完整列表](../test/evidence/oa-action-boundaries-20260906/todo-full-list.png)
- [第二条待办更多操作](../test/evidence/oa-action-boundaries-20260906/pending-second-more.png)
- [第三条待办更多操作](../test/evidence/oa-action-boundaries-20260906/pending-third-more.png)
- [第四条待办更多操作](../test/evidence/oa-action-boundaries-20260906/pending-fourth-more.png)
- [催办提交后的审批详情](../test/evidence/oa-action-boundaries-20260906/continuation-20260906/physical-remind-submitted.png)
- [在线催办接收端通知](../test/evidence/oa-action-boundaries-20260906/continuation-20260906/physical-notifications-reminder-online.png)
- [在线催办刷新后唯一计数](../test/evidence/oa-action-boundaries-20260906/continuation-20260906/physical-notifications-reminder-online-refresh.xml)
- [离线催办发送端成功记录](../test/evidence/oa-action-boundaries-20260906/continuation-20260906/emulator-5554-reminder-offline-confirmed.png)
- [真机冷启动恢复离线催办](../test/evidence/oa-action-boundaries-20260906/continuation-20260906/physical-notifications-reminder-offline-recovered2.png)
- [离线催办刷新后唯一计数](../test/evidence/oa-action-boundaries-20260906/continuation-20260906/physical-notifications-reminder-offline-refresh.xml)
- [服务端催办冷却提示](../test/evidence/oa-action-boundaries-20260906/continuation-20260906/emulator-5554-reminder-offline-result.png)
- [通讯录进入会话性能报告](757-mobile-contact-chat-open-profile-real-device-20260906.md)
- [下载断网失败态](../test/evidence/oa-large-download-20260906/11-download-interrupt-500ms.png)
- [恢复后系统打开器](../test/evidence/oa-large-download-20260906/retry-06.png)
- [Office 三格式真实申请](../test/evidence/oa-action-boundaries-20260906/continuation-20260906/emulator-5554-office-submit-result.png)
- [真机 Office 附件详情](../test/evidence/oa-action-boundaries-20260906/continuation-20260906/physical-office-detail.png)
- [Office 下载进度与完整性报告](755-mobile-office-mime-local-render-real-device-20260906.md)

## 仍需继续执行

1. 已完成“后台发布明确允许 `return` 的 AI-UAT 流程”这一步，但运行实例仍未下发该权限；待服务端修复 [774](774-mobile-oa-return-published-flow-live-verification-20260906.md) 后，继续真实执行退回并核对原节点、新节点、通知和历史。
2. DOCX、XLSX、PPTX 的标准 MIME、本地内容渲染和 OA 服务端上传/回下载闭环已在 [755 Office 真机验证](755-mobile-office-mime-local-render-real-device-20260906.md) 通过。PDF 内容渲染仍受真机默认阅读器云端授权限制。
3. 桌面与真机的同任务并发已验证一次成功、旧版本重放 HTTP 409；仍建议在服务端压测窗口补充不同动作组合（同意/驳回、转交/同意）的并发矩阵。
4. 服务端容量压测需使用独立压测脚本和可观测指标，在授权窗口内逐级增加虚拟用户；不应继续通过 GUI 模拟器堆叠来推断容量。
