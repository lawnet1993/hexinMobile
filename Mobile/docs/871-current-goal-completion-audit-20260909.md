# 871 · SecureAccess 移动端当前目标完成审计

时间：2026-09-09（Asia/Shanghai）  
权威代码：当前 `Client/Mobile` 工作树  
Android Profile APK SHA-256：`EC15C44654FEF019374461ABFEA4ACC280869396A237DD1E9F58065FF704EA81`

## 总体判定

**部分通过，目标尚未完成。**

当前 Android 客户端自身能够闭环的主页面、信息密度、动态 OA 表单、IM 单聊/群聊边界、真实 Presence、历史分页、缓存、Outbox、图片本机处理、附件流、自动登录和前台恢复均已有代码、自动化或真实运行证据。最终工作树全量测试 **1438/1438**、静态检查 **0 issue**，同一 APK 已覆盖安装一台 realme 真机和三台模拟器。

测试全绿不能替代仍缺失的服务端、桌面、锁屏推送、多登录端和 iOS 真实证据，因此不得将目标标记为完成。

## 当前通过矩阵

| 范围 | 当前状态 | 当前直接证据 |
| --- | --- | --- |
| 工作台、消息、待办、通讯录、我的 | Android 当前构建通过 | [867](867-current-build-five-main-pages-runtime-audit-20260909.md) |
| 页面密度、底部 Tab、抽屉、输入框和操作尺寸 | Android 当前边界通过 | [843](843-mobile-modal-interaction-boundary-audit-20260909.md)、[867](867-current-build-five-main-pages-runtime-audit-20260909.md) |
| 单聊/群聊边界、连续头像聚合、真实在线状态 | Android 当前边界通过 | [837](837-mobile-contact-to-chat-avatar-cluster-real-device-20260909.md)、[847](847-mobile-contact-presence-authoritative-runtime-20260909.md) |
| 历史消息自动上滑分页、缓存和热打开 | Android 当前边界通过 | [842](842-mobile-chat-30-reopen-memory-soak-20260909.md)、当前全量测试 |
| OA 动态表单和页面内审批流程 | 当前请假 v1 运行页通过 | [870](870-current-oa-dynamic-form-configuration-text-runtime-20260909.md) |
| 图片、附件、视频和音频 | Android 主要链路通过 | [803](803-real-device-chat-media-grid-and-cache-20260908.md)、[817](817-oa-19m-stream-upload-roundtrip-20260909.md)、[824](824-oa-attachment-cache-reuse-real-device-20260909.md) |
| 图片本机处理和文件流上传 | 当前代码通过 | [859](859-mobile-compressible-image-upload-policy-20260909.md)、[869](869-mobile-extensionless-image-local-processing-20260909.md) |
| 账号安全、断网恢复、登录设备隐私 | Android 当前边界通过 | [862](862-mobile-account-security-offline-recovery-20260909.md)、[865](865-mobile-profile-security-notification-truthful-state-20260909.md)、[866](866-mobile-login-device-identifiable-revoke-20260909.md) |
| 最终代码回归 | 1438/1438，0 issue | [822](822-current-mobile-full-regression-20260909.md) |

## 当前无法由本线程单独完成的门槛

### 1. 多移动端登录状态

- `emulator-5556` 已登录 Test Terminal 03。
- `emulator-5554`、`emulator-5560` 当前在登录页。
- realme 真机处于锁屏 Doze。
- 需要通过设备屏幕登录第二个测试端，或由用户解锁 realme，才能继续 M1/M2 消息、已读、OA 状态和 `session_replaced` 验收。
- 不得通过命令行、日志或文档注入密码，也不得绕过锁屏。见 [868](868-current-multi-device-session-readiness-20260909.md)。

### 2. 当前 Windows 桌面窗口

- Bundled Computer Use 的 `@oai/sky` 初始化及 kernel reset 后唯一重试均失败：`failed to write kernel assets: 系统找不到指定的路径。 (os error 3)`。
- 尚未进入 `list_apps`，无法读取当前 Windows v1.0.105 可见窗口。
- 不得用旧桌面源码、PE 文件版本或移动端表现替代当前可见窗口，也不得自制 PowerShell UI Automation 绕过。见 [863](863-windows-current-baseline-observation-blocker-20260909.md)。

### 3. 服务端契约

- 服务端再次更新后，“不可见会话提前推进本人已读”复测继续通过：新消息 281 落库后保持 `read=280/unread=1`，真实打开后才变为 `read=281/unread=0`，发送端同步显示已读。
- OA 详情 125/125 个任务已下发 `completionMode`，原“详情缺字段”缺陷关闭；当前样本仍仅覆盖 `all`，缺 `any/sequential` 运行态样本。
- 群事件提交后的 Gateway 长轮询唤醒已明显恢复，但连续三条从点击发送到收件人事件生成仍约 3.9–4.0 秒，前台 UI 可见为 3.2–6.0 秒；剩余慢点位于发送请求、消息事务或收件人事件生成链路，而非移动端渲染。
- 37 条当前申请仍无 `return` 候选，且原退回验收流程已不在 test01 可发起目录；必须重新发布多节点退回流程并创建新实例后真实执行，不能用旧实例或发布声明替代。
- 更新后详细数据、复现步骤和服务端所需时间点见 [873](873-server-update-live-recheck-20260909.md)；更新前基线见 [872](872-server-contract-fix-live-recheck-20260909.md)。

### 4. 后台系统推送

- 服务端推送注册和前台事件补偿已接入。
- 厂商推送通道、锁屏通知、Doze 到达及通知点击定位仍未完成；当前页面已如实标记“待接入”。

### 5. iOS

- 当前没有可用 iPhone；Keychain、PHPicker/有限照片权限、ImageIO 大图峰值、媒体、附件、通知、键盘和 VoiceOver 均没有真机证据。

## 恢复后最短验收顺序

1. 在第二台模拟器屏幕登录测试账号，先跑 M1/M2 单聊、群聊、已读、OA 状态和同平台会话替换。
2. 解锁 realme 后跑后台、锁屏、Doze 和通知点击定位；厂商通道未接入前保持未通过。
3. Computer Use 恢复后枚举唯一合兴智联窗口，按当前桌面版本逐项对照工作台、IM、OA、附件和通知。
4. 服务端契约补齐后重跑错误已读、群事件长尾、`return` 和 `completionMode`。
5. 提供 iOS 真机后补齐 iOS 专项矩阵。

只有以上五类证据全部闭环，才能将当前持久目标标记为完成。
