# 709：连续输入草稿保护与断网发送验收

日期：2026-09-03，Asia/Shanghai。结论：本轮修复与双模拟器专项通过；整体 IM/OA 对齐目标仍未完成。

## 问题与修复

708 原生批量发送中观察到：上一条发送后马上输入下一条，后续草稿被清空。本轮确认 `_send()` 在等待 `ImRepository.send()` 后无条件清空控制器及引用、提及上下文。这里等待的是本地 SQLite 入库，不是等待服务端确认；网络再快也不能消除本地异步竞态。

- 点击发送时同步截取当前文本、引用、提及成员与稳定 `clientMessageId`，立即腾空输入框。
- 后续入库回调不再清空或重置下一条草稿。输入保持可用，重复发送按钮回调仍单次处理。
- 本地事务失败时显示紧凑的“未发送”行，可重试原消息；不会把原消息覆盖到新草稿，也不会谎称“已保存”。重试复用原 `clientMessageId` 与引用/提及快照。
- 未入库消息按当前账号及会话保存在进程内状态中，离开会话后返回仍可重试；换账号或退出后清理，并忽略旧操作的迟到结果。
- 仓库入队增加调用账号校验，并用既有会话锁保护短本地事务；不在锁内进行网络请求。
- 普通断网仍走原有持久化 Outbox，不使用“未入库”失败行。服务端确认前显示等待图标，恢复网络后自动补偿。

主要代码：[聊天页](../lib/features/messages/presentation/chat_page.dart)、[未入库草稿状态](../lib/features/messages/presentation/chat_composer_drafts.dart)、[仓库](../lib/features/collaboration/data/collaboration_repositories.dart)。没有修改后台代码、接口协议、既有业务数据或桌面源码。

边界：SQLite 写入失败的恢复项属于内存兜底，**不保证杀进程后恢复**；已成功入库的离线消息才具备现有 SQLite 持久性。没有为模拟磁盘损坏而删除数据库或破坏加密密钥。

## 本地回归

新增 16 项测试：10 项 widget、6 项状态/真实 SQLite 仓库测试。专项 101/101，全量 1179/1179，静态分析 0。

覆盖即时清空、旧内容相同的新输入、主动清空、中文与 emoji、重复按钮回调、下一条草稿、独立 @成员、引用不串消息、入库失败与重试、离开会话后失败恢复、账号切换迟到成功/失败、恢复项去重与会话隔离、账号退出/切回、状态销毁、错误账号禁止入队、事务回滚及稳定客户端 ID。

- [专项最终日志](../test/evidence/im-composer-20260903/focused-3.log)
- [全量日志](../test/evidence/im-composer-20260903/full.log)
- [静态分析](../test/evidence/im-composer-20260903/analyze-clean.log)
- [修复前失败记录](../test/evidence/im-composer-20260903/red-4.log)
- [测试夹具](../test/support/chat_composer_fixture.dart)：真实仓库和 SQLite，控制加密写入边界，不运行网络同步。

红测构建过程也保留：最初测试异步区与 SQLite 调度配合不当曾超时，已终止相应测试进程并修正为驱动 widget 帧与真实 I/O；`RawTooltip` 定位、弹层动画等待、模拟安全存储泄漏影响热缓存用例等夹具问题已修正，没有降低产品断言。早期红测同时暴露默认同步协调器在 Provider 销毁时调用已销毁状态的异常；本轮最终夹具使用未启动的协调器，生命周期问题单独列入待查，不能当作已修复。

## 正常构建与安装

目标 `lib/main.dart`，profile，android-arm64 + android-x64；非 demo、非注入延迟的临时测试入口。

[最终构建](../test/evidence/im-composer-20260903/build-final.log)、[安装记录](../test/evidence/im-composer-20260903/install.json)、[正常 APK](../test/evidence/im-composer-20260903/normal-709.apk)。

SHA256：`2D32FC79E7635723DB2E4236C59648207C31EAD0E0C8C36E6066EB946731110E`。

M3 `emulator-5556` / test03 / PID19790；M4 `emulator-5558` / test04 / PID15775。两端保留数据安装，实际运行 APK 哈希与产物一致。既有 secure_tunnel Kotlin 插件未来迁移提示仍在，不影响本轮构建。

## 原生真实操作

使用已有两人测试群 `AI-UAT-20260903-IM-BATCH-701`，会话 `245e652d-14be-4c29-a7aa-57b7659fa4e6`。开始时两端各610条、未读0。M4发送，M3接收。仅新增4条测试消息，前缀 `AI-UAT-20260903-102141-COMPOSER-`。

| 场景 | 原生操作与证据 | 结果 |
| --- | --- | --- |
| 在线连续输入 | 同一次设备 shell 中点击发送01，紧接输入02，中间不抓层级或人为等待输入框清空 | 02完整留在编辑框，随后发送；两端到612 |
| 断网连续输入 | 关闭M4 Wi-Fi与移动数据，发送03后紧接输入04 | 04完整保留，发送后两条均显示等待图标 |
| 离线持久化 | 只读检查M4 SQLite | 614条消息，其中2条 sequence=0/pending，Outbox=2 |
| 网络恢复 | 恢复原来开启的两个网络开关，不手动重发 | 两条自动确认，使用原clientMessageId，Outbox=0 |
| 双端一致与已读 | 对比双方账本、UI与M4对方已读游标 | 614条唯一ID、顺序1–614一致，双方未读0，回执614 |

在线01发送/02输入发生于10:21:47–10:21:49；离线03发送/04输入发生于10:22:36–10:22:38，10:22:50恢复网络。设备截图采用UTC时区，02:21/02:22对应本机10:21/10:22，不是时间倒退。

- [在线下一条草稿](../test/evidence/im-composer-20260903/m4-online-next-draft.png)
- [离线下一条草稿](../test/evidence/im-composer-20260903/m4-offline-next-draft.png)
- [离线等待状态](../test/evidence/im-composer-20260903/m4-offline-sent.png)
- [接收端最终画面](../test/evidence/im-composer-20260903/m3-final-received.png)
- [发送端最终双勾](../test/evidence/im-composer-20260903/m4-final-receipts.png)
- [在线操作日志](../test/evidence/im-composer-20260903/native-online.json)、[离线操作日志](../test/evidence/im-composer-20260903/native-offline.json)
- [离线队列](../test/evidence/im-composer-20260903/m4-offline-queued.json)、[M3最终账本](../test/evidence/im-composer-20260903/m3-after.json)、[M4最终账本](../test/evidence/im-composer-20260903/m4-after.json)

上述截图均实际打开核对。在线显示真实在线人数，断网期间隐藏在线人数；没有把离线缓存冒充在线状态。连续头像合并在本轮消息组首条保留。

原生脚本先因会话列表的“群聊”语义前缀、空搜索框导航保护停止，均发生在发送日志建立及任何消息点击之前；按新抓取的层级修正后才执行。发送日志已有阶段不自动重放。真实设备操作证明当前正常包的连续输入链路正常；精确卡住本地事务的竞态由可控 SQLite/widget 测试证明，不把 ADB 指令耗时当作毫秒级性能指标。

## 数据保留与运行检查

[证据核对12/12](../test/evidence/im-composer-20260903/verification.json)，[只读核对脚本](../scripts/verify-im-composer-709.mjs)。两端原610条消息逐行保留，新4条服务端ID及客户端ID一致；离线临时消息使用原客户端ID确认，没有新增重复记录。

M3原2条媒体Outbox身份保留，未手动重试；M4最终Outbox仍为0。M3原2份OA草稿、10条通知已读记录及OA Outbox保持一致。没有清除应用数据，没有直接改库。

[运行采样](../test/evidence/im-composer-20260903/runtime.json)中两端PID和APK哈希匹配安装记录，未发现当前进程FATAL、未处理异常或RenderFlex溢出；Wi-Fi和移动数据均恢复为1。此结果是本次采样，不证明长期无崩溃、内存/帧率已经达标。

## 尚未完成

1. 同步协调器销毁时的异步状态写入：早期测试记录出现 `UnmountedRefException`。需要单独可复现生命周期测试，明确退出/换账号/容器销毁路径，不能从本次正常运行采样宣称该边界安全。
2. 真机仍锁屏：[当前状态](../test/evidence/im-composer-20260903/physical-device-state.json)。未绕过锁屏、未安装或操作真机；其他模拟器未动。
3. 本轮没有操作最新Windows窗口，也没有重做完整桌面/双移动端替换、改密码会话矩阵；不以旧桌面源码代替当前窗口。
4. 长时间大群性能、增量列表优化、真实推送、iOS安全存储、已有媒体上传500，以及高级OA金额分支、会签/或签、多人办理/付款、公式附件和全状态通知仍开放。

上一轮708的未读定位与真实账本证据已存在且本轮原610条得到保留核对；本轮继续带来源码、回归及4条真实消息证据，是实际进展。不能据本专项通过将整体目标标为完成。
