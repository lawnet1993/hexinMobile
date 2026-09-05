# 746 · 最新媒体改造 Profile 真机性能复测

日期：2026-09-05（Asia/Shanghai）  
设备：realme RMX3366，Android 14，1080×2400  
构建：正常 `lib/main.dart`，arm64 Profile，1.0.1+2

## 结论

本轮通过。最新图片/视频说明、用户点击后下载、下载进度、视频端内播放和音频内联播放改动，在正常 Profile 包上没有造成可观测的冷启动或短时媒体重开退化。

这不是完整性能目标通过：当前只覆盖 10 条消息的真实单聊、10 次视频重开和短时断网；510+ 真实长历史、30 分钟内存曲线、未缓存大视频的 Range/取消恢复、iOS 真机和厂商推送仍保留为未完成。

## 构建与安装

- Profile APK：`build/app/outputs/flutter-apk/app-profile.apk`
- 大小：69,497,080 bytes
- SHA-256：`A10778EEFBAE4BD19061582DA9D792EA821828F58F00E5BC7B80C33550DB0E65`
- `adb install -r` 成功；没有清应用数据，原 Test Terminal 01 登录态、IM 消息和 OA 数据均保留。
- 最终包移除了工作台启动时对 TUN/托管浏览器运行态的自动同步；站点页面仍保留显式网络能力，IM/OA 启动不再依赖 TUN。
- 构建日志：[build-profile.log](../test/evidence/mobile-profile-performance-20260905/build-profile.log)

## 冷启动

每轮执行正常 `am force-stop` 后以 `am start -W` 启动真实 `MainActivity`，不跳过登录恢复、IM、OA 或后台同步初始化。

| 轮次 | LaunchState | TotalTime | WaitTime |
| ---: | --- | ---: | ---: |
| 1 | COLD | 714 ms | 719 ms |
| 2 | COLD | 700 ms | 705 ms |
| 3 | COLD | 709 ms | 714 ms |
| 4 | COLD | 700 ms | 705 ms |
| 5 | COLD | 685 ms | 690 ms |

中位数 700 ms，最大值 714 ms。最终包完整数据：[cold-start-after-tunnel-removal.json](../test/evidence/mobile-profile-performance-20260905/cold-start-after-tunnel-removal.json)，最终页面：[01-cold-start-final.png](../test/evidence/mobile-profile-performance-20260905/01-cold-start-final.png)。

## 通讯录头像进入会话

真实入口为“通讯录 → 公司总部 → Test Terminal 02 头像”，使用 Profile 模式内置的脱敏分段诊断；日志只含阶段、数量和耗时，不含账号 ID、会话 ID、正文、Token 或附件地址。

- 新进程首次：消息热缓存未命中，本地 10 条消息在 59.625 ms 可用，末条消息在 107.853 ms 完成布局。
- 同进程五次热重开：消息热缓存全部命中，末条消息布局为 61.351—82.439 ms。
- 五次热重开的 raster p95 为 6.639—8.440 ms；个别完整帧超过 16.667 ms，不能据此宣称所有导航动画均为满帧。

证据：[contact-chat-first.json](../test/evidence/mobile-profile-performance-20260905/contact-chat-first.json)、[contact-chat-hot.json](../test/evidence/mobile-profile-performance-20260905/contact-chat-hot.json)、[首次 200 ms 页面](../test/evidence/mobile-profile-performance-20260905/02-contact-chat-200ms.png)、[热开 200 ms 页面](../test/evidence/mobile-profile-performance-20260905/03-contact-chat-hot-200ms.png)。

## 缓存视频与短时内存

真实 27.7 MB、5:08 视频此前已经由用户点击下载并通过大小/SHA-256 校验写入账号及环境隔离缓存。本轮 Profile 包不删除该缓存，用于验证重复打开不重新下载和播放器释放：

| 状态 | Total PSS | Total RSS |
| --- | ---: | ---: |
| 10 次循环前 | 258,906 KiB | 381,324 KiB |
| 第 2 次关闭后 | 273,052 KiB | 395,568 KiB |
| 第 5 次关闭后 | 272,729 KiB | 395,468 KiB |
| 第 10 次关闭后 | 271,707 KiB | 394,588 KiB |
| 静置 10 秒 | 259,851 KiB | 382,732 KiB |

短时峰值为 273,052 KiB；静置后较初始增加 945 KiB，没有随打开次数持续上升。本数据只能证明短时收敛，不能替代 30 分钟内存曲线。

证据：[media-reopen-memory.json](../test/evidence/mobile-profile-performance-20260905/media-reopen-memory.json)、[缓存视频播放](../test/evidence/mobile-profile-performance-20260905/04-cached-video-playing.png)。

最终 SHA-256 构建另做了一次真实缓存视频点击回归：用户点击视频卡片后进入播放器，页面同时暴露“关闭”和“暂停”语义，关键崩溃、ANR、Unhandled Exception 和 `E/flutter` 匹配 0 条。证据：[最终包缓存视频播放](../test/evidence/mobile-profile-performance-20260905/06-final-build-cached-video.png)。

## 真实断网

先读取真机原始网络状态，再临时关闭 Wi-Fi 和移动数据；完成后在 `finally` 中恢复为原状态（Wi-Fi 关闭、移动数据开启）。

- 断网冷启动仍进入 Test Terminal 01 工作台，没有跳回登录页。
- 已缓存视频在断网状态下仍可进入端内播放器。
- 应用进程关键崩溃、ANR、Unhandled Exception 和 `E/flutter` 匹配 0 条。
- 该用例没有证明未缓存视频的断点续传；服务端单段 Range 仍返回 500，详见 744 报告。

证据：[offline-recovery.json](../test/evidence/mobile-profile-performance-20260905/offline-recovery.json)、[断网缓存视频](../test/evidence/mobile-profile-performance-20260905/05-offline-cached-video.png)。

## 自动化与数据边界

- 聊天页完整组件回归：97/97 通过。
- 离线媒体下载进度回调 Repository 用例：通过。
- 本轮组合执行聊天页与离线媒体 Repository 回归：102/102 通过。
- 本轮没有清账号数据、删除消息、修改 OA 业务数据或直接写数据库。
- 为强制验证未缓存视频进度，前一轮只清除了一条可重新下载的临时播放缓存；验证完成后缓存由正常下载恢复。
- 真机音频用现有 `AI-UAT-offline-audio.wav` 执行发送与内联播放；未使用的临时 M4A 已从电脑构建目录和手机 Downloads 删除。

## 未完成与外部阻塞

1. 当前真实会话只有 10 条消息；需补 510+ 真实历史持续上滑、首条未读定位、图片/视频混合消息和内存曲线。
2. 需运行不少于 30 分钟的前后台、会话切换、媒体打开和空闲组合采样，验证最终 PSS/RSS 收敛。
3. 服务端附件预览单段 Range 返回 500，当前只能“点击 → 显示完整下载进度 → 校验 → 播放”，不能判定边下边播、取消或断点恢复通过。
4. Windows v1.0.91 入站实时事件消费仍需桌面/Gateway 修复；移动端不能用重复轮询掩盖。
5. 厂商推送 SDK、合法 provider token、后台/杀进程投递和 iOS 真机仍未验收。
