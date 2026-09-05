# 待办离线状态与移动交互验收

## 结论

服务不可用时，待办页现在保留 SQLite 中的本机记录，并明确显示“当前显示本机记录”；本机无缓存时显示“本机暂无审批记录”，不再用“暂无审批事项”冒充服务端真实空结果。

## 操作链路与健康度

1. 进入待办：通过。真机与 Android 16 模拟器均正常打开，未崩溃。
2. 等待 OA 同步失败：通过。5 秒环境探测超时后，页面进入离线缓存状态。
3. 点击“重新同步”：通过。同步期间离线栏暂时收起；请求失败后恢复离线栏，没有退出登录。
4. 横向滑动分类标签：通过。真机可从“待我处理”滑到“待同步”，长标签不压缩、不换行。
5. 打开筛选：通过。筛选与每个下拉选项均使用向上展开的移动端抽屉；选择“任务”后返回父筛选并可应用。
6. 离线审批详情：未执行。两台设备当前均无可打开的本机审批记录，服务端也不可用。

## 当前运行证据

- 真机离线待办：`Mobile/test/evidence/todo-audit-20260902/02-todo-offline-final-real.png`
- 模拟器离线待办：`Mobile/test/evidence/todo-audit-20260902/02-todo-offline-final-emulator.png`
- 真机横向标签：`Mobile/test/evidence/todo-audit-20260902/03-todo-tabs-horizontal-final-real.png`
- 真机筛选抽屉：`Mobile/test/evidence/todo-audit-20260902/04-todo-filter-sheet-final-real.png`
- 真机筛选选项抽屉：`Mobile/test/evidence/todo-audit-20260902/05-todo-filter-choice-final-real.png`

## 自动验证

- `flutter test`：281/281 通过。
- `flutter analyze`：通过。
- `flutter build apk --profile`：通过。
- APK SHA-256：`AF6D086E0F98F426966E15E8E66D56996F668D6B4F161ECF27D3FC5F3B87FA40`。
- 同一 APK 已覆盖安装到真机 `realme RMX3366` 和 Android 16 模拟器。
- 两端 `AndroidRuntime` 与 Flutter 错误日志为空。

## 无障碍与限制

待办标签、筛选按钮、离线状态和重试入口均有语义标签；本轮以 UIAutomator 可识别性验证。TalkBack 人工朗读、焦点顺序和大字号模式尚未执行。

## 阻塞

2026-09-02 测试服务在 5 秒内仍无响应，因此无法核对在线审批列表、真实审批详情、提交后实时刷新和跨端待办同步。本轮只判定离线状态与本机交互通过，不判定完整 OA 在线链路通过。
