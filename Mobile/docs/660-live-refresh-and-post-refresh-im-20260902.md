# 新环境真实续期与续期后消息验收

时间：2026-09-02 21:35–21:45，Asia/Shanghai。结论：**主动调用真实续期及其后业务请求通过；整体验收仍部分通过**。本轮属于 progress，没有将自然到期、历史 401 根因或完整桌面矩阵视为完成。

## 协议核对

- 当前安装 Windows 客户端文件版本、产品版本均为 1.0.87；检查的是安装目录下的实际程序，不是旧桌面源码。
- `/.well-known/openid-configuration` 返回 JSON，声明 `/connect/token` 和 `refresh_token` 授权类型，与当前移动端路径一致。[公开配置快照](../test/evidence/session-refresh-20260902/discovery.json)。公开认证方式列表本身不能证明移动端刷新能否成功，以下实际请求才是证据。
- `/swagger/v1/swagger.json` 和 `/openapi.json` 虽为 200，实际是平台 HTML 回退页，**没有拿它们当作 API 文档**。

## 真实刷新，不导出凭据

使用显式测试入口 [session_refresh_probe.dart](../test_driver/session_refresh_probe.dart)，只允许 api.sfhkh.com 的已有 test03，并要求 Profile/Debug + `UAT_VERIFY_REFRESH=true`。调用的是应用现有 `AuthController.refreshSession`，不是脚本伪造新 Token，也不修改数据库。它会按正常刷新协议旋转系统安全存储内的令牌，因此不是纯只读操作；没有修改业务记录。

仅安装于独立 M3/emulator-5556，未操作 M1 真机 UI/网络或 M2。请求没有发往其他来源，也没有打印密码、Token、指纹、设备 ID 或响应描述。

真实请求结果（中国时间 21:38:18–19）：

| 核对项 | 结果 |
| --- | --- |
| POST /connect/token | HTTP 200 |
| 应用返回新 session | 是 |
| 访问令牌已更新 | 是，仅比较结果，不输出值 |
| 刷新令牌已更新 | 是，仅比较结果，不输出值 |
| 账号与设备 | 保持 test03 原会话归属 |
| 旧 Token 时间提示 | nbf=12:08:10Z，exp=14:08:10Z |
| 新 Token 时间提示 | nbf=13:38:19Z，exp=15:38:19Z |

JWT 时间字段未单独验签，仅用于诊断提示；真实 HTTP 200 和后续实际业务成功共同证明当前返回的令牌可用。新到期字段对应中国时间 23:38:19。[设备日志](../test/evidence/session-refresh-20260902/real-refresh.log)。

这次是在旧访问令牌到期前，显式调用应用刷新方法。**没有伪造服务端 401，也没有等到自然到期，所以不能称“自然到期自动续期验收通过”。** 同样不能据此解释 658 中 M1 的历史 managed_commands 401。

## 客户端补充

[AuthController](../lib/features/auth/application/auth_controller.dart) 增加：

- 刷新结果日志仅含 HTTP 状态、白名单错误码及 accepted/rejected/retry/stale_result/invalid_response。错误描述和未知错误内容不直接输出，避免服务端回显凭据泄漏。
- 保持原有策略：网络/5xx 重试、不直接清会话；400/401 刷新拒绝交由既有失效处理；并发刷新和旧响应隔离不改弱。
- 禁止刷新请求自动跟随重定向，防止携带刷新凭据跳转到其他地址。

[新增测试](../test/session_refresh_diagnostics_test.dart) 七项，包括成功/invalid_grant/invalid_client/未知错误/网络故障的诊断白名单、重定向选项、真实本地 HTTP 307：原端点收到一次，目标端点收到零次。最初五项诊断缺失与一项选项断言失败属于新增诊断/安全要求，不将它们包装成六个业务故障。[初始日志](../test/evidence/session-refresh-20260902/diagnostics-before.log)。

## 正常包业务验证

测试入口包 SHA256 `138062913E106383C834A4BBF8FAC6AA943D929ED7E7C09C1C94FAF7E0CD1F95`，随后已被正常 lib/main.dart 包替换。正常包不包含主动测试调用：

```
Profile / Android arm64 + x64 / 1.0.1+2
SHA256 841E174F2FF1936C4E832D8BCD4B4056CF588B30CCA6F1B1D291C1629932C828
84,396,355 bytes
```

M3 覆盖安装 Success，未清数据，设备 base.apk 哈希一致。冷启动 TotalTime=10262ms，仅记录，不作为性能通过证据。M1 仍未更新，避免打断可能正在进行的审批操作；未收到上一轮确认答复。

使用正常 UI：进入消息 → test01 单聊 → 输入 → 核对输入框和发送按钮 → 发送一次 `AI-UAT-20260902-214200-AFTER-REFRESH`。这是本轮唯一新业务消息；前缀为输入准备时间，实际服务端接收是 21:43:11。

| 字段 | 值 |
| --- | --- |
| 单聊 ID | 2a2ea21f-2ad6-49b3-b3da-407d1e7e4136 |
| 服务端消息 ID | 3f44c0f9-ba64-4eb8-b94d-e7dee5eed99e |
| clientMessageId | 7092616b-3b9e-4fdb-bf41-fb50083b81c4 |
| 消息序号 | 5 |
| 服务端 UTC 时间 | 2026-09-02T13:43:11.481588Z |
| 实际 senderId | c404c59a-6dc3-4e6b-a1dc-d5d0c20786cc（test03） |

[输入框证据](../test/evidence/session-refresh-20260902/03-composer.xml)、[正常包发送截图](../test/evidence/session-refresh-20260902/04-sent.png)。截图显示已发送而不是虚假已读，头像和已有四条历史保留。

只读核对：

- M3：五条消息、目标唯一、sent，Outbox 空，last5/read5/unread0，事件 applied=acked=206。[发送端](../test/evidence/session-refresh-20260902/05-sender.json)。
- M1：没有打开该聊天或调用 read；后台自动落到同一 server/client ID，last5/read4/unread1，事件 applied=acked=205。[接收端](../test/evidence/session-refresh-20260902/06-receiver.json)。
- D1：使用原桌面 test01 会话只读 GET，bootstrap/events/目标历史均 200，目标消息唯一且 senderId/ID/seq 一致，unread1/read4。[桌面会话核对](../test/evidence/session-refresh-20260902/07-desktop-readonly.json)。**这是桌面会话/API证据，不是桌面窗口操作证据。**

M3 最终返回[消息列表](../test/evidence/session-refresh-20260902/08-normal-list.png)，正常进程 PID27653，Wi-Fi/数据均为1、默认网络114。最近1500行无 FATAL/Unhandled/RenderFlex overflow 或新的会话失败。M1、M2 网络没有改变。

## 回归及余项

- 针对性 **22/22**：[日志](../test/evidence/session-refresh-20260902/targeted-tests.log)。
- 全量 **445/445**：[日志](../test/evidence/session-refresh-20260902/full-tests.log)。
- 静态检查 0 问题：[日志](../test/evidence/session-refresh-20260902/analyze-final.log)。
- [正常包构建](../test/evidence/session-refresh-20260902/build-final.log)成功，第三方 Built-in Kotlin 警告保留。

继续待办：自然到期自动触发续期、M1 历史失效根因、真机新版回归、其他 IM/OA 请求归属竞争、服务端群事件缺项与未读 P1、旧媒体/附件 500、当前桌面窗口真实矩阵、高级 OA 与性能验收。目标保持进行中。
