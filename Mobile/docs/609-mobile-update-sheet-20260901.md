# 609 · 移动端更新提示抽屉对齐

时间：2026-09-01

## 结果

- 当前已登录 Windows 桌面端真实出现 `v1.0.81` 强制更新提示，发布包大小为 `100.81 MB`。本轮只读取版本、大小与发布说明，没有下载或安装桌面更新。
- 移动端启动自动检查与“关于合兴智联 → 检查更新”已共用同一个底部更新抽屉，不再使用居中 `AlertDialog`。
- 强制更新抽屉不可拖拽、不可点击遮罩关闭、不可系统返回，也不显示关闭或“稍后”；可选更新保留关闭和“稍后”。
- 版本、包大小、更新说明和强制标识使用紧凑排版；下载按钮固定为 40dp，不使用默认大号通栏按钮。
- 下载地址只接受 `http/https`。无效地址不会唤起外部应用，并显示明确错误。

## 验证

| 项目 | 结果 |
| --- | --- |
| `flutter analyze` | 0 项问题 |
| 更新抽屉定向测试 | 2/2 通过 |
| “关于”页手动检查定向测试 | 1/1 通过 |
| 视觉基线 | 13/13 通过 |
| 全量自动化 | 234/234 通过 |
| 模拟器安装与真实导航 | 通过 |
| 模拟器关键异常 | 0 条 |

模拟器已真实执行：工作台 → 我的 → 关于合兴智联 → 检查更新。当前服务端对 `terminal-mobile` 返回“暂无发布版本”，因此线上接口没有触发更新抽屉；未将桌面版本假投影为移动版本。更新抽屉的真实 Flutter 渲染、强制阻断行为和可选关闭行为由 Golden 与 Widget 测试覆盖。

证据：

- `test/goldens/13-mandatory-update.png`
- `docs/evidence/609-mobile-update-sheet/04-emulator-about.png`
- `docs/evidence/609-mobile-update-sheet/04-emulator-about.xml`
- `docs/evidence/609-mobile-update-sheet/05-emulator-check-result.png`
- `docs/evidence/609-mobile-update-sheet/05-emulator-check-result.xml`
- `docs/evidence/609-mobile-update-sheet/06-profile-realme-install.txt`

## 构建与真机边界

- Production Profile APK：67,131,199 bytes。
- SHA-256：`FE0057E2C8C4691FC1E5F32DAE5DFB79B5F81815DD315FE7A046FCDC6B30E1A7`。
- 已覆盖安装到 realme RMX3366；从设备拉取的实际安装 APK 哈希与构建产物一致。
- 真机仍处于系统锁屏：`showing=true / mInputRestricted=true / isKeyguardShowing=true`。本轮未绕过锁屏，真机触控复验待用户正常解锁。
- Windows 桌面端 `v1.0.81` 下载和安装会运行新获取的软件，需用户明确确认后才能继续；在此之前桌面端最新版 OA/IM 比对仍被强制更新页阻塞。
