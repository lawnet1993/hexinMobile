# 574 记住登录与密码语义安全验收

## 结论

本轮通过。移动端仍支持“记住登录”，但不再把安全存储中的密码回填进 `TextEditingController`。记住的凭据只在提交时于内存中使用，密码输入框保持空值，避免 Android UI 自动化树、辅助功能快照或截图流程暴露原文。

## 实现

- 读取安全存储后只回填终端账号；密码保留在非渲染状态，不进入输入框控制器。
- 有有效记住密码时显示“已保存密码”和非交互状态图标，不能通过显示按钮展开原文。
- 用户修改账号或输入新密码后立即丢弃页面内记住密码引用。
- 使用记住密码登录收到明确 401“账号或密码错误”后，删除失效安全凭据，避免重启后继续自动使用。
- “忘记密码”由居中 `AlertDialog` 改为移动端底部消息抽屉。

## 双设备验证

- 真机：realme RMX3366，既有登录会话在新 Profile 包中正常进入工作台。
- 模拟器：未提交登录；密码输入框在 UI 树中标记为密码字段且 `text` 为空。
- [模拟器安全登录页截图](device-acceptance/login-remembered-security-20260901-emulator.png)
- [模拟器安全登录页 UI 树](device-acceptance/login-remembered-security-20260901-emulator.xml)
- [忘记密码底部抽屉截图](device-acceptance/login-remembered-security-20260901-forgot-sheet.png)
- [忘记密码底部抽屉 UI 树](device-acceptance/login-remembered-security-20260901-forgot-sheet.xml)
- [真机会话 UI 树](device-acceptance/login-remembered-security-20260901-device.xml)

## 回归与边界

- Profile APK SHA-256：`3578DC86CEAC0BDFA3C93C87F84337D8C08A9334A480B33673F8F9976FFE3524`。
- `flutter analyze`：0 问题。
- 登录安全专项：2/2 通过，覆盖记住密码不渲染、内部提交和 401 清理。
- 完整自动化：202/202 通过。
- 双设备关键崩溃日志均为 0。
- 初次观察发现模拟器旧版本曾把记住密码放进 UI 树；相关 XML、截图和临时文件已立即删除，报告与代码未记录凭据。
- 双端 IM 真实发送仍未执行：模拟器当前没有可用登录会话，且本轮没有通过环境变量获得测试凭据；未绕过该安全边界，也未向任何联系人发送消息。
