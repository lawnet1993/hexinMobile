# 573 通知事件身份与精确去重验收

## 结论

本轮通过。真机显示的两条“在岗确认”不是同一事件重复渲染，而是服务端在不同时间生成的两个不同通知 ID；移动端保留两条是正确行为。通知投影现补充同 ID 精确去重，能够消除分页、缓存或接口重复返回造成的同一事件双行，同时不会按相同标题、正文或日期误删合法的多次巡检。

## 真实事件核对

- 类型均为 `inspection.started`。
- 两条通知 ID 不同。
- 创建时间分别为 `2026-08-29 23:00:42` 与 `2026-08-29 23:32:44`，相差约 32 分钟。
- 两条通知均没有 `requestId`，不能把空业务目标当作相同事件键。
- [脱敏事件身份摘要](device-acceptance/notification-dedup-20260901-identity-summary.txt)

## 去重规则

- 同一个非空通知 ID 在统一时间流中只保留第一次投影。
- 不使用标题、正文、日期、`requestId` 空值或“巡检”类型作为合并键。
- IM 会话投影继续使用 `im-conversation:{conversationId}` 命名空间，不与 OA 通知 ID 混淆。
- 分页加载原有同 ID 防重继续保留，首屏、缓存和合并投影增加相同保护。

## 真机与回归

- 设备：realme RMX3366，Android 14，1080×2400。
- Profile APK SHA-256：`8857CBAFD84FDFBC95A4B86FBC3E4FD3D227441844EF757C9F2ACF0D1827609E`。
- Profile 真机仍显示 2 条真实巡检通知，证明不同事件没有被错误合并。
- [Profile 通知列表截图](device-acceptance/notification-dedup-20260901-profile.png)
- [Profile 通知列表 UI 树](device-acceptance/notification-dedup-20260901-profile.xml)
- `flutter analyze`：0 问题。
- 通知专项：4/4 通过，包含同 ID 去重和不同巡检 ID 保留。
- 完整自动化：200/200 通过。
- Profile 中临时诊断日志匹配 0 条，关键崩溃日志匹配 0 条。
- 真机加密数据库临时只读副本已删除，原数据库未修改；未标记已读、未提交巡检响应、未修改线上数据。
