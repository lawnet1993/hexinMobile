# “我的”与通知设置离线交互审计

## 结论

“我的”首页、个人资料和通知设置已在 realme 真机与 Android 16 模拟器重新运行验证。当前信息密度、入口命名和离线反馈一致；成员同步未完成时个人资料入口仍可使用，系统推送失败不再膨胀为大段错误卡片。

## 步骤与健康度

1. “我的”首页 — 健康
   - 账号卡只展示头像、姓名和部门，不展示账号或内部设备 ID。
   - 设置入口按账号、通知、网络、设备和通用设置分组，图标与行高保持紧凑。
   - “通知设置”补充“消息、审批与公告”摘要，入口含义不再与系统推送混淆。
   - 成员资料仍在同步或网络中断时，账号卡保持可点击，可进入本地资料页。

2. 个人资料 — 健康
   - 昵称输入区固定 40dp，签名输入区固定 72dp，保存按钮固定 104×36dp。
   - 不再重复展示终端账号，头像与相机入口缩小并保持真实头像。
   - 远端同步失败后显示“当前显示本机资料”，可重新同步；认证会话仍在恢复时不会误报资料不存在。
   - 用户开始输入后，迟到的远端响应不会覆盖本地编辑内容。

3. 通知设置 — 健康（系统推送能力部分受阻）
   - “应用内通知”说明通知中心来源和当前同步状态。
   - “系统推送”在离线和请求失败时都显示单行“暂时无法同步推送设置”与“重试”。
   - 不显示虚假的启用开关或已注册状态。

4. Android 系统后台推送 — 未验收
   - 当前项目仍未接入实际 FCM 或厂商推送服务，无法验证后台通知、点击定位和推送唤醒同步。

## 当前截图

- 真机“我的”：`Mobile/test/evidence/profile-audit-20260902/03-profile-final-real.png`
- Android 16 模拟器“我的”：`Mobile/test/evidence/profile-audit-20260902/03-profile-final-emulator.png`
- 真机通知设置：`Mobile/test/evidence/profile-audit-20260902/04-notification-final-real.png`
- Android 16 模拟器通知设置：`Mobile/test/evidence/profile-audit-20260902/04-notification-final-emulator.png`
- 修正前真机个人资料：`Mobile/test/evidence/profile-audit-20260902/05-profile-edit-real.png`
- 真机个人资料最终状态：`Mobile/test/evidence/profile-audit-20260902/06-profile-edit-final-real.png`
- Android 16 模拟器个人资料最终状态：`Mobile/test/evidence/profile-audit-20260902/06-profile-edit-final-emulator.png`

## 可访问性与交互

- 设置项通过完整行响应点击，不要求用户精准点击箭头。
- 资料输入区保留清晰标签，文本输入目标未低于 40dp；最终触控和读屏顺序仍需 TalkBack 专项测试。
- 系统推送失败详情保留在语义标签中，视觉层只显示简短状态；截图不能证明读屏顺序和触控辅助完整合规，仍需真机 TalkBack 专项测试。

## 验证

- `flutter analyze`：通过，无问题。
- `flutter test`：280/280 通过。
- `flutter build apk --profile`：通过。
- APK SHA-256：`5E4DC347FBA8040603C2AD23B4238B6E1726C70FCE6E881713EE735EC4014734`。
- 已覆盖安装到 realme RMX3366 与 Android 16 模拟器。
- 两端进入“我的”、个人资料和通知设置后，AndroidRuntime 与 Flutter 关键错误日志均为 0。
