# 681：通讯录进入会话防重入与当前运行复核

## 结论

**部分通过，完整 IM/OA 和性能目标继续。** 修复了联系人入口在收起键盘期间可被重复触发、已有会话也会重复入栈的问题。新增 8 项组件回归，全量 **775/775**、静态分析 **0 问题**。正常 Profile 包仅更新 M3，20 次真实“头像进入已有单聊 → 一次返回通讯录”全部完成，原消息与 OA 草稿保留。

**性能不能整体判通过。** 新包安装后的首次模拟器冷启动 `TotalTime=10617ms`，明显偏慢；本轮尚未取得 Flutter UI/Raster 帧数据，也没有完成大组织、多会话、大群和真机性能验收。常驻 PSS 回落，但交换内存增加，不能只看 PSS 就宣告没有泄漏。

前一目标轮是实质进展：680 修复、验证并记录了待发列表摘要与真实媒体阻塞。本轮继续从当前设备和工作树验证，不沿用 633 旧环境真机结果为当前包背书。

## 环境及证据范围

- 时间：2026-09-03 02:58—03:08，Asia/Shanghai。
- 项目：`E:\SecureAccess-client-source-20260824-151204\Client\Mobile`；既有未提交改动保留，未重置、提交或推送。
- M3：`emulator-5556`，Android 16，test03。只操作此设备，不接管 M1/M2，不更改密码、不新建会话或发送消息。
- 已有单聊：Test Terminal 01，会话 `2a2ea21f-2ad6-49b3-b3da-407d1e7e4136`；原 6 条已确认文字及 1 条待发图片。
- 入口：`lib/main.dart`，正常 Profile APK；SHA-256 `3494CF36ACAD83C752824695C2636144619CFE588229C809A890A1F36F1D8B78`，安装包与设备 APK 一致，见[安装核对](../test/evidence/im-navigation-performance-20260903/installed-final.json)。
- 本轮没有 Windows 窗口操作，不用桌面旧源码推测新窗口行为；已有会话复用逻辑与移动端真实当前数据核对，不宣称完成桌面/移动双端性能对照。

## P2-681-01：收起键盘期间重复进入（已修复）

### 可复现步骤与实际表现

1. 通讯录中存在一个允许发起单聊的联系人；分别覆盖已有单聊和需要创建单聊两条路径。
2. 让 `TextInput.hide` 保持未完成，连续触发两次联系人行或头像。
3. 完成键盘收起。原代码在这之前没有设置 `_openingConversation`；已有单聊分支还完全绕过该标记。
4. 组件测试实际观察到 **2 次会话路由入栈**；新会话场景有重复调用创建方法的风险。保留型回调在会话已经打开时也能再次入栈。键盘平台调用异常原先落在 try/catch 外，产生未处理异常。

预期：一个进入操作只创建/打开一次会话，进入前先收起键盘，返回后允许再次进入，失败后可重试，页面销毁后不再导航。

本次重复入栈由真实 Flutter/GoRouter 组件测试加受控异步平台调用复现；**没有故意在远端重复创建业务会话**。真机/模拟器的键盘延迟竞态尚未单独捕获，不把组件注入当作原生竞态录像。

### 修复

- `contacts_page.dart` 在第一个 await 前锁定进入操作，统一覆盖已有/新建两条分支。
- 等待聊天路由返回后再解锁，防止过渡期与保留回调重复入栈；已有会话仍直接复用，不为这次防重入增加网络请求。
- 键盘收起也纳入异常处理；创建返回后先判断 mounted，再更新 Provider/导航；所有退出路径在 finally 释放标记。
- 提取 `contactConversationCreatorProvider` 作为测试边界，默认仍调用原仓库的 `createDirect`，未改变服务端协议或业务权限。

没有为了规避重复导航取消头像入口、增加确认弹窗、添加大加载层或清空消息缓存。

### 回归证据

新增 `test/contact_navigation_guard_test.dart` 8 项：已有/新建 × 行/头像四个并发用例、路由存续期锁定、键盘失败重试、创建失败重试、键盘等待中销毁。

首次夹具尝试实现 final 仓库类导致编译失败，未作为有效红测；改用 Provider 边界后，有效[红测](../test/evidence/im-navigation-performance-20260903/navigation-red-verified.log) **2 过/6 失败**，包含两次入栈及平台异常。修复后与通讯录/首页冒烟共同[回归 36/36](../test/evidence/im-navigation-performance-20260903/navigation-green.log)，最终[全量 775/775](../test/evidence/im-navigation-performance-20260903/full-final.log)、[分析 0 问题](../test/evidence/im-navigation-performance-20260903/analyze-final.log)、[正常包构建成功](../test/evidence/im-navigation-performance-20260903/build-final.log)。

## 当前模拟器真实操作

1. 进入通讯录，默认只有折叠组织；展开“其他联系人”，显示 Test Terminal 01，不需要右侧聊天按钮，头像可直接进入已有单聊。见[新包默认折叠](../test/evidence/im-navigation-performance-20260903/06-new-contacts.png)、[展开后](../test/evidence/im-navigation-performance-20260903/07-new-contacts-expanded.png)。
2. `scripts/verify-contact-reopen.ps1` 连续 20 轮：每次由新 UI 层级定位头像 → 点击 → 新 UI 层级确认目标单聊 → 单次 Android 返回 → 新 UI 层级确认通讯录。任何页面不符合预期立即停止，不按旧坐标继续盲点。
3. [逐轮结果](../test/evidence/im-navigation-performance-20260903/normal-20.json) **20/20**，每轮只有一次返回操作，进程始终为 8507。41 份独立 XML 留在同一证据目录，不复用旧页面树。
4. [第 20 轮返回后](../test/evidence/im-navigation-performance-20260903/08-after-20-contacts.png)仍为展开的通讯录；随后再次点头像，[最终聊天](../test/evidence/im-navigation-performance-20260903/09-final-chat.png)显示相同文字、头像和原待发图片，图片状态仍为等待确认，不伪装已发送。最后返回通讯录。
5. [最终进程核对](../test/evidence/im-navigation-performance-20260903/runtime-final.json)未检出 Flutter 错误或 FATAL EXCEPTION；Wi-Fi/移动数据均开启。该检查不等于所有原生崩溃/ANR 场景已覆盖。

这是连续导航及单次返回稳定性验收，不等于 20 次原生双击竞态复现，也没有证明所有会话切换都不发生必要的 Widget build。原有消息窗口缓存回归仍通过，本次没有清缓存或以静态截图替换消息渲染。

## 性能事实与边界

### 慢启动：仍待定位

正常包覆盖安装成功后第一次 `am start -W`：Status ok、LaunchState COLD、TotalTime **10617ms**、WaitTime **10762ms**，见[记录](../test/evidence/im-navigation-performance-20260903/post-install-launch.json)。随后真实[工作台截图](../test/evidence/im-navigation-performance-20260903/05-new-home.png)和 UI 层级确认应用已进入，不仅依据 Activity 状态。

这是一条安装后模拟器样本，不是均值/P95，不归因于本次防重入代码，也不排除应用启动路径、模拟器图形/IO/宿主争用。`main.dart` 当前没有等待远端请求才调用 runApp，但这不足以排除后续首屏工作。需要补齐重复冷启动、首帧分段和真实设备采样，再定位优化；**不标记性能通过**。

### 内存：保留交换占用，不能只报 PSS 下降

| 完成循环 | PSS KB | Swap PSS KB | 两项合计 KB |
| --- | ---: | ---: | ---: |
| 0 | 180621 | 5330 | 185951 |
| 5 | 193228 | 9502 | 202730 |
| 10 | 184963 | 13638 | 198601 |
| 15 | 183410 | 32215 | 215625 |
| 20 | 178654 | 32190 | 210844 |

PSS 峰值后回落，但两项合计从 185951 到 210844 KB；短样本不能据此确定泄漏或排除泄漏。没有强制 GC、清缓存或重启来压低末次结果。[宿主内存快照](../test/evidence/im-navigation-performance-20260903/host-memory.json)仅记录当时可用量，不据此猜测启动慢根因。

### 帧耗时：未取得有效结果

现有 Profile 进程日志没有发现可连接的 VM service 地址；一次诊断启动命令被工具拒绝且未执行，未绕过限制或关闭认证。改为执行独立的 UI 层级/进程内存检查。

读取到的 Android 宿主窗口累计统计为 28 帧/26 janky，不是 Flutter Surface 的 UI/Raster 帧耗时，不能用它报聊天 92.86% 掉帧，也不能拿 adb 截图/层级生成时长充当用户点击延迟。见[采样口径记录](../test/evidence/im-navigation-performance-20260903/measurement-scope.json)。Flutter 官方建议在 Profile 模式分析 UI/Raster 帧，本轮这部分证据仍缺失。[官方性能说明](https://docs.flutter.dev/tools/devtools/performance)

## 数据保留

[前后逐项核对](../test/evidence/im-navigation-performance-20260903/preservation-final.json)均通过：单聊消息账本一致；所有缓存会话类型、末序号/已读/未读及消息数一致；原两条媒体 Outbox 的 clientMessageId、会话、类型与创建时间一致；OA 2 份草稿、9 条回执、空队列和游标 449 不变。IM applied/acked 均保持 236。

没有发送新消息、重新选择附件、提交/修改审批或直接修改数据库。原媒体队列最后错误仍 HTTP 500；本轮导航成功不能关闭 680 媒体跨端阻塞。

## 复用与剩余项

```powershell
# Mobile 目录；仅独立 M3，先真实打开包含目标联系人的展开通讯录。
# 每次使用新的 RunName，避免覆盖证据。
./scripts/verify-contact-reopen.ps1 -Iterations 20 -EvidenceDirectory 'E:\SecureAccess-client-source-20260824-151204\Client\Mobile\test\evidence\im-navigation-performance-20260903' -RunName 'next-run'
```

- P2-681-01 防重入：本地修复、自动回归和当前正常包顺序导航验证已完成；原生快速连点的不同键盘/设备时序仍需扩展。
- 安装后 10.6 秒冷启动：新增性能调查项，尚未定位；Flutter 帧、长时内存、大目录/大群和多会话性能没有充分证据。
- 真机/M2 接管与更新、Windows 真实操作、完整跨端在线/已读/替换/离线补偿矩阵继续保留。
- 复杂 OA 分支/公式/会签或签/接收人完成/抄送付款、原生推送，以及已记录的服务端媒体、群已读投影、审批任务终态/通知正文缺陷仍未全部验收。

不把本轮导航通过率缩写成完整业务通过率；目标保持进行中。
