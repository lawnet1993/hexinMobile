# 670 移动端到期前续期与会话保护

日期：2026-09-02，Asia/Shanghai。本轮为 progress：修复主动续期缺口，完成定向/全量回归和独立模拟器真实刷新链路。**整体目标仍未完成；自然到期后的无感续期没有判定通过。**

## 事实与边界

- 669 已记录真实心跳 401 → 刷新 401 → 回到登录页，发生在原访问令牌到期提示附近；其服务端拒绝原因仍不明确。
- 660 实测访问令牌到期前刷新成功。修改前移动端只有收到 401 后才尝试刷新，没有提前续期；新增用例实际复现 `refreshCalls=0`，[修改前日志](../test/evidence/session-protocol-20260902/proactive-before.log)。
- 本轮读取的是已安装 Windows 1.0.87 的受保护 test01 会话，IM/OA bootstrap 均 200；不是旧源码，也不是桌面窗口操作。当前桌面令牌未验签时间提示为 nbf=15:28:57Z、exp=17:28:57Z，不能据此断言桌面的具体刷新算法。[只读核对](../test/evidence/session-protocol-20260902/desktop-health-corrected.json)。
- 只读脚本第一份结果错误地把时间标记为 unavailable：PowerShell 参数 `$Value` 与局部 `$value` 不区分大小写，导致数字被转换为字符串。已改名 `$claimValue`，补充数字、opaque、白名单和语法检查；以 corrected 文件为准，不将此脚本问题归因于业务服务。[脚本回归](../test/evidence/session-protocol-20260902/desktop-script-tests.json)。

## 实现

- AuthController 新增 `maintainSession`，由正常心跳在恢复登录、前台恢复及每 30 秒运行前调用。
- 对系统安全存储中的访问令牌，仅解析受限长度、有限范围的整数 exp，提前 5 分钟尝试现有 `/connect/token` 协议；解析结果只用于调度，不能代替服务端认证，也不凭本地时间退出登录。opaque/缺失 exp/无刷新令牌沿用原有心跳与 401 处理。
- 与并发 401 共用同一个刷新任务，原子替换令牌后再发送心跳。网络、超时、5xx 不清会话，主动刷新重试间隔至少 30 秒。
- 主动刷新被拒绝时不立即丢弃尚可使用的访问令牌，不反复主动刷新同一令牌；真正的 401/409 session_replaced 仍走既有失效处理。
- 心跳增加停止代次与发出前会话检查，停止后的异步任务不再发心跳或处理旧失效响应。既有账号/设备/完整令牌隔离、停止同步和单次登录提示没有弱化。
- 没有改服务端协议、修改数据库、静默使用保存密码重新登录或新增刷新接口。

## 自动化

新增 [18 项主动续期测试](../test/session_proactive_refresh_test.dart)：提前边界、重复前台恢复、旧格式/opaque/空/超长令牌、无刷新凭据、过期提示、400/401 拒绝、断网/503 冷却与恢复、并发刷新、登出/重新登录/替换/停止竞争，以及数字声明边界。

- [42/42 定向](../test/evidence/session-protocol-20260902/targeted-tests.log)。
- [614/614 全量](../test/evidence/session-protocol-20260902/full-tests.log)，未更新 Golden。
- [静态检查 0 问题](../test/evidence/session-protocol-20260902/analyze-final.log)。初次检查的一处花括号风格提示已处理。
- `git diff --check` 通过；现有不相关改动保留，未提交代码、未清理工作区。

## M3 真实协议验证

仅操作独立 M3/emulator-5556、test03；M1 真机和 M2 未操作、未覆盖安装。保留 M1 可能由用户操作的边界。

显式测试入口 [session_proactive_probe.dart](../test_driver/session_proactive_probe.dart)，仅 Profile/Debug + `UAT_VERIFY_PROACTIVE=true`，限制已有 test03 与 api.sfhkh.com。它将**注入的续期判断时钟**设置到原 exp 前 4 分钟，调用真正的 presence → maintainSession → refresh → heartbeat。没有改操作系统时间、没有伪造/替换服务器令牌、没有直接写入数据库。

23:51:13 中国时间的[实际结果](../test/evidence/session-protocol-20260902/real-proactive.log)：

| 项目 | 结果 |
| --- | --- |
| 原访问令牌提示 | nbf=15:40:19Z，exp=17:40:19Z |
| 仅调度时钟 | 17:36:19Z；并非实际运行时间 |
| 真实刷新接口 | HTTP 200，访问/刷新令牌均旋转 |
| 账号与设备归属 | 保持不变 |
| 随后心跳 | HTTP 204，使用更新后的令牌 |
| 再次检查 | 不重复刷新，顺序 refresh → heartbeat → heartbeat |
| 会话与提示 | 会话保留、无登录失效提示 |
| 新访问令牌提示 | nbf=15:51:13Z，exp=17:51:13Z |

测试入口包 SHA256：`165A3A4DD86BB55E29AB62CBE36F09DF7D30675580DEF8D0F3C3CEA7BDF6D2F9`。

这证明真实协议与到期前调度分支能够协同工作，**不等同于等待两小时自然到期的验收**。如果没有再次旋转令牌且应用运行，普通包下一次预计进入主动刷新窗口为 2026-09-03 01:46:13 中国时间，原 exp 为 01:51:13；仍须实际观察，不能提前记为通过。

探针运行后自动进入正常首页，test03、通知未读 7 不变。只读 OA 元数据对照：两条草稿 ID/更新时间完全一致，两个已读回执仍 sent，Outbox 为空。日志只输出白名单元数据，未记录密码、完整令牌、指纹或附件地址。

## 普通包复验

随后重新构建 `lib/main.dart` 普通 Profile 包并覆盖安装 M3，未清数据：

```
Profile / Android arm64 + x64 / 1.0.1+2
84,396,355 bytes
SHA256 654A7A01A028CE96C6F0371CF9484565B21FE99AB5361B9956E0B6EC38947EE5
```

设备 `base.apk` 哈希一致；冷启动 TotalTime=7,871ms，仅记录，未视为性能通过。正常首页 test03 和未读 7 保留，消息列表及草稿箱真实打开正常。进入既有加班草稿后，事由 `AI-UAT-20260902-232100-FORM-INTERACTION_LATEST-232400`、开始时间和流程保持；返回后两条草稿 ID/更新时间仍完全不变，未产生保存、提交或 Outbox 数据。[草稿 UI](../test/evidence/session-protocol-20260902/11-draft-open.xml)、[最终 OA 元数据](../test/evidence/session-protocol-20260902/oa-final.json)。

使用正常 UI 向 test01 单聊发送本轮唯一新业务数据 `AI-UAT-20260902-235400-PROACTIVE`：

| 字段 | 值 |
| --- | --- |
| 会话类型/ID | direct / `2a2ea21f-2ad6-49b3-b3da-407d1e7e4136` |
| 服务端消息 ID | `a8b658fb-c983-4f4f-92e7-5196528ae4fb` |
| clientMessageId | `441e5fa7-a85c-48ac-9ecb-35eb3fdad5f8` |
| 消息序号 | 6 |
| 服务端时间 | 2026-09-02T15:54:49.857999Z |
| 移动端 | 唯一、sent、Outbox 空、last/read=6、unread=0、事件 applied/acked=207 |
| D1 只读接口 | bootstrap/sync/history 均 200；同一 ID/client ID/seq 唯一；test01 last=6、read=4、unread=2 |

[正常包截图](../test/evidence/session-protocol-20260902/07-sent.png)、[移动端 SQLite 元数据](../test/evidence/session-protocol-20260902/im-after-send.json)、[桌面端会话只读核对](../test/evidence/session-protocol-20260902/desktop-after-send.json)。D1 证据来自安装客户端受保护会话的只读 API，不是控制桌面窗口。

本轮同时捕获一个尚未处理的真实状态差异：消息列表同一 test01 显示“对方在线”，点入聊天页却显示“离线 · 09-02 15:45”，返回列表仍是在线。[列表进入前](../test/evidence/session-protocol-20260902/04-messages.xml)、[聊天页](../test/evidence/session-protocol-20260902/05-chat.xml)、[返回列表](../test/evidence/session-protocol-20260902/08-list-return.xml)。不能把它记为真实在线状态通过；后续需核对列表实时事件投影、资料状态来源和桌面心跳，不能靠 UI 猜测。

最近 1,800 行过滤无 FATAL、`E/flutter` 或 `MOBILE_SESSION_AUTH`；最终停在草稿箱，网络未改变。[最终错误检查](../test/evidence/session-protocol-20260902/final-errors.json)。

## 未完成

自然经过到期窗口的自动续期、长时间离线后刷新拒绝原因、真机新版验收、当前桌面 UI 与 D2/M2 完整互斥矩阵、高级 OA 分支/权限/会签、系统推送、较大规模性能，以及已记录的服务端群消息/未读 P1、旧附件 500 仍保留。没有将本轮的单链路通过等同于 IM/OA 全面验收。
