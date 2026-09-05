# 730 桌面入站同步复核与交接提示词

时间：2026-09-05 01:42–01:44（Asia/Shanghai）。结论：**P1 仍未解决，而且不能仅按“忽略自己发送的消息”解释**。

## 新证据

桌面现有进程 139028 自 2026-09-04 23:52:54 持续运行，本轮未重启、重登、清缓存、更新安装或修改桌面数据。用户先前截图确认运行界面 v1.0.91，本轮没有 Windows UI 控制运行时，不能重新验证界面版本或视觉收发。

当前桌面保存的授权账号仍为 test01，原会话只读访问 IM bootstrap、sync/events、目标 messages 均 HTTP 200。消息请求编号：`e37d9569-6c73-4df6-8cce-5c711662b81e`。

会话 ID：`2a2ea21f-2ad6-49b3-b3da-407d1e7e4136`（test01 与 Test03 单聊）。

| 位置 | 当前真实结果 |
| --- | --- |
| 服务端 | 完整 1–15 条 |
| test01 真机 | 完整 1–15，ID/clientMessageId/sequence 与服务端逐条一致 |
| test03 M3 | 完整 1–15，ID/clientMessageId/sequence 与服务端逐条一致 |
| 桌面 test01 | 1–7、9、11、12、14、15，缺 8、10、13 |
| 桌面会话同步状态 | last_message_sequence 仍为 7；messages_synced_at 仍为 1788537185 |

三个缺口：

| sequence | 消息 ID | clientMessageId | 发送账号 |
| --- | --- | --- | --- |
| 8 | 4d277f77-b799-45ac-a1a7-6d6c375ebcc6 | c1bee507-132e-4e5f-addc-98f5c7581cf5 | test01 |
| 10 | 9238309b-aa1e-4b11-b4b1-bb7c4a11f769 | e7c337c7-d393-4207-acf1-e792abc07738 | test01 |
| 13 | dd238a45-8f76-4b80-9ebf-608c4c8dd9c2 | 3f99ef56-a217-4849-bbc2-ea48199d501c | test03 |

13 是 00:22:00.817674（本地时间）由 M3 test03 真实发送的 `AI-UAT-20260905-002300-M3-PHONE-RECEIPT`。它不是当前桌面账号自己的消息。其已在真机显示并回执的旧操作记录见 721；本轮重新通过服务器和两端 SQLite 核对，不依赖旧截图推断当前记录存在。

因此，桌面“只过滤当前账号事件”不能单独解释现象；需把其他账号入站投递、订阅生命周期、消费与落库也纳入排查。仍不能凭缓存缺失判定唯一根因是在 Gateway、客户端接收还是持久化。

桌面两张 collaboration_event_* 表中当前账号计数仍为 0；新版可能另存游标，不能凭此断言从未连接。当前 latest.log 为 0 字节；有内容的最近轮转日志修改时间 23:52:26 早于当前进程启动，不把旧 transport error 当成本进程故障证据。

## 可直接交给桌面端 AI 的提示词

请排查当前已登录 test01 的最新版桌面客户端 IM 入站同步。以真实运行窗口/实际加载版本为准，不要拿旧源码或 EXE 文件元数据否定用户 v1.0.91 运行截图。测试凭据由安全环境或既有会话提供，不写入提示词、代码、日志或报告。

已有可复现反例：会话 2a2ea21f-2ad6-49b3-b3da-407d1e7e4136 的服务端、test01 手机、test03 模拟器均完整保存序号 1–15，桌面本地缺 8、10、13。尤其 13 是 test03 发来的消息，不是桌面账号自己发的；不能只修 SenderId == 当前账号的过滤。桌面现有凭据 GET messages/sync 均 200，但本地 last_message_sequence 仍为 7。

请按真实版本逐段追踪：

1. 登录/恢复后实际启用哪个入站通道：Push Gateway、gRPC、长轮询或组合；订阅是否带正确账号、独立 desktop deviceId、令牌，连接失败/Token 更新后是否重新订阅，旧循环是否误取消新循环。
2. 在不输出 Token、Cookie、指纹、正文或附件地址的前提下，增加事件 ID、事件序号、会话 ID、连接代次和阶段诊断，区分未投递、收到后被过滤、落库失败、落库成功未发布 UI。查清新版真实游标存储位置，不能仅凭旧表空就下结论。
3. 事件先事务幂等落库和更新本地游标，成功后发布状态，再 ACK；不要让慢 ACK 阻塞已经落库的消息显示。当前账号自己的跨设备事件也必须处理并按服务端 ID/clientMessageId 去重。
4. 核对断线/重连及可见会话历史补偿：即使本地已有更高序号 15，也不能把中间缺失 8、10、13 当作已覆盖；检查批次、分页、取消和错误处理。不使用人工 SQL 插入或清库掩盖根因。
5. 处理 conversation.read 时当前账号 ReaderId 不能被过滤，SQLite 以 max 更新已读游标并重算未读/@我，再通知 UI。
6. 修复后让现有账号会话自然补齐 8、10、13，逐条对比消息 ID/clientMessageId/sequence。再用真实桌面与手机 UI 双向发送、第三账号发送、单聊/群聊/@我、离线恢复、同账号跨端已读及落库后 ACK 前中断验证。不以脚本 GET 能看到或手动刷新后看到当作实时同步通过。

移动端当前实现可参考 722/723：`GET /api/im/sync/events?afterSequence=...&waitSeconds=25&take=500` 作为主同步；SQLite 成功提交后通知订阅者刷新，再执行 ACK；满批立即继续、重复事件幂等。可见会话另有 12 秒历史核对兜底。这是当前已实现链路，不代表已接入新版统一 Push Gateway，也不保证所有事件无延迟。若最新版必须走新 Gateway，请提供实际连接、鉴权、订阅、事件与 ACK 契约，让移动端按同一协议对齐。

输出根因与证据、所改版本/文件、实际请求和事件编号、双端截图、最终 SQLite 对账和未执行项。未经用户同意不要卸载、清数据或更改正式账号/业务数据。

## 可复核材料

- [桌面当前只读缓存](../test/evidence/desktop-sync-730/desktop-cache.json)
- [当前服务端与两移动端逐条对账](../test/evidence/desktop-sync-730/server-mobile-comparison.json)
- 新增 `scripts/inspect-desktop-im-cache.py`：固定此测试账号和会话；SQLite mode=ro、query_only、显式读事务，只 SELECT 白名单元数据，不读取 payload_json/search_text、凭据或设备 ID。
- 复核命令：在 Mobile 目录运行 `python scripts/inspect-desktop-im-cache.py`。访问服务端仍用既有 `inspect-desktop-im-uat.ps1 -ConversationId ...`，不发送测试消息或 ACK。

本轮没有移动端应用代码修改或重新构建，未新增消息发送。整体移动端目标仍未完成；当前桌面故障需要新版桌面链路处理，不能用修改过时桌面源码或人为补库冒充修复。
