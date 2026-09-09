# 771 · Windows / 移动端事件契约现场对照

日期：2026-09-06，Asia/Shanghai。

结论：**当前 Windows 运行端未通过 IM/OA 实时同步验收。移动端同一测试环境已经把带稳定 ID 的 IM/OA 事件落入 SQLite 并推进游标；Windows 当前日志则从未进入 realtime `ready`，IM/OA 分别累计 227/226 次 `collaboration event id is missing`，桌面事件 inbox 和事件游标均为 0。不能把该问题归因于移动端未发出消息。**

## 当前运行态

- Windows 进程：`C:\Users\86137\AppData\Local\合兴智联\hexing-zhilian.exe`，启动时间 01:50:57。
- 运行文件的 FileVersion / ProductVersion 均为 1.0.87；更新缓存中已经存在 1.0.94 和 1.0.95 安装包。前端版本文案、下载完成和实际进程文件仍未形成一致的安装证据。
- 最新日志采样中，IM/OA `ready` 次数均为 0；`retry-wait` 分别为 97/100 次。已观测到 IM `attempt=739`、`reason=transport error`。
- IM/OA 缺少事件 ID 的持久化警告分别为 227/226 次。
- Windows `collaboration_event_inbox` 为 0 行，`collaboration_event_cursors` 为 0 行；消息缓存有 596 行，但最大消息序号仍为 20840，不能把 bootstrap/索引刷新当成事件同步成功。

## 移动端对照

读取 emulator-5554 当前 test02 的 SQLite 副本后立即删除副本，全程未输出消息正文、账号 ID、Token、设备 ID或附件地址：

| 数据 | IM | OA |
| --- | ---: | ---: |
| 已落库事件 | 350 | 102 |
| 空事件 ID | 0 | 0 |
| 最大事件序号 | 4071 | 818 |
| 本地事件游标 | 4071 | 818 |
| ACK 游标 | 4071 | 不适用 |

移动端 IM 使用 `GET /api/im/sync/events?afterSequence=...&waitSeconds=25&take=500`，读取服务端字段 `id / sequence / type / payloadJson`；事务落库后推进设备独立游标，最后调用 ACK。当前模拟器 IM 事件游标与 ACK 游标均为 4071，证明 REST 事件契约和移动端持久化链路在该环境可工作。随后 realme 真机在系统锁屏下启动并完成一条积压事件追平，event/ACK cursor 均推进到 4101，详见 [772](772-mobile-locked-device-session-catchup-20260906.md)。

## 根因边界

运行日志足以证明 Windows 入站链路失败，但还不能只凭旧源码断言唯一根因。现有桌面源码显示 gRPC DTO 的 `event_id` 被转换为缓存层要求的 `eventId`，缓存会拒绝空值；现场警告可能来自以下任一边界：

1. 服务端 gRPC 流没有填充 `event_id`，而 REST 同一事件返回了 `id`；
2. 桌面 DTO / protobuf 与当前服务端版本字段不一致；
3. fallback/事件派发层把 `id` 原样传入，但缓存只接受 `eventId`；
4. realtime Gateway 地址、scheme、TLS 或 HTTP/2 配置错误，导致 gRPC 永不 ready，同时错误的补偿路径仍持续投递无 ID 事件。

禁止用随机 UUID 补齐事件 ID，这会破坏崩溃重放和跨端幂等。应优先修正服务端稳定事件 ID 和桌面字段映射；如果协议明确允许用 `(service, accountId, sequence)` 作为确定性兼容键，也必须由协议和测试共同约束。

## 可直接交给桌面端 AI 的提示词

```text
你是一名高级 Windows/Tauri/Rust 客户端和 gRPC 协议工程师。请以当前运行安装包、当前测试服和脱敏日志为准，修复 Windows IM/OA 实时事件入站链路；不要把旧桌面源码或前端版本文案当成运行事实，不要输出密码、Token、Cookie、完整 deviceId、消息正文或附件真实地址。

2026-09-06 现场证据：
- 运行进程路径为 C:\Users\86137\AppData\Local\合兴智联\hexing-zhilian.exe，磁盘 FileVersion/ProductVersion 均为 1.0.87；更新目录已有 1.0.94 和 1.0.95 安装包。先查清实际安装/重启目标，不允许只看前端显示。
- latest.log 中 IM/OA realtime 从未进入 ready；retry-wait 分别累计 97/100 次，IM 已见 attempt=739、reason=transport error。
- `im realtime events could not be persisted: collaboration event id is missing` 227 次；OA 同类警告 226 次。
- Windows collaboration_event_inbox=0，collaboration_event_cursors=0；消息缓存刷新不能替代事件游标成功。
- 同一测试环境的移动端 IM 已落库 350 个事件，OA 已落库 102 个事件，空事件 ID 均为 0；IM event/ACK cursor=4071，OA cursor=818。移动端 REST 契约读取字段为 id、sequence、type、payloadJson。

请完成：
1. 从运行进程、安装目录、卸载注册项、快捷方式和更新器日志确认真正执行的版本；修复下载包、覆盖目录和重启目标不一致。
2. 记录服务端下发的 realtime Gateway 的脱敏 host、scheme、port、TLS、HTTP/2 和 gRPC status；连接必须实际进入 ready。
3. 在 gRPC 解码、fallback 拉取、Tauri event emit、Rust Value 转换和 SQLite record_incoming_events 每一层记录脱敏字段存在性：hasEventId、sequence、type，不记录 payload。
4. 核对当前 protobuf：服务端 gRPC event_id 与 REST id 必须表示同一个稳定事件身份；桌面边界可兼容 id/eventId 命名，但不得生成随机 ID。
5. 单个坏事件不得导致整个批次永久停滞。先事务落地 inbox/message，再推进 device 独立游标，最后 ACK；崩溃重放不得重复。
6. 不得过滤 senderId 为当前账号的 message.created 或 ReaderId 为当前账号的 conversation.read。
7. realtime 不可用时，REST 长轮询补偿也必须使用独立 desktop deviceId 游标并持续追平，且明确暴露当前使用的是 realtime 还是 fallback。
8. 添加自动化：空 ID 拒绝但不死循环、id/eventId 映射、500 条连续追平、ACK 前崩溃重放、同账号跨设备消息、跨端已读、会话摘要刷新。
9. 安装真实修复包后执行 D1+M1：双向各发 20 条、他人发 20 条、单聊/群聊/@我/离线恢复/已读互清；记录事件序号、唯一性、时延 P50/P95 和请求编号。

输出根因、改动文件、协议字段、运行版本/路径、Gateway 摘要、修复前后日志计数、SQLite inbox/cursor/sequence、自动化和真实安装包回归。只有 Windows 进入 ready 或可靠 fallback、事件 inbox/游标持续推进且双向实测无丢失无重复，才能判定通过。
```

结构化证据：[result.json](../test/evidence/windows-mobile-event-contract-20260906-094000/result.json)。

## 当前判定

- 移动端事件持久化与设备游标：通过。
- Windows IM/OA realtime ready：未通过。
- Windows 稳定事件 ID 入站：未通过。
- Windows 当前运行版本与更新包一致性：未通过。
- 真实窗口收发：本轮因 Computer Use 必需的 `node_repl/@oai/sky` 入口未挂载而未重新操作；此前 v1.0.94 窗口双向文本曾通过，不能覆盖本轮持续发生的运行日志与游标异常。
