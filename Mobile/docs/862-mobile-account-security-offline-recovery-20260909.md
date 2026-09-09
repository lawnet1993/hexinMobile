# 862 · 账户与安全断网恢复实测

时间：2026-09-09（Asia/Shanghai）  
设备：Android 16 模拟器 `emulator-5556`

## 结论

- “我的”页不再暴露与移动 IM/OA 无关的站点、隧道或“网络与安全”入口。
- 账户与安全页只呈现终端账号、当前设备、登录状态和修改密码入口，没有把 TUN/站点状态当成移动端网络状态。
- 同时关闭 Wi-Fi 与移动数据后，登录状态从“已登录”变为“已登录·同步中断”；不会显示误导性的“网络不可用”，也不会清理令牌或跳回登录页。
- 恢复网络后无需用户操作，状态自动回到“已登录”。
- 恢复后的健康日志：心跳 204，IM `cursorHealth=healthy`，OA `state=healthy`，待 ACK、待命令和待通知已读队列均为 0。

## 运行证据

- `test/evidence/account-security-offline-recovery-20260909/account-security-offline.png`
- `test/evidence/account-security-offline-recovery-20260909/account-security-recovered.png`

## 边界

- 本次是前台断网/恢复；锁屏后台厂商推送、Doze 唤醒和 iOS 网络切换仍不在通过范围内。
