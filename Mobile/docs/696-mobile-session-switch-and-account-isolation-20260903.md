# 696 移动会话替换、账号隔离与恢复实测

日期：2026-09-03（主机 Asia/Shanghai），正常 695 Profile 包。结论：本轮场景通过，总 IM/OA 验收仍未完成。记录涵盖前一段已执行的切换和本次恢复、可见阅读、冷启动核对，不重复发送测试消息。

## 范围与操作

- M3：Android 16 模拟器，原账号 test03；M4：Android 16 模拟器，原账号 test04。M4 原生退出 test04、登录 test03，触发 M3 被替换，随后两台分别恢复原账号。
- D1：当前运行 Windows 1.0.87 / test01，仅用其现有会话只读检查 IM、OA 状态。本轮 D1 与被替换移动端不是同一账号，不能由此证明完整同账号桌面矩阵。
- 真机和另一台模拟器未操作。未卸载、清除应用数据、修改密码或组织配置；仅原生发送一条 AI-UAT 群消息，读取 SQLite 一致性快照用于核对，没有修改数据库。
- 凭据从现有授权测试保存凭据在内存读取，通过环境传给原生输入助手；未输出密码、Token、设备指纹或附件地址。截图不含填好的密码。

## 实际结果

| 场景 | 实际结果 | 证据 |
| --- | --- | --- |
| M4 登录 test03 替换 M3 | M3 返回登录页，持续显示“当前移动端已在另一台设备登录，请重新登录”；密码框为空 | [登录页](../test/evidence/mobile-account-switch-20260903/m3-after-replacement-attempt.png)、[持续提示](../test/evidence/mobile-account-switch-20260903/m3-still-terminated-ui.json) |
| 心跳失效与迟到刷新竞态 | 捕获一次 heartbeat HTTP 409 / terminated；116ms 后到达的刷新 200 被标为 stale_result，后续旧 401 ignored_stale_response，没有恢复旧登录 | [正常包白名单日志](../test/evidence/mobile-account-switch-20260903/m3-terminated-events.json) |
| 被替换后的事件停止落库 | M4/test03 发送第 6 条消息后，M3 仍保持 applied/acked=296、群 seq5/read5/unread0；再次检查相同 | [发送前](../test/evidence/mobile-account-switch-20260903/m3-stopped-before-new-message.json)、[发送后](../test/evidence/mobile-account-switch-20260903/m3-stopped-after-new-message.json)、[后续检查](../test/evidence/mobile-account-switch-20260903/m3-stopped-later.json) |
| M4 切换账号列表隔离 | test03 显示财顺和其会话，不混入 test04 的 Test05/合盈；切回 test04 后恢复其原会话 | [test03 列表](../test/evidence/mobile-account-switch-20260903/m4-test03-list.png)、[test04 列表](../test/evidence/mobile-account-switch-20260903/m4-restored-list.png) |
| 同设备不同账号未读隔离 | M4/test03 已读 seq6；M4 切回 test04 后，test04 仍是 seq6/read5/unread1 | [按账号分区投影](../test/evidence/mobile-account-switch-20260903/m4-restored-before-read.json) |
| 同账号消息恢复 | M3/test03 重新登录后补到 M4/test03 发送的 seq6，只有一条，read6/unread0 | [恢复快照](../test/evidence/mobile-account-switch-20260903/m3-restored-im.json)、[本人消息](../test/evidence/mobile-account-switch-20260903/m3-own-message-restored.png) |
| 可见阅读与对端回执 | M4/test04 原生打开群，seq6 实际可见后 read6/unread0；M3 对应消息显示双勾已读入口 | [M4 阅读](../test/evidence/mobile-account-switch-20260903/m4-restored-group-read.png)、[持久化结果](../test/evidence/mobile-account-switch-20260903/m4-after-visible-read.json)、[M3 回执](../test/evidence/mobile-account-switch-20260903/m3-own-message-restored.png) |
| 冷启动恢复 | 两台仍登录原账号，群 seq1–6 每个账号分区各一条、read6/unread0；原会话保留 | [M3 冷启动](../test/evidence/mobile-account-switch-20260903/m3-cold-home.png)、[M4 冷启动](../test/evidence/mobile-account-switch-20260903/m4-cold-home.png)、[M3 数据](../test/evidence/mobile-account-switch-20260903/m3-cold-im.json)、[M4 数据](../test/evidence/mobile-account-switch-20260903/m4-cold-im.json) |
| 既有本地数据保留 | M3 两条待发媒体身份不变，未迁移至 M4；M3 两条 OA 草稿、10 条通知已读记录不变；两端 OA outbox 不变 | [M3 OA](../test/evidence/mobile-account-switch-20260903/m3-cold-oa.json)、[M4 OA](../test/evidence/mobile-account-switch-20260903/m4-cold-oa.json)、[31 项核对](../test/evidence/mobile-account-switch-20260903/verification-final.json) |
| D1 不受本轮操作影响 | test01 仍运行，IM/OA GET 均 200；不代表 Windows 页面验收 | [最终桌面只读健康](../test/evidence/mobile-account-switch-20260903/desktop-final.json) |

日志的白名单不包含服务端原始响应体；409 的精确错误文本由登录页确认，不把日志中的空 errorCode 字段当作已捕获原始 code。停止同步证据证明本轮观察窗口内事件没有继续应用到旧账号缓存，不声称对所有后台网络任务作了抓包证明。

初次无效 UI 登录是测试助手的 Ctrl+A 没有清空用户名导致，不能判定测试账号密码错误。随后改成按已观察字符数移动到末尾逐字删除，并在填密码前核对用户名，真实登录成功。恢复记录：[M4/test04](../test/evidence/mobile-account-switch-20260903/m4-restore-test04.log)、[M3/test03](../test/evidence/mobile-account-switch-20260903/m3-restore-test03.log)。

## 唯一新增业务记录

- 群：`95e704ae-0e34-4f56-87db-038526796d6c`，AI-UAT-20260903-050600-M3-M4-GROUP。
- 原生发送标记：`AI-UAT-20260903-064100-REPLACEMENT-HOLD`，只执行一次，见 [单次操作记录](../test/evidence/mobile-account-switch-20260903/send-once.json)。
- 发送人 test03，操作设备 M4；server ID `63992535-b438-4e0a-81f4-928c27a22a32`，clientMessageId `50d6d450-615b-4192-a833-2cde32e7eeef`，sequence=6。
- 服务端创建时间 `2026-09-02T22:42:00.175786Z`，最终 sent。M3/test03、M4/test03、M4/test04 的本地分区记录均保持同一身份各一次；同一数据库存在两个账号分区是预期，不是重复消息或数据泄漏。
- 本轮未手工重试旧上传；普通队列仍自动退避重试，冷启动快照两条 attempts=52。不能把“记录保留”写成“次数未变化”或“媒体已送达”。

## 测试助手与回归

仅调整测试助手和报告，未改动生产 Flutter 代码、未重建 APK：

- [login-uat-m4.ps1](../scripts/login-uat-m4.ps1)：限定 M3/M4 与 test03/test04，临时环境传入授权测试凭据，finally 恢复环境；不会主动退出已有账号。
- [mobile_ui_login_env.mjs](../tool/mobile_ui_login_env.mjs)：增加只读检查、安全清空已存字段、用户名实际值验证及时间戳；不将凭据或原始登录 XML 输出到文件。
- [verify-mobile-account-switch.mjs](../scripts/verify-mobile-account-switch.mjs)：只读、按账号检查本次实测证据。首次检查 30/31 是旧 inspect-only 文件没有 passwordFieldEmpty 属性，已改为检查实际截图对应 XML 的唯一空密码节点；原始证据未改写，最终 **31/31**，不是产品失败被跳过。
- 五组会话、刷新、安全存储、账号作用域和 Outbox 专项 **81/81**：[日志](../test/evidence/mobile-account-switch-20260903/targeted.log)。
- 重新执行全量 **966/966**：[日志](../test/evidence/mobile-account-switch-20260903/full-tests.log)；分析 **0 问题**：[日志](../test/evidence/mobile-account-switch-20260903/analyze.log)。
- 最终两台实际安装 APK SHA-256 均为 `5021590ADF094F2033089DAD1C31FDE3325C958EB828984BEC614DEA9DF6C89A`，与正常 695 包一致；Wi-Fi/移动数据恢复为开启，当前进程异常/溢出和临时诊断标记匹配均 0：[运行核对](../test/evidence/mobile-account-switch-20260903/normal-runtime-final.json)。此为短时抽查，不是长期稳定性或 Release 性能结论。
- 最终 M3 留在 [消息全部](../test/evidence/mobile-account-switch-20260903/m3-final-list.png)，M4 留在工作台。

## 仍未完成

1. [695 图片、视频上传 500](695-im-upload-failure-diagnostics-20260903.md) 已取得 traceId，仍待后端日志定位与恢复后真实送达，不继续重复手工撞相同错误。
2. [642](642-mobile-session-replacement-and-login-notice-20260902.md) 已有此前同账号 D1/M1 与 M2 替换 M1 的实测，不能写成从未执行；本轮补正常新包的 409、迟到刷新与账号未读隔离证据，不替代 D2 替换 D1、改密其他会话失效等完整矩阵。
3. 本轮未完整证明所有同步任务停止、全部安全存储命名空间、推送令牌注销/重注册。对应生命周期和推送实测仍待完成。
4. 当前工具清单仍没有 Windows UI 控制能力；桌面只读接口 200 不能替代真实桌面操作对照。真机全页、完整多端、推送、500 条追平、多崩溃窗口、长时性能和高级 OA 分支/会签/或签/公式/附件矩阵继续保留。
5. 本轮未重新设计图标和页面；已单独提供图标文件，不宣称已安装为 Launcher 图标。总体目标保持进行中。
