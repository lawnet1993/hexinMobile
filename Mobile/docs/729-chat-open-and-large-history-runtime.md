# 729 联系人进入会话耗时与大群历史实测

时间：2026-09-05 01:36–01:42（Asia/Shanghai）。本轮为真实运行取证，整体 IM/OA 对齐仍未完成。

## 真机进入会话

realme RMX3366，当前正常应用 Profile 进程 28654，test01；没有重装、重登、清数据或重启进程。从首页进入通讯录，初始组织均收起；展开公司总部及其他联系人后，实际点击 Test Terminal 03 头像进入已有单聊。返回通讯录再点击同一头像 5 次，每次验证实际会话标题。

使用应用已有 `MOBILE_CHAT_OPEN` 数值诊断，记录点击、键盘收起、导航、消息数据与最新消息可见布局阶段。每次留足 3.3 秒后才抓取 UI 树，避免 UI 抓取干扰 3 秒测量窗口。不是以 ADB 命令耗时或截图出现时间代替 Flutter 耗时。

| 第几次 | 内存窗口命中 | 消息数 | 最新消息可见布局 ms | build P95 ms | raster P95 ms |
| --- | --- | --- | --- | --- | --- |
| 1 | 否 | 15 | 121.836 | 11.866 | 11.936 |
| 2 | 是 | 15 | 78.598 | 12.026 | 7.643 |
| 3 | 是 | 15 | 97.136 | 13.967 | 6.500 |
| 4 | 是 | 15 | 65.187 | 8.349 | 7.153 |
| 5 | 是 | 15 | 74.420 | 9.581 | 6.968 |
| 6 | 是 | 15 | 78.090 | 8.673 | 7.597 |

热重开中位数 78.090ms；首次数据可用 55.341ms，首次路由帧 25.462ms。首个样本仅指本轮首次打开、内存窗口未命中，不是应用冷启动或全新账号。

6 个窗口共 277 个帧样本，刷新率约 60Hz，预算 16.667ms。build 超预算 2 帧，最大 18.722ms；raster 超预算 1 帧，最大 21.285ms。没有证据称“零掉帧”，更不能外推所有机型或长时压力结果。最新消息可见布局也不等同所有远程媒体下载完成。

- [采集前：0 个样本](../test/evidence/chat-performance-729/phone-before.json)
- [首次进入完整数值](../test/evidence/chat-performance-729/phone-first.json)
- [六次完整数值](../test/evidence/chat-performance-729/phone-six-opens.json)
- [真机会话截图](../test/evidence/chat-performance-729/phone-chat.png)：真实头像、图片、合并消息及时间/回执已显示。

本轮将 `scripts/inspect-chat-open-timings.ps1` 从固定 M3 改为可选 `-Serial` 参数，默认仍为 M3。保持 PID 限定、数值字段白名单、禁止输出原始日志与拒绝覆盖证据文件。真机三次采集 rejected=0。

## 模拟器大群历史

M3 emulator-5556，test03，进程 16494，仍使用既有 727 包；本轮没有更新安装包。进入既有 `AI-UAT-20260903-IM-BATCH-701` 群。

1. [最新位置](../test/evidence/chat-performance-729/group-latest.png)可见 UNREAD-0095 至 COMPOSER-04。
2. 连续 14 次向下拖动消息列表（浏览更早消息），到达 BATCH-0357～0377，[中段截图](../test/evidence/chat-performance-729/group-older.png)。
3. 再 28 次拖动到达 BATCH-0001，[最早位置](../test/evidence/chat-performance-729/group-earliest.png)。首条显示真实发件人头像/姓名，连续消息不重复头像。
4. 返回列表后重新打开同一群，[重新打开](../test/evidence/chat-performance-729/group-reopen.png)回到最新 COMPOSER-04；无“加载更早消息”按钮，没有停在空白页。
5. 只读 SQLite 元数据核对：群 ID `245e652d-14be-4c29-a7aa-57b7659fa4e6`，本地消息 614，末序号 614，已读序号 614，未读 0；数据库 integrity=ok，Outbox=0。窗口查询使用 `ix_im_messages_visible_window` 索引。

这些数据本来已在本地；本轮证明缓存历史滑动和分页交互，不证明新的远程历史分页请求或离线补偿。没有逐条截取 614 条，也不以首尾截图宣称所有中间消息逐条验收。群列表入口尚未连接联系人专用计时器，本轮不报告大群 FPS 或布局延迟。

## 验证与边界

- `flutter test test/chat_open_diagnostics_test.dart test/mobile_startup_diagnostics_test.dart test/contact_navigation_guard_test.dart test/im_cached_history_test.dart`：32/32 通过。
- 两端当前进程可用日志中 FATAL EXCEPTION、Unhandled Exception、RenderFlex overflowed 各 0；这不是无限时段无崩溃保证。
- 测后两端均返回工作台并核对选中态。未输入或发送新消息、未提交审批、未改群配置、未切换账号、未动手机热点。正常打开会话仍可能执行应用的可见已读/心跳请求。
- 应用 Dart 代码本轮没有修改，不另行构建或安装；本轮修改仅为诊断脚本与报告。不能宣称本轮“优化提速”，目前是确认已有缓存复用在该场景生效。
- 待完成：大群持续滚动的帧时序与内存曲线、新会话网络创建路径、低端机/弱网、多端新版 Push Gateway、桌面入站缺消息问题及完整高级 OA。整体目标继续保持未完成。
