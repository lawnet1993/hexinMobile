# “我的”帮助与反馈移动端密度验收

## 结论

- 常见问题保持单列紧凑折叠，不在首屏展开冗长说明。
- FAQ 中的旧名称“消息通知”已统一为当前入口名称“通知设置”。
- “复制诊断信息”不再使用大面积独立按钮，改为设置卡片内 48dp 的“诊断信息 / 复制”行。
- 诊断内容只通过系统剪贴板复制，页面和报告不展示令牌、密码、完整设备 ID 或设备指纹。

## 证据

- 真机最终页：`Mobile/test/evidence/108-help-feedback-final-real.png`
- Android 16 模拟器最终页：`Mobile/test/evidence/109-help-feedback-final-emulator.png`
- 真机展开通知问题：`Mobile/test/evidence/110-help-notification-name-real.png`

## 自动验证

- `flutter test test/help_feedback_page_test.dart`：通过。
- 完整 `flutter test`：280/280 通过。
- `flutter analyze`：通过。
- 最新 profile APK 已覆盖安装到真机和 Android 16 模拟器。

## 限制

测试服务当前不可达，本页的版式、折叠、复制入口和离线可用性已验证；需要服务恢复后才能核对服务端可能追加的远程帮助内容。
