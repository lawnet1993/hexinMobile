# IM 移动消息推送服务端验证

> 验证时间：2026-09-05 21:12（Asia/Shanghai）  
> 环境：线上测试环境 `api.sfhkh.com`  
> 身份：Windows 桌面端当前有效的编号测试账号会话  
> 结论：**服务端推送设备注册接口已经上线；真实离线推送投递尚不能判定通过。**

## 1. 实测结果

契约路径：`/api/im/push/devices/current`

| 用例 | 状态 | 请求编号 | 判定 |
| --- | ---: | --- | --- |
| 带有效登录态和当前设备头 `GET` | 404 | `4e34959f-a873-4ad9-b0db-88f6d6be22d9` | 路由存在，但当前 Windows 设备没有推送注册记录 |
| 不带登录态 `GET` | 401 | `83367d16-85fe-4244-9790-5d437ec2ed29` | GET 受鉴权保护 |
| 带登录态但不带设备标识 `GET` | 401 | `9560089e-202d-4c03-aa30-d176e19758d3` | 服务端要求设备身份 |
| 带登录态、损坏 JSON `PUT` | 400 | `1bc208b9-16f4-49c0-b6d9-5b638fd3c38b` | PUT 路由和 JSON 请求绑定已上线；请求未进入有效注册流程 |
| 不带登录态、损坏 JSON `PUT` | 400 | `52595f9e-88f8-4b8d-91c1-1260ec6038b0` | 损坏 JSON 在鉴权结果前被请求解析层拒绝 |

本次没有发送有效 provider token，没有覆盖当前设备注册，也没有调用 DELETE。

## 2. 可以确认的服务端能力

- API Gateway 已转发 `/api/im/push/devices/current`。
- GET 和 PUT 方法已经映射，不是未知路由。
- GET 会校验登录态和设备身份。
- 当前接口可接受移动端代码现有的 `platform`、`provider`、`token`、`privacyMode` 注册模型。
- 当前测试账号的 Windows 设备尚未注册推送，这与桌面端本身不需要移动推送令牌一致。

## 3. 不能据此确认的能力

以下仍缺少真实投递证据：

- 服务端是否能把 IM、OA、公告等事件投递到选定的 FCM/厂商/APNs 通道。
- provider token 的格式校验、更新、失效清理和解绑。
- 多账号、多安装 ID、多环境隔离。
- 应用前台、后台、被系统杀死、断网恢复后的通知到达。
- 推送点击后先同步再定位会话/审批。
- 推送与实时事件同时到达时的事件去重。
- 隐私模式 `summary`、`detail`、`none` 的正文与敏感信息边界。

只有拿到真机生成的有效 provider token，完成 PUT 注册，并从服务端触发真实测试事件后，才能判定“消息推送服务”整体完成。

## 4. 当前移动端实际状态

移动端已经具备：

- `ImRepository.registerPushDevice` / `unregisterPushDevice`，对应 PUT/DELETE 当前设备接口。
- 登录切换、会话过期和退出时的注册生命周期隔离。
- Android MethodChannel/EventChannel 推送令牌桥接。
- Android Keystore 中按环境隔离的推送令牌存储。
- 通知点击目标路由白名单。

但当前有效源码仍未接入真实 Android 推送 SDK：

- `pubspec.yaml` 没有 `firebase_messaging` 或其他厂商推送依赖。
- Android Gradle 没有 Google Services/厂商推送插件和依赖。
- Manifest 没有推送消息 Service，也没有 Android 13+ 的 `POST_NOTIFICATIONS` 权限声明。
- 只有 `MainActivity.publishPushToken(...)` 桥接入口，没有实际 SDK 在 token 生成/轮换时调用它。
- 没有后台消息接收、系统通知展示和推送唤醒同步实现。

因此当前边界应表述为：**服务端设备注册接口已支持，移动端真实推送通道尚未接通。**

### 4.1 移动端服务端能力接入状态

本轮已按上述边界调整通知设置页：

- 服务端 REST 推送状态不再被 IM 实时同步连接状态遮盖，两类状态分别展示。
- 服务端接口成功返回“当前设备未注册”时，显示“服务端注册接口：已接入”。
- 没有原生 provider token 时，显示“厂商推送通道：待接入”，不再笼统显示“离线推送未注册”。
- 只有服务端设备记录和本机 provider token 都存在时，才显示已启用状态、隐私模式和具体通道。

验证结果：

- 通知设置专项 Widget 测试：5/5 通过。
- 推送注册、生命周期、账号隔离和原生存储范围测试：27/27 通过。
- `flutter analyze`：本轮改动没有新增问题；项目另有 6 条既有 `curly_braces_in_flow_control_structures` info。

### 4.2 真机验收

2026-09-05 使用已连接的 realme RMX3366（Android 14 / API 34，1080×2400，480 dpi）完成：

- 使用 Flutter 3.47.0 / Dart 3.13.0 构建 arm64 Debug APK；默认 Gradle 用户缓存复现 Kotlin settings 解析异常，切换到项目既有隔离缓存 `E:\CodexToolchains\gradle-cache-secureaccess-mobile` 后构建通过。
- APK 大小 143,702,403 bytes，SHA-256：`DC4262C3240C3A6F454B3815BEA52B7DC5FD3978B069CAECB1DCA698C8C166CC`。
- `adb install -r` 覆盖安装成功，保留 Test Terminal 01 登录态；安装后多次强制结束并重新启动，均未跳回登录页。
- 在线进入“我的 → 通知设置”，显示“同步状态：实时同步”“厂商推送通道：待接入”“服务端注册接口：已接入”。系统推送卡片高度 192 px，即当前 480 dpi 下 64 dp，没有溢出或截断。
- 关闭手机数据网络并重新启动应用，登录态和本地页面保留；应用内同步显示“连接恢复后同步”。完整等待 50 秒后，系统推送卡片从加载态进入紧凑的“推送状态加载失败 + 重试”，没有永久转圈或错误退出登录。
- 恢复手机数据网络并点击“重试”，10 秒内恢复“实时同步”“服务端注册接口：已接入”“厂商推送通道：待接入”。
- 最终应用进程仍运行；该进程日志中 `FATAL EXCEPTION`、ANR、Unhandled Exception 和 `E/flutter` 均为 0。

真机证据目录：`Mobile/test/evidence/push-server-capability-real-device-20260905/`。关键证据为：

- `03-notification-settings-online.png/xml`
- `08-notification-settings-offline-final.png/xml`
- `09-notification-settings-retry-recovered.png/xml`

本轮验收覆盖服务端能力展示、断网、超时、重试、恢复和登录态保持。真实厂商通知投递仍按既定范围标记为未完成，不在本轮伪造 provider token。

## 5. 下一步真实验收条件

1. 确认 Android 使用的推送提供商，并提供测试环境合法配置。
2. 真机产生 provider token，移动端通过现有 PUT 接口注册。
3. 用 AI-UAT 前缀发送单聊、群聊、`@我`、OA 待办和公告事件。
4. 分别在前台、后台、锁屏、进程被杀和网络恢复场景验证。
5. 点击通知后先执行 IM/OA 增量同步，再定位目标；不得直接把推送正文落库成最终消息。
6. 退出、切换账号、Token 轮换和拒绝系统通知权限时验证注销与恢复。

复验脚本：`Mobile/scripts/inspect-im-push-server.ps1`。脚本只输出状态码、请求编号和非敏感字段，不输出登录凭据、设备 ID 或推送令牌。
