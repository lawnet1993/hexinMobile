# 580 待办分类与根级抽屉真机验收

## 结论

待办页六个分类继续保持横向滑动，避免在 360dp 真机上强行压缩文字和角标。本轮为左右可滚动方向增加 22dp 渐隐边缘，滑动后不再在屏幕边缘露出突兀的半个字或孤立笔画；分类名称和数量角标仍保持完整语义。

移动端选择、确认、文本、日期、日期范围和时间抽屉统一挂到根导航。待办“同步操作”抽屉现在覆盖底部主 Tab 和安全区，背景整体进入模态遮罩，不再停在 Shell 内容区上方形成半截抽屉，也不会在操作期间误触底部导航。审批详情中的直接抽屉同步采用同一根导航行为。

## 真机结果

- 设备：realme RMX3366，Android 14，1080×2400。
- 待办真实分类：待我处理、我发起的、抄送我的、已完成、草稿箱 1、待同步 7。
- 搜索框保持 34dp，筛选按钮保持 34dp，空态继续上移显示。
- 待同步列表真实显示 7 条旧校验失败记录，列表行、时间、状态和操作入口没有被本次布局修改。
- 打开“同步操作”后，抽屉完整覆盖到底部屏幕边缘；仅查看后关闭，没有修改后重提、重试或放弃任何记录。

## 自动化与构建

- OA 专项测试：37/37 通过。
- 完整自动化：209/209 通过。
- `flutter analyze`：0 问题。
- 新增覆盖：窄屏分类左右渐隐、根级抽屉覆盖 Shell 底部导航。
- 只更新 `06-todos.png` 黄金图；其余视觉基线未批量覆盖。
- Profile APK：`build/app/outputs/flutter-apk/app-profile.apk`。
- SHA-256：`D10920B3310EB5A6285B253F30803B518BDB200412093CA0984742E2CEA506AC`。
- 真机覆盖安装：成功。
- 本轮真机 `AndroidRuntime` 与 Flutter 错误日志：0 条。

## 证据

- `docs/device-acceptance/580-todos-before.png`
- `docs/device-acceptance/580-todos-tabs.png`
- `docs/device-acceptance/580-outbox-before.png`
- `docs/device-acceptance/580-outbox-actions.png`
- `docs/device-acceptance/580-todos-fade-initial.png`
- `docs/device-acceptance/580-todos-fade-scrolled.png`
- `docs/device-acceptance/580-outbox-actions-root.png`
- `docs/device-acceptance/580-outbox-actions-root.xml`

## 验证边界

- 没有删除草稿、重试、修改、放弃或提交待同步记录。
- 当前旧记录是在详细错误持久化修复前产生的，因此列表只能显示既有泛化原因；本轮不伪造具体字段原因。
- 根级抽屉行为已覆盖共享移动抽屉和审批详情直接抽屉；其他业务页面仍需随真实操作继续抽查。
