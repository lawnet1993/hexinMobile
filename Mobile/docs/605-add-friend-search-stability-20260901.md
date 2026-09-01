# 605 · 添加好友搜索稳定性与桌面链路实操

时间：2026-09-01

## 结果

- 真实操作当前已登录桌面 `v1.0.80`，确认链路仍为“通讯录 → 添加好友 → 输入完整终端账号 → 查找 → 按服务端会话能力显示发消息或申请好友”；“新的朋友”继续独立承接好友申请，群聊没有混入。
- Android 模拟器按同一路径输入 `laowang` 并点击“查找”，修复前稳定出现 Flutter 红屏：`Bad state: No element`。
- 根因是查找请求进入加载中或失败状态时，结果列表仍为空，但页面提前构建结果卡片并读取 `_items.first`。
- 结果区域现在先判断空列表：加载中只保留进度条，接口失败只显示错误，查无账号显示空结果；只有至少一条真实结果时才构建头像、账号和操作按钮。
- `canStartDirect` 与好友关系的现有桌面语义保持不变，没有把可直接单聊的成员误改为好友申请，也没有改变好友申请接口。

## 自动化与模拟器实操

- 新增等待中的异步搜索与接口失败回归，明确断言两种状态均不创建结果卡片且无框架异常。
- 通讯录冒烟：19/19 通过。
- 全量测试：229/229 通过。
- `flutter analyze`：0 项问题。
- 修复后的 Debug 包覆盖安装到 1080×2400 模拟器，重复 `laowang` 搜索后页面保持在添加好友上拉抽屉；当前隔离 Demo 会话的真实仓储返回登录失效，界面显示可读错误，没有红屏。
- 清空日志后重放链路，`Bad state: No element`、`Unhandled Exception`、`FATAL EXCEPTION`、`RenderFlex overflowed` 合计 0 条。
- 桌面端只执行精确账号查找，没有点击“发消息”或发送好友申请。

证据：

- `docs/evidence/605-add-friend-search-stability/01-before-bad-state.png`
- `docs/evidence/605-add-friend-search-stability/01-before-bad-state.xml`
- `docs/evidence/605-add-friend-search-stability/02-after-readable-error.png`
- `docs/evidence/605-add-friend-search-stability/02-after-readable-error.xml`

## 构建与真机边界

- Production Profile APK：79,725,862 bytes。
- SHA-256：`CBFC3FE04EBDB11DDFE13C8E20F872977DFA4F0BBDA644C30BC91CCFD20CD4B6`。
- 已覆盖安装到 realme RMX3366，设备端 APK 哈希一致。
- 真机仍处于系统锁屏：`showing=true / mInputRestricted=true / isKeyguardShowing=true`。没有绕过锁屏；解锁后还需用真实非好友账号完成“查找 → 申请 → 对端新朋友 → 接受/拒绝 → 好友列表”的双端闭环。发送好友申请属于对外通信，执行最终发送动作前会单独确认。
