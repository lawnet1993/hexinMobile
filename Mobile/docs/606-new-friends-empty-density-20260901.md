# 606 · 新朋友空状态信息密度对齐

时间：2026-09-01

## 结果

- 真实操作当前已登录桌面 `v1.0.80`，确认“新的朋友”当前为 `0` 条，仅显示小号文字“暂无好友申请”；桌面没有大图标、发送记录分类或群聊内容。
- 移动端原空状态使用大号添加好友图标和粗体居中标题，视觉重心过低，也与桌面的低信息密度状态不一致。
- 移动端现改为 13sp 弱化文字提示，距列表顶部 44dp，移除内容区大图标；顶部“添加好友”工具按钮继续保留，因此入口能力没有丢失。
- 空列表仍使用可滚动容器和 `RefreshIndicator`，用户可以直接下拉刷新好友申请，不需要额外按钮。
- 没有修改好友申请、接受、拒绝、群聊或单聊业务逻辑，也没有创建、发送或处理线上申请。

## 验证

- 定向回归：1/1 通过；断言空态容器、下拉刷新、13sp 字号、位置和内容区无大图标。
- 全量自动化：229/229 通过。
- `flutter analyze`：0 项问题。
- 1080×2400 模拟器真实打开“通讯录 → 新朋友”，UI 树确认空提示边界为 `[32,543][1049,593]`，内容区不再渲染大图标。
- 清空日志后，`Bad state: No element`、`Unhandled Exception`、`RenderFlex overflowed`、`FATAL EXCEPTION` 合计 0 条。

证据：

- `docs/evidence/606-new-friends-empty-density/01-before-large-empty-state.png`
- `docs/evidence/606-new-friends-empty-density/01-before-large-empty-state.xml`
- `docs/evidence/606-new-friends-empty-density/02-after-compact-empty-state.png`
- `docs/evidence/606-new-friends-empty-density/02-after-compact-empty-state.xml`

## 构建与真机边界

- Production Profile APK：79,725,862 bytes。
- SHA-256：`433586A2B1B06605BE58073C8227A964A24FBCFD811B192A356B7E677DA86CBA`。
- 已覆盖安装到 realme RMX3366；从设备拉取的实际安装 APK 哈希与构建包一致。
- 真机仍处于系统锁屏：`showing=true / mInputRestricted=true / isKeyguardShowing=true`。本轮没有绕过锁屏；解锁后还需在真机复看空状态、下拉刷新和真实好友申请列表。
