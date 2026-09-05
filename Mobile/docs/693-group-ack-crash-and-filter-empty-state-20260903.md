# 693：群聊 @我 的 ACK 前杀进程验收与筛选空态

日期：2026-09-03。结论：**本轮两人群断点场景通过，整体移动端仍部分通过**。658 已有单聊断点证据，本轮补群聊、原生提及、未读保留、可见后阅读与发送端回执，不重复宣称未做过单聊验收。

## 真实执行范围

- M3：emulator-5556/test03，接收端；M4：emulator-5558/test04，发送端。两台独立 Android 16 模拟器均保留原身份与数据，M1 真机及 M2 未操作。
- 使用已有测试群 `AI-UAT-20260903-050600-M3-M4-GROUP`，ID `95e704ae-0e34-4f56-87db-038526796d6c`，两名成员，原消息 seq1–3。
- M4 在真实群聊点“提及成员”，选择 Test Terminal 03，再输入 `AI-UAT-20260903-055540-GROUP-ACK-CRASH`，**仅点一次发送**。没有 API 创建消息、手工写数据库、重置游标或重发消息。
- M3 全程停在工作台，直到正常重启补确认和检查未读完成，才进入群聊阅读。

证据：[测试配置](../test/evidence/im-group-ack-crash-20260903/run-config.json)、[原生提及选择](../test/evidence/im-group-ack-crash-20260903/m4-mention-picker.png)、[发送前输入框](../test/evidence/im-group-ack-crash-20260903/m4-ready-to-send.png)、[唯一发送与终止日志](../test/evidence/im-group-ack-crash-20260903/send-and-kill.json)。

本次 [受控执行脚本](../scripts/uat-group-ack-checkpoint.ps1) 校验群标题、原生 @ 文本和唯一标记，发送前写防重日志；存在日志就拒绝再发。只在事务/未读/@我均已验证且 ACK 未推进时终止 M3。初次 M4 页面切换抓图失败，改用新文件名重新抓取成功，没有复用旧 XML 或据失败抓图点击。

## 精准断点与恢复

[独立测试入口](../test_driver/im_ack_checkpoint.dart) 不由正常 main 引入，拒绝 release、非测试环境、非 test03 会话或无明确 AI-UAT 标识。此次额外限定群 ID 和真实 mentions 中的当前成员，确认消息解密读取唯一、提及持久化且会话确为 group 后才暂停。保留当前正常仓库的成员状态依赖与启动初始化。

暂停点仍是生产仓库真实 `applySyncBatch` 事务成功之后、`/api/im/sync/ack` 之前；不是模拟生成消息或抛出本地异常代替真实杀进程。

| 主机时间 +08:00 / 阶段 | 真实结果 |
| --- | --- |
| 初始 | 群 seq3/read3/unread0/@[]；M3 applied=acked=286 |
| 05:59:10 | M4 点击发送一次，原生 @Test Terminal 03 |
| 05:59:11 | 命中断点：message seq4、copies=1、group、mentionsSelf=true；applied=289，acked=286 |
| 05:59:11.760 | 只读 SQLite+WAL 再确认：4 条消息、read3/unread1/@[4]，确认游标仍286 |
| 05:59:12.047 | `am force-stop` 后原 PID7451 已不存在；不是只退到后台 |
| 进程死亡后 | 数据仍为 applied289/acked286、4 条消息、read3/unread1/@[4] |
| 正常包冷启动，仍在工作台 | 自动补 ACK 到289，消息 ID 均不变，read3/unread1/@[4] 保留 |
| 打开消息列表及 @我筛选 | 唯一测试群、角标1；只看列表不清已读 |
| 实际打开群，seq4 正文进入可见区域 | read4/unread0/@[] 持久化；M3收到 conversation.read，applied=acked=291 |
| M4 不刷新、不重开群 | 新消息从“已发送”变为已有接收人已读；M4收到 conversation.read，applied=acked=290 |

断点、数据库和恢复证据：[断点白名单记录](../test/evidence/im-group-ack-crash-20260903/checkpoint.json)、[提交未确认](../test/evidence/im-group-ack-crash-20260903/m3-committed-before-kill.json)、[死亡后](../test/evidence/im-group-ack-crash-20260903/m3-after-process-death.json)、[自动恢复](../test/evidence/im-group-ack-crash-20260903/m3-auto-recovered.json)、[只看提及列表仍未读](../test/evidence/im-group-ack-crash-20260903/m3-mentioned-list-unread.json)、[实际阅读后](../test/evidence/im-group-ack-crash-20260903/m3-after-visible-read.json)、[发送端读事件](../test/evidence/im-group-ack-crash-20260903/m4-peer-read-state.json)。

已查看的原生截图：[重启后 @我 与角标](../test/evidence/im-group-ack-crash-20260903/m3-mentioned-list.png)、[真实消息唯一可见](../test/evidence/im-group-ack-crash-20260903/m3-visible-group-message.png)、[发送端未读时](../test/evidence/im-group-ack-crash-20260903/m4-sent-before-read.png)、[发送端已读后](../test/evidence/im-group-ack-crash-20260903/m4-after-peer-read.png)。

消息 ID：`1f44b476-c5ca-427b-91f7-53f65856e574`；clientMessageId：`c34c41c9-4392-4783-92a2-00ac6c51cf70`；群序号4；服务端时间 `2026-09-02T21:59:11.477303Z`。M3 的 message.created 为 seq289 / `19d80306-c77f-486e-8c37-4ef2bc33e0b3`，M4 对应事件为 seq288；两账号事件序号本就不同，不能要求数值相等。服务器未提供的请求编号不编造，以消息/事件 ID 追踪。

恢复首先使用已验证正常 main 包 `24A60B…DD1157`，而不是重新进入断点入口：[正常恢复安装](../test/evidence/im-group-ack-crash-20260903/normal-recovery-install.json)。后续空态修复又安装最终正常包，再次核对4条消息与已读状态跨冷启动保留。

## 实测发现并修复：P3 筛选空态误导

复现：进入 @我 → 打开唯一未读提及 → 阅读 → 返回 @我。群和消息都还在，“@我”筛选为空，旧界面却显示“暂无会话”，容易误解为会话丢失。[修复前真实截图](../test/evidence/im-group-ack-crash-20260903/m3-mentions-cleared.png)。

[MessagesPage](../lib/features/messages/presentation/messages_page.dart) 仅调整空态文案，不删除会话、不改过滤或已读规则：

| 条件 | 当前文案 |
| --- | --- |
| 全部为空 | 暂无会话 |
| 未读为空 | 暂无未读消息 |
| @我为空 | 暂无未读提及 |
| 群组为空 | 暂无群聊 |
| 有搜索词但无匹配 | 没有匹配的会话 |

新增 [10 项空态测试](../test/messages_empty_state_test.dart)，包括四种筛选、搜索后清空/空白词、已读更新后仅筛选变空而全部仍有群。**修复前2过/8失败，修复后10过**，没有删断言：[红测](../test/evidence/im-group-ack-crash-20260903/empty-state-before.log)、[修复后专项](../test/evidence/im-group-ack-crash-20260903/targeted-final.log)。

最终包原生验证：[暂无未读提及](../test/evidence/im-group-ack-crash-20260903/m3-final-mentions-empty.png)、[暂无未读消息](../test/evidence/im-group-ack-crash-20260903/m3-final-unread-empty.png)、[全部列表仍保留原群](../test/evidence/im-group-ack-crash-20260903/m3-final-all-list.png)。群组空态与搜索组合由组件测试覆盖，未删除已有群来构造空数据。

## 回归、最终安装与保留检查

- [ACK 恢复测试](../test/im_ack_recovery_test.dart) 在既有单聊3项上增加群聊3项：落库后中断、ACK 500、ACK前换账号；使用真实本地 HTTP、AES-GCM SQLite、关库重开及故意重复事件，检验消息唯一、mentions、首条未读、未读提及和设备游标隔离。这里的重复投递与500属于本地受控测试，不当成线上证据。
- 本轮合计新增13项；[专项29/29](../test/evidence/im-group-ack-crash-20260903/targeted-final.log)、[全量915/915](../test/evidence/im-group-ack-crash-20260903/full-test-final.log)、[分析0问题](../test/evidence/im-group-ack-crash-20260903/analyze-final.log)。
- [最终构建](../test/evidence/im-group-ack-crash-20260903/normal-build-final.log)：正常 `lib/main.dart`、profile、arm64+x64，93.2MB。SHA-256 `6F9720AE46895F9DEEB4BEB65812811BE28C0E57870472CD1460D4EDF4C4C245`；[M3安装](../test/evidence/im-group-ack-crash-20260903/final-install-emulator-5556.json)、[M4安装](../test/evidence/im-group-ack-crash-20260903/final-install-emulator-5558.json) 的 base.apk 均一致，未清数据。
- [14项核对](../test/evidence/im-group-ack-crash-20260903/verification.json) 全部通过：两端各4条唯一服务端/客户端消息ID，逐项账本一致，原3条未改；目标群已读4、未读0、@[]；其他会话元数据、Outbox身份和OA草稿/回执保留。M3 原2条待发媒体、2草稿、10回执仍在，并不代表待发媒体已发送成功。
- 原始最终快照：[M3](../test/evidence/im-group-ack-crash-20260903/m3-final.json)、[M4](../test/evidence/im-group-ack-crash-20260903/m4-final.json)、[OA](../test/evidence/im-group-ack-crash-20260903/oa-final.json)。
- [最终运行窗口](../test/evidence/im-group-ack-crash-20260903/runtime-final.json)：两台双网络均1/1，本轮未改网络；当前PID无断点/状态诊断日志，Unhandled/overflow/FATAL均0。原始logcat仅内存过滤，不落盘，不输出密码/令牌/设备指纹/附件地址。
- [D1健康核对](../test/evidence/im-group-ack-crash-20260903/desktop-health.json)：安装桌面端1.0.87/test01运行，授权只读IM/OA均200。这不是本轮Windows UI、同账号双端已读或桌面群参与的实测。

## 尚未证明的范围

本轮证明一条真实群 message.created + @我的“事务提交后、ACK前”进程死亡与恢复。线上服务按已落库游标继续同步，**没有证明服务端在这次实际重复投递了同一事件**；重复投递幂等由本地HTTP测试覆盖。500条批量积压、其他崩溃窗口、大群规模、系统推送、同账号跨端替换/已读、Windows UI与授权真机完整矩阵、高级OA流程仍需继续。

692的离线及时性、包体差异和既有媒体发送问题未在本轮解决。整体目标保持进行中，不把这次局部通过当作最终验收完成。
