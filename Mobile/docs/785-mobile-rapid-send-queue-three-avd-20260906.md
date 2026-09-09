# 785 · 连续发送队列与三 AVD 并发实测

> 日期：2026-09-06，Asia/Shanghai。结论：修复“上一条发送未完成时后续点击被吞、文本累积在输入框”的问题；修复后三台 AVD 在双发送端 10+10 条并发下完整性、去重、顺序、未读和游标均通过。未打开会话的接收端仍出现约 13.2 秒事件年龄长尾，实时及时性保持部分通过。

## 真实发现与修复

- test02 与 test04 同时在 `AI-UAT-MULTIVM-20260906-1100` 群发送，test03 停留在会话列表。
- 修复前，test04 的 10 条全部提交；test02 的 10 次发送点击发生在 `_sending=true` 期间，被页面直接忽略，多段测试文本留在同一个草稿中。三端都只收到 test04 的 10 条。
- 根因是聊天页用一个网络请求级 `_sending` 锁禁用发送，输入框仍可继续录入；不是消息丢失或 SQLite 投影错误。
- 改为页面内 FIFO 发送队列：每次点击同步快照并清空当前输入，普通发送与失败草稿重试共用队列；队列有待发项时持续显示进度，但发送按钮仍允许下一条入队。
- 空输入和真正的重复点击仍不会产生消息；每条消息继续使用原有稳定 `clientMessageId`、Repository 与 Outbox。

## 修复后实测

test02、test04 各发送 10 条。两端 journal 均显示最后一条可见、输入框为空。

| 项目 | test02 | test03（未打开群） | test04 |
| --- | ---: | ---: | ---: |
| 最终消息数 | 126/126 | 126/126 | 126/126 |
| sender 分布 | 35 / 41 / 50 | 35 / 41 / 50 | 35 / 41 / 50 |
| ID / sender+client ID 唯一 | 126 / 126 | 126 / 126 | 126 / 126 |
| 序号 | 1..126 连续 | 1..126 连续 | 1..126 连续 |
| 未读 | 0 | 30 | 0 |
| Outbox / SQLite | 0 / ok | 0 / ok | 0 / ok |
| 事件游标 | applied=acked | applied=acked | applied=acked |

三台 PID 范围日志均未发现 FATAL、ANR 或 OOM。

## 及时性

| 设备 | 含事件数 | commit P95 | total 最大 | oldest event age 最大 |
| --- | ---: | ---: | ---: | ---: |
| test02 / emulator-5554 | 26 | 247 ms | 2,594 ms | 284 ms |
| test03 / emulator-5556 | 21 | 247 ms | 15,146 ms | 13,159 ms |
| test04 / emulator-5558 | 31 | 130 ms | 5,407 ms | 2,158 ms |

test03 最终完整追平，但其未打开会话场景出现 13 秒级事件年龄，故不能以最终一致性冒充实时 SLA 已通过。本地提交 P95 仅 247 ms，长尾主要发生在事件返回前，仍需结合服务端长轮询唤醒与网关日志排查。

## 自动化

- composer 专项：12/12 通过。
- 完整聊天页：97/97 通过。
- 全量 Flutter 测试：1405/1405 通过。
- `flutter analyze --no-fatal-infos`：0 error、0 warning，仅 7 条已有风格 info。
- Profile APK SHA-256：`599237F6F0252DA8897150E8662CDC3B2EDE0C55D16F41DA6CAF4455C1873E04`。

## 证据

- [结构化结果](../test/evidence/multivm-three-client-20260906-1320/result.json)
- [test02 修复后发送 journal](../test/evidence/multivm-three-client-20260906-1320/m1-fixed.json)
- [test04 修复后发送 journal](../test/evidence/multivm-three-client-20260906-1320/m3-fixed.json)
- [修复前残留草稿画面](../test/evidence/multivm-three-client-20260906-1320/m1-stuck-composer.png)
- [test02 修复后连续发送与空输入框](../test/evidence/multivm-three-client-20260906-1320/test02-fixed-chat.png)
- [test03 未打开会话时真实未读 30](../test/evidence/multivm-three-client-20260906-1320/test03-unopened-list.png)
- [test04 修复后连续发送与空输入框](../test/evidence/multivm-three-client-20260906-1320/test04-fixed-chat.png)
- 三端最终 SQLite 摘要：`test02-fixed-db.json`、`test03-fixed-db.json`、`test04-fixed-db.json`。
