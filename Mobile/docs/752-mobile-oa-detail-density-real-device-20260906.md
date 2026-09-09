# 752 · 移动端 OA 审批详情密度与附件打开真机验证

日期：2026-09-06，Asia/Shanghai。结论：审批详情已按移动端交互展开真实表单与审批路径；底部处理按钮、确认按钮及公共紧凑操作由 48 dp 布局高度收紧为 34 dp。真机上“更多”、“同意”均使用底部抽屉，没有改动现有审批业务数据。

## 真机环境

- 设备：realme RMX3366，Android 真机。
- 应用：1.0.1+2，arm64 Profile，保留数据覆盖安装。
- 账号：test01 / Test Terminal 01；安装后登录态、工作台、待办数和消息入口均保留。
- 样本申请：`OA-20260904-FE90A4`，审批中。

## 详情与交互核对

- 表单内容来自服务端可视化表单：请假类型、开始/结束时间、请假天数、事由和附件正常展示，界面没有把“自动计算、只读”等配置说明当作用户数据。
- 审批路径在详情页内联展开，显示实际节点、处理人、账号、部门和状态。
- 底部“更多 / 驳回 / 同意”控件真机布局高度为 102 物理像素，即 34 dp；改造前为 144 物理像素，即 48 dp。
- “更多”打开底部抽屉，包含转交、加签、催办和撤回；“同意”打开底部意见抽屉。
- 本轮仅打开并取消交互，未点击“确认同意”、“驳回”或其他最终操作，申请状态仍为审批中。

## 附件

- 样本附件 `AI-UAT-20260902-165500-leave-proof.txt`，176 B。
- 点击后成功进入 Android `ResolverActivity`，使用 FileProvider 向系统应用交付 `text/plain` 文件。
- 这符合“不内置 Office 引擎”的当前决定。本轮没有选择第三方查看器，因此“文件内容实际渲染”不等同于已验收；PDF、Word、Excel、PPT 仍需分格式真机抽样。

## 自动化与构建

- `flutter test --concurrency=1`：1391/1391 通过。
- 设计基准：13 个页面基准和 4 个离线/会话状态用例通过；本轮按意图更新工作台、审批详情、网络安全和强制更新 4 张基准图。
- `flutter analyze`：新增 warning/error 为 0；仅保留 7 条仓库已有的大括号风格 info。
- arm64 Profile APK：69,497,080 字节。
- APK SHA-256：`1385BE4E5928DC58A1BF82BD5BA6ADFDA10B76D1660ADBF8AB3178B9E7350082`。

## 证据

- [审批详情与 34 dp 底栏](../test/evidence/oa-detail-20260906/01-approval-detail-compact.png)
- [更多操作底部抽屉](../test/evidence/oa-detail-20260906/02-more-actions-bottom-sheet.png)
- [同意意见底部抽屉](../test/evidence/oa-detail-20260906/03-approve-opinion-bottom-sheet.png)
- [附件交付系统打开器](../test/evidence/oa-detail-20260906/04-attachment-system-open.png)

## 尚未通过的边界

- 驳回、转交、前加签、后加签、撤回、跨账号待办/通知、通知未读变更、大附件进度与断网恢复已在 [754 多设备实测](754-mobile-oa-boundary-multi-device-real-device-20260906.md) 补齐。
- 退回仍未通过：已专门新建、启用并发布允许“退回”的 AI-UAT 流程，但真实负责人待办仍没有下发 `return`；配置发布链路的实测与服务端排查项见 [774](774-mobile-oa-return-published-flow-live-verification-20260906.md)。
- 催办在线接收、App 被强制停止后的离线恢复以及刷新后单事件去重，已在 [754 多设备实测](754-mobile-oa-boundary-multi-device-real-device-20260906.md) 补齐。
- PDF 的选择、真实提交、服务端回下载和系统打开路由已在 [753 真机闭环](753-mobile-oa-pdf-attachment-real-device-20260906.md) 验证；PDF 内容渲染仍受未安装经批准的纯本地阅读器限制。Word、Excel、PPT 的标准 MIME、本地内容渲染及 OA 服务端往返已在 [755 Office 真机验证](755-mobile-office-mime-local-render-real-device-20260906.md) 通过。
- Windows 当前版本的跨端状态同步仍需在可控桌面窗口上逐项复验；754 的多端证据来自一台真机和两台 Android 模拟器。
- 媒体预览 Range、切后台、强杀断点恢复与历史视频 404 兼容已继续实测并通过，见 [760](760-mobile-preview-resume-legacy-video-real-device-20260906.md)。预览分片主动取消/续传与摘要拒绝自动化见 [764](764-mobile-attachment-cancel-storage-integrity-boundaries-20260906.md)；普通 IM 附件已在第三台 Android 模拟器完成真实低存储提示、残件清理和点击取消，见 [766](766-mobile-attachment-low-storage-cancel-boundary-followup-20260906.md)。服务端破坏摘要、realme 真机点击取消/低存储和 iOS 仍未通过。
- 最新三模拟器在线并发、离线追平和通知权限首启复验见 [767](767-mobile-multivm-permission-offline-followup-20260906.md)；Windows 未打开会话的后台同步、真机锁屏通知和厂商推送仍未通过。
- 三模拟器联系人进入会话累计 40 次重复打开、Profile 时延以及 test01 当前 28 条申请仍无 `return` 候选的追加复验见 [768](768-mobile-contact-hot-reopen-multivm-20260906.md)。
- 联系人进入单聊在 SwiftShader 与宿主 GPU 下的控制变量性能复验见 [769](769-mobile-chat-renderer-isolation-20260906.md)；宿主 GPU 冷开与 20 次热开显著改善，但物理真机仍需解锁后给出最终结论。
- 五个主入口的同态视觉、触控区和默认通讯录折叠审计见 [770](770-mobile-main-shell-ux-audit-20260906.md)；待办页签点击区已由 26 dp 修复为 40 dp，真机交互与完整无障碍仍待解锁后复验。
