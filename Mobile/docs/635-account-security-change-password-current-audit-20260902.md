# 账户与安全 / 修改密码真机复核

## 结论

- 用户截图中的旧版不合适：密码表单不应常驻主页面，内部设备 ID 不应作为普通用户信息展示，“已验证·状态未知”也存在语义冲突。
- 当前真机版本已改为两步移动端交互：账户与安全页展示账户、安全设备摘要和登录状态；点击“修改登录密码”后，从底部展开紧凑表单。
- 服务当前不可达，因此页面真实显示“已登录·同步中断”；未伪造在线状态，也未实际提交密码变更。

## 步骤与状态

1. 进入“我的 → 账户与安全”：通过。仅展示账号、可读设备名称和登录状态，未展示内部设备 ID。
2. 点击“修改登录密码”：通过。底部抽屉包含当前密码、新密码、再次输入新密码三个字段。
3. 校验控件：通过。三个密码可见性按钮互相独立；内容未填写时提交按钮禁用；按钮尺寸为 118 × 36 dp。
4. 在线提交：未执行。测试服务不可达，不能验证服务端密码修改与其他会话失效链路。

## 真机证据

- `Mobile/test/evidence/account-security-current-audit-20260902/19-account-security-current-run.png`
- `Mobile/test/evidence/account-security-current-audit-20260902/20-change-password-sheet-current-run.png`
- `Mobile/test/evidence/account-security-current-audit-20260902/22-account-security-current-device.png`
- `Mobile/test/evidence/account-security-current-audit-20260902/23-change-password-sheet-current-device.png`
- 同目录 XML 记录了可访问性节点、控件状态和点击范围。

## 自动化验证

- `flutter test test/account_security_page_test.dart`
- 结果：3 / 3 通过。

## 可访问性边界

- 真机语义树确认返回、修改密码入口、关闭按钮、三个密码可见性按钮和提交按钮均具有可读名称。
- 截图与语义树不能替代 TalkBack 完整手势、焦点顺序和服务端错误恢复测试；这些项目需在服务恢复后继续验收。
