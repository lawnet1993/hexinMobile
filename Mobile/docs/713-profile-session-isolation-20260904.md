# 713 个人资料会话隔离与真机回归

2026-09-04，Asia/Shanghai。阶段性完成；完整移动端对齐目标仍进行中。

## 问题与修复

本地真实 HTTP + SQLite 回归复现：个人资料保存期间切换登录后，后续 bootstrap 刷新可能使用新账号请求；旧资料结果、错误及选图回调也可能影响新的编辑页面。这是受控测试复现，不代表已在真机执行跨账号攻击。

- 资料读取、保存、头像更新固定原始会话，请求前后与缓存写入均校验；保存后的 bootstrap 同样绑定原始会话。
- bootstrap 失败也重新校验会话，旧会话的迟到 500 不再当成当前会话错误。
- 切账号或退出立即清除旧编辑内容；同账号正常令牌轮换保留未保存草稿，并取消旧异步回调影响，下一次保存绑定新会话。
- 选择头像前记录会话，选图返回时再次校验，禁止跨会话上传；保存和上传互斥。
- 缓存只采用当前账号资料，后台刷新和重试不覆盖正在输入的内容。

没有延长服务器会话、保存密码自动重登或绕过 session_replaced。真机此前旧包缺少主动续期的排查见 [710](710-phone-session-upgrade-20260904.md)。

## 自动化证据

- [修改前跨账号失败](../test/evidence/profile-session-20260904/cross-account-before.log)：应只请求 a，实际出现 a、b。
- 新增资料仓库 42 项及页面 7 项：账户切换、退出、同账号会话轮换，迟到成功/失败、选图等待、缓存重试草稿保护。
- [专项 79/79](../test/evidence/profile-session-20260904/focused-passed.log)。
- 最终代码 [全量 1242/1242](../test/evidence/profile-session-20260904/full-final.log)、[静态分析 0](../test/evidence/profile-session-20260904/analyze-final.log)。
- [普通 Profile 构建成功](../test/evidence/profile-session-20260904/build.log)，lib/main.dart，arm64+x64。
- APK 与真机 base.apk SHA256 相同：`6300871B67498083A8C9E995F8D18F0537356C51443966AF902512523EAA8A63`。

## 真机实际操作

设备 RMX3366，当前测试账号 test01。保留数据覆盖安装；没有卸载、清数据、主动退出或切换系统网络。

1. 更新后直接恢复 test01 工作台，不需要输入密码。
2. 个人资料原昵称为 Test Terminal 01，原签名为空。
3. 仅签名改成 `AI-UAT-20260904-PROFILE-SESSION` 并保存；返回我的页面，再打开编辑，确认签名已读回。[保存后截图](../test/evidence/profile-session-20260904/profile-saved.png)。
4. 确认当前签名仍为本轮标记后恢复为空并保存；重新打开确认昵称未变、签名为空。[恢复截图](../test/evidence/profile-session-20260904/profile-restored.png)。临时签名已移除，原值恢复。
5. 强制停止应用后重新打开，23:24:12 工作台仍恢复原账号。[冷启动截图](../test/evidence/profile-session-20260904/cold-restored.png)。当前进程日志采样 FATAL、Unhandled Exception、RenderFlex overflow 均为 0，不代表历史日志全无错误。

恢复命令末尾一次无效的输出命令报错发生在保存点击之后；随后独立重新打开页面核验原值已恢复，未依赖该命令退出码判定成功。截图中个人资料最终头像已加载；未更改头像，也不据此宣称所有头像链路通过。

## 未完成与限制

- 真机跨实际令牌到期时间、隔夜保持登录尚未验证；短时冷启动不是长时无感续期证据。
- 真机没有实际切换账号或强制轮换令牌；这些竞态由本地 HTTP、SQLite、widget 测试覆盖。
- 本轮不修改服务端，不提供无限期登录承诺。会话被替换、密码安全策略或刷新凭据失效仍应要求重新登录。
- 当前 Windows 控制所需运行时不可用，最新版桌面窗口对照未执行；完整多端替换矩阵、高级 OA、推送和长期性能继续待验收。
