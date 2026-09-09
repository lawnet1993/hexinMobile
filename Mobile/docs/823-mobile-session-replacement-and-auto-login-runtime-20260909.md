# 823 · 移动端自动登录与同平台会话替换实测

日期：2026-09-09（Asia/Shanghai）  
桌面功能基线：真实运行窗口 **v1.0.105**

## 本轮结论

- **真机冷启动自动登录：通过。** 真机 `realme RMX3366` 已登录 Test Terminal 01；执行强制结束进程并重新从 Launcher 启动后，8 秒内直接恢复工作台，没有进入登录页，也没有出现“登录已失效或已到期”。工作台的通知数、待办数和列表内容均恢复。
- **账号间保存密码隔离：通过。** M3 原为 test05 的“已保存密码”状态；只把账号改为 test01 后，密码立即变为空并要求重新输入，没有把 test05 的保存密码复用给 test01。
- **同平台 `session_replaced`：尚未执行完成。** M3 已停在 test01 登录页，但安全环境中没有可调用的测试凭据变量；本轮没有通过 ADB、命令行、截图或日志注入/输出密码。需要在 M3 屏幕上人工输入一次 test01 密码后继续观察 M1 的 409、同步任务终止和登录页跳转。
- **桌面会话隔离：部分证据。** M1 登录设备页在测试前显示当前 Android 设备及两条 Windows 授权记录；这证明授权记录没有被本轮冷启动清除，但不能代替桌面窗口在线和消息收发验证。

## 实际设备

| 角色 | 设备 | 当前状态 |
| --- | --- | --- |
| M1 | Android 真机 realme RMX3366 | Test Terminal 01 已登录，冷启动恢复通过 |
| M2 | emulator-5556 | 已登录其他测试会话，未改变 |
| M3 | emulator-5560 | test01 登录页，等待设备端输入密码 |
| D1 | Windows | 登录设备列表中存在近期授权；当前线程不能控制原生窗口 |

## 证据

- `Mobile/test/evidence/session-matrix-20260909/dd00d66d-current.png`：测试前 M1 登录设备列表。
- `Mobile/test/evidence/session-matrix-20260909/emulator-5560-current.png`：M3 原 test05 保存密码状态。
- `Mobile/test/evidence/session-matrix-20260909/emulator-5560-after-login.png`：改为 test01 后密码未跨账号复用。
- `Mobile/test/evidence/session-matrix-20260909/dd00d66d-cold-auto-login.png`：M1 强制结束并重启后的真实工作台。

## 后续验收步骤

1. 在 M3 真机界面人工输入 test01 密码并登录，不通过自动化输出凭据。
2. 同时采集 M1 脱敏日志，确认心跳/业务请求收到 `409 + session_replaced` 后只提示一次、停止同步、清理令牌并进入登录页。
3. 确认 M3 工作台、IM 和 OA 正常，登录设备列表仍保留 Windows 会话。
4. 在 M1 重新登录 test01，反向确认 M3 被替换；再次冷启动 M1，确认新会话可自动恢复。
5. 用桌面真实窗口验证 D1 未被移动端登录替换；授权列表只能作为辅助证据。

本报告不包含密码、Token、Cookie、设备完整标识或附件地址。
