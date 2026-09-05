# 698 Android 原生推送令牌安全存储

日期：2026-09-03（Asia/Shanghai）。结论：Android 原生令牌存储迁移、环境隔离与异常关闭行为在 M3 模拟器通过；真实离线推送尚未接入，完整 IM/OA 目标未完成。

## 实现

修复 [697](697-mobile-push-lifecycle-and-session-isolation-20260903.md) 发现的 Android `mobile_push` SharedPreferences 明文副本问题。

- 新增 [SecurePushTokenStore.kt](../android/app/src/main/kotlin/com/hexing/zhilian/hexing_terminal_mobile/SecurePushTokenStore.kt)：AndroidKeyStore AES-256-GCM，每次写入产生新 IV，以环境 namespace 作为 AAD；不同环境使用不同密钥别名和文件。采用系统 Keystore，模拟器测试不能证明硬件安全芯片能力。
- 密文用 AtomicFile 写入应用 `noBackupFilesDir`，不将其放入自动备份目录；读取不自动重建丢失密钥，篡改/未知版本/无密钥返回空，不回退明文。
- 原生 `getToken` 和事件订阅带上与 Flutter 相同的 `AppEnvironment.storageNamespace`；Android 忽略不匹配或未带 namespace 的令牌，SDK 发布入口也要求明确 namespace。
- 旧数据没有环境归属，先迁移到不可作为当前令牌读取的加密隔离记录，验证成功后仅删除旧 provider/token 两个键，保留其他偏好。不会猜测并自动把历史令牌绑定到当前测试或正式环境。
- [MainActivity.kt](../android/app/src/main/kotlin/com/hexing/zhilian/hexing_terminal_mobile/MainActivity.kt) 将加解密/存储任务放到单线程执行器，不阻塞主线程；失败不输出令牌，不写不安全备份。
- 设计依据：[Android 官方 Keystore 文档](https://developer.android.com/privacy-and-security/keystore) 对不可导出密钥、加密用途约束及避免主线程密码学操作的说明。代码和实测是本项目实现证据，文档不是端到端验收证据。

本轮只改 Android 原生安全存储。现有 APNs 桥接仍是单独待迁移项；Dart 保留其旧协议兼容，增加测试防止 Android 升级静默禁用 APNs，**不宣称 iOS 存储已安全或已实测**。

## Android 16 模拟器原生验证

仅在 M3 执行 [独立 Instrumentation](../android/app/src/androidTest/kotlin/com/hexing/zhilian/hexing_terminal_mobile/PushStoreInstrumentation.kt)，合成数据使用独立 `ai-uat-push-<runId>` 目录、密钥别名和偏好文件，不读取现有登录密码/Token，不接入线上推送、不生成真实业务消息。测试 APK 不包含生产功能入口。

| 阶段 | 原生实际结果 | 证据 |
| --- | --- | --- |
| 首进程：17 项 | 空夹具、读写、环境隔离、密文不含令牌/provider、密钥 encoded=null、不备份目录、重复写 IV 变化、新实例读取、非法路径/过长值拒绝、篡改拒绝、跨环境复制密文拒绝、丢失密钥不重建、新令牌恢复、旧明文清除/加密隔离/幂等 | [seed 日志](../test/evidence/native-push-keystore-20260903/native-seed.log) |
| 新进程：5 项 | 结束首进程后再次运行，测试/正式夹具独立保留、隔离旧记录不可读取、篡改仍拒绝，最后清理本轮夹具密钥和值 | [新进程日志](../test/evidence/native-push-keystore-20260903/native-restart-verify.log) |
| 进程独立性 | PID 20055 → 20095，总计 **22/22** | [核对结果](../test/evidence/native-push-keystore-20260903/native-verification.json) |

Instrumentation 先在独立 Debug 构建上执行原生存储类，之后恢复正常 Profile 包。没有用 Mock 加密器替代 AndroidKeyStore；但这不是物理手机、卸载重装、系统备份恢复或真实 APNs/FCM 投递验证。测试中的密钥丢失为指定夹具 alias 删除，不是删除真实设备密钥。

复现入口：先构建 `:app:assembleDebug :app:assembleDebugAndroidTest`，安装对应 Debug APK 和 test APK；使用同一新 runId 分别执行 runner 的 `phase=seed` 和 `phase=verify`，中间结束目标进程。runId 只接受 32 位十六进制，测试状态仅写固定检查名称/计数，不输出令牌。不可复用已经清理的 runId 当作新的重启保留证明。

## Flutter 与正常包回归

- 新增 [native_push_storage_scope_test.dart](../test/native_push_storage_scope_test.dart) 五项：匹配/错误/无 namespace 的原生返回、事件订阅环境隔离、APNs 兼容。专项 **28/28**：[日志](../test/evidence/native-push-keystore-20260903/targeted-final.log)。
- 全量 **989/989**：[日志](../test/evidence/native-push-keystore-20260903/full-tests.log)；分析 **0 问题**：[日志](../test/evidence/native-push-keystore-20260903/analyze-final.log)。
- Android Debug/test APK 构建成功：[原生测试构建](../test/evidence/native-push-keystore-20260903/native-test-build.log)。正常 `lib/main.dart` arm64+x64 Profile 构建成功，93.2 MB：[正常包构建](../test/evidence/native-push-keystore-20260903/normal-build.log)。
- 两台最终正常包 SHA-256 均为 `0DF03E73F7500F5E4216E36835690CB5A6B1F7CE76C7EA711034AD1F23277FB7`，实际安装 base.apk 与本地相同：[运行核对](../test/evidence/native-push-keystore-20260903/normal-runtime-final.json)。网络开启，短时当前进程异常/溢出和临时诊断匹配 0，不等于长期性能通过。
- M3 保留 test03、M4 保留 test04：[M3 工作台](../test/evidence/native-push-keystore-20260903/m3-normal-home.png)、[M4 工作台](../test/evidence/native-push-keystore-20260903/m4-normal-home.png)。M3 原生打开 [消息列表](../test/evidence/native-push-keystore-20260903/m3-normal-messages.png)，M4 打开 [我的](../test/evidence/native-push-keystore-20260903/m4-normal-profile.png) 和 [通知设置](../test/evidence/native-push-keystore-20260903/m4-normal-notifications.png)。
- 安装前后群消息/读状态、两条待发媒体身份、OA 草稿/已读/outbox，**12/12 保留检查通过**：[结果](../test/evidence/native-push-keystore-20260903/retention-checks.json)。不要求后台自动重试次数不变，不宣称旧媒体送达。
- M3 测试夹具敏感值和专用 alias 已清理，test APK 已卸载，可从本地构建产物重装；没有卸载正式目标应用、清除业务数据库或回滚源文件。最终 M3 停在消息列表，M4 回到工作台；真机和其他模拟器未操作。

## 未完成与边界

1. 当前正常包仍显示“离线推送未注册”。SDK/平台测试配置尚未提供；本轮没有注册合成 token 到线上，不能把 22 项原生检查等同于推送唤醒/投递通过。
2. `publishPushToken` 现在必须传入确定的环境 namespace；后续实际 SDK 接入必须把后台回调也绑定到对应环境，不允许使用默认环境猜测。
3. iOS `AppDelegate` 的 UserDefaults 副本仍需 Keychain 迁移与 Mac/真机验证；当前仅兼容原桥接。跨冷启动推送隐私配置、注销在途请求与服务端排序、点击推送定位消息等仍待完整验收。
4. Keystore 丢失/重装后的真实设备绑定规则、系统备份恢复和多系统版本/物理手机安全行为未在本轮执行。
5. [695 媒体上传 500](695-im-upload-failure-diagnostics-20260903.md)、完整桌面/移动矩阵、高级 OA、Windows 实际 UI、真机逐页与长期性能等仍保持开放。没有缩小总体目标。
