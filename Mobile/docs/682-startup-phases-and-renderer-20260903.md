# 682：启动分段、Flutter 帧采样与渲染器实测

## 结论

**部分通过；性能和完整 IM/OA 目标未完成。** 正常移动端 Profile 入口已取得原生启动分段和真正的 Flutter build/raster 帧数据。新增 11 项测试，全量 **786/786**，静态分析 **0 问题**，正常 Profile APK 构建、安装及设备哈希核对通过。

独立 M3 从 SwiftShader 切换到已验证的 RTX 4070 主机渲染，保留同一 AVD、APK、账号和本地数据。但冷启动仍有较大波动：普通软件渲染冷启动 4.467 秒，主机渲染两次为 7.571 / 3.458 秒。**不能选择最快一次作为“卡顿已修复”的证据，也不能把安装首启与普通冷启动混比。** 首帧等待、光栅化峰值仍存在，需要进一步定位。

本轮实质进展是补齐此前缺失的 Flutter 帧证据、修正独立模拟器启动助手，并完成同数据渲染器对照及真实导航回归，不是重复报告等待。应用图标已另行交付，本轮未擅自替换启动图标。

## 范围与环境

- 时间：2026-09-03 03:10—03:25，Asia/Shanghai；设备日志以设备时间为准。只比较同一计时器内的时长，不混算跨时区时间。
- 实际项目：`E:\SecureAccess-client-source-20260824-151204\Client\Mobile`；保留既有未提交更改，无重置、提交、推送和数据库写入。
- M3：`emulator-5556` / `SecureAccess_UAT_M3`，Android 16，1080×2400，test03；独立 AVD 位于 `E:\CodexToolchains\secureaccess-uat-avds\M3.avd`。
- 正常入口 `lib/main.dart`，Profile APK SHA-256 `3F99ABFE55BF732F4906414C5870B764E5D5DFD58256DD833B84841802A5CBB6`；切换前后 APK 一致，见[最终设备核对](../test/evidence/startup-phases-20260903/installed-host-final.json)。
- 只控制 M3；未操作 M1 真机、M2 或 Windows 窗口。当前桌面窗口仍是业务基准，本轮没有新增桌面交互证据，不以旧桌面源码推断线上功能。
- 没有清除 AVD、账号数据、网络设置、媒体队列或草稿；没有新发消息、创建会话、提交审批、修改密码。

## 实现与安全边界

1. [启动诊断](../lib/core/diagnostics/mobile_startup_diagnostics.dart)：仅 Profile 安装 `addTimingsCallback`；15 秒或 240 帧即停止并移除回调。保存 build、raster、totalSpan、vsyncOverhead 的数字摘要，p50/p95/max、超预算数量及首帧；空样本为未知而不是 0。
2. [正常入口](../lib/main.dart)：记录 Dart main、隧道注册返回、runApp 返回和首次框架帧。没有绕过认证、同步、业务初始化或更换为测试入口。
3. [Android Activity](../android/app/src/main/kotlin/com/hexing/zhilian/hexing_terminal_mobile/MainActivity.kt)：debuggable 包记录 onCreate、引擎配置、插件注册和首次 Flutter UI 显示。Release 不记录；原生命周期逻辑保留。
4. [采集助手](../scripts/inspect-startup-timings.ps1)：只读取当前 M3 进程，严格白名单提取数字字段及固定阶段；原始 logcat 只在内存中处理，不保存完整日志、调试地址或会话数据。每份证据使用新名称，失败不复用旧文件。
5. [启动助手](../scripts/start-uat-m3.ps1)：仅启动既有 M3，验证 AVD 定义和数据路径；独立目录仅传给子进程，不改系统环境。隐藏运行，不 wipe、不新建 AVD；发现已有 M3 或占用端口则拒绝重复启动。启动返回不等于开机成功，另查进程、ADB、`sys.boot_completed` 和实际 GLES。

Flutter 官方区分构建、光栅化与端到端帧跨度，不能把所有 `totalSpan > 16.67ms` 简化为 UI 构建丢帧；本报告保留各项独立统计。[FrameTiming](https://api.flutter.dev/flutter/dart-ui/FrameTiming-class.html)、[addTimingsCallback](https://api.flutter.dev/flutter/scheduler/SchedulerBinding/addTimingsCallback.html)。

## 真实测量

### 渲染器切换

- 原实际 GLES：Google SwiftShader，启动参数 `-gpu swiftshader_indirect`，见[软件渲染器](../test/evidence/startup-phases-20260903/renderer-software.txt)。
- 首次主机启动退出。再次明确捕获为 **Unknown AVD name**，原因是助手遗漏 `ANDROID_AVD_HOME`，不是 GPU 驱动崩溃。保留[失败证据](../test/evidence/startup-phases-20260903/host-launch-diagnostic.log)，补充独立目录验证和子进程环境后正常启动。
- 最终 GLES：NVIDIA GeForce RTX 4070 Laptop GPU，OpenGL ES Translator；确认开机完成，不仅依据请求的 `-gpu host` 参数，见[硬件渲染器](../test/evidence/startup-phases-20260903/renderer-host.txt)、[修正后启动记录](../test/evidence/startup-phases-20260903/host-launcher-resolved.json)。
- 仅对已核对名称的 M3 执行 `emu kill` 后原数据重启，没有停止其他 emulator/qemu。重复启动阻止实测通过，见[防重复证据](../test/evidence/startup-phases-20260903/launcher-guard.json)。

Android 官方说明 `host` 使用主机 GPU、SwiftShader 为软件渲染；软件渲染性能不能代表真机。此处配置仅是诊断环境，不是移动端生产代码优化。[官方图形加速说明](https://developer.android.com/studio/run/emulator-acceleration)。

### 冷启动与帧时间

完整字段见[可复核对照 JSON](../test/evidence/startup-phases-20260903/comparison.json)。所有请求是普通 `am start -W`，没有添加调试服务参数；普通冷启动之前执行正常应用 force-stop。

| 样本 | Android TotalTime ms | onCreate 到首个 Flutter UI ms | Flutter 采样数 | build p95 ms | raster p95 ms | raster 超 16.667ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 软件：安装后首次启动 | 11620 | 5444 | 70 | 28.876 | 101.652 | 48/70 |
| 软件：普通冷启动 | 4467 | 2818 | 48 | 29.827 | 71.600 | 19/48 |
| 主机：模拟器开机后首次启动 | 8232 | 6087 | 未完整采集 | — | — | — |
| 主机：普通冷启动 1 | 7571 | 5270 | 63 | 14.321 | 123.295 | 33/63 |
| 主机：普通冷启动 2 | 3458 | 2345 | 39 | 32.120 | 25.998 | 6/39 |

- [软件安装首启明细](../test/evidence/startup-phases-20260903/timings-01-complete.json)：Dart 首次框架帧约 99ms，但首个引擎帧 vsyncOverhead 1913ms、raster 433ms；只优化 Widget build 不能覆盖这些延迟。
- [软件普通冷启](../test/evidence/startup-phases-20260903/timings-02-software.json) 与[主机普通冷启 1](../test/evidence/startup-phases-20260903/timings-04-host-cold.json)、[主机普通冷启 2](../test/evidence/startup-phases-20260903/timings-05-host-cold.json)均有完整数字帧摘要，无无效样本、无被拒绝字段。
- 主机开机首启在 15 秒窗口结束前已重新启动，只有原生阶段，没有完整帧摘要；明确作为不完整样本排除帧对比，不补造数据。
- `am TotalTime`、原生 onCreate 计时和 Dart/Flutter 帧计时起止不同，**不能将差值直接归因于网络或操作系统**；首帧也不代表所有业务数据就绪。
- 未控制全部系统负载、文件/图形缓存和服务端耗时，样本量不足以做显著性或整机性能结论；未变更其他正在运行的设备来制造有利条件。

## 真实 UI 与数据保护

- 正常恢复 test03 工作台，见[主机渲染工作台](../test/evidence/startup-phases-20260903/05-host-ordinary-home.png)。
- 通讯录默认组织收起，展开后才出现人员，见[收起](../test/evidence/startup-phases-20260903/06-host-contacts-collapsed.png)、[展开](../test/evidence/startup-phases-20260903/07-host-contacts-expanded.png)。
- 通过头像进入已存在的 Test Terminal 01 单聊，连续 **5/5** 次“一次返回到通讯录”，进程始终 4246。每次有新鲜聊天与返回 UI hierarchy，不是仅发送坐标。见[循环记录](../test/evidence/startup-phases-20260903/host-contact-reopen.json)、[最终界面](../test/evidence/startup-phases-20260903/08-host-after-five-returns.png)。这是导航正确性证据，ADB/UI dump 的耗时不作为输入延迟或 Flutter 帧指标。
- 5 次循环 PSS 177580→199253KB、Swap PSS 5102→7598KB；未做长时收敛和大群压力测试，不能据此宣称无内存泄漏。
- IM 只读元数据核对：消息台账、群消息、原两条待发媒体的 clientMessageId/会话/类型/创建时间保持一致；applied/acked 游标仍 236。OA 原 2 份草稿、9 条回执及游标 449 保留。见[最终保护核对](../test/evidence/startup-phases-20260903/preservation-final.json)、[IM 只读快照](../test/evidence/startup-phases-20260903/im-final.json)、[OA 只读快照](../test/evidence/startup-phases-20260903/oa-final.json)。
- 媒体上传最近失败摘要仍 HTTP 500，本轮未消除服务端阻塞；原队列重试次数可以增加，不把重试次数变化误判为重复消息，也不把保留本地媒体算发送成功。

## 自动回归

- [新增诊断测试](../test/mobile_startup_diagnostics_test.dart)：11 项覆盖空样本、分位数、帧预算、样本上限、无效刷新率/时长、输出字段及非 Profile 禁用。
- [全量日志](../test/evidence/startup-phases-20260903/full-final.log)：786/786；[静态分析](../test/evidence/startup-phases-20260903/analyze-verified.log)：0；[正常构建](../test/evidence/startup-phases-20260903/build-final.log)：成功，未使用替代业务入口。
- [PowerShell 语法](../test/evidence/startup-phases-20260903/script-syntax.json)：2 个助手、0 语法错误；启动防重复实际通过。仅启动助手在构建之后修正，APK 源码未再次变化。

## 未完成与下一步

1. P2-681 慢启动仍在：需要扩大同条件样本，区分原生引擎准备、首帧等待、光栅化和业务就绪；硬件模式下单次更快不等于修复。
2. 聊天进入/滚动的分段帧与输入延迟、2000 人大群和大组织、长时内存与断网重连压力尚未完成；本轮是启动帧窗口，不冒充这些链路。
3. 当前新包真机、Windows UI 对照、多端替换/真实通知/媒体跨端、高级 OA 接收人处理和完整分支验收仍需继续。未接管所有权未确认的 M1/M2。
4. 保留既有服务端媒体 500、前加签撤回后原任务 waiting、取消通知正文错误等记录，没有绕过后端状态伪造通过。

目标继续保持活动，不把本报告的部分通过替代完整 IM/OA 交付。
