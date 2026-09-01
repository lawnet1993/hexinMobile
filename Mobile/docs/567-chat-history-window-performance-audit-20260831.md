# 567 IM 历史窗口与会话重开性能验收

## 结论

本轮通过代码、自动化和现有真实数据范围内的真机验收。移动端仍通过向上滑动自动加载更早消息，不提供额外“加载更早消息”按钮；已加载历史窗口和耗尽状态在快速退出、重进后复用，不再每次重置为 80 条并重复读取同一历史页。快速重开产生的最新消息核对也会合并，但不会削弱双端同步补偿。

## 修复内容

- 为最近 32 个会话保存消息窗口大小与 `hasOlder` 状态，使用有界 LRU，避免应用会话内无限增长。
- 上滑成功后同时记住扩展后的窗口；不足一页时记住历史已到底。
- 重开会话恢复已加载窗口；已到底的会话再次滑到顶部不会重复请求同一历史页。
- 同一会话 10 秒内的最新消息核对合并为一次；并发进入复用同一个 Future。
- 原有 12 秒最新消息补偿同步、IM 事件同步和 25 秒在线状态刷新保持不变。
- 消息列表继续使用惰性 `ListView.builder`、稳定消息 Key、`findChildIndexCallback` 和历史滚动锚点，不一次构建全部历史气泡。

## 自动化证据

- 顶部上滑自动调用更早消息接口，页面不存在加载按钮。
- 分页请求使用当前最小 `sequence` 作为 `beforeSequence`。
- 历史请求失败后下一次上滑可重试。
- 历史已到底后，重开恢复扩展窗口且不再次调用分页加载器。
- 最新消息核对的并发调用合并，10 秒内重开被节流，超过窗口后恢复同步。
- 32 个会话上限达到后淘汰最久未使用窗口。

## 真机证据

- 设备：realme RMX3366，Android 14，1080×2400。
- 应用：`com.hexing.zhilian.hexing_terminal_mobile`，v1.0.1 (2)。
- Profile APK SHA-256：`C3D45F1B50967F38D94B2798508E62DE939869151558DB590003DB461B8C1D01`。
- 真实群聊：`Mobile-Group-20260825`，服务端显示 2 位成员、1 人在线。
- 连续退出并重开群聊 10 次后，文本、图片、音频和视频消息仍正常；视频继续显示真实缩略图和 0:01 播放层，不重复显示文件名。
- 页面和 UI 树均不存在“加载更早消息”按钮。
- 首次打开后 PSS 256211 KB；连续重开后的即时 PSS 287051 KB；空闲 5 秒后回落到 242378 KB。
- 三次采样均保持 `Activities=1`、`Views=7`，本轮未观察到路由或原生 View 数量累积。该采样只证明当前 10 次重开窗口，不替代长时间压力测试。
- 真机页面：[11-final-build-after-10.png](device-acceptance/chat-window-reopen-20260831/11-final-build-after-10.png)
- 真机 UI 树：[11-final-build-after-10.xml](device-acceptance/chat-window-reopen-20260831/11-final-build-after-10.xml)
- 内存基线：[10-final-build-meminfo-baseline.txt](device-acceptance/chat-window-reopen-20260831/10-final-build-meminfo-baseline.txt)
- 重开后内存：[12-final-build-meminfo-after-10.txt](device-acceptance/chat-window-reopen-20260831/12-final-build-meminfo-after-10.txt)
- 空闲后内存：[13-final-build-meminfo-after-idle.txt](device-acceptance/chat-window-reopen-20260831/13-final-build-meminfo-after-idle.txt)

## 验证边界

- 当前真实群聊只有 6 条可见缓存消息，不能伪造超过 80 条的线上历史分页正向证据；完整分页、锚点和耗尽复用由带调用计数的 Widget 测试覆盖。
- Android `gfxinfo` 对本 Flutter SurfaceView 只统计到 2 帧，本报告不使用该样本宣称帧率达标。
- 不发送消息、不删除消息、不修改群资料，线上业务数据未改变。
- 不同员工双端实时同步仍需要第二个有效员工终端会话；同账号重复登录会使先前会话失效，不能替代该验收。

## 回归

- `flutter analyze`：0 问题。
- IM 专项测试：19/19 通过。
- 完整自动化：194/194 通过。
- Profile 构建、覆盖安装、冷启动、会话列表、群聊打开、上滑、连续重开和媒体缓存恢复均正常。
- 关键崩溃日志匹配 0 条。
