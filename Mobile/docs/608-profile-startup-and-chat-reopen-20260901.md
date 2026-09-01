# 608 · Profile 冷启动与会话重开性能核查

时间：2026-09-01

## 结论

- 使用 1080×2400 Android 36 x86_64 模拟器和 Flutter Profile Demo 包重复实测，不把 Debug/JIT 启动延迟当作生产结果。
- 三次强制停止后的冷启动分别为 6829ms、6221ms、3783ms；每次都出现一条 Choreographer 跳帧事件，分别跳过 116、245、67 帧。模拟器冷启动目前不能判定通过。
- 将应用切到后台再返回的三次热启动为 1074ms、730ms、372ms，没有 Choreographer 跳帧事件。
- 随后连续执行 20 次“返回消息列表 → 打开唐泽单聊”，包含文件、图片、视频预览和新增回执入口，跳帧事件 0、关键异常 0。
- 连续重开前后 PSS 从 171180KB 回落到 111861KB，Activity 保持单实例；没有观察到会话重开导致的持续内存增长。

## 代码边界

- `main()` 在 `runApp` 前只做 Flutter binding、图片缓存上限和一个空实现的 `SecureTunnel.registerWith()`，没有等待网络、数据库或协作同步。
- MobileShell 的设备授权、推送、在线状态、IM、OA、安全通道、更新和巡检同步均由首帧后的回调触发，没有加入首帧阻塞。
- 本轮没有为了改善模拟器冷启动数字而删减真实初始化或改成假数据。热返回和会话重开已经满足当前可测性能边界；冷启动需在解锁后的 realme Profile 包上用相同口径复测后再决定是否做原生启动优化。
- Android `gfxinfo` 没有为 Flutter Surface 返回有效帧总数，因此没有用无效的 `0 frames` 结果宣称流畅；报告只采用 `am start -W`、Choreographer、PSS/RSS 和关键异常。

证据：

- `docs/evidence/608-profile-startup-and-chat-reopen/01-profile-startup-workbench.png`
- `docs/evidence/608-profile-startup-and-chat-reopen/02-profile-chat-after-reopen.png`
- `docs/evidence/608-profile-startup-and-chat-reopen/03-profile-metrics.txt`

## 构建状态

- 性能测量使用独立 x86_64 Profile Demo 包，仅安装到模拟器。
- 测量完成后已把 `build/app/outputs/flutter-apk/app-profile.apk` 恢复为第 607 轮生产包：79,725,862 bytes，SHA-256 `5DCBE76222776DAE208C75D273D1CCF2C06920A3B154E140161E83CBB9844CBB`。
- realme 上已安装并校验的仍是同一生产包；真机继续处于系统锁屏，本轮未绕过锁屏。
