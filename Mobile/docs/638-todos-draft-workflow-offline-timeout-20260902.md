# 待办、草稿与审批流程离线状态真机验收

## 结论

- 待办六个分类可以横向滑动，`草稿箱`、`待同步`均可完整显示和点击，选中下划线与文字保持移动端间距。
- `待同步`无记录时使用独立空态，不再附带普通审批列表的搜索栏和离线提示。
- 本机草稿可在服务不可达时打开，后台表单字段、草稿值、附件入口和底部操作均保持可用。
- 审批流程预览的移动端等待上限由 12 秒缩短为 6 秒；超时后停止转圈，显示“网络不可用，表单与草稿已保留”，并提供独立重试。
- 重试只重新解析流程，不清空表单或草稿；真机重试后再次在 6 秒内恢复到同一离线状态。

## 真机步骤

1. 打开待办并横向滑动分类：通过，六分类均可见，`待同步`可点击。
2. 打开待同步：通过，显示“没有待同步申请”。
3. 打开草稿箱：通过，显示一条本机草稿，列表信息保持紧凑。
4. 打开草稿：通过，表单从本机恢复，未保存、未提交、未删除。
5. 等待审批流程解析：通过，6 秒内进入明确离线状态，草稿仍在。
6. 点击重试：通过，先显示解析中，6 秒后重新回到离线可重试状态，没有重复弹窗。
7. Android 16 模拟器覆盖安装并启动：通过，工作台和底部导航正常。

## 证据

- 分类横滑：`Mobile/test/evidence/todos-current-audit-20260902/02-todos-tabs-scrolled.png`
- 待同步空态：`Mobile/test/evidence/todos-current-audit-20260902/03-pending-sync.png`
- 草稿列表：`Mobile/test/evidence/todos-current-audit-20260902/04-drafts.png`
- 修正前 12 秒等待：`Mobile/test/evidence/todos-current-audit-20260902/05-draft-detail.png`
- 原有超时状态：`Mobile/test/evidence/todos-current-audit-20260902/06-draft-detail-timeout.png`
- 干净构建真机最终状态：`Mobile/test/evidence/todos-current-audit-20260902/10-clean-build-real-final.png`
- 真机重试后状态：`Mobile/test/evidence/todos-current-audit-20260902/13-retry-offline-returned.png`
- Android 16 模拟器：`Mobile/test/evidence/todos-current-audit-20260902/11-clean-build-emulator-final.png`

## 验证结果

- OA 页面测试：55/55 通过。
- 全量自动化：303/303 通过。
- `flutter analyze`：0 问题。
- 干净 Profile APK：69,428,260 bytes。
- SHA-256：`939E081D6D9E036C814FF89445AED71E8BE37ACBA9194EF8CD7125312DEEA1ED`。
- 已覆盖安装 realme RMX3366 与 Android 16 模拟器。

## 未覆盖边界

- 测试服务仍不可达，无法验证流程预览恢复后的真实审批人、岗位、部门和审批方式。
- 本轮只读打开已有草稿，没有保存、提交、删除或修改业务数据。
