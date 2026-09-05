# 711 IM 同步任务销毁与重启隔离

2026-09-04，Asia/Shanghai。本轮为 progress；完整移动端 IM/OA 对齐目标仍未完成。

## 复现与修复

此前 709 记录的同步协调器销毁异常已通过实际 Provider 容器和本地 HTTP/SQLite 测试复现，不依赖线上故障：

1. 仅创建、尚未启动的 `imSyncCoordinatorProvider`，销毁容器后即出现 `UnmountedRefException`。旧 `stop()` 在等待网络订阅取消之后调用 `markUnavailable()`，此时目标 Provider 已销毁。
2. bootstrap 尚未返回时停止任务，迟到成功仍发布 `onChanged` 并标记可用。新增用例期望 0 次发布，实际 1 次。
3. 在旧 bootstrap 等待期间停止再启动，旧结果仍发布，期望只有新任务发布 1 次、实际 2 次，并可能产生另一同步循环。

本轮只针对同步生命周期修改，不修改登录协议、服务端、业务数据库或历史业务数据：

- 将永久 `dispose()` 与可重启 `stop()` 分开：Provider 销毁只终止工作，不再写其他 Provider。
- 每次开始/停止更新任务代次，所有异步返回点核对归属。旧 bootstrap、补偿、发送结果、事件拉取及失效处理不能影响新循环。
- 停止立即取消长轮询、解除旧句柄、清理唤醒标记并完成等待者，再等待订阅/旧循环结束。旧清理回调不覆盖新句柄。
- 失效终止同时关闭网络监听，永久销毁后禁止重新启动；只停止则仍可重新启动。
- Provider 回调额外检查存活状态，避免已销毁 Ref 失效。

## 回归

新增 9 项生命周期测试：未启动容器销毁、bootstrap 迟到成功/失败、停止再启动、长轮询取消及推送等待释放、销毁后迟到成功/失败、旧会话终止回调、新旧网络订阅异步取消竞争。使用真实本地 HTTP 与 SQLite，所有账号、令牌均为本地夹具；没有线上凭据输出。

- 最初 5 项中 3 项失败、2 项通过，失败对应以上三个产品问题；工具输出中保存原异常栈与断言结果。
- [新增 9/9](../test/evidence/im-sync-lifecycle-20260904/lifecycle-tests.log)。
- 同步专项首次 27/27：新生命周期初始 5 项、断网恢复、500/510/1000 条补拉、历史修复、精确失效。
- [全量 1188/1188](../test/evidence/im-sync-lifecycle-20260904/full-tests.log)，未更新 Golden。
- [静态检查 0 问题](../test/evidence/im-sync-lifecycle-20260904/analyze.log)。

## 构建环境

第一次构建使用默认 Gradle 缓存，在 `settings.gradle.kts` 出现 `run/file/require/plugins/id` 无法解析，已在工具输出记录，未修改 Gradle 脚本绕过。

改用本机既有 `E:\CodexToolchains\gradle-cache-secureaccess-mobile` 作为本次进程 `GRADLE_USER_HOME` 后重新构建；[本次构建日志](../test/evidence/im-sync-lifecycle-20260904/build-project-cache.log)。没有删除任何缓存或修改全局环境变量。Flutter 使用 `E:\CodexToolchains\flutter-3.47.0`，普通入口 `lib/main.dart`、Profile、arm64+x64。

## 真机安装与交互

- 使用项目缓存构建成功，60.2 秒；第三方 secure_tunnel 的 Built-in Kotlin 未来迁移警告仍在，没有修改依赖来消除提示。
- RMX3366 保留数据覆盖安装成功，设备 base.apk 与产物 SHA256 一致：`4DC8AA76CE4CA2A8316C5CF88E65E14F48EA40B3C6499AA0EF3F1B5E3A961558`。使用普通入口，未运行测试探针。
- Test Terminal 01 自动恢复；真实从消息列表进入 Test Terminal 02 单聊并返回 3 次，进入已有 `AI-UAT-20260902-202100-M1-M3-GROUP` 测试群并返回 3 次。每次读取实际界面节点定位，验证会话标题和输入框存在，未盲点固定坐标。
- [单聊截图](../test/evidence/im-sync-lifecycle-20260904/phone-direct.png)和[群聊截图](../test/evidence/im-sync-lifecycle-20260904/phone-group.png)已人工查看：真实头像、合并消息头像、图片及视频预览可见；单聊保留任务页签，群聊显示成员信息和 @ 入口。截图不证明对方在线状态或媒体播放端到端通过。
- Home 后返回及强停进程冷启动成功；[冷启动截图](../test/evidence/im-sync-lifecycle-20260904/phone-cold-restored.png)中同一账号、工作台仍在，没有登录页。冷启动系统 Activity 时间 737ms，仅记录，不视为完整页面或 IM/OA 性能达标。
- 页面往返期间按当前进程采样，FATAL、未处理异常、已销毁 Ref、RenderFlex 溢出计数均 0。本次没有捕获会话续期/失效日志事件，不将其包装为续期 HTTP 成功。
- 没有新建、发送或删除消息；打开会话仍允许应用正常进行已读/事件确认。未登出、清令牌、清应用数据或切换系统网络。手机正在共享网络，本轮不关闭其 Wi-Fi/移动数据干扰其他设备；断网边界由本地受控回归覆盖。

## 验收边界

自动化验证了受控异步竞争，真机验证了普通包安装、会话往返和冷启动恢复，不等同于已在线上真机复现相同的毫秒级时序。未进行真实账号登出/重新登录，避免打断用户本轮关注的登录保持。

仍开放：真机长时间会话续期、完整桌面/多移动端互斥与改密码矩阵、推送、iOS、长期大群性能、高级 OA 分支/会签/或签/多人办理付款/公式附件与全部通知状态。不得以本轮测试通过将完整目标标为完成。
