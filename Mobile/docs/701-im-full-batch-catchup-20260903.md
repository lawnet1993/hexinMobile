# 701：IM 满页补拉修复与真实离线积压验收

2026-09-03 08:42收尾：原任务已结束exit0，真实观察到500+10事件页；两端510条账本、已读、原IM/OA记录、正常包及冷启动核对15/15通过。历史上滑暴露的顶部手势缺陷在704修复并离线滑到第1条。最新状态、截图与范围见 [704完整收尾](704-im-history-edge-and-batch-acceptance-20260903.md)。当前运行正常704包，22983不再存活，不要按下方旧计划重复发送。完整IM/OA目标仍未完成。

以下保留701执行时的历史过程快照；其中“正在运行/下一步/待回装”只描述当时状态，已由上述收尾替代。

日期：2026-09-03，Asia/Shanghai。**整体部分通过；真实 510 条消息任务尚在运行，未判定批量验收通过。** 前一响应交付应用图标，未推进核心 IM/OA 验收；本轮重新核对模拟器、源码与数据后继续未完成的满 500 事件门槛。

## 已完成的修复及本地证据

生产同步协调器在收到满 500 条后，把 `catchupProgressed` 重置为 false，下一请求仍使用 `waitSeconds=25`。改为 `result.eventCount >= 500`，满页后使用 0 立即探测下一页，追平并完成必要历史补偿后恢复 25 秒长轮询。未修改消息、游标、账号或服务端业务规则。

- [生产协调器](../lib/features/collaboration/application/im_sync_coordinator.dart)：仅修改上述赋值并加两行说明；本文件还有既有改动，不等同整份 git diff 均为本轮新增。
- [新增三个本地 HTTP + SQLite 用例](../test/im_full_batch_catchup_test.dart)：500、510、1000 事件分页，核对每次 ACK 到达时消息和设备游标已落库、前次 ACK、唯一服务端/客户端 ID、连续消息序号、同账号消息不被过滤、未读保持、满页不抢先历史补拉，最终回到长轮询。
- [修改前](../test/evidence/im-batch-catchup-20260903/batch-test-before.log)：三项均失败，后续请求的 waitSeconds 为25而非0。
- [专项](../test/evidence/im-batch-catchup-20260903/targeted-passed.log)：26/26；[全量](../test/evidence/im-batch-catchup-20260903/full-test-final.log)：1007/1007；[静态分析](../test/evidence/im-batch-catchup-20260903/analyze-passed.log)：0问题。
- 新增“最终恢复长轮询”断言时，先错误地假定只能有一次空页探测；已有历史补偿任务完成会再产生一次合法立即探测。修正测试等待实际25秒长轮询，并限制请求总次数，没有删除最终恢复/防空转断言。此前两项失败保留于 [首次专项日志](../test/evidence/im-batch-catchup-20260903/targeted-final.log)。最初两处花括号风格问题也已修正。

正常入口 arm64+x64 [构建日志](../test/evidence/im-batch-catchup-20260903/normal-build-final.log) 成功；待回装 APK 为 `test/evidence/im-batch-catchup-20260903/normal-701.apk`，SHA256 `FD47597BF5849EF29B584E12BB793E77323F6996D537C7B1EE08DED8D42A6114`。ZIP 内两种架构都有 libapp/libflutter/sqlite 库，x64 libapp 摘要已不同于700。**尚未回装，不把构建成功当成最终运行通过。**

## 正在运行的真实任务

- M3：emulator-5556 / test03，接收端；M4：emulator-5558 / test04，发送端，Android16模拟器。
- M4真实消息页 → 发起会话 → 群聊 → 输入 `AI-UAT-20260903-IM-BATCH-701` → 仅选 Test Terminal03 → 创建一次。
- 新群 ID：`245e652d-14be-4c29-a7aa-57b7659fa4e6`，两名测试成员，原消息0。未向既有业务群发送批量内容。
- 证据：[创建前](../test/evidence/im-batch-catchup-20260903/m4-group-ready-701.png)、[创建成功](../test/evidence/im-batch-catchup-20260903/m4-group-created-701.png)、[M3基线](../test/evidence/im-batch-catchup-20260903/m3-before-batch.json)、[M4基线](../test/evidence/im-batch-catchup-20260903/m4-before-batch.json)、[原OA记录](../test/evidence/im-batch-catchup-20260903/m3-oa-before.json)。

[一次性原生发送脚本](../scripts/uat-im-batch-701.ps1) 已启动，计划510次发送点击，标记 `AI-UAT-701-BATCH-0001` 至 `0510`。每次点击前重新读取原生层级，验证确为该两人群、输入框完整文本恰等于唯一标记、发送按钮可用及实时位置。发送前后写 [防重运行日志](../test/evidence/im-batch-catchup-20260903/native-send-run.json)，已有日志则拒绝重跑；点击不等于服务端确认。

仅关闭 M3 的 Wi-Fi/移动数据，确认无活动默认网络。脚本 finally 恢复原值1/1；其他设备和电脑网络未动。运行中的 shell 会话为 **22983**，必须先观察原句柄/实际进程，不得因等待超时重发或另开同一任务。若原生层级失败，脚本会停止并恢复网络，保留输入框与日志以便核对。

中间证据：M4 [第59条已确认快照](../test/evidence/im-batch-catchup-20260903/m4-progress-60.json) 显示群 seq59/read59/unread0；M3 [离线快照](../test/evidence/im-batch-catchup-20260903/m3-observer-offline.json) 仍为 applied=acked=315、新群0消息、原2条媒体Outbox未删。原生 [离线工作台](../test/evidence/im-batch-catchup-20260903/m3-offline-home-701.png) 保留登录，展示缓存应用和连接不可用状态。

## 接收端观察入口与必须收尾的项目

M3断网期间替换为 [独立观察入口](../test_driver/im_batch_observer.dart)，不由正常main引入，只允许测试环境test03、拒绝release。它使用生产同步仓库和既有 `beforeEventAck` 接口，不暂停、不生成事件、不写游标；每个相关批次在事务完成、ACK之前读取真实本地消息，记录事件数、游标、唯一数量、测试序号及顺序。只保存有限数字/布尔元数据，不输出令牌、设备标识、正文或附件地址。

[观察安装记录](../test/evidence/im-batch-catchup-20260903/observer-install.json)：PID32276，APK SHA256 `56FEF7C1EE734DBFE170235B29B34E88250132E983F37B03FF6691E935A77CEA`。离线冷启动后仍为 [缓存工作台](../test/evidence/im-batch-catchup-20260903/m3-observer-offline-home-701.png)，游标315未推进。

下一步（仍未完成）：

1. 等原发送任务终止，核对每条服务端确认与客户端消息ID，不能只统计点击。
2. 自动恢复网络后，读取 M3 `cache/ai-uat-im-batch-*.jsonl` 中只含白名单的观察记录；必须实际出现500事件批次及紧随其后的补拉，才算真实满页证据。
3. 比对两账号、两设备各自账本、顺序、唯一性及未读，检查落库前后/ACK推进，保留原消息、2媒体待发、2OA草稿/10回执。
4. 原生打开接收群，核对首条未读、仅可见后阅读、历史上滑自动加载与回执，不将本地模型测试代替这些操作。
5. 给M3/M4回装后续 [702报告](702-im-visible-read-session-isolation-20260903.md) 中的 `normal-702.apk`（保留数据，含本轮补拉修复），验证已安装base.apk哈希、正常运行和无观察入口；M4当前仍在700正常包发送，不应中途安装。旧701包仅保留构建证据，不作为最终回装包。
6. 补最终截图、只读账本、验证结果，再更新本报告结论。

本轮真机 ADB已授权但仍锁屏，未操作/安装，已有解锁询问未重复发送。Windows安装客户端只读 [IM/OA健康检查](../test/evidence/im-batch-catchup-20260903/desktop-health.json) 均200，当前无可调用Windows控制工具；这不是桌面UI实测。高级OA、跨端完整矩阵、真实推送、媒体上传500、真机性能等原未完成项保持开放。目标继续进行。
