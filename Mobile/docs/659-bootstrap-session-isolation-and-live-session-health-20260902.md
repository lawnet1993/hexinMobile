# IM/OA 普通刷新隔离与当前会话核对

时间：2026-09-02 21:22–21:34，Asia/Shanghai。结论：**本轮客户端修复及 M3 断网回归通过；整体仍部分通过**。

本轮取得新的复现、修复、测试和设备证据，属于 progress。没有将原目标缩减为本轮测试，也没有更改服务端代码或数据库。

## 1. 修复范围与复现

658 处理的是 IM 事件拉取。此次检查发现 IM 和 OA 的普通 `refreshBootstrap` 仍有独立问题：先捕获 session，随后 HTTP 客户端再次读取 session；收到响应后不核对会话，直接按最初账号写缓存。同账号重新登录时，晚到的旧响应还能覆盖新请求已经写入的内容。

新增真实本地 HTTP + SQLite 回归，分别验证 IM/OA：

- 请求过程中切换账号、同账号重新登录、退出登录：旧响应不得成功交付或写缓存。
- 先挂起旧请求，再完成新会话请求，最后释放旧响应：新缓存不得被覆盖。
- 正常刷新可写入；服务停止后 cache-first 不再发请求；另一账号不能读取前一账号缓存。

修复前有效回归为 **2 通过、8 失败**。[修复前日志](../test/evidence/bootstrap-session-20260902/before.log)。编写测试时另修正了测试关闭 HTTP 服务后读取 `server.port` 的夹具错误；不是产品缺陷，也不计入上述 8 个失败。

实现：

1. IM/OA 普通刷新及 cache-first 缺缓存后的请求，均使用最初捕获的 session；OA HTTP 客户端增加可选的 `forSession` 参数。
2. `SecureSessionStore.withCurrentSession` 将短时缓存读写与登录/退出持久化放在同一会话锁下，校验实际账号、设备和 token。**网络请求不持有锁**，回调不允许调用 session 方法。
3. 过期操作抛出不含凭据的 `SessionChangedException`，不将其伪装成 401，不清理新会话。
4. 增加两项锁顺序测试：进行中的缓存提交先完成，再切换/清理会话；随后旧提交被拒绝；拒绝不会阻塞后续登录。

源文件：[会话存储](../lib/core/storage/secure_session_store.dart)、[协作客户端](../lib/core/network/collaboration_client.dart)、[IM/OA 仓库](../lib/features/collaboration/data/collaboration_repositories.dart)、[12 项新增隔离回归](../test/bootstrap_session_isolation_test.dart)。

**边界：此次没有将同样改造扩展到所有 OA catalog/notifications/events 或所有 IM 写操作；这些路径仍须逐项检查。不能宣称整个仓库已完全隔离所有竞争。**

## 2. 401 与新环境协议证据

此前 M1 于 21:14:08 的 `managed_commands 401 → terminated` 仍未确定根因；此次没有恢复旧 Token、猜测到期原因或绕过鉴权。

新增显式测试入口 [session_health_probe.dart](../test_driver/session_health_probe.dart)，只允许新测试环境的已有 test01/test03，会在设备内部读取会话，并 GET commands、IM bootstrap、OA bootstrap。不会刷新 token、发送心跳、提交业务或导出凭据；禁用跨站重定向。输出严格限定为时间、是否存在刷新令牌、数字状态码、传输错误枚举。JWT 时间只是**未验证的诊断提示**，不参与认证决策。[输出白名单测试](../test/session_health_probe_test.dart) 两项通过。

本轮只在 M3 使用该入口。实际输出：

- 核对时间 2026-09-02 13:30:06 UTC / 21:30:06 中国时间。
- `hasRefreshToken=true`。
- 未验证时间字段：`nbf=12:08:10Z`，`exp=14:08:10Z`，两者相差 2 小时。
- commands / IM bootstrap / OA bootstrap 均 HTTP 200。

[设备内诊断日志](../test/evidence/bootstrap-session-20260902/session-health.log)。新环境当前会话已经不同于早期“12 小时、暂不提供刷新令牌”的描述，但上述证据**不证明正常续期成功，也不解释 M1 历史 401**。当前客户端 `/connect/token` 续期路径与实际新服务的契合、续期失败处理仍需真实核对。

D1 既有 Windows test01 会话只读核对 bootstrap/events 均 200，目标单聊 seq4/read4/unread0，测试群 seq11/read9/unread2。[D1 核对数据](../test/evidence/bootstrap-session-20260902/desktop-readonly.json)。当前没有可调用的桌面控制工具，不能将 GET 当作桌面窗口操作证据。

## 3. 正常包设备验收

- M3：独立 emulator-5556，test03，Android 16，系统时区 UTC。
- M1：真机已授权且原应用进程仍在，但发现页面已变为补卡审批详情，可能有用户正在操作；已询问，本轮未收到答复，因此**不安装、不切页、不改网络**。不能写成新版已装真机。
- M2：未操作。

诊断包 SHA256 `6BAEB133108FC4A6F90B68AF13C5FD6E3806CBCE5AD2B1EEF52531FCE8929667`，已被正常入口包替换。最终正常包：

```
lib/main.dart / Profile / Android arm64 + x64 / 1.0.1+2
SHA256 D3725F7327745E19A8F3645990F3DFD06BD7FFB1C8E0A7F6433CCDC6C8C8B05A
84,396,355 bytes
```

M3 安装 Success，设备 base.apk 哈希与本地相同。没有清除数据或改库。正常包首次冷启动 TotalTime=9264ms；断网冷启动=6834ms，仅作设备记录，**不判定性能验收通过**。诊断入口未被正常 main 引用。

实际操作及截图：

1. [正常首页](../test/evidence/bootstrap-session-20260902/01-normal-home.png)：test03 身份、应用目录、待办区正常，无其他账号缓存。
2. 关闭 M3 Wi-Fi 和移动数据，随后确认两者为 0、`Active default network: none`。杀进程并重开，仍为 test03，没有被网络错误退出登录。[断网首页](../test/evidence/bootstrap-session-20260902/02-offline-home.png)。
3. 点击消息，再点击 test01 单聊。原有四条消息可直接读取，头像保留，同组连续消息头像位于第一条，状态显示未知而不是误报对方离线。[断网聊天](../test/evidence/bootstrap-session-20260902/04-offline-chat.png)、[列表语义证据](../test/evidence/bootstrap-session-20260902/03-offline-messages.xml)。
4. 返回后进入待办：“当前显示本机记录 / 本机暂无审批记录”，不是把断网解释为线上无待办。[断网待办](../test/evidence/bootstrap-session-20260902/05-offline-todos.png)。
5. 进入我的：test03 与所属部门保留，登录设备显示暂时无法同步，未错误显示会话失效。[断网我的](../test/evidence/bootstrap-session-20260902/06-offline-profile.png)。
6. 恢复 Wi-Fi/数据，确认新默认网络 114。没有手动点重新同步；回到待办时离线说明已消失，消息列表恢复真实“对方在线”。[恢复待办](../test/evidence/bootstrap-session-20260902/07-reconnected-todos.png)、[恢复消息](../test/evidence/bootstrap-session-20260902/08-reconnected-messages.png)。

只读数据库核对：目标单聊 `2a2ea21f-2ad6-49b3-b3da-407d1e7e4136` 的四条消息完整 ledger 前后一致，last4/read4/unread0；事件 applied=acked=203，Outbox 为空。未新增、修改业务数据。[之前](../test/evidence/bootstrap-session-20260902/device-before.json)、[之后](../test/evidence/bootstrap-session-20260902/device-final.json)。正常进程最终 PID25393，最近 1800 行日志无 FATAL/Unhandled/RenderFlex overflow 或新的 session failure。

## 4. 验证结果与未完成项

- 针对性回归 **32/32**：[日志](../test/evidence/bootstrap-session-20260902/targeted-tests.log)。
- 全量 **437/437**：[日志](../test/evidence/bootstrap-session-20260902/full-tests.log)。
- 静态检查 0 问题：[日志](../test/evidence/bootstrap-session-20260902/analyze-final.log)。
- [正常包构建](../test/evidence/bootstrap-session-20260902/build-final.log)成功，第三方插件 Built-in Kotlin 迁移警告仍在，不算业务缺陷修复。

继续保留：M1 原因未明的 401、新环境自动续期实测、其他仓库异步归属、服务端未打开群却清未读 P1、群事件缺失、历史媒体/附件 500、真机新版回归、桌面 D2/真实窗口、完整高级 OA 与性能验收。整体目标继续进行，不标完成。
