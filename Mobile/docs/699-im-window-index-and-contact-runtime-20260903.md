# 699 长历史消息窗口查询与联系人进入会话回归

日期：2026-09-03，Asia/Shanghai。结论：**最近消息查询的历史全量排序瓶颈已修复，完整性能及 IM/OA 验收仍未完成。**

## 问题与修改

原查询虽然只取最近 80 条，但排序为 `CASE WHEN sequence = 0 THEN 1 ELSE 0 END DESC, sequence DESC, created_at DESC`。原 `(account_id, conversation_id, sequence)` 索引不能完整提供此顺序：实际 M3/M4 升级前 SQLite 只读快照均出现 `USE TEMP B-TREE FOR ORDER BY`，独立夹具的完整查询（包括已读投影）也复现。

- [ImMessageQuery](../lib/features/collaboration/data/im_message_query.dart) 集中排序、已读投影与索引表达式，避免查询和索引不匹配。
- [ImLocalStore](../lib/features/collaboration/data/im_local_store.dart) 本地 schema 14→15，新建和升级均增加 `ix_im_messages_visible_window`，索引包含账号、会话、待发排序、sequence、created_at，仅索引 `is_deleted = 0`。
- 保留原 sequence 索引：向上翻页仍需读取删除墓碑判断连续区间，不改变该查询或跳过缓存缺口。
- 不改消息去重、收发、已读上报、账号隔离、远端 API、群聊/单聊逻辑；没有向线上插入压测历史。
- 依据 [SQLite 表达式索引文档](https://www.sqlite.org/expridx.html)，索引与查询表达式需匹配；[部分索引文档](https://www.sqlite.org/partialindex.html) 说明只索引满足条件的记录。实际是否使用索引以本轮 EXPLAIN 结果为准。

## 自动化回归

[新增 6 项索引测试](../test/im_message_window_index_test.dart) 覆盖新库双向顺序、旧计划对照、包含已读投影的 80 条结果一致性、待发/时间次序/限量/账号会话隔离、v14 升级所有表逐行不变、确认/删除/恢复更新、保留相邻历史索引与墓碑连续性。

先运行修复前测试：两个 schema/迁移用例失败，其余四项对照通过，见 [修正夹具后的红灯](../test/evidence/im-window-index-20260903/red-corrected-test.log)。首次夹具遗漏 `ImMessage.conversationId` 导致额外失败，已纠正，不记为产品缺陷。旧 v1 测试原本仅创建成员表，也已补上消息基础表以覆盖新索引迁移，未通过在生产迁移中忽略缺表来消除测试失败。

另有 [1 项压测夹具自测](../test/im_window_benchmark_fixture_test.dart)，验证使用生产查询、加密内容与旧索引对照。

- [专项](../test/evidence/im-window-index-20260903/targeted-final.log)：34/34。
- [全量](../test/evidence/im-window-index-20260903/full-test.log)：996/996。
- [静态分析](../test/evidence/im-window-index-20260903/analyze-final.log)：0 问题。

## Android 16 真运行的独立长历史夹具

[测试入口](../tool/im_window_benchmark_main.dart) 显式单独构建，不被正常 `lib/main.dart` 引用，release 禁止运行。M3 临时安装 Profile 测试包，使用 [夹具](../tool/im_window_benchmark_fixture.dart) 在新建临时目录内创建真实生产 schema，通过 Android sqflite 平台通道读写；AES-GCM 使用仅用于合成数据的临时固定测试密钥，不访问真实安全存储、业务数据库或网络。测试结束清理本次临时数据库目录。

SQLite 3.44.3；每档 1,000 / 10,000 / 50,000 条合成已确认消息，另加 3 条合成待发，每第 101 条为删除墓碑。只解密最近 80 条。每个指标预热 2 次，采样 9 次，记录中位数和全部原始样本。测完新索引再次删除索引测旧查询，以观察顺序/预热偏差。

共运行两轮。首轮与正常包构建有时间重叠，不能忽略主机负载影响；第二轮在该构建退出后重新启动独立进程运行。以下完整列出第二轮结果，单位 ms：

| 历史条数 | 旧 SQL | 新 SQL | 再测旧 SQL | 旧 readMessages 含解密 | 新 readMessages 含解密 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1,000 | 8.990 | 14.138 | 15.197 | 8.128 | 15.619 |
| 10,000 | 31.035 | 15.275 | 30.995 | 31.653 | 15.845 |
| 50,000 | 107.467 | 10.434 | 108.528 | 122.787 | 15.349 |

第一轮 50,000 条 SQL 为 109.741→3.735 ms，含解密为 111.461→15.360 ms。两轮均验证完整行和已读投影一致、返回 80 条、待发数量/内容解密正确；新计划不再有临时排序，已读状态仍走账号范围内的索引查询。

**小会话不能承诺提速**：1,000 条第二轮新查询比首次旧查询慢，接近再测旧查询；平台调度、模拟器噪声仍明显。长历史的全量排序成本明确消除，但不能把合成 SQL 耗时等同为点击、页面动画、图片解码或出光延迟。

代价：第二轮 50,000 条建索引约 85.173 ms；第一轮该档数据库页增长 4,018,176 字节（约 3.83 MiB）。页增长不是精确索引文件占用，不包含对线上写入吞吐的验收。本轮没有证明低端真机、超大历史、长期内存、写入吞吐或硬件加密能力。

证据：[首轮](../test/evidence/im-window-index-20260903/android-benchmark.json)、[第二轮](../test/evidence/im-window-index-20260903/android-benchmark-repeat.json)、[测试完成截图](../test/evidence/im-window-index-20260903/m3-benchmark-complete.png)。

## 正常应用安装、实际数据与 UI

最终两台均安装正常入口、无附加诊断开关的 Profile APK，93.2 MB，SHA256：`EA885F6C5881EE77B608B8A7C0EF3976D2B94CB3FD8871C50E7E72065DBBE5A2`。M3 为 test03，M4 为 test04，未清数据、未卸载正常应用、未改密码、未重新发送原失败媒体。测试入口不再运行。

- [M3 升级前](../test/evidence/im-window-index-20260903/m3-before-im.json) / [后](../test/evidence/im-window-index-20260903/m3-after-im.json)、[M4 前](../test/evidence/im-window-index-20260903/m4-before-im.json) / [后](../test/evidence/im-window-index-20260903/m4-after-im.json)：schema 14→15，quick_check 为 ok，排序走新索引；实际消息、会话、待发及其他非事件表行数不变。该快照 EXPLAIN 只验证排序，完整已读投影在上面的夹具测量。
- M3 保留 28 条本地消息及 2 条旧待发媒体，M3/M4 测试群仍 seq6、read6、unread0；M4 内账号03/04分区保留。
- OA 两台草稿、未读回执、本地待提交记录一致；M3仍2草稿、10个通知已读回执。
- 首次审计 27/28：M4 `im_event_inbox` 72→73。核对唯一新增事件为 `presence.changed`，seq309，事件 ID `5bbb3326-16fb-4dd8-a8fd-95d1fc2de6da`；应用保持在线同步，非丢失或重复消息。检查器改为逐个对账新增事件及游标不回退，不能要求运行中的事件总数冻结。保留 [首次结果](../test/evidence/im-window-index-20260903/verification-initial.json)，[最终审计](../test/evidence/im-window-index-20260903/verification.json) 31/31。
- [正常运行校验](../test/evidence/im-window-index-20260903/normal-runtime.json)：两台安装包 hash 一致，采样时 FATAL、Unhandled、RenderFlex overflow、测试入口日志均0；[完成在线/断网操作后的复核](../test/evidence/im-window-index-20260903/normal-runtime-final.json) 同样为0。
- UI截图已实际打开检查：[M3 首页](../test/evidence/im-window-index-20260903/m3-normal-home.png)、[通讯录默认收起](../test/evidence/im-window-index-20260903/m3-normal-contacts.png)、[单聊](../test/evidence/im-window-index-20260903/m3-normal-direct.png)、[M4 群聊](../test/evidence/im-window-index-20260903/m4-normal-group.png)。头像与连续消息分组保留，原待发图片仍显示等待确认；截图不构成媒体送达证明。

## 联系人进入会话与断网实测

正常包 M3 原有 Test Terminal 01 单聊：6条已确认文字+1条待发图片。每次用新 UI 层级定位头像，进入后检查聊天页，返回一次确认回通讯录。

| 阶段 | 完成次数 | 首次末条布局 | 后续末条布局范围 |
| --- | ---: | ---: | ---: |
| 修改前在线 | 5 | 159.887 ms | 51.666–74.511 ms |
| 修改后在线 | 5 | 77.809 ms | 33.585–69.301 ms |
| 修改后关闭 Wi-Fi/移动数据 | 3 | 30.799 ms | 61.553–63.950 ms |

这是点击处理函数到末条行进入视口布局的阶段计时，不是完整动画或触摸到出光。离线首条报告 cacheHit=false，后续为true；三个页面均真实显示原消息并可返回，最后恢复 Wi-Fi/移动数据，见 [网络恢复](../test/evidence/im-window-index-20260903/network-restore.json)。未在此轮离线发送新消息或伪造断网状态。

在线修改后多个样本 raster p95 仍约26.6–55.2 ms，高于60Hz单帧预算；因此**没有判定整体不卡顿**。前后进程、预热及模拟器调度不同，且只有7条消息，不能把小会话布局差值全部归因于新增索引。5轮后PSS也受前进程存活时间/换页影响，不作内存优化结论。

完整证据：[前5次](../test/evidence/im-window-index-20260903/before-index.json)、[前分段](../test/evidence/im-window-index-20260903/before-index-timing.json)、[后5次](../test/evidence/im-window-index-20260903/after-index.json)、[后分段](../test/evidence/im-window-index-20260903/after-index-timing.json)、[断网3次](../test/evidence/im-window-index-20260903/after-index-offline.json)、[断网分段](../test/evidence/im-window-index-20260903/after-index-offline-timing.json)。

## 未完成与下一步

1. 继续定位真实页面 raster 高耗时、图片解码、长列表滚动与生命周期后的缓存失效；补大群、长会话真实数据与真机测量，不能用本轮合成数据库代替。
2. 桌面仍以已安装1.0.87为准，[本轮只读检查](../test/evidence/im-window-index-20260903/desktop-final.json) 显示 test01 进程运行、IM/OA GET 200；没有新增 Windows UI 或完整同账号多端验收。M1真机/M2未改动。
3. 原媒体上传500等待后端证据；真实离线推送SDK与配置未就绪；iOS原生存储、D2替换/改密矩阵、批量500/更多崩溃窗口、完整高级OA流程/表单/通知验收继续保留，不缩小目标。

本轮仅本地索引优化与运行证据，没有提交/推送代码，没有修改正式业务配置。总目标保持进行中。
