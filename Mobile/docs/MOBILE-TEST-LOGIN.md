# 移动端测试登录助手

脚本 `tool/mobile_test_login.mjs` 用于给已连接的 Android 测试设备或模拟器输入终端测试账号，并等待五项主导航出现。脚本不会输出账号、密码、Token 或页面 XML。

凭据通过 `MOBILE_TEST_CONFIG` 或 `ADMIN_TEST_CONFIG` 指向本机 JSON 文件，字段为：

```json
{
  "terminal_username": "通过本机环境配置提供",
  "terminal_password": "通过本机环境配置提供"
}
```

当前工作区若存在 Desktop 测试登录助手创建的、已被 Git 忽略的 `Desktop/Windows/scripts/admin-test-env.local`，移动端脚本会复用其中的终端测试字段。该文件只作为本地凭据来源，不作为桌面功能或 UI 基准。

运行示例：

```powershell
node tool/mobile_test_login.mjs --serial emulator-5554
```

需要用另一名测试员工执行双端互发时，可只覆盖非敏感账号名；密码仍从本地忽略配置读取：

```powershell
node tool/mobile_test_login.mjs --serial emulator-5554 --username <测试账号>
```

安全边界：

- 只接受明确指定的设备序列号。
- 不把凭据写入仓库、命令参数、截图或报告。
- 不读取或输出移动端 Token、Cookie 和本地数据库内容。
- 通过 Android KeyEvent 逐字符输入常见 ASCII 测试凭据；ADB 命令只包含键码，不包含账号或密码内容。不支持的字符会安全失败并要求人工输入。
