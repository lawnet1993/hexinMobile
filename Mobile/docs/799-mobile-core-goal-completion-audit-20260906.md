# 移动端核心目标完成度审计（2026-09-06）

> 2026-09-08 增量：当前真实桌面基准已更新为 v1.0.105。移动端站点与网络安全边界改为仅提醒，不再建立隧道、展示连接诊断或直接打开站点；构建、安装与验证见 [801](801-windows-1105-desktop-only-site-boundary-20260908.md)。完整目标仍未完成。

> 2026-09-09 会话增量：Test Terminal 01 真机强制结束进程后可直接恢复工作台，自动登录真实通过；保存密码未跨 test05/test01 复用。同平台 `session_replaced` 仍需在 M3 屏幕人工输入一次 test01 密码后完成双向替换，见 [823](823-mobile-session-replacement-and-auto-login-runtime-20260909.md)。

> 2026-09-09 无障碍与成员隐私增量：Android 16、2 GB 模拟器启用 TalkBack 后完成焦点移动抽查，底部 Tab 原生语义包含名称、序号、总数和选中状态。群成员目录的可见搜索提示收敛为“搜索成员”，当前布局树不再出现登录账号；当前 APK 已覆盖安装真机并保留登录态。全量回归 1422/1422，见 [838](838-mobile-talkback-member-directory-privacy-20260909.md)。真人完整听读和 iOS VoiceOver 仍未验收。

> 2026-09-09 图片异常边界增量：头像、聊天图片和 OA 图片的原生编码现支持逐档降级重试；全部失败时返回可操作中文提示，且临时原图仍保证清理。图片定向测试 13/13、全量回归 1424/1424 通过，见 [839](839-mobile-image-compression-failure-recovery-20260909.md)。低内存 Android 真机和 iOS ImageIO 峰值仍未验收。

> 2026-09-09 权限增量：最终 APK 权限清单和 realme 真机运行时权限均已核对，应用不申请相册、视频、音频或外部存储的广泛读取权限；媒体与附件使用系统选择器单文件授权，失效时显示文件权限提示而非网络故障。Android 当前边界通过，iOS PHPicker/有限照片权限仍待真机验证，见 [840](840-mobile-picker-permission-apk-audit-20260909.md)。

> 2026-09-09 低内存恢复增量：当前 Profile APK 在约 2 GB Android 16 模拟器收到 `RUNNING_CRITICAL` 内存回收通知后，可继续进入消息页及长群聊，没有崩溃或丢失登录态；采样 PSS 约 201 MB。`gfxinfo` 未获得有效 Flutter 帧样本，因此不宣称该轮帧率通过，也不替代真实低内存手机的大图峰值，见 [841](841-mobile-2gb-trim-memory-chat-recovery-20260909.md)。

> 2026-09-09 会话重开压力增量：2 GB Android 16 模拟器连续 30 轮滚动、退出并重新打开同一长群聊，应用 PID 全程不变；PSS 从 172,881 KB 到短时峰值 182,993 KB，结束后回落至 177,236 KB，未见按轮次线性累积。系统 Google 首次设置页抢占的无效轮次已排除，见 [842](842-mobile-chat-30-reopen-memory-soak-20260909.md)。30 分钟持续聊天、视频播放和真实低端手机仍未验收。

> 2026-09-09 模态交互审计：当前 OA 单/多选、日期时间、筛选、新建和审批动作均使用底部抽屉，审批流程在详情内展开；全项目剩余 Dialog 仅为强制更新、头像视觉库及沉浸式图片预览，没有发现 OA 桌面式居中表单弹窗残留，见 [843](843-mobile-modal-interaction-boundary-audit-20260909.md)。

> 2026-09-09 头像交互增量：Android 16 模拟器真实走通“我的—个人资料—内置头像库—系统选择器—圆形裁剪—取消”，取消后原头像与禁用保存状态保持不变、应用缓存为空，测试图片已从公共相册清理；头像库维持紧凑居中网格而不是底部抽屉，见 [844](844-mobile-avatar-library-crop-cancel-runtime-20260909.md)。本轮未确认裁剪，因此没有修改线上头像；iOS 仍待真机验证。

> 2026-09-09 附件性能增量：真机复现同一 20 MB OA 附件每次点击都会重新下载并留下完整副本，现改为账号/环境隔离的稳定对象缓存、临时下载原子提交及服务端 SHA-256 流式校验；第二次点击 0.8 秒内直接进入系统打开方式，不再下载。同尺寸损坏缓存可识别并重取，定向分析 0 issue，见 [824](824-oa-attachment-cache-reuse-real-device-20260909.md)。
>
> 同日真机重新检查消息、待办、通讯录和我的：修复长群名后的群聊标签挤占日期空间，通讯录默认保持组织折叠，个人页不显示账号和设备 ID；证据见 [802](802-real-device-main-pages-and-group-row-density-20260908.md)。
>
> 随后只读复验真实单聊、群聊和会话资源：连续消息头像合并、群/单聊身份及在线状态正确；“图片/视频”由文件名列表改为三列真实缩略图网格，视频保留封面和播放标识。冷图 4 秒仍加载、15 秒内完成，热开约 700 ms 命中磁盘缓存；证据与服务端缩略图缺口见 [803](803-real-device-chat-media-grid-and-cache-20260908.md)。
>
> 2026-09-09 真机消息密度增量：会话列表长标题与日期之间增加固定间距，避免省略号和“昨天”粘连；聊天页收藏、搜索、更多调整为 44dp 点击区和 20dp 图标后，`Test Terminal 04` 可完整显示。主搜索框和路由自持控制器的成员/审批选择器进一步在不改变视觉布局的前提下把用途写入可编辑文本语义，抽样原生 `EditText` 不再出现 `NAF=true`。完整回归 1420/1420、静态分析 0 issue，见 [827](827-mobile-message-title-time-spacing-real-device-20260909.md)、[828](828-mobile-chat-compact-header-real-device-20260909.md)、[829](829-mobile-search-accessibility-real-device-20260909.md)。
>
> 同轮真机打开“群聊详情—查看全部”时发现群成员目录仍把终端账号拼入部门副标题，现已统一为只显示姓名、部门、真实在线状态和角色；账号仍可用于搜索，但不在列表展示。真机 XML 确认 `test01/test03` 均不存在，见 [830](830-mobile-group-member-account-privacy-real-device-20260909.md)。
>
> 同日继续在解锁 realme 真机验证音频资源页、系统键盘和返回手势：音频在 App 内播放/暂停，边缘返回正确回到消息列表，输入框唤起键盘后首次返回仅收起键盘。完整测试 1405/1405、静态分析 0 issue；见 [804](804-real-device-chat-input-navigation-regression-20260908.md)。
>
> 真机 OA 详情随后发现补卡流程把内部考勤异常 UUID 暴露为业务值，且审批路径及转交成员选择器混入登录账号；移动端已隐藏技术引用和账号，保留补卡时间、原因、姓名与部门，真实待办及转交抽屉复验通过。完整测试为 1407/1407；见 [805](805-real-device-oa-internal-reference-display-20260908.md)。
>
> 同日继续只读抽查真实请假发起页：后台 v1 表单字段、类型与日期底部抽屉、紧凑操作尺寸均通过。个人页原“浅色 · English”混淆了固定中文界面与账号内容语言，现已改为主题摘要，并在设置页明确为“内容语言”；真机复验与边界见 [806](806-real-device-oa-picker-and-profile-language-semantics-20260908.md)。
>
> 真机系统通知权限引导、系统设置跳转和返回刷新已通过。有效双端样本证明应用恢复前台后 15 秒内可自动追平消息并更新会话摘要，但应用后台时没有系统通知；厂商推送通道仍为未完成，见 [807](807-real-device-system-notification-and-background-message-20260908.md)。
>
> 按用户确认的桌面 v1.0.105 可见工作台继续核对真机：移动端没有站点、隧道、日程及桌面网络能力入口，首页、全部应用和待办信息密度符合当前边界；电脑控制服务未配置，桌面二级页面仍待恢复后核对，见 [808](808-real-device-workbench-v1105-boundary-20260908.md)。

> 通讯录已在当前 Profile APK 上复验为默认组织折叠、展开后显示成员、隐藏账号、无行尾联系图标，并可点击头像直接进入既有单聊。模拟器热打开 80 条消息缓存时消息可用约 16 ms、最新消息布局约 98 ms，Raster 仍有 12 帧超预算。2026-09-09 当前测试服两次真实 Presence 响应均为 4/4 状态明确、2 人在线、4 人有最后上线时间，展开列表与服务端汇总一致且没有“状态未知”，真实在线状态当前通过，见 [810](810-contact-organization-and-chat-open-profile-20260908.md)、[847](847-mobile-contact-presence-authoritative-runtime-20260909.md)。
>
> 2026-09-09 真机补测：同一 80 条消息单聊首次/热打开最新消息布局约 204/93 ms，两轮 Raster 超预算均为 0；通讯录及会话标题已显示服务端返回的最近上线/离线时间。联系人进入会话性能和 Presence 当前真机边界改判通过，详见 [810](810-contact-organization-and-chat-open-profile-20260908.md)。

> “我的”、账户安全、修改密码与登录设备断网状态已在当前 Profile APK 上复验：不展示移动端无关的隧道/网络诊断或敏感设备标识，修改密码为紧凑底部面板，设备同步失败保持登录并给出局部重试；相关自动回归 71/71 通过。真实设备列表与会话替换仍受当前服务端同步异常阻塞，见 [811](811-profile-account-security-offline-state-20260908.md)。

> 真实请假表单已确认继续由后台 Schema 驱动，配置对象不会暴露为业务值；流程预览失败文案由“网络不可用”收敛为“审批流程暂时无法同步”，避免与手机网络/隧道混淆。OA 定向回归 107/107 通过，新 Profile APK 已安装模拟器和真机，见 [812](812-oa-dynamic-form-scoped-sync-error-20260908.md)。

> 后台单选和日期字段已实测为移动端底部面板；OA 附件通过 Android 系统文件选择器取得授权，905.7 KB PNG 能即时预览并保存草稿。图片压缩、200 KB 头像、文件流暂存和账号隔离回归 9/9 通过；真实大照片与服务端 multipart 全链路仍待真机/服务恢复后验证，见 [813](813-oa-mobile-picker-and-attachment-staging-20260908.md)。
>
> 当前网络恢复后，Test Terminal 03 模拟器向 Test Terminal 01 realme 真机完成单聊和群聊实测：单聊在真机未打开会话时出现 1 条未读并刷新摘要，打开后目标消息唯一且发送端收到已读，强制停止并重启真机应用后消息仍唯一、未读不回涨；群消息没有串入当前单聊，目标群独立显示摘要、未读、发送人和已读回传。证据见 [814](814-mobile-to-real-device-direct-sync-20260908.md)。
>
> 群提及成员抽屉遗漏的账号展示已去除，当前 Profile APK 真机/模拟器安装后确认只显示姓名与部门，定向聊天测试 97/97 通过。结构化 `@我` 消息虽已落地，但随后发生同账号另一端消息及已读推进，样本受到桌面 test01 并发活动污染，暂不判定通过或失败，见 [815](815-group-mention-picker-and-unread-boundary-20260909.md)。

> OA 大图片附件补充真机证据：Test Terminal 01 从系统选择器选择 2.80 MB 相片，客户端压缩至 1.3 MB，以账号隔离加密文件暂存并通过 multipart 文件流上传，真实创建 `OA-20260909-39AB5B`；详情回显和应用内图片预览通过，最终 outbox 为 0 且加密暂存文件清空。10 MB 以上、20 MB 边界、弱网恢复、多附件及 iOS 权限仍未验收，见 [816](816-oa-large-photo-multipart-roundtrip-20260909.md)。

> 继续以同一真机真实提交 19 MiB 普通附件，创建 `OA-20260909-CB7E5C`；上传期间 Outbox 保留加密源文件，最终自动恢复到健康状态并清空上传暂存。详情回显、下载百分比、系统打开器和回下载 SHA-256 一致性通过。大文件上传只有“正在提交”没有百分比，见 [817](817-oa-19m-stream-upload-roundtrip-20260909.md)。

> 同一真机继续完成精确上限：20 MiB 文件被客户端和服务端接受，创建 `OA-20260909-EA73D4` 并正确回显；20 MiB + 1 字节在选择返回后立即提示明确错误，附件计数保持 0，未进入队列。图片继续执行“本机压缩后上传”，普通文件保持原始字节流。20 个附件、上传中杀进程/断网及 iOS 路径仍未验收，见 [817](817-oa-19m-stream-upload-roundtrip-20260909.md)。

> 当前 Profile 构建又在 emulator-5556 真实打开测试服“请款审批”动态表单，选择图片后页面由 `0 / 20` 变为 `1 / 20`，账号隔离目录落入主体与预览两份加密 `.imq`；点击删除后目录文件数恢复为 0，全程未提交申请。realme 已覆盖安装同一 SHA 构建且锁屏冷启动无崩溃，但页面退出和单附件替换仍需解锁后补证，见 [850](850-mobile-oa-ephemeral-attachment-cleanup-20260909.md)。

> 继续补测 10 MB 以上图片源：12 MiB 有效 JPEG 在真机完成本机压缩并显示为 1.3 MB，没有套用普通文件上限；但 PSS 最高采样比操作前增加约 100 MB，说明一次性读入原图和两级压缩仍有性能优化空间。测试副本与未提交草稿附件均已清理，见 [818](818-oa-12m-image-local-compression-memory-20260909.md)。
>
> 真实补卡待办详情验证了后端表单字段、页面内审批进度、紧凑底部操作和加签抽屉；移动端已把同一 `stage + nodeId` 的多人任务合并为一个节点，真机重复节点消除。详情接口仍未提供权威 `completionMode`，真实页面只能降级标注“多人审批”，见 [809](809-oa-detail-multi-actor-node-contract-20260908.md)。

## 总体判定

当前目标仍为**部分通过，不能结束验收**。移动端 Android 客户端自身能够独立完成的主页面、信息密度、IM/OA 本地状态、附件流、自动登录和多实例一致性已经有较完整证据；仍有服务端错误已读、群事件长尾、OA 退回权限、当前 Windows 实时窗口对照和锁屏真机推送/交互等外部或设备状态阻塞。

本审计以当前工作树、当前 Profile APK、四 AVD 实际运行、已有真机证据和当前控制通道状态为准，不使用“没有发现问题”替代通过证据。

## 当前构建与回归

- 2026-09-09 最新 Profile APK SHA-256：`9A1265A1E10BF720291E165D32621458B729D86572BDA8A0ACBA0F8348E99A97`（85,792,566 bytes）。
- 四台 AVD 均已保留数据覆盖安装，未回到登录页。
- 三台群聊成员安装后仍完整保留 324 条消息，序号 1..324、ID 和 `clientMessageId` 键唯一、Outbox 为 0、SQLite `quick_check=ok`、事件游标 applied=acked。
- 2026-09-09 图片降级处理、头像裁剪缓存清理与裁剪前原生采样、成员目录隐私、Presence 安全诊断、聊天多图增量 Outbox、OA 图片即时加密暂存和页面临时附件清理合入后，当前工作树全量 Flutter 测试 **1427/1427 通过**，最近一次耗时约 1 分 17 秒；相关静态分析 0 issue，见 [822](822-current-mobile-full-regression-20260909.md)、[848](848-mobile-chat-multi-image-incremental-outbox-20260909.md)、[849](849-mobile-oa-image-immediate-encrypted-staging-20260909.md)、[850](850-mobile-oa-ephemeral-attachment-cleanup-20260909.md)、[851](851-mobile-avatar-native-path-memory-20260909.md)。
- 2026-09-09 OA 20 附件真实边界已补齐：当前构建在 emulator-5556 达到 `20 / 20` 后添加入口禁用，40 个加密文件删除后归零，PSS 保持受控；全量 Flutter 测试仍为 **1427/1427 通过**，见 [852](852-mobile-oa-20-attachment-limit-runtime-20260909.md)。
- 2026-09-09 OA 提交准备阶段强杀后，19 MiB 附件和表单草稿可完整恢复且没有重复申请；现场发现并修复 1.8 MB 孤立加密临时文件，启动清理保持账号隔离且不阻断业务。当前全量 Flutter 测试 **1428/1428 通过**，见 [853](853-mobile-oa-submit-kill-temp-cleanup-20260909.md)。
- 全项目静态分析：0 issue。
- Android Profile 构建：通过。

## 要求与证据矩阵

| 范围 | 当前状态 | 直接证据 | 未闭环项 |
| --- | --- | --- | --- |
| 工作台、消息、待办、通讯录、我的 | Android 真机当前页面通过 | [796](796-mobile-current-build-five-main-pages-audit-20260906.md)、[798](798-mobile-notification-center-system-notification-semantics-20260906.md)、[808](808-real-device-workbench-v1105-boundary-20260908.md) | 桌面 v1.0.105 二级页面因电脑控制服务未配置仍不可直接读取 |
| 页面密度、按钮、输入框、Tab、抽屉 | Android 视觉、点击区域和搜索框原生名称当前边界通过 | [752](752-mobile-oa-detail-density-real-device-20260906.md)、[780](780-mobile-compact-header-touch-targets-20260906.md)、[796](796-mobile-current-build-five-main-pages-audit-20260906.md)、[804](804-real-device-chat-input-navigation-regression-20260908.md)、[815](815-group-mention-picker-and-unread-boundary-20260909.md)、[826](826-real-device-main-tab-hit-target-and-accessibility-audit-20260909.md)、[827](827-mobile-message-title-time-spacing-real-device-20260909.md)、[828](828-mobile-chat-compact-header-real-device-20260909.md)、[829](829-mobile-search-accessibility-real-device-20260909.md) | TalkBack 实际朗读顺序和 iOS 键盘/返回手势未测 |
| 单聊/群聊边界、头像、真实在线状态 | 移动端通过；当前服务端 Presence 汇总与 UI 一致 | [779](779-mobile-realtime-presence-ttl-multivm-20260906.md)、[783](783-mobile-im-event-projection-multivm-20260906.md)、[796](796-mobile-current-build-five-main-pages-audit-20260906.md)、[847](847-mobile-contact-presence-authoritative-runtime-20260909.md) | 服务端错误已读会破坏跨端未读语义 |
| 历史消息、滚动加载、缓存和热打开 | 通过当前 Android 边界 | [768](768-mobile-contact-hot-reopen-multivm-20260906.md)、[769](769-mobile-chat-renderer-isolation-20260906.md)、完整测试中的 510/1000 事件用例 | 中低端真机长会话和 30 分钟内存曲线未完成 |
| 多端消息、离线追平、去重、Outbox | 单聊/群聊实时到达、会话隔离、显式已读、重启去重通过；总体及时性部分通过 | [792](792-mobile-four-avd-im-latency-read-semantics-20260906.md)、[797](797-mobile-multivm-sustained-load-offline-recovery-20260906.md)、[814](814-mobile-to-real-device-direct-sync-20260908.md)、[815](815-group-mention-picker-and-unread-boundary-20260909.md) | 本轮 direct/group 通过；`@我` 样本受桌面同账号并发活动污染，需独立账号重跑；历史群事件长尾及桌面 v1.0.105 可见窗口仍需复验 |
| OA 表单、详情、路径、提交和恢复 | 大部分通过 | [752](752-mobile-oa-detail-density-real-device-20260906.md)、[754](754-mobile-oa-boundary-multi-device-real-device-20260906.md)、[793](793-mobile-oa-submit-process-death-draft-recovery-20260906.md)、[809](809-oa-detail-multi-actor-node-contract-20260908.md) | 多人节点合并已通过；已发布流程未下发 `return`，详情仍缺 `completionMode`，无法权威显示会签/或签 |
| OA/IM 附件、图片、视频、音频 | Android 主要闭环通过 | [751](751-mobile-media-stream-download-real-device-20260906.md)、[755](755-mobile-office-mime-local-render-real-device-20260906.md)、[760](760-mobile-preview-resume-legacy-video-real-device-20260906.md)、[766](766-mobile-attachment-low-storage-cancel-boundary-followup-20260906.md) | iOS、真机极低存储和服务端故意错误摘要未完整覆盖 |
| 自动登录、设备身份、断网恢复 | Android 已验证 | [781](781-mobile-profile-session-offline-recovery-20260906.md)、[795](795-mobile-current-build-real-device-locked-startup-20260906.md) | 当前真机锁屏下不能完成交互和推送点击定位 |
| 应用内通知与系统通知 | 权限与前台补偿通过，后台推送未通过 | [763](763-mobile-system-notification-permission-20260906.md)、[798](798-mobile-notification-center-system-notification-semantics-20260906.md)、[807](807-real-device-system-notification-and-background-message-20260908.md) | 真机权限已开启；恢复前台 15 秒内追平并更新摘要，后台无系统通知，厂商通道仍待接入 |
| 当前 Windows 桌面端对照 | 入站缓存与会话投影通过，UI 未验证 | [750](750-windows-1094-real-window-regression-20260906.md)、[800](800-current-desktop-mobile-inbound-cache-latency-20260906.md) | 当前移动到桌面缓存约 737 ms、摘要投影约 2.623 s；`getTab` 两次超时，仍无法证明可见窗口刷新 |

## 当前明确阻塞

### 服务端

1. 未打开会话时仍可能推进本人已读游标；必须由服务端保证只有显式 `/read` 才能推进。
2. 群事件曾出现 20.259 秒到达长尾；需要 Gateway 等待器、消息提交和唤醒指标定位。
3. 后台已发布“退回”能力，但真实待办仍没有 `return` 可执行权限。
4. 审批详情接口未返回节点级 `completionMode`；移动端不能靠任务人数或状态猜测会签、或签和依次审批。

### 当前环境

1. realme 真机现已开启系统通知权限；有效消息的前台追平通过，但后台消息通知、锁屏通知点击定位与 Doze 推送链路仍未通过。
2. 当前 Windows 电脑控制服务未配置，不能直接读取和操作桌面 v1.0.105 运行窗口；不得用仓库内旧桌面源码替代真实窗口验收。

## 下一轮通过门槛

1. 服务端修复后重跑：不可见会话未读、显式可见已读、同账号桌面/移动已读互通、群聊长尾。
2. 接入厂商推送通道后重跑：后台消息、锁屏通知、点击定位和 Doze；继续回归已通过的前台追平。
3. 电脑控制通道恢复后读取当前 Windows 版本，逐项对照工作台、消息、OA、附件和通知；不沿用历史窗口结论。
4. 上述证据全部通过后再执行最终完成审计；任一项目缺少真实证据时不得把目标标记为完成。
# 2026-09-09 图片上传补充

- [818 · OA 12 MiB 图片本机压缩与真机内存观察](818-oa-12m-image-local-compression-memory-20260909.md)
- [819 · 移动端图片流式本机压缩改造](819-mobile-image-stream-native-compression-20260909.md)
- [820 · OA 外部预览缓存回收](820-oa-external-preview-cache-retention-20260909.md)
- [821 · 真机“我的”、账户安全与登录设备复验](821-real-device-profile-security-and-device-list-20260909.md)
- [822 · 当前移动端全量可信回归](822-current-mobile-full-regression-20260909.md)

> 18.63 MB、6000×4000 高熵 JPEG 真机选择与本机压缩功能通过。进一步启用 Android 原生自适应采样解码后，同样本峰值 PSS 从395 MB降至267 MB（约-32%），相对基线增量约减半，输出2.5 MB且临时目录无残留；当前realme边界改为部分通过。约 2 GB Android 模拟器随后以 12.74 MB、6000×4000 高熵 JPEG 通过，峰值相对基线约 +28 MB，进程存活且暂存清理完成，见 [819](819-mobile-image-stream-native-compression-20260909.md)、[846](846-mobile-low-memory-large-image-runtime-20260909.md)。iOS 仍待补测。

# 2026-09-09 头像成功链路补充

- [845 · 头像本机裁剪、压缩、上传、回显与恢复](845-mobile-avatar-local-processing-upload-restore-20260909.md)

> Android 模拟器已真实完成头像相册选择、圆形裁剪、本机压缩、上传回显和恢复原内置头像；同时修复成功上传后裁剪临时 JPG 残留。头像仍是现有小图片协议例外，IM/OA 图片与文件继续使用压缩后的文件流，不转 Base64。
