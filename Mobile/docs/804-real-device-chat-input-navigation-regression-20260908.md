# 804 · 真机会话输入、返回手势与音频资源回归

日期：2026-09-08（Asia/Shanghai）

## 结论

- 当前桌面功能基准按用户确认的 Windows `v1.0.105` 记录。
- realme 真机已安装本轮 Android Profile 构建，并在已登录的 Test Terminal 01 会话中执行只读回归。
- 从单聊“文件”页执行系统边缘返回手势，正确回到消息列表，没有退出应用或停留在半展开状态。
- 重新进入 Test Terminal 05 单聊并点击输入框，系统键盘正常弹出，输入栏保持贴合键盘且未遮挡；首次返回只收起键盘，仍停留在当前会话。
- 音频资源点击后在 App 内播放，右侧图标由播放切换为暂停；再次点击后恢复播放图标。操作前后前台均为移动端 `MainActivity`，没有跳转第三方播放器。
- 消息页“群聊”标签移入摘要行后，单独更新 `04-messages` 黄金图；人工检查未发现日期挤压、文本遮挡或底部 Tab 回归。

## 自动验证

- `flutter analyze`：0 issue。
- 聊天详情专项：97/97 通过。
- 完整 Flutter 测试：1405/1405 通过。
- Android Profile APK：72,014,759 bytes。
- SHA-256：`4487DE7DBA8C0699FDE28AF03306C38C08BB84F4EF6DCB283C55EBD7279C2E24`。

## 证据

- [系统键盘打开且输入栏未遮挡](../test/evidence/real-device-main-pages-20260908/chat-keyboard-open.png)
- [音频资源页播放态](../test/evidence/real-device-main-pages-20260908/audio-resource-playing.png)
- [音频资源页暂停态](../test/evidence/real-device-main-pages-20260908/audio-resource-paused.png)
- [消息页黄金图](../test/goldens/04-messages.png)

## 未由本轮证明

- 键盘输入、换行、表情、附件选择和发送后的跨端可见性没有在本轮写入测试数据；本轮仅验证布局、键盘和返回交互。
- iOS 返回手势和键盘没有设备证据。
- Windows `v1.0.105` 原生窗口仍不在当前可控制的窗口表面中，因此桌面可见 UI 的逐像素对照仍缺证据。
