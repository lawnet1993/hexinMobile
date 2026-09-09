# 847 · 通讯录真实在线状态端到端验证

时间：2026-09-09（Asia/Shanghai）  
设备：Android 模拟器 `emulator-5556`  
账号：Test Terminal 03

## 结论

当前测试服通讯录 Presence 端到端通过。两次真实 `/api/im/bootstrap` 响应均为 HTTP 200，各返回 4 名成员，4/4 具有明确在线状态、2 人在线、4 人具有最后上线时间。移动端展开“其他联系人”后显示 1 名其他联系人在线、2 名联系人显示具体最近上线时间，没有“状态未知”。当前账号本人的在线状态不重复展示在联系人列表，因此 UI 数量与服务端汇总一致。

这次结果替代 [810](810-contact-organization-and-chat-open-profile-20260908.md) 中服务端返回“状态未知”的历史样本；历史样本不能继续代表当前环境。

## 安全诊断

新增显式开关 `MOBILE_IM_PRESENCE_DIAGNOSTICS`。只有 Profile/Debug 且构建时主动开启才输出汇总：

- 来源与 HTTP 状态；
- 返回人数；
- Presence 已知人数；
- 在线人数；
- 带最后上线时间人数。

日志不包含姓名、账号、成员 ID、Token、请求头或响应正文。取证完成后已经重新生成默认关闭诊断的正常 Profile APK并覆盖安装模拟器。

## 证据

- 汇总日志：`test/evidence/main-tabs-20260909/emulator-5556-presence-aggregate.log`。
- 通讯录展开截图：`test/evidence/main-tabs-20260909/emulator-5556-presence-expanded.png`。
- 原生布局树：`test/evidence/main-tabs-20260909/emulator-5556-presence-expanded.xml`。
- 正常构建覆盖安装：`test/evidence/main-tabs-20260909/emulator-5556-presence-normal-reinstall.png`。

## 验证

- Presence 诊断测试：4/4 通过，包括固定字段白名单和身份信息不泄漏断言。
- 相关静态分析：0 issue。
- 当前全量 Flutter：1425/1425 通过，约 1 分 33 秒。
- 默认 Profile APK：85,792,566 bytes，SHA-256 `41D11FC5D764FE430887E08A6204FD31A089F932571971D7F98B436FBC50C2F6`。

## 边界

- 当前服务端/模拟器在线与最近上线显示通过；离线 60 秒过期后不得继续冒充在线的逻辑已有自动测试覆盖。
- 当前 realme 真机仍锁屏，没有绕过锁屏重复执行本轮可见界面检查。
- Windows v1.0.105 窗口未被电脑控制服务暴露，仍不能完成桌面同屏 Presence 对照。

