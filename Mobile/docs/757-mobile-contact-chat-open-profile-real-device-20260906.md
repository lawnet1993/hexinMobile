# 757 · 通讯录进入会话与热打开性能实测

日期：2026-09-06，Asia/Shanghai。结论：**当前 Profile 包未复现联系人进入既有单聊时的明显卡死或全量历史重复下载**。通讯录默认只显示组织，展开部门后才显示人员；点击人员头像进入已有单聊。两台测试端均使用应用内 `MOBILE_CHAT_OPEN` 数字检查点记录首次路由、消息可用和消息布局时间，诊断日志不含账号、会话 ID、消息正文、Token 或 URL。

## 页面行为

- 通讯录初始状态只显示“公司总部”和“其他联系人”两个已收起组织，不默认铺开人员列表。
- 展开“公司总部”后显示人员姓名与真实在线、离线或最近上线状态，不在列表正文暴露终端账号。
- 人员头像本身是“联系某人”的可点击区域；没有保留右侧重复的聊天图标。
- 本轮从头像进入已经存在的单聊，不会错误创建第二个会话。

## 模拟器热打开 10 次

设备：`emulator-5554`，test02，x86_64 Profile 包；目标会话本地已有 58 条消息。

| 指标 | 结果 |
| --- | ---: |
| 缓存命中 | 10 / 10 |
| 路由挂载 P50 / P95 / 最大 | 13.038 / 17.379 / 18.692 ms |
| 路由首帧 P50 / P95 / 最大 | 18.374 / 22.932 / 23.979 ms |
| 最新消息完成布局 P50 / P95 / 最大 | 116.965 / 162.782 / 182.682 ms |
| Flutter build 超预算帧 | 3 / 468 |

模拟器使用软件渲染，因此它的 raster/总帧跨度不能作为真机流畅度结论；缓存命中、路由阶段和消息布局检查点仍可用于识别重复加载。

## 真机连续打开 10 次

设备：realme RMX3366，test01，ARM64 Profile 包；从通讯录头像进入 test02 单聊。

| 指标 | 结果 |
| --- | ---: |
| 路由挂载 P50 / P95 / 最大 | 12.189 / 28.856 / 34.915 ms |
| 路由首帧 P50 / P95 / 最大 | 24.656 / 58.156 / 77.246 ms |
| 消息窗口可用 P50 / P95 / 最大 | 55.189 / 118.602 / 133.574 ms |
| 最新消息完成布局（5 个适用样本）P50 / P95 / 最大 | 163.374 / 188.363 / 194.034 ms |
| Flutter build 超预算帧 | 14 / 468 |
| Raster 超预算帧 | 2 / 468 |

前几次进入时会话仍有较长未读区间，客户端按“首条未读真正进入可见区域才提交已读”的规则逐步定位 50、52、58 条窗口；这不是每次向服务端全量拉取。未读窗口处理结束后，第 8、9、10 次直接命中保留的 58 条最新窗口。前 5 个样本没有 `latestMessageLaidOut` 检查点，是因为页面当时定位首条未读而不是最新消息，不能把缺失检查点解释为三秒未完成渲染。

## 代码与自动化交叉验证

- `messagesCacheFirst` 先读取按账号和会话隔离的 SQLite；只有本地窗口为空时才补取服务端最新页。
- 历史上滑优先读取相邻本地页，仅在缓存存在真实缺口时请求服务端。
- 消息窗口最多保留 32 个会话、4096 条消息，空闲 30 分钟后释放；活跃窗口不会因为另一页大小变化而被截断。
- 同一会话事件只失效对应会话 revision；未变化的 12 秒兜底对账不重建消息列表。
- 以下 5 个测试文件共 125/125 通过：`chat_open_diagnostics_test.dart`、`im_cached_history_test.dart`、`im_sync_invalidation_test.dart`、`im_message_window_retention_test.dart`、`chat_page_type_test.dart`。

## 催办补充验证

催办接收端已经补齐。test02 对包含 test01 的真实会签申请发出在线催办 `AI-UAT-REMIND-ONLINE-20260906-0357`，test01 通知中心即时出现且刷新后仍恰好一条。随后 test01 被强制停止并确认进程不存在，test02 在新申请 `OA-20260905-4FEE3F` 提交 `AI-UAT-REMIND-OFFLINE-0405`；test01 冷启动后从持久通知恢复，刷新后仍恰好一条。短时间重复催办被服务端冷却规则拒绝，没有产生重复通知。

## 证据

- [模拟器 10 次数字摘要](../test/evidence/oa-action-boundaries-20260906/continuation-20260906/emulator-5554-contact-chat-open-10-summary.json)
- [模拟器 10 次原始无敏感诊断](../test/evidence/oa-action-boundaries-20260906/continuation-20260906/emulator-5554-contact-chat-open-10.log)
- [真机 10 次数字摘要](../test/evidence/oa-action-boundaries-20260906/continuation-20260906/physical-contact-chat-open-10-summary.json)
- [真机 10 次原始无敏感诊断](../test/evidence/oa-action-boundaries-20260906/continuation-20260906/physical-contact-chat-open-10.log)
- [模拟器通讯录默认收起结构](../test/evidence/oa-action-boundaries-20260906/continuation-20260906/emulator-5554-contacts-current.xml)
- [模拟器通讯录展开及头像联系语义](../test/evidence/oa-action-boundaries-20260906/continuation-20260906/emulator-5554-contacts-expanded.xml)
- [真机通讯录默认收起结构](../test/evidence/oa-action-boundaries-20260906/continuation-20260906/physical-contacts.xml)
- [真机通讯录展开及在线状态](../test/evidence/oa-action-boundaries-20260906/continuation-20260906/physical-contacts-expanded.xml)
- [催办提交后的审批详情](../test/evidence/oa-action-boundaries-20260906/continuation-20260906/physical-remind-submitted.png)
- [在线催办接收端通知](../test/evidence/oa-action-boundaries-20260906/continuation-20260906/physical-notifications-reminder-online.png)
- [离线催办冷启动恢复](../test/evidence/oa-action-boundaries-20260906/continuation-20260906/physical-notifications-reminder-offline-recovered2.png)
- [离线催办刷新后唯一计数](../test/evidence/oa-action-boundaries-20260906/continuation-20260906/physical-notifications-reminder-offline-refresh.xml)

## 当前判断与后续

1. “每次打开会话都重新全量下载并重新构建全部历史”在当前代码、自动化和 Profile 真机样本中均被否定；但打开会话仍会构建当前可见窗口，这是正常 UI 布局。
2. 旧版本或特定超长未读会话的卡顿不能由本轮样本完全排除。后续应在 500+ 条混合图片、视频、语音的真实会话上重复同一诊断，重点观察图片解码和首条未读锚点。
3. 催办的在线接收、离线恢复和单事件去重已经通过；剩余 OA 边界见 [754 多设备实测](754-mobile-oa-boundary-multi-device-real-device-20260906.md)。
