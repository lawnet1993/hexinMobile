# 合兴智联移动终端

Flutter 移动终端，提供终端登录、工作台、IM、OA 待办、通讯录和个人设置。网络能力由仓库内的 `secure_tunnel` 联邦插件托管，业务页面不直接管理 mihomo 进程。

## 目录

- `lib/core`：环境、网络、路由、安全存储和受签名产物管理。
- `lib/features`：按登录、工作台、消息、待办、通讯录、个人中心和安全连接拆分。
- `lib/shared`：通用移动组件和页面状态。
- `test/goldens`：与确认设计稿对应的十个页面基准图。
- `android`：Android 应用壳和 Release 签名约束。
- `ios`：iOS Runner、Packet Tunnel Extension 和 mihomo XCFramework 接入。

## 本地验证

```powershell
C:\dev\flutter\bin\flutter.bat pub get
C:\dev\flutter\bin\flutter.bat analyze
C:\dev\flutter\bin\flutter.bat test
C:\dev\flutter\bin\flutter.bat build apk --debug --target-platform android-arm64,android-x64
```

完整构建、密钥注入、原生内核和真机验收见 [移动终端交付说明](../../docs/mobile-terminal-delivery.md)。
