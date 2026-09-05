# 683：联系人进入会话分段与断网重开实测

## 结论

**当前小会话的缓存重开与断网恢复通过；完整性能目标仍未通过。** 正常 Profile 包在独立 M3 完成联网 5 次、断网热重开 3 次及断网杀进程后首次进入 1 次，共 9 份实际分段数据。当前单聊为 6 条已确认文字和 1 条原待发图片，没有新造消息或用模拟数据替代。

从点击处理函数开始，到末条消息行完成视口内布局：首次联网进入 **195.642ms**，四次缓存重开 **49.133—79.459ms**；断网重开 **61.899—71.863ms**，断网杀进程后 **83.502ms**。这些是布局检查点，**不是完整过渡动画、图片解码或物理触控到屏幕出光的耗时**。

新增 8 项诊断测试；全量 **794/794**、分析 **0 问题**，正常 Profile 构建及安装核对通过。本轮没有凭最快样本宣称修复全部卡顿，也没有为取得好成绩清缓存、停同步、绕过登录或缩减业务页面。

## 范围及改动

- 时间：2026-09-03 03:26—03:35，Asia/Shanghai。承接 [682 启动分段](682-startup-phases-and-renderer-20260903.md) 的真实进展，继续定位点击会话而非重复测启动。
- M3 `emulator-5556`，Android 16、test03、RTX 4070 主机渲染；真实数据及原 AVD 保留。未操作 M1、M2、Windows 窗口；不以旧桌面源码代替当前桌面业务验证。
- [诊断模块](../lib/core/diagnostics/chat_open_diagnostics.dart)：仅 Profile 启用，单进程最多 25 次、同时最多一个观察窗口、每次 3 秒/最多 240 帧；关闭页面或被新测量取代时清理计时回调。只记录固定阶段、数量和数值，内部路由匹配键从不写日志，结束即释放。
- [联系人入口](../lib/features/contacts/presentation/contacts_page.dart)：在已有防重入锁之后记录点击、键盘收起及导航请求；保留原创建/已有会话分支和权限规则。
- [聊天页](../lib/features/messages/presentation/chat_page.dart)：记录挂载、首个框架帧、消息快照是否已在内存、首个消息数量和末条行布局；没有改变消息顺序、已读上报、分页或头像分组算法。
- [采集助手](../scripts/inspect-chat-open-timings.ps1)：只从当前 M3 进程日志白名单提取固定字段，原始 logcat 不落盘，不输出正文、会话 ID、凭据、附件地址或设备指纹。两次进程各自编号，不把重启后的 sampleId=1 误判重复事件。

## 实际分段

全部检查点从同一次点击处理函数开始计时，单位 ms；并非每列之间的独立耗时。完整微秒值和帧摘要见[对照 JSON](../test/evidence/chat-open-phases-20260903/comparison.json)。

| 场景 / 样本 | 内存消息命中 | 键盘收起 | 路由挂载 | 消息数据可用 | 末条行布局 |
| --- | --- | ---: | ---: | ---: | ---: |
| 联网首次 1 | 否 | 8.008 | 25.314 | 155.868 | 195.642 |
| 联网重开 2 | 是 | 13.901 | 29.494 | 29.643 | 79.459 |
| 联网重开 3 | 是 | 6.804 | 10.062 | 10.207 | 49.133 |
| 联网重开 4 | 是 | 5.495 | 22.484 | 22.621 | 59.486 |
| 联网重开 5 | 是 | 5.937 | 36.897 | 37.049 | 78.166 |
| 断网重开 6 | 是 | 13.334 | 31.081 | 31.241 | 61.899 |
| 断网重开 7 | 是 | 5.663 | 36.150 | 36.305 | 71.863 |
| 断网重开 8 | 是 | 10.632 | 16.877 | 17.009 | 62.006 |
| 断网杀进程后首次 1 | 否 | 14.694 | 30.202 | 65.094 | 83.502 |

证据：[联网及断网热开](../test/evidence/chat-open-phases-20260903/timings-online-and-offline.json)，PID 6253；[断网冷开](../test/evidence/chat-open-phases-20260903/timings-offline-cold.json)，PID 7828。9 次均有真实末条布局检查点，提取拒绝数 0，无缺失值补 0。

### 可以与不可以推断的内容

- 当前已缓存消息不需要每次打开都等待网络正文；重开时现有 Provider 快照立即可用。断网新进程仍能读取本地消息并显示头像、文字和待发图片，证实不只依赖进程内存。
- 路由 Widget 仍需挂载和布局；“数据命中缓存”不等于“整个界面完全不重建”，也不等于所有后台 HTTP 都停止。
- 键盘收起在这些样本中约 5.5—14.7ms，没有证据支持删掉收键盘交互来优化。首次消息快照可用较慢，但不能仅凭联网/离线两次差异就归因于网络，仍有本地 I/O、系统负载、渲染和缓存差异。
- 帧观察窗口接收引擎批次，可包括导航动画及其他活跃组件，**不是某一个气泡的独占绘制耗时**。联网首次 build p95 25.958ms；联网重开 raster p95 17.249—28.963ms，断网冷开 raster p95 36.144ms，仍有超过 60Hz 帧预算的阶段。
- 仅 7 条消息，没有验证 2000 人群、长历史、大通讯录、连续快速滑动或长时内存收敛，不能外推整体性能合格。

## 真实界面与恢复

1. 正常包恢复原 test03，[工作台](../test/evidence/chat-open-phases-20260903/01-profile-home.png)可见；通讯录[默认组织收起](../test/evidence/chat-open-phases-20260903/02-contacts-collapsed.png)，[点击组织才显示联系人](../test/evidence/chat-open-phases-20260903/03-contacts-expanded.png)。
2. 联网 5/5 次头像进入既有单聊、一键返回通讯录，见[循环记录](../test/evidence/chat-open-phases-20260903/measured-reopen.json)；每次均有独立、实时 UI hierarchy，不仅发送坐标。
3. 只关闭 M3 的 Wi-Fi/移动数据；通讯录显示[状态未知](../test/evidence/chat-open-phases-20260903/04-offline-contacts.png)，没有把本机断网映射成所有人离线。断网热开 3/3 次单次返回成功，见[断网循环](../test/evidence/chat-open-phases-20260903/offline-measured-reopen.json)。
4. 断网正常 force-stop/start 后仍是原账号，[首页标识缓存数据](../test/evidence/chat-open-phases-20260903/05-offline-cold-home.png)，未跳登录；[单聊](../test/evidence/chat-open-phases-20260903/08-offline-cold-chat.png)恢复头像、六条文字、原待发图片。对端头部只显示“最后在线”，待发图片为等待时钟，不伪造送达/已读。
5. 恢复原 Wi-Fi=1、移动数据=1，见[网络恢复记录](../test/evidence/chat-open-phases-20260903/network-restored.json)；无需手动刷新，头部重新取得[“离线 · 最后在线时间”](../test/evidence/chat-open-phases-20260903/09-reconnected-chat.png)。没有强行显示在线绿点。

## 数据、安全与回归

- 正常 `lib/main.dart` Profile APK SHA-256：`33F58C91A7B2970D67B4DCC7A936B3DE04529E7D13E324566E691958708DB1A0`，设备与本地一致，见[安装核对](../test/evidence/chat-open-phases-20260903/installed-final.json)。
- [最终只读保护核对](../test/evidence/chat-open-phases-20260903/preservation-final.json)：消息台账、群消息、原图片/视频两条 Outbox 标识、草稿和回执均未改变；IM applied/acked 236，OA 游标 449。原 2 草稿、9 回执保留，没有删除重建测试数据。
- 图片/视频最后失败摘要仍 HTTP 500，未宣称跨端发送成功。没有新建业务数据或直接写数据库。
- [诊断测试](../test/chat_open_diagnostics_test.dart) 8 项：禁用模式、缺失阶段、首次值防覆盖、非法/回退时间、热缓存快照、空会话、非法数量与快照时间。固定阶段与空值语义保留，避免制造“零毫秒完成”。
- [全量 794/794](../test/evidence/chat-open-phases-20260903/full-final.log)、[分析 0 问题](../test/evidence/chat-open-phases-20260903/analyze-verified.log)、[正常构建成功](../test/evidence/chat-open-phases-20260903/build-final.log)；前序联系人防重入、单群边界、可见已读、历史加载和热重开测试继续通过。

## 后续与验收边界

需要进一步取得大群/长历史与真机的同类分段证据，处理真实耗时峰值，再做长时性能回归；当前不更改未经证实有问题的收键盘、缓存和同步规则。Windows 当前窗口真实交互、高级 OA 接收人处理、完整多端/推送矩阵和媒体 500 等既有阻塞仍未完成。目标保持活动。
