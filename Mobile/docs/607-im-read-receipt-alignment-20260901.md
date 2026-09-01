# 607 · IM 已读回执入口与性能对齐

时间：2026-09-01

## 结果

- 真实操作当前已登录桌面 `v1.0.80` 的“消息 → Codex 测试终端”，确认自己发送的消息直接显示“已读”；打开详情后服务端真实显示 `1 / 1 已读`、成员“Codex 测试终端”和读取时间。
- 移动端此前只能长按消息，再从操作抽屉选择“查看已读”，正常浏览中没有可发现入口。
- 移动端现在仅对“自己发送、服务端已落库、账号具备 `readReceipt` 权限”的消息显示双勾和小号“回执”。发送中、发送失败、收到的消息及无权限账号均不显示。
- “回执”是入口，不在未查询时伪称“已读/未读”；点击后才调用 `/api/im/messages/{messageId}/read-receipts`，底部抽屉显示真实已读人数、总人数、成员和时间。
- 没有在消息构建或滚动时逐条预取接口；入口使用原有 14dp 消息间距，不增加长列表整体高度，历史消息上滑分页行为保持不变。
- 已读详情使用根导航底部抽屉，覆盖底部 Tab 和安全区，保留长列表约束，不使用桌面居中弹窗。

## 验证

- 新增正向测试：页面初次构建接口调用为 0；点击“回执”后仅调用 1 次，并显示 `已读 1/1` 和真实成员。
- 新增权限测试：服务端关闭 `readReceipt` 时不渲染入口。
- IM 页面定向回归：25/25 通过，包含自动加载更早消息、失败重试、热重开、视频预览和单聊/群聊边界。
- 全量自动化：231/231 通过。
- 视觉基线：聊天页黄金图已人工复核并通过；气泡、资源区和输入区没有被挤压。
- `flutter analyze`：0 项问题。
- 1080×2400 模拟器真实打开唐泽单聊，两个服务端已落库的自己发送消息均显示“回执”；UI 树边界分别为 `[808,662][915,706]`、`[808,1651][915,1696]`。
- `Bad state: No element`、`Unhandled Exception`、`RenderFlex overflowed`、`FATAL EXCEPTION` 合计 0 条。

证据：

- `docs/evidence/607-im-read-receipt-alignment/01-emulator-compact-receipt-entry.png`
- `docs/evidence/607-im-read-receipt-alignment/01-emulator-compact-receipt-entry.xml`
- `docs/evidence/607-im-read-receipt-alignment/02-approved-chat-composition.png`

## 构建与未完成边界

- Production Profile APK：79,725,862 bytes。
- SHA-256：`5DCBE76222776DAE208C75D273D1CCF2C06920A3B154E140161E83CBB9844CBB`。
- 已覆盖安装到 realme RMX3366，从设备拉取的实际安装 APK 哈希与构建包一致。
- 真机仍处于系统锁屏：`showing=true / mInputRestricted=true / isKeyguardShowing=true`，因此本轮不能在生产会话中点击移动端回执抽屉。
- 桌面端只读打开已有消息的已读详情，没有发送消息、修改会话或产生新业务数据。真机解锁后仍需用真实生产会话复验移动端回执详情和双端已读变化。
