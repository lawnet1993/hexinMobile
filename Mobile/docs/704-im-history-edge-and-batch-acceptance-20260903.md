# 704：顶部连续上滑修复与 510 条原生离线积压收尾

日期：2026-09-03，Asia/Shanghai。结论：本次“两台 Android 模拟器、独立测试群、510 条文本离线补拉、可见已读、历史上滑与冷启动保留”专项通过；完整 IM/OA 目标仍为部分通过。

## 真实发现与修复

702 正常包中，M3 连续上滑停在第191条。重复16次同向手势仍为191–208，见 [原始滚动记录](../test/evidence/im-batch-catchup-20260903/history-scroll.json) 与 [旧界面](../test/evidence/im-batch-catchup-20260903/m3-history-07.png)。SQLite 内实际有510条。最初猜测320条窗口上限，源码核查否定了该猜测；反向离开顶部再滑回后可继续到121，见 [反向后截图](../test/evidence/im-batch-catchup-20260903/m3-history-after-reverse-704.png)。

根因：原分页只监听 ScrollController 的像素变化。Android 顶部钳制状态下继续拖动不再改变像素；加载期间到达顶部或失败后停在顶部，后续同向手势无法再次触发。

[ChatPage](../lib/features/messages/presentation/chat_page.dart) 增加真实手势的负向 OverscrollNotification 监听，复用现有分页互斥、历史耗尽、资源标签和搜索过滤。只接受 depth=0、dragDetails 非空的拖动；布局变化与程序定位不触发额外加载。不提高任意条数上限，不更改数据库、业务消息、已读协议或服务端。

新增两个 Widget 用例：顶部加载等待期间不重复请求、失败后原地同向重试、耗尽后不再请求；510条依次用游标431/351/271/191/111/31加载到1。旧实现 [红测](../test/evidence/im-batch-catchup-20260903/history-edge-red-confirmed-704.log) 预期2次、实际1次。首次测试尚未处理加载指示器的26px布局偏移，修正测试等待位置后才得到上述有效红测，原日志也保留。

- [专项101/101](../test/evidence/im-batch-catchup-20260903/history-regression-704.log)。
- [全量1025/1025](../test/evidence/im-batch-catchup-20260903/full-test-704.log)。
- [静态分析0问题](../test/evidence/im-batch-catchup-20260903/analyze-704.log)。
- [正常main入口 profile arm64+x64构建](../test/evidence/im-batch-catchup-20260903/normal-704-build.log)。secure_tunnel 仍有未来Flutter版本的Kotlin迁移警告，不是本次构建失败。

## 原生历史验收

接收M3：emulator-5556 / test03；发送M4：emulator-5558 / test04。正常704包保留数据安装后，两端实际base.apk SHA256均为 `E874F608E5BFABCB34F8C0F2B5BB5AFD7CB428F4AE0CBBEDCD71D7C306F4153D`；[最终运行核对](../test/evidence/im-batch-catchup-20260903/normal-runtime-final.json)。首次安装记录查询PID太早且夹有安装器stdout，不以其空PID判定启动成功；随后明确核对运行进程、已登录UI和最终哈希。

[原生上滑脚本](../scripts/uat-im-history-704.ps1) 只操作既有测试群，不发送消息。暂时关闭M3网络，验证无活动默认网络，finally恢复原Wi-Fi/数据1/1。M4及电脑网络不变。

| 累计同向手势 | 截图中最早消息 |
| --- | --- |
| 0 | 492 |
| 4 | 405 |
| 8 | 321 |
| 12 | 226 |
| 16 | 146 |
| 20 | 23 |
| 24 | 1 |
| 48 | 1，仍稳定 |

[第1条真实截图](../test/evidence/im-batch-catchup-20260903/m3-history-704-06.png)：头像与姓名位于合并组第一条，时间在气泡内。离线时群头不伪造在线人数。模拟器时区GMT，因此消息日期/时间与主机Asia/Shanghai不同，未修改设备时间。

证据脚本最初用行首正则漏掉Flutter把日期/姓名与首条消息合并后的多行语义标签，误报最早为2并退出1。保留 [原始运行记录](../test/evidence/im-batch-catchup-20260903/history-native-704.json)，修正解析为多行行首匹配；对同批原生XML重新只读解析得到 [复核记录](../test/evidence/im-batch-catchup-20260903/history-native-704-reviewed.json)，且人工查看第1条截图。没有伪造原脚本退出码，也没有重新发送数据。

返回列表再打开，[热重开截图](../test/evidence/im-batch-catchup-20260903/m3-normal-704-hot-reopen.png) 显示最新510，未回到旧窗口顶部。此次入口没有生成有效的联系人打开耗时样本，因此不声称热重开耗时或帧率达标。

两端 [强制停止后冷启动](../test/evidence/im-batch-catchup-20260903/cold-restart-704.json) 均为新PID且保持登录。最终SQLite仍各510条、read510/unread0；最终运行日志白名单检查未见FATAL、未处理异常、RenderFlex溢出或观察入口标记。仅证明所采集日志，不等价长期无崩溃。

冷启动后再次真实从工作台→消息→测试群，[M3最新510可见](../test/evidence/im-batch-catchup-20260903/m3-cold-704-latest.png)、[M4最新510与双勾](../test/evidence/im-batch-catchup-20260903/m4-cold-704-latest.png)，并非只查SQLite而没有打开页面。

## 701真实离线510条任务：已完成，不可重跑发送

原发送会话22983已结束exit0；[一次性发送日志](../test/evidence/im-batch-catchup-20260903/native-send-run.json) 为510个不同标记各点击一次，最后network-restored。实际两端消息账本确认服务端已接受，不能单靠点击数判断。

测试群：`AI-UAT-20260903-IM-BATCH-701`，ID `245e652d-14be-4c29-a7aa-57b7659fa4e6`，仅两名测试成员。消息使用 `AI-UAT-701-BATCH-0001`–`0510`：这是早前脚本未包含日期的命名偏差，群名含日期；保留原数据/证据，不为了命名重写历史，后续新数据应使用完整日期前缀。

[事务提交后、ACK之前的原生观察](../test/evidence/im-batch-catchup-20260903/batch-observations.json)：

| 事件批次 | 持久消息/唯一服务端ID/唯一客户端ID | applied | 前次acked | 本地未读 |
| --- | --- | --- | --- | --- |
| 500 | 500/500/500 | 1815 | 315 | 510 |
| 10 | 510/510/510 | 1845 | 1815 | 510 |

序号1–510连续；事件序号是全局事件序列，可存在合法间隔，不等同消息序号。两观察点相差1334ms，包括诊断读取、网络、ACK等，不能作为纯生产同步耗时。

- [M3恢复但未进群](../test/evidence/im-batch-catchup-20260903/m3-recovered-unread.json)：read0/unread510，applied=acked1845。
- [正常702包列表未读截图](../test/evidence/im-batch-catchup-20260903/m3-normal-message-list-unread.png) 与 [进群后最新消息可见](../test/evidence/im-batch-catchup-20260903/m3-normal-group-visible.png)，[可见后SQLite read510/unread0](../test/evidence/im-batch-catchup-20260903/m3-after-visible-read.json)。证明最新510进入可见区域后上报，不声称逐条阅读或首条未读定位已经验证。
- [M4进入群前已收到对方已读](../test/evidence/im-batch-catchup-20260903/m4-peer-read-before-open.json)，[704正常包双勾截图](../test/evidence/im-batch-catchup-20260903/m4-normal-704-receipt.png)。非仅修改UI数字。
- [最终M3账本](../test/evidence/im-batch-catchup-20260903/m3-final.json)、[最终M4账本](../test/evidence/im-batch-catchup-20260903/m4-final.json)、[M3原OA记录](../test/evidence/im-batch-catchup-20260903/m3-oa-final.json)：双方510条身份/顺序完全一致，旧会话保留，M3原2条媒体待发、2份OA草稿、10条通知回执保留，未重新手动上传。
- [只读证据核对器](../scripts/verify-im-batch-701.mjs) 实际执行 [15/15](../test/evidence/im-batch-catchup-20260903/verification.json)。其检查范围不包含首条未读定位、性能、推送、WindowsUI或高级OA。

正常702包已在08:27–08:28回装并完成可见已读，再由704包替换；观察入口不再运行。704未做真实切账号競争测试，702的16项隔离测试仍是本地HTTP+SQLite证据。

## 仍需继续

未在本轮操作真机、Windows窗口；不能用两模拟器替代完整桌面/移动/多设备矩阵。首条未读跳转、持续帧率/长期内存、真实推送SDK及到达、媒体上传500、高级OA分支/会签/或签/办理付款/公式附件及完整通知状态仍需独立验收。没有修改密码、删除原账号/业务数据或调整后台流程。本轮没有新建测试业务数据。完整目标继续保持活动。
