# 移动端四虚拟机 IM 压力、及时性与已读语义复验（2026-09-06）

## 结论

本轮结论为**部分通过**：

- 四台独立 Android AVD 同时在线，群聊与单聊的数据完整性、顺序、去重、Outbox 和 SQLite 完整性通过。
- 群聊实时性仍未通过。纯接收端观测到最老事件约 20.259 秒后才到达，而本地提交峰值约 1.088 秒，主要等待仍发生在事件到达客户端之前。
- 发现新的 P1 服务端缺陷：接收端进程停止、冷启动后停在工作台且从未打开目标单聊，服务端仍把新消息标为该接收账号本人已读，并通过 `conversation.read`、`/api/im/bootstrap` 和 `/api/im/conversations` 三条路径下发 `read=last、unread=0`。

## 环境与方法

| 设备 | 账号 | 本轮角色 |
| --- | --- | --- |
| M1 | test02 | 群聊发送/接收 |
| M2 | test03 | 群聊发送/接收与纯接收时延观察 |
| M3 | test04 | 群聊发送、单聊接收、进程停止恢复 |
| M4 | test05 | 单聊发送 |

四台 AVD 使用独立 userdata、移动端安装身份和账号数据。消息只通过真实 UI 发送，全部使用 `AI-UAT-` 前缀；数据库核对为 `run-as` 只读一致性快照，没有直接写库或调用发送 API。

## 并发与完整性

### 三发送端群聊并发

M1、M2、M3 同时各发送 15 条，共新增 45 条。三端最终快照一致：

- 累计 229/229 条；
- 序号均为 1..229 且严格递增；
- 229 个服务端消息 ID 唯一；
- 三端 Outbox 均为 0；
- 三端 SQLite `quick_check=ok`；
- 三端事件游标均满足 `applied=acked`。

### M4 到 M3 单聊

第一次以 120 ms 自动化节奏执行时，低性能软件渲染设备未及时消费发送按钮点击，15 段文本停留在一个未发送草稿中。数据库确认没有落库，该批次排除，不计入通过率；测试生成草稿随后被清除。

测试工作器增加输入稳定等待后，以 750 ms 输入稳定时间和 800 ms 间隔重跑 10 条：

- M3、M4 均落库 10/10；
- 本轮序号为 33..42，累计会话序号为 1..42；
- 双端消息序号、服务端消息 ID 和 `clientMessageId` 映射一致；
- 双端 Outbox 为 0、SQLite `quick_check=ok`。

后续隔离用例再新增 5 条，双端最终均为 47 条、序号 1..47、47 个消息 ID 唯一且逐序号身份完全一致。

## 及时性与资源

| 场景 | 结果 | 观测 |
| --- | --- | --- |
| 群聊并发完整性 | 通过 | 三端 229/229，无丢失、重复或乱序 |
| 群聊实时唤醒 | 未通过 | M2 最老事件年龄最大约 20.259 秒 |
| 群聊本地提交 | 观察通过 | 四端压力下提交峰值约 1.088 秒 |
| 单聊在线事件年龄 | 通过 | M4 侧最新事件年龄最大约 1.584 秒；M3 存在设备时钟偏差，不以负年龄作延迟结论 |
| 四 App 内存 | 通过 | 峰值 PSS 约 155.7–188.5 MiB |
| 稳定性 | 通过 | 四进程均存活，未发现目标包 Crash buffer、FATAL、ANR 或 OOM 记录 |

## P1：不可见会话被服务端提前标记已读

### 可复现步骤

1. M3 单聊基线为 `last=45、read=45、unread=0`。
2. M3 通过真实页面进入并离开测试群，等待 active 会话清理，然后停止 App 进程。
3. M4 在与 M3 的单聊中发送 2 条消息。
4. 冷启动 M3，只停留在工作台，不进入消息列表或目标单聊。
5. 等待事件追平，读取 Profile 白名单诊断和 SQLite 只读快照。

### 预期

M3 应得到 `last=47、read=45、unread=2`。只有消息真正进入可见区域并由客户端显式提交 `/api/im/conversations/{conversationId}/read` 后，`read` 才能推进到 47。

### 实际

- M3 工作台状态、目标单聊不可见；
- 服务端发给 M3 的两条 `conversation.read` 均被诊断为 `isSelf=true`，序号分别覆盖新消息 46、47；
- `/api/im/bootstrap` 返回目标会话 `last=47、read=47、unread=0`；
- `/api/im/conversations` 同样返回 `last=47、read=47、unread=0`；
- M3 本地最终投影变为 `last=47、read=47、unread=0`。

移动端本地事件处理已经区分本人和其他成员 ReaderId，不能安全地忽略这些事件，因为服务端把错误事件标成了本人。若客户端强制忽略，会同时破坏桌面端真实已读同步。因此主修复必须在 IM 服务端。

## 可直接交给服务端 AI 的修复提示词

```text
请修复 IM 已读语义。真实四 AVD 验收已复现：接收端 App 进程停止，随后冷启动且只停留在工作台、从未打开目标单聊时，服务端仍为该接收账号生成 conversation.read，并在 /api/im/bootstrap 与 /api/im/conversations 中返回 lastReadSequence=lastMessageSequence、unreadCount=0。

要求：
1. 消息送达、在线状态、active conversation、心跳或长轮询均不得自动推进已读游标。
2. 只有经过鉴权的 POST /api/im/conversations/{conversationId}/read 才能推进该账号在该会话的 lastReadSequence；必须单调 max 合并并保持幂等。
3. conversation.read 的 readerId 必须是实际调用 /read 的账号/成员，不能使用接收目标、发送目标或会话当前成员代填。
4. /api/im/bootstrap 与 /api/im/conversations 必须返回当前鉴权账号自己的 read/unread 投影，不能返回会话全局最大游标或其他成员的游标。
5. PUT/DELETE /active 只能维护在线/会话活跃状态，不能读消息或写已读；进程死亡、断网和 active 状态过期也不能产生 read。
6. 增加回归：A 停留工作台或离线，B 连发 3 条，A 应为 last=N+3/read=N/unread=3；A 真正打开并看到 1 条后只读到 N+1；看到全部后才读到 N+3；B 仅收到与 A 显式 /read 对应的回执。
7. 增加多端回归：同账号桌面端显式已读可同步到移动端，但另一参与人的已读只更新 recipient read receipt，不能清空当前账号未读。
8. 为 message commit、目标等待器数量、唤醒时间、Gateway 实例、read actor 和 read source 增加不含正文/Token 的结构化指标。
```

桌面端不需要为本缺陷修改消息渲染；修复服务端后，再用桌面 + M3 + M4 做显式已读互通回归。

## 证据

- [三端群聊快照：M1](../test/evidence/multivm-pressure-20260906-154756/group-test02.json)
- [三端群聊快照：M2](../test/evidence/multivm-pressure-20260906-154756/group-test03.json)
- [三端群聊快照：M3](../test/evidence/multivm-pressure-20260906-154756/group-test04.json)
- [四端 UI 并发发送日志](../test/evidence/multivm-pressure-20260906-154756/m1-group.json)
- [M4 低节奏适配后的单聊发送日志](../test/evidence/multivm-pressure-20260906-154756/m4-direct-retry-20260906-155325.json)
- [M3/M4 最终单聊数据库快照](../test/evidence/multivm-pressure-20260906-154756/m3-read-diagnostic-db.json)
- [不可见会话已读诊断摘要](../test/evidence/multivm-pressure-20260906-154756/m3-read-diagnostic-summary.json)
- [四端时延与内存摘要](../test/evidence/multivm-pressure-20260906-154756/timing-memory-summary.json)
- [未发送草稿失败截图](../test/evidence/multivm-pressure-20260906-154756/m4-direct-composer-failure.png)

## 未覆盖边界

- 本轮为 Android AVD，不替代真机厂商系统后台冻结、弱网和推送唤醒测试。
- 服务端修复前无法判定跨端已读矩阵通过。
- Windows 云桌面本轮仍受远程桌面网络错误影响，未加入这次并发；此前 Windows 与移动端的消息同步问题继续单列。
