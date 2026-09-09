# 769 · 联系人进入单聊的渲染器隔离复验

日期：2026-09-06，Asia/Shanghai。

结论：**同一 AVD、同一 test02 登录态、同一 Test Terminal 01 会话、同一 80 条消息窗口，在宿主 GPU 下冷开最新消息完成布局为 122.8 ms，20 次热开 P50/P95 为 80.2/102.1 ms；此前 719.0 ms 冷开主要由 SwiftShader 软件渲染放大，不是网络重复请求、头像重复解码或会话进程重启。真机未解锁，因此最终性能仍为部分通过。**

## 控制变量

- 设备：`emulator-5554` / `Medium_Phone_API_36.0`，Android 16。
- 账号：test02；目标：Test Terminal 01 单聊。
- 两轮均保留应用数据和 SQLite，不切账号、不发送消息、不修改业务数据。
- 两轮均先强制停止应用得到一次进程冷启动，再从默认折叠的组织通讯录展开公司总部、点击联系人头像进入单聊，随后执行 20 次“头像进入 / 单次返回”。
- 消息窗口保持 80 条，未修改未读定位、已读判定和向上自动分页语义。
- 每次打开与返回均由新的 Android UI hierarchy 验证，20/20 成功且热循环保持同一 PID。

## 对照结果

| 指标 | SwiftShader | 宿主 RTX 4070 GPU |
| --- | ---: | ---: |
| 冷开 route mounted | 10.6 ms | 6.0 ms |
| 冷开消息可用 | 54.8 ms | 35.5 ms |
| 冷开最新消息完成布局 | 719.0 ms | 122.8 ms |
| 冷开首帧 | 20.6 ms | 11.2 ms |
| 冷开最大 Build | 46.8 ms | 17.4 ms |
| 冷开最大 Raster | 551.6 ms | 33.8 ms |
| 热开消息可用 P50 / P95 | 13.7 / 22.6 ms | 12.1 / 19.2 ms |
| 热开最新消息布局 P50 / P95 | 171.3 / 252.3 ms | 80.2 / 102.1 ms |
| 热开首帧 P50 / P95 | 17.6 / 21.4 ms | 11.2 / 14.2 ms |
| 每次热开最大 Raster 的 P50 / P95 | 75.2 / 89.0 ms | 17.9 / 25.9 ms |

SurfaceFlinger 明确报告软件组使用 `Google SwiftShader`，宿主组使用 `NVIDIA GeForce RTX 4070 Laptop GPU`。宿主 GPU 把冷开最新消息布局缩短约 82.9%，最大 Raster 缩短约 93.9%。消息可用时间两组都很短，因此瓶颈不在 HTTP/SQLite 取数。

## 代码核对

- 头像数据 URL 只在首次遇到时做 Base64 解码，之后使用有上限的 64 项缓存；实际解码尺寸按头像物理像素分桶，不会把原始大图重复全尺寸解码。
- 聊天消息使用 `ListView.builder` 懒构建；同发送者连续消息仅在第一条保留头像，当前截图已证明重复头像没有重新出现。
- 首次打开仍要把普通方向的可变高度消息列表定位到末尾；这一段在软件 GPU 下会放大为多次布局/栅格帧。把 80 条窗口降为 40 会破坏未读和历史分页测试，已经撤销。

本轮不直接把消息列表改成反向列表：这会同时改变向上分页、未读锚点、可见已读、附件高度变化与新增消息定位，必须作为独立重构并用真机 timeline 和现有语义矩阵验证，不能用模拟器单点数据冒险替换。

## 证据

- [结构化对照](../test/evidence/contact-host-gpu-20260906-090000/result.json)
- [宿主 GPU 冷开页面层级](../test/evidence/contact-host-gpu-20260906-090000/host-cold-chat.xml)
- [宿主 GPU 最终聊天截图](../test/evidence/contact-host-gpu-20260906-090000/host-final-chat.png)
- [宿主 GPU 20 次 UI 循环](../test/evidence/contact-host-gpu-20260906-090000/test02-host-gpu-hot-reopen-20.json)
- [宿主 GPU Profile 明细](../test/evidence/contact-host-gpu-20260906-090000/test02-host-gpu-chat-open-timings.json)
- [SwiftShader 20 次 UI 循环](../test/evidence/contact-single-emulator-20260906-085000/test02-hot-reopen-20.json)
- [SwiftShader Profile 明细](../test/evidence/contact-single-emulator-20260906-085000/test02-single-emulator-chat-open-timings.json)

## 尚未通过

1. realme 真机仍为锁屏状态，不能用模拟器宿主 GPU 代替真机点击联系人、首帧和 Raster 证据。
2. 宿主 GPU 的热开 P95 最大 Raster 仍为 25.9 ms，高于 60 Hz 的 16.7 ms 帧预算；虽然最新消息在 102.1 ms 内完成布局，仍需真机 timeline 判断是否可感知。
3. 三模拟器同时运行时宿主内存压力会使无头 AVD 的 System UI 无响应；这属于压测环境容量边界，不能把三台 SwiftShader AVD 的绝对帧时延当作单机产品指标。
