# 832 · 移动端同步状态真实化与真机复验

日期：2026-09-09（Asia/Shanghai）  
设备：realme RMX3366，Android 14

## 发现

首次启动时 IM bootstrap 曾短暂失败，事件同步循环已立即开始重试，但账户安全页在整个 25 秒长轮询期间仍显示“已登录·同步中断”。同一时段运行日志已经显示心跳 204、IM/OA 游标健康，因此该文案会把主动重试误报为持续故障。

## 修复

- bootstrap 失败后进入事件循环前把状态切换为“同步中”。
- 运行中遇到网络或服务端临时错误时，仅在 3 秒退避窗口显示“同步中断”；下一轮请求发出前切换为“同步中”。
- 成功拉取后仍切换为可用，并根据真实 Presence 显示“在线/离线”；不根据本机网络接口猜测服务端健康。
- `401` 与 `session_replaced` 的会话处理规则保持不变。

## 证据

- 真机日志：心跳状态 204，IM `appliedSequence` 与 `acknowledgedSequence` 均为 6104、无待 ACK，OA 游标 1614 且无待提交命令或通知已读。
- 冷启动后账户安全页显示“已登录·在线”。
- [冷启动截图](../test/evidence/main-tabs-20260909/real-device-account-security-cold-retry.png)
- [冷启动布局树](../test/evidence/main-tabs-20260909/real-device-account-security-cold-retry.xml)
- 同步生命周期与账户安全定向回归 18/18 通过，相关静态检查 0 issue。
- 全量 Flutter 回归 1421/1421 通过。
- Profile APK 已覆盖安装真机，SHA-256 `1398696D1EAA0CF6060C97644977C0725FD0C862E2483B2C7050373D4BF2D213`。

## 边界

当前电脑控制接口没有返回 Windows v1.0.105 客户端窗口，本轮没有把桌面可见窗口状态作为通过证据。厂商后台推送、iOS 真机和真实 M2 替换 M1 仍未完成。
