# 842 · 2 GB Android 长群聊反复打开内存压力样本

时间：2026-09-09（Asia/Shanghai）  
环境：Android 16、约 2 GB RAM 模拟器；当前 Profile APK  
账号：测试账号（不记录密码、令牌或设备标识）

## 操作

- 从工作台进入消息列表和既有长群聊。
- 连续执行 30 轮：群聊内上下滚动、返回消息列表、重新打开同一群聊。
- 每轮读取应用 PID、TOTAL PSS、TOTAL RSS 和 Swap PSS。
- 完成后再次等待内存整理并检查页面、进程和登录态。

## 结果

- 应用 PID 30 轮始终为同一值，未发生崩溃或系统重启进程。
- 第 1 轮 TOTAL PSS：172,881 KB。
- 轮次短时最高 TOTAL PSS：182,993 KB。
- 第 30 轮 TOTAL PSS：182,188 KB。
- 完成后再次采样 TOTAL PSS：177,236 KB，证明中间对象可以回收，不是每次打开会话都永久累积。
- 最后 10 轮主要稳定在约 178–182 MB；相对首轮最大增加约 10 MB，没有呈现按轮次线性增长。
- 结束页面仍为目标群聊，群标题、成员在线数、日期分隔、群/单聊消息方向、头像聚合和输入栏正常。

## 环境干扰处理

第一次自动循环前，Android 模拟器的 Google 首次设置页抢占前台。该次循环立即终止，关闭系统引导并重新进入应用后才开始上述 30 轮有效样本；系统页面不计入应用失败或性能结果。

## 证据

- `test/evidence/main-tabs-20260909/emulator-5556-chat-reopen-soak-final.png`
- `test/evidence/main-tabs-20260909/emulator-5556-chat-reopen-soak-final.xml`

## 边界

- 本轮证明 2 GB 模拟器上短时 30 次反复进入会话没有明显线性内存泄漏，不等于 30 分钟持续聊天、视频播放或真实低端手机通过。
- Android `gfxinfo` 无法为当前 Flutter Surface 提供可靠帧样本，因此本报告不宣称帧率或逐次打开耗时达标。
- 真机联系人进入单聊的 250 ms 可见与 0 卡顿帧证据仍以 [837](837-mobile-contact-to-chat-avatar-cluster-real-device-20260909.md) 为准。
