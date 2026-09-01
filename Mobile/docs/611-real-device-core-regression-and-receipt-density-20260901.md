# 611 · 真机核心回归与已读入口密度修正

时间：2026-09-01

## 结果

- realme RMX3366 已解锁并运行生产 Profile 会话，当前账号为 `Codex 测试终端`。
- 三次真机冷启动 TotalTime 为 710 / 650 / 652 ms；后两次跳帧事件为 0，关键崩溃日志为 0。608 报告中的模拟器冷启动不确定项已由真机结果关闭。
- 工作台真实显示 10 个服务端应用；当前无公告时不占位，不显示常用站点和空日程卡；五项底部导航保持稳定。
- 消息列表真实区分单聊和群聊；老王单聊标题使用真实离线时间，历史消息和已发送同步消息正常恢复。
- 最新已登录 Windows 桌面端为 v1.0.81。桌面端与移动端当前都显示 `Codex 测试终端` 的 Flutter 自定义头像，服务端成员投影为 `avatarKey=custom`，因此这不是移动端漏载；更换人物头像需要先提供或选定真实原图后再修改测试账号资料。

## 已读入口修正

- 删除气泡下方重复的“回执”文字。
- 保留与桌面端一致的双勾入口，并改为与消息气泡同一行、靠近气泡底部，不再额外占一行。
- 双勾只对“自己发送、服务端已落库、账号具备 readReceipt 权限”的消息显示；发送中、失败、收到的消息和无权限账号不显示。
- 点击双勾才请求真实回执，不在列表构建或滚动时逐条预取。
- 真机点击已有消息后真实返回“已读 1/1”和老王的读取时间。
- 单成员详情列表固定为 52dp 内容高度；成员较多时按实际人数增长，最多占屏幕 45% 后滚动，不再让一条记录撑满大抽屉。

## 验证

- IM 定向：25/25 通过。
- 全量自动化：234/234 通过。
- Golden：13/13 通过。
- `flutter analyze`：0 项问题。
- 最终 Production Profile APK：65,819,655 bytes。
- SHA-256：`4D46B97E027DCD02C7CF318369FCAAF1437F2022C28ABB0184D5037F0D24E6EE`。
- 真机已安装 `base.apk` 哈希与构建包完全一致。
- 真机 UI 树：不存在“回执”文本，存在“查看已读详情”语义；历史自动分页和热重开回归未退化。

## 数据边界

- 本轮只读打开已有单聊和已有已读记录，没有发送新消息、提交审批或修改业务数据。
- 用户已授权后续在测试环境提交审批、发送消息和修改测试业务数据；发送消息等对外动作仍在实际执行前确认目标与内容。

## 证据

- `docs/evidence/611-real-device-core-regression/01-startup.png`
- `docs/evidence/611-real-device-core-regression/02-cold-start-runs.txt`
- `docs/evidence/611-real-device-core-regression/03-messages.png`
- `docs/evidence/611-real-device-core-regression/04-direct-chat.png`
- `docs/evidence/611-real-device-core-regression/05-profile.png`
- `docs/evidence/611-real-device-core-regression/10-final-inline-receipt.png`
- `docs/evidence/611-real-device-core-regression/11-final-compact-receipt-sheet.png`
