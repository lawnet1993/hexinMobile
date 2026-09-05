# 工作台与待办同步状态验收

## 结论

工作台审批摘要与待办页现在共用同一套真实同步语义：冷启动期间显示“同步中 / 正在同步审批”，服务不可用后显示“本机记录 / 本机暂无审批记录”，仅在服务端同步成功且结果确实为空时显示“暂无审批事项”。离线提示不是装饰项，工作台点击“本机记录”可直接进入待办并继续查看本机投影或重新同步。

## 操作链路与健康度

1. 冷启动工作台：通过。realme 真机和 Android 16 模拟器均先显示“同步中 / 正在同步审批”，没有提前显示真实空态。
2. 等待同步失败：通过。两端最终均切换为“本机记录 / 本机暂无审批记录”，没有退出登录或清空 SQLite 投影。
3. 从工作台进入待办：通过。真机点击紧凑“本机记录”入口后进入待办，显示“当前显示本机记录 / 重新同步”。
4. 冷启动后立即进入待办：通过。两端均显示 32dp 的“正在同步审批 / 同步中”状态行；同步未结束时不显示“暂无审批事项”。
5. 启动性能：通过客户端检查。设备授权后 Presence、IM 与 OA 三个协调器改为并行启动，OA 状态不再等待前两个网络超时后才更新。
6. 在线正向状态：未执行。测试服务仍不可达，无法验证由“同步中”进入真实在线列表或在线空态。

## 当前运行证据

- 真机工作台同步中：`Mobile/test/evidence/workbench-offline-audit-20260902/03-workbench-connecting-real.png`
- 真机工作台离线完成态：`Mobile/test/evidence/workbench-offline-audit-20260902/04-workbench-offline-final-real.png`
- 模拟器工作台离线完成态：`Mobile/test/evidence/workbench-offline-audit-20260902/05-workbench-offline-settled-emulator.png`
- 真机由工作台进入待办：`Mobile/test/evidence/workbench-offline-audit-20260902/05-todos-from-workbench-real.png`
- 真机待办同步中：`Mobile/test/evidence/workbench-offline-audit-20260902/06-todos-connecting-real.png`
- 模拟器待办同步中：`Mobile/test/evidence/workbench-offline-audit-20260902/06-todos-connecting-emulator.png`

对应 UIAutomator XML 与截图同目录保存；语义树确认同步中、离线空态和入口标签均存在，且各阶段均不存在错误的“暂无审批事项”。

## 自动验证

- `flutter analyze`：通过，无问题。
- `flutter test test/oa_mobile_pages_test.dart`：54/54 通过。
- `flutter test`：284/284 通过。
- `flutter build apk --profile`：通过。
- APK 大小：78,546,214 bytes。
- APK SHA-256：`09C7646130BC437C9F3E247FB768306F75960BB7037B2802DF0BC9E108E64904`。
- 同一 APK 已覆盖安装到 realme RMX3366 真机和 Android 16 模拟器。
- 两端最近 500 行 `AndroidRuntime` 与 Flutter 错误日志为空。

## 限制与阻塞

2026-09-02 测试服务仍不可达，因此本轮证明的是启动、离线降级、状态真实性、入口跳转与布局；在线审批列表、真实新增审批、跨端通知和在线空结果仍需服务恢复后复验。TalkBack 人工朗读、焦点顺序与大字号模式也尚未执行。
