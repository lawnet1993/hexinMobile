# 移动端当前构建 realme 真机锁屏启动复验（2026-09-06）

## 结论

当前 Profile APK 已在 realme RMX3366 真机保留数据覆盖安装成功。锁屏状态冷启动后，安全会话恢复、Shell 首帧和协同同步请求均完成，没有出现登录失效、会话替换、崩溃、ANR 或 OOM；但 App 处于锁屏后台生命周期，一个完整长轮询观察窗口内没有产生完成的 IM 同步阶段。

系统当前明确拒绝通知权限，因此本轮不能判定锁屏系统通知、厂商推送唤醒或点击通知定位通过。客户端没有在已经拒绝后反复申请权限，符合“拒绝后由用户去设置开启”的交互要求。

## 当前构建

- APK：`app-profile.apk`，68.7 MiB。
- SHA-256：`F2F0B74578EE5C7956A66D97EC9A16040959A740515F30EC12D84EC3F58BAD4C`。
- 安装方式：保留应用数据覆盖安装。
- 设备状态：锁屏、Dozing；没有尝试绕过或自动解除锁屏。

## 锁屏启动证据

冷启动并观察 15 秒：

- 目标进程存活；
- `secureSessionHydrated=true`；
- `shellFirstFrame=true`；
- `collaborationSyncRequested=true`；
- 登录失效/会话替换命中 0；
- Fatal/ANR/OOM 命中 0。

继续跨过一个完整 25 秒长轮询窗口后，进程仍存活，但 `MOBILE_IM_SYNC_STAGE` 仍为 0。这里说明锁屏后台没有执行常驻拉取，不能把“请求过同步”写成“锁屏消息已经到达”。锁屏消息应由系统推送负责唤醒，再进入事件同步和定位流程。

## 通知权限

Android 当前状态：

- `POST_NOTIFICATIONS`：`granted=false`；
- AppOp：`POST_NOTIFICATION=ignore`。

移动端现有行为：

- 首次未决定时才请求系统权限；
- 已拒绝时不重复弹系统申请；
- 通知设置页显示“已关闭”，由用户点击“去设置”；
- App 恢复前台后重新读取权限状态；
- 没有推送令牌时显示通道未完成，不能宣称厂商推送可用。

## 后续真机验收步骤

1. 用户解锁设备并在系统设置中开启通知权限；该权限不由自动化替用户修改。
2. 前台打开一次 App，确认通知设置页变为“已开启”并完成推送令牌注册。
3. 锁屏并停止 App 进程，使用另一测试账号发送一条 `AI-UAT-` 单聊和一条 OA 通知。
4. 验证系统通知只出现一次，通知正文遵循当前隐私模式。
5. 点击通知后先同步，再定位到对应会话/审批和具体消息；未读数与 SQLite 游标一致。
6. 重复覆盖弱网、Doze、重启 App、令牌轮换和前台同时收到推送/事件的去重。

## 证据

- [锁屏冷启动摘要](../test/evidence/realme-current-build-locked-startup-20260906.json)
- [启动与会话恢复诊断](../test/evidence/realme-current-build-locked-diagnostics-20260906.json)
- [完整长轮询窗口后的诊断](../test/evidence/realme-current-build-locked-after-longpoll-20260906.json)
- [系统通知权限状态](../test/evidence/realme-current-build-notification-permission-20260906.json)
- [此前锁屏会话追平测试](772-mobile-locked-device-session-catchup-20260906.md)
- [系统通知权限实现与边界](763-mobile-system-notification-permission-20260906.md)

## 证据限制

- 本轮只证明锁屏冷启动的自动登录恢复和进程稳定性，不证明系统推送到达。
- 设备未解锁，不能用于当前构建的点击、键盘、返回手势、安全区和可访问性验收。
- 当前桌面客户端位于无影云桌面；本轮电脑控制通道连续两次获取该标签超时，因此没有把历史桌面截图当作当前版本对照证据。
