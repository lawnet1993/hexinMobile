# 741 移动端同步健康与桌面 Gateway 核对

日期：2026-09-05

## 结论

- 移动端三项协议加固已完成：登录与心跳显式携带移动安装 ID；心跳上报 IM 同步模式和游标健康；事件、消息去重及已读游标统一到可复用语义。
- test01 真机与 test03 模拟器覆盖安装后均保留原会话，连续心跳返回 204。两端均为 `http_long_poll`，已落库游标等于已 ACK 游标，`pendingAckCount=0`，健康状态为 `healthy`。
- Windows 当前配置的 IM REST 为 `http://api.sfhkh.com:80`，IM gRPC 为 `http://api.sfhkh.com:7273`；OA REST 为 `http://api.sfhkh.com:80`，OA gRPC 为 `http://gw02.sfjxd.com:9080`。
- 2026-09-05 03:37（UTC+8）从桌面所在机器连续三轮探测：`api.sfhkh.com:80` 三次可达，`:443` 与 `:7273` 三次均不可达。运行中的桌面进程只有到解析地址 `95.40.88.9:80` 的已建立连接，没有到 `:7273` 的连接。
- 桌面日志连续数百次处于 `connecting -> transport error -> retry-wait`，未出现 `ready/connected/event received/ACK`。用户在后台连续三次看到 gRPC 在线连接数为 0；该后台指标本轮未直接读取，但与本机端口及进程连接证据一致。
- 因而当前主故障仍在 Windows 实时同步与测试服 Gateway 可用性之间。不能把“手机已通过 HTTP 长轮询收到消息”当成 Windows gRPC 正常。

## 移动端改造

### 独立安装 ID

- 安装 ID 继续存于环境隔离的移动端安全存储，覆盖安装、应用重启和切换账号不轮换。
- 登录请求同时携带兼容字段 `deviceId` 和明确字段 `installationId`，二者来自移动安装身份；`clientPlatform` 固定为 `mobile`。
- 心跳中的 `deviceId` 仍使用登录响应确认的服务端设备记录，另独立携带 `installationId`。这样服务端可以区分“设备记录”与“移动安装”，且不会复用桌面应用的本地设备存储。
- 日志、页面和报告均不输出安装 ID、设备 ID或指纹。

### 同步模式与游标健康

心跳新增以下安全遥测，不含账号、设备标识或消息正文：

```json
{
  "imSync": {
    "mode": "http_long_poll",
    "appliedSequence": 2363,
    "acknowledgedSequence": 2363,
    "pendingAckCount": 0,
    "cursorHealth": "healthy"
  }
}
```

状态定义：

- `healthy`：落库游标与 ACK 游标一致。
- `ack_pending`：事件已事务落库，ACK 尚未完成；下轮拉取先补 ACK。
- `invalid`：ACK 游标大于落库游标，属于不可接受的本地状态。
- `unavailable`：本地 IM 数据库暂时不可读；心跳仍继续，不因此退出登录。

### 去重与已读语义

- 事件按账号 + event sequence 主键以及账号 + event ID 唯一约束幂等落库。
- 消息以服务端消息 ID为权威主键；发送回声再按账号 + sender ID + `clientMessageId` 合并本地临时消息。
- 不过滤“发送者是当前账号”的 `message.created`，所以桌面发送的同账号消息仍会落入移动端。
- 不过滤“ReaderId 是当前账号”的 `conversation.read`；使用 `max(local, incoming)` 单调推进已读游标，再持久化重算未读与 @我。
- 只有真正进入可见区域的消息才调用 read API；他人的 read 只更新己方发送消息的已读回执，不能反推本端收件箱已读。
- 事件批次仍保持 SQLite 事务落库和游标提交在前、ACK 在后；ACK 前崩溃允许重放且不产生重复消息。

## Windows / Gateway 主修复提示词

```text
你负责修复当前 Windows 桌面端 IM/OA 实时同步，不要修改移动端，也不要根据旧源码版本猜测线上行为。当前已登录运行窗口是功能基准；本地桌面源码可能落后，先核对正在运行的安装包和对应版本源码。

已确认事实：
1. 当前桌面配置实际保存的 collaboration-im-api-url 是 http://api.sfhkh.com:80，collaboration-im-grpc-url 是 http://api.sfhkh.com:7273；OA REST 是 http://api.sfhkh.com:80，OA gRPC 是 http://gw02.sfjxd.com:9080。
2. Windows 日志连续数百次只有 connecting、transport error、retry-wait，从未出现 ready/connected/event received/ACK。
3. 同机 2026-09-05 03:37 连续三轮 TCP 探测中 api.sfhkh.com:80 可达，443 与 7273 都不可达；桌面进程只有到 95.40.88.9:80 的 Established 连接，没有 7273 连接。后台 gRPC 在线指标连续三次为 0。
4. 移动端使用 GET /api/im/sync/events?afterSequence={cursor}&waitSeconds=25&take=500 + POST /api/im/sync/ack，test01/test03 均持续收到 204 心跳，游标健康，能收到桌面消息。反向“手机发送 -> 服务端/另一手机收到 -> Windows 不出现”已真实复现。

请完成并给出可复现证据：
A. 服务端：从桌面登录响应/设备策略的 collaboration.imGrpcUrl 与 oaGrpcUrl 一路追踪到最终 managed_access.yaml，确认测试服为何下发上述 host/port；分别从公网、网关宿主机和容器/进程监听侧验证 7273、9080，核对安全组、NAT、反向代理、HTTP/2 h2c/TLS、服务监听地址与健康检查。不能只用“端口能连”代替成功收到 stream.ready。
B. Windows：记录 tonic Endpoint 的 scheme/host/port、DNS 解析结果、连接阶段和脱敏后的完整 error chain；给 connect 设置明确超时。确认 http://:7273 是否按 h2c 连接，若服务实际要求 TLS，则修正服务端下发地址与证书/SNI，不能客户端盲猜 443。
C. 在 gRPC 不可用时，实现与移动端相同的授权 REST 长轮询兜底，而不是永久重试空转：独立设备游标；事件和消息先在 SQLite 事务落库；事务成功后更新 applied cursor；最后 ACK；500 条拉满立即继续；崩溃重放幂等。
D. 统一去重和已读：事件按 account+eventId/sequence 去重；消息按 serverMessageId 以及 senderId+clientMessageId 合并；不得过滤当前账号发送的 message.created；conversation.read 即使 ReaderId 是当前账号也必须用 max(local,event) 持久化推进并重算未读/@我/首条未读。
E. 加入安全可观测状态：transportMode(grpc/rest_long_poll)、endpointAuthority、connectionState、retryAttempt、lastReadyAt、appliedSequence、acknowledgedSequence、pendingAckCount、cursorHealth；禁止输出 token、cookie、密码、设备 ID、指纹、消息正文和附件地址。
F. 验收：手机发一条 AI-UAT 前缀单聊，Windows 无需打开会话即可在一个同步周期内更新会话预览和 SQLite；Windows 打开后跨端 read 清零；杀进程于落库后 ACK 前，重启不重复；恢复 gRPC 后只能有一个活跃消费通道，REST fallback 停止，不能双重落库或双重 ACK。

同时核对版本一致性：当前 UI 显示 v1.0.91，但运行 exe 的 ProductVersion/FileVersion 元数据仍为 1.0.87。确认是否只是发布元数据漏更新，还是安装目录并非预期 1.0.91 二进制。
```

## 验证

- `flutter test`：1366/1366 通过。
- `flutter analyze`：0 问题。
- Debug APK 构建成功并覆盖安装到 `dd00d66d` 与 `emulator-5556`；SHA-256 为 `9A8604285129351103BE71CD1AD7C374359E291FEDAB5EC368838FDEE4BF911E`。
- 真机：连续两次心跳 204，游标 2363/2363，健康。
- 模拟器：连续两次心跳 204，游标 2364/2364，健康。
- 两台设备均保持原登录并停留在工作台；没有 `MOBILE_SESSION_AUTH`、FlutterError 或 FATAL EXCEPTION。

## 未完成

- 服务端是否已把新增心跳字段写入监控指标，需要后台 DTO/存储和指标面板配合确认；客户端已经真实发送且服务端返回 204。
- Windows gRPC 与 OA gRPC 的服务器监听、安全组和代理配置不在移动端仓库内，本轮只读核对后未修改。
- Windows REST 长轮询兜底尚未由桌面端实现，因此手机发消息到 Windows 的实时入站仍不能判定通过。
