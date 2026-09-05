# 673 聊天页面可见性、已读与轮询

日期：2026-09-03，Asia/Shanghai。上一目标轮 672 有具体修复与实测进展，本轮补齐其最终恢复/数据核对记录，并继续 IM 交互与性能。整体目标仍未完成。

## 结论与缺陷证据

聊天页只在销毁时取消两只 Timer；路由被覆盖、Offstage 或应用后台时仍每 25 秒更新 active conversation、每 12 秒校对消息。已读检查仅看 RenderBox 是否在消息容器内，没有确认页面对用户可见。

- [修改前四项回归](../test/evidence/chat-visibility-20260903/before.log)：三个隐藏场景 60 秒后 active 更新次数从 1 增至 3；慢请求 75 秒内发起 4 次，未合并请求。该初次日志另有测试生命周期跳跃的断言；之后按 resumed→inactive→hidden→paused 和逆序修正 fixture，不把测试夹具问题作为应用缺陷。
- [单独撤去已读保护的对照](../test/evidence/chat-visibility-20260903/read-guard-before.log)：实际 ChatPage 被底部抽屉覆盖后，注入第二条消息，原有几何检查提交 `[1, 2]`，应仍为 `[1]`。仅撤去两处可见性保护复现，之后已恢复；没有绕过生产渲染逻辑测试纯布尔函数。

## 修改

- 复用 672 的 `VisibleRefreshScheduler`；保持可见时 25/12 秒的既有频率。当前路由、TickerMode 与前台状态共同决定是否轮询，返回/前台恢复触发更新；消息缓存和历史滚动位置不因隐藏而清空。
- active 请求及后续 presence 查询纳入同一串行刷新；前一轮未返回不重复发起，隐藏后返回的 active 请求不再额外触发 presence GET。
- 已读同时在安排帧回调、执行帧回调时检查路由/前台状态，并重新检查聊天资源 Tab 与搜索状态。页面布局仍挂载不再被视作实际阅读。恢复可见后重新计算真正进入消息视口的序号。
- 保持全局 IM 事件同步独立运行；没有关闭全账号同步、Outbox 或通知。已发出的请求不伪装为取消；服务器 active 状态的释放/到期规则未在本轮更改。
- 新增三个轻量动作 provider，正常环境仍直接调用原仓库方法；测试可核对真实页面触发的已读、进入和退出命令，不需要伪造数据库或线上消息。

## 验证

- 新增 5 项：完整路由覆盖、底部抽屉覆盖、后台、Offstage、慢请求合并。[聚焦通过](../test/evidence/chat-visibility-20260903/focused-final.log)。四种隐藏场景均验证：不提交第二条已读、不继续页面轮询，恢复后提交序号 2 并恢复一次刷新。
- [全量 649/649](../test/evidence/chat-visibility-20260903/full.log)、[静态检查 0](../test/evidence/chat-visibility-20260903/analyze.log)，未更新 Golden。构建现有 Kotlin 插件迁移警告仍存在，不是本轮新增失败。
- 正常 `lib/main.dart` Profile arm64+x64 构建 53.5 秒；仅安装独立 M3/test03。设备 APK 与本地哈希一致：`AF2ED5F07D8F6D020F65E76AB78CC926D4271CE73CA4A39F606381CA96B3C7C4`。[安装记录](../test/evidence/chat-visibility-20260903/installed.json)。未启用诊断入口、未替换启动图标。
- 真实 M3 打开现有 11 条消息的群聊，头像首条合并、最新消息和输入栏保留；打开附件底部抽屉后返回聊天，再打开群详情。[聊天](../test/evidence/chat-visibility-20260903/03-chat.png) / [抽屉](../test/evidence/chat-visibility-20260903/04-overlay.png) / [返回](../test/evidence/chat-visibility-20260903/05-overlay-return.png) / [群详情](../test/evidence/chat-visibility-20260903/06-detail.png)。安装后的首次截图仍在初始化，不能用该截图证明首页就绪；后续真实消息/群详情截图确认应用可交互。
- 通过 Android Home 进入后台，确认前台 Activity 为系统桌面；43.6 秒后以原任务返回而非重启应用，群详情保留，再返回聊天，最新消息及滚动位置仍保持。[前台恢复详情](../test/evidence/chat-visibility-20260903/07-foreground-detail.png) / [最终聊天](../test/evidence/chat-visibility-20260903/08-final-chat.png)。
- [最终数据与运行核对](../test/evidence/chat-visibility-20260903/final-verification.json)：对照 672 结束时记录，三条会话元数据、目标群 11 条消息账本、IM 游标及 Outbox、OA 两条草稿、已读回执、游标及 Outbox 均未改变。00:46 M3 进程仍运行，网络 WiFi/移动数据为 1/1；当前进程 58 行日志样本内无 FATAL EXCEPTION 或 E/flutter。不据此宣称长时间稳定性或真实多端已读矩阵通过。

## 验收边界与后续

本轮未向线上发送新消息、创建审批，也未操作 M1 真机/M2 或 Windows 窗口。隐藏期间新消息到达的已读回归目前是实际 Flutter 组件注入消息及命令记录，**不是两台真实终端的实时未读验收**；正常包截图也不能证明网络请求次数。

跨来源在线状态仍需统一：先前通讯录旧在线快照与较新的群成员离线快照采样时间不同；不能固定优先通讯录或成员来替代有时效的统一来源。还需完成自然会话续期、可操作真机和桌面、多端替换、群读/事件与媒体服务端问题、高级 OA 分支/会签/或签、通知推送及大规模性能。保留完整目标，不以本轮局部回归代替总体验收。
