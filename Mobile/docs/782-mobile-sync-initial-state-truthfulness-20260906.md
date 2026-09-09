# 782 · 移动端同步初始状态真实性与升级回归

> 日期：2026-09-06  
> 结论：已修正 IM 同步状态在链路尚未证明健康前就默认显示“实时可用”的问题。新安装包会先进入“正在连接”，只有同步协调器确认传输成功后才标记为可用。两台 Android 模拟器保留数据升级、冷启动、自动登录及 IM/OA 前台同步均通过；锁屏真机后台唤醒仍未通过。

## 修正内容

- `ImRealtimeAvailabilityController` 的初始值从 `available` 改为 `connecting`，与 OA 的初始语义保持一致。
- 单元测试直接断言：同步链路尚未证明健康时不能先显示实时可用。
- 依赖在线状态的联系人/在线一致性测试改为显式注入 `available`，不再通过错误的生产默认值隐式成立。
- 连接成功后的既有界面与行为不变；本次修正只消除冷启动及恢复同步窗口中的虚假“实时同步/在线”状态。

## 自动化验证

- 状态与相关定向测试：37/37 通过。
- 联系人/在线状态夹具回归：40/40 通过。
- Flutter 全量测试：1405/1405 通过。
- Profile APK 构建成功，大小 111,236,918 字节。
- SHA-256：`86F896B5964F498BA479628FBACE7F124E22BDE246A3997DF2E5885C71656FB7`。

## 双模拟器升级与冷启动

Profile 包使用 `adb install -r` 升级，保留账号和本地数据库。

| 设备 | 安装 | 冷启动 | 登录态 | heartbeat | IM | OA |
| --- | --- | ---: | --- | ---: | --- | --- |
| emulator-5556 | Success | 3266 ms | 保留 | 204 | 4616/4616，pending ACK=0，healthy | sequence=743，pending=0，healthy |
| emulator-5558 | Success | 2846 ms | 保留 | 204 | 4628/4628，pending ACK=0，healthy | sequence=821，pending=0，healthy |

两台设备的 `MainActivity` 均为前台 resumed 状态；筛查日志未发现 FATAL、ANR、OOM 或 `E/flutter`。

## 真机后台边界

realme 真机仍已连接且应用进程存活，但当前为锁屏、`Dozing`。由于 USB 供电环境下 `deviceidle deep` 仍为 `ACTIVE`，这不是可用于验收的深度 Doze 样本；本轮也没有捕获到新的后台 heartbeat 或推送唤醒证据。

因此以下项目继续保持未通过：

- 锁屏/深度 Doze 下的厂商推送唤醒；
- 进程被系统回收后的通知唤醒、同步追平和消息定位；
- iOS APNs 前后台与杀进程验收。

不能使用前台模拟器的长轮询健康结果替代这些真实设备边界。

## 证据

- [结构化验证结果](../test/evidence/main-shell-touch-targets-20260906-1510/sync-initial-state-result.json)
- [上一轮自动登录、断网恢复与 Profile 页面实测](781-mobile-profile-session-offline-recovery-20260906.md)

