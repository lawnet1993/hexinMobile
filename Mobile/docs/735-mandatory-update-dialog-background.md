# 735 强制更新弹窗背景修正

时间：2026-09-05（Asia/Shanghai）。按用户截图修正居中强制更新弹窗的背景层级。

## 改动

- 强制更新仍使用不可关闭的居中弹窗；普通更新继续使用底部抽屉。
- 弹窗主体固定为纯白并关闭 Material surface tint，避免灰紫色背景。
- 去掉会形成粗黑外圈的阴影和外边框，仅保留 16 px 圆角。
- 页面遮罩使用中性黑 36% 透明度；更新说明直接排在白色弹窗中，不再增加灰底或内边框。
- 版本、大小、强制更新标签、文案和下载逻辑均未改变。

## 验证

- `test/client_update_sheet_test.dart`：4/4。
- `test/design_golden_test.dart` 强制更新用例：1/1。
- 全量 `flutter test`：1362/1362；`flutter analyze`：0 问题。
- 320 x 640、640 x 320、150% 字体与长说明覆盖通过。
- 遮罩点击和系统返回均不能关闭强制更新；下载回调仍只触发一次。
- 对照图：`test/evidence/update-dialog-735/01-source-vs-implementation.png`，左侧为用户截图，右侧为最终 Flutter 渲染。
- 覆盖安装同一 Debug APK 到 Android 16 模拟器和 realme 真机均成功；账号会话与本地数据保留。真机工作台显示 Test Terminal 01，未发现 RenderFlex 溢出、Flutter 异常或崩溃；截图见 `test/evidence/update-dialog-735/04-real-device-header-fixed.png`。
- APK SHA-256：`B07051DC471C189E9F9FC86A7771EC1FD499D55788C0E13ADA47B54CED1C7437`。

## 同步修正

- 首次模拟器覆盖安装暴露工作台品牌头部在设备字体度量下底部溢出 1 px；已把固定高度改为最小高度约束，并增加 130% 字体回归。
- 最终模拟器和真机复核均无溢出，旧问题截图保留在 `02-emulator-after-upgrade.png`，修正证据为 `03-emulator-header-fixed.png` 与 `04-real-device-header-fixed.png`。

## 边界

- 本轮只调整视觉背景，不改变版本判断、下载地址、安装和强制策略。
- 线上是否出现强制更新仍由后台版本配置决定；没有修改后台配置来制造弹窗。
