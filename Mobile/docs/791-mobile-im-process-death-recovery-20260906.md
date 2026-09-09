# 移动端 IM 系统回收进程恢复实测（2026-09-06）

## 结论

在低性能 Android 虚拟机上使用系统 `am kill` 回收后台 App 进程，并在进程不存在期间由另一台已登录虚拟机真实发送 5 条群消息。重新启动后自动登录、本地缓存、增量事件追平、未读定位、可见区域已读和发送方回执均通过。

该用例不同于普通 `force-stop`：没有清除应用数据、数据库、安全存储或安装身份，也没有重新登录。

## 基线

测试群在发送端和接收端均为：

- 179 条消息，sequence 1..179；
- test02/test03/test04 分别为 68/41/70 条；
- 179 个服务端消息 ID 唯一；
- 179 个 `senderId + clientMessageId` 唯一；
- Outbox=0，SQLite `quick_check=ok`；
- 接收端事件游标 `applied=acked=4966`。

## 回收与离线消息

1. 接收端退到后台后执行 Android 系统 `am kill`；操作前进程存在，操作后 PID 消失，确认不是只切换页面。
2. 发送端通过真实 Flutter 输入框发送 `AI-UAT-PROCDEATH-20260906-1530-M1-001..005`。
3. 5 次发送均完成，最后一条在发送端可见，输入框恢复为空。
4. 接收端重新启动为 COLD，Activity `TotalTime=3689 ms`，未进入登录页。
5. 从启动命令开始到只读数据库首次确认完整，观测上界为 8009 ms；其中真正的 5 事件同步批次为 544 ms：request 208 ms、bootstrap 14 ms、SQLite commit 145 ms、ACK 165 ms。

恢复后最终状态：

| 项目 | 结果 |
| --- | --- |
| 消息总数 | 184/184 |
| 发送者计数 | test02=73、test03=41、test04=70 |
| sequence | 1..184 严格递增 |
| 消息 ID / 客户端键 | 184 / 184，均唯一 |
| Outbox | 0 |
| SQLite | `quick_check=ok` |
| 会话投影 | `lastMessageSequence=184` |
| 事件游标 | `applied=acked=5027` |

## 未读和跨端已读

- 恢复后的会话列表立即显示最新消息预览和未读 88；这是原有 83 条未读加本轮 5 条，没有少计或重复累加。
- 第一次打开会话定位到 sequence 97 的“以下为未读消息”，最新 sequence 184 尚未进入可见区域；持续观察 15 秒，客户端没有错误地清空全部未读。
- 点击“回到最新”使 sequence 184 真正可见后，约 2510 ms 内持久状态更新为 `lastReadSequence=184、unreadCount=0`，事件游标继续推进至 `applied=acked=5032`。
- 发送端 5 条消息全部出现“已有接收人已读”，完成跨端闭环。

## 时间显示排除项

发送端截图一度显示 07:27，而接收端显示 15:27。设备侧核对后确认发送虚拟机系统时区为 GMT，接收虚拟机为 Asia/Shanghai；两者表示同一时刻，客户端均按各自系统本地时区显示，因此不是 UTC 渲染缺陷，也没有把客户端强制固定为北京时间。

当前生产镜像禁止通过 ADB 修改持久时区和发送系统时区广播。后续重启发送虚拟机时应使用模拟器启动参数统一时区，避免跨设备截图误判。

## 证据

- [真实发送工作记录](../test/evidence/process-death-recovery-20260906/m1-send-while-m2-dead.json)
- [进程恢复后的工作台](../test/evidence/process-death-recovery-20260906/01-recovered-workbench.png)
- [恢复后会话列表未读 88](../test/evidence/process-death-recovery-20260906/02-message-list-unread.png)
- [首次打开定位第一条未读](../test/evidence/process-death-recovery-20260906/03-first-unread-anchor.png)
- [最新消息可见后已读清零](../test/evidence/process-death-recovery-20260906/04-latest-visible-read-closed.png)
- [发送端已读回执](../test/evidence/process-death-recovery-20260906/05-sender-read-receipt.png)

## 仍未覆盖

- 真机低内存回收、深度 Doze、锁屏厂商推送唤醒仍未通过；虚拟机 `am kill` 不能替代真实厂商系统行为。
- 无厂商推送通道时，进程死亡期间不会被推送主动拉起；本轮验证的是用户再次打开 App 后的可靠补偿。
- iOS 进程回收恢复仍无真机证据。

