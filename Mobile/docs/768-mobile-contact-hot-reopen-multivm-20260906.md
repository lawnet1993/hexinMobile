# 768 · 三模拟器联系人进入会话重复打开与 OA 退回候选复验

日期：2026-09-06，Asia/Shanghai。

结论：**三台模拟器累计 40/40 次“点联系人头像进入单聊、一次返回通讯录”通过，热打开使用内存消息窗口，进程未重启且内存峰值后回落；三模拟器并发压力下仍观测到一次 846.6 ms 冷开栅格长帧，性能仅部分通过。OA 退回仍无服务端授权样本。**

## 联系人进入会话

| 设备 / 账号 | 目标 | UI 循环 | 进程 | PSS（前 / 峰值 / 后） |
| --- | --- | ---: | --- | --- |
| emulator-5554 / test02 | Test Terminal 01 | 10/10 | 同一 PID | 169.5 / 191.3 / 178.0 MiB |
| emulator-5556 / test03 | Test Terminal 01 | 20/20 | 同一 PID | 180.9 / 203.3 / 196.5 MiB |
| emulator-5558 / test04 | Test Terminal 03 | 10/10 | 同一 PID | 175.1 / 176.6 / 176.6 MiB |

每次循环都通过新的 UI hierarchy 核对：头像入口存在、目标单聊已打开、Android 返回一次即回到通讯录。没有发送消息、创建联系人或修改业务数据。脚本现支持受校验的 `Serial` 与 `ContactName`，可继续扩展到新 AVD。

## Profile 时延

| 设备 | 样本 / 缓存命中 | route mounted P50 | 消息可用 P50 | 最新消息布局 P50 / P95 | 首帧 P50 / P95 |
| --- | --- | ---: | ---: | ---: | ---: |
| emulator-5554 | 10 / 9 | 11.3 ms | 11.3 ms | 182.0 / 846.6 ms | 19.5 / 23.0 ms |
| emulator-5556 | 19 / 19 | 15.9 ms | 15.9 ms | 138.0 / 246.5 ms | 20.0 / 56.8 ms |
| emulator-5558 | 10 / 9 | 13.1 ms | 13.2 ms | 47.1 / 217.8 ms | 13.5 / 17.9 ms |

test02 首次冷开不是网络等待：80 条消息在 94.6 ms 可用，但最大栅格帧为 623.6 ms，最新一条到 846.6 ms 才完成布局。当时三台 AVD 同时运行且各进程已有 33–55 MiB Swap PSS，因此不能把该单点直接判为真机常态；也不能据此判定性能完全通过。

尝试把首批消息窗口从 80 降为 40 后，未读定位、可见已读与连续向上分页相关回归出现 9 项失败。该改动已撤销，不能以缩减功能换取指标；恢复后聊天、窗口保留和联系人导航 114/114 通过。

## OA 退回

使用当前 Windows test01 会话只读检查测试服：`all` 28 条、`pending` 3 条，共 28 个唯一申请详情；动作包含 approve、reject、transfer、add_sign、remind、withdraw，`return` 候选仍为 0。移动端继续严格服从 `allowedActions`，不伪造“退回”按钮，也不绕过服务端权限调用。

## 证据

- [结构化汇总](../test/evidence/contact-reopen-20260906-082100/result.json)
- [test02 10 次 UI 循环](../test/evidence/contact-reopen-20260906-082100/test02-contact-reopen-10.json)
- [test03 20 次 UI 循环](../test/evidence/contact-reopen-20260906-082100/test03-contact-reopen-20.json)
- [test04 10 次 UI 循环](../test/evidence/contact-reopen-20260906-082100/test04-contact-reopen-10.json)
- [test02 Profile 明细](../test/evidence/contact-reopen-20260906-082100/test02-chat-open-timings.json)
- [test03 Profile 明细](../test/evidence/contact-reopen-20260906-082100/test03-chat-open-timings.json)
- [test04 Profile 明细](../test/evidence/contact-reopen-20260906-082100/test04-chat-open-timings.json)

## 下一验收边界

1. 真机解锁后，在单设备和三模拟器并发两种宿主负载下各做冷开/热开对照，要求消息可用、最新消息布局、首帧和 raster 都有证据。
2. 如果真机仍出现超过 500 ms 的 raster 长帧，再使用 Flutter timeline 定位具体头像、媒体缩略图或末尾定位帧，不能仅凭 ADB 点击耗时修改消息语义。
3. 后台发布明确返回 `allowedActions=return` 的 AI-UAT 流程后，真实执行退回并核对原节点、目标节点、通知和历史。

单模拟器 SwiftShader 与宿主 RTX 4070 GPU 的控制变量复验见 [769](769-mobile-chat-renderer-isolation-20260906.md)：同一 80 条消息窗口的冷开最新消息布局由 719.0 ms 降至 122.8 ms，证明软件渲染显著放大了此前长帧；真机结论仍未替代。
