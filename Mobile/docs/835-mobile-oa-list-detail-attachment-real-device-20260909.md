# 移动端 OA 待办、详情与附件真机验收

> 验收日期：2026-09-09  
> 设备：Android 真机  
> 范围：待办列表、审批详情、审批进度、附件下载与打开

## 结论

本轮已验证范围通过；首次下载进度仍保留“自动化已覆盖、真机本轮未重新捕获”的证据边界。

- 待办分类栏支持横向滚动，较长分类不会被强制压缩或换行。
- 搜索框、筛选入口、事项行和状态标签保持移动端紧凑尺寸。
- 事项列表使用标题、申请编号/人员/部门、时间与状态的两行结构，没有桌面表格式拥挤。
- 审批详情展示后端实际表单字段和值，没有把“自动计算、只读、单位”等设计器配置文本冒充业务值。
- 审批进度直接在详情下方展开，显示当前节点、多人审批方式、实际人员、部门和个人状态。
- 更多、驳回、同意组成固定底部操作条，未使用过大的悬浮操作按钮。
- 20 MB 文本附件由用户点击后打开；本轮命中本地完整缓存，随后成功通过 Android 文件查看器选择页交接，MIME 类型为 `text/plain`。
- 普通附件以流式文件下载和落盘方式处理，不以 Base64 载入内存；完成缓存按账号和环境隔离并执行大小/摘要完整性校验。

## 真机证据

- `test/evidence/main-tabs-20260909/real-device-todos-current.png`
- `test/evidence/main-tabs-20260909/real-device-todos-current.xml`
- `test/evidence/main-tabs-20260909/real-device-approval-detail-current.png`
- `test/evidence/main-tabs-20260909/real-device-approval-detail-current.xml`
- `test/evidence/main-tabs-20260909/real-device-approval-attachment-immediate.png`
- `test/evidence/main-tabs-20260909/real-device-approval-attachment-after-2s.png`
- `test/evidence/main-tabs-20260909/real-device-approval-attachment-after-2s.xml`

## 自动化回归

```text
flutter test test/oa_action_dialog_guard_test.dart test/oa_action_session_isolation_test.dart test/oa_attachment_stream_storage_test.dart
```

结果：147/147 通过。

覆盖首次流式下载与进度、完整缓存复用、同尺寸损坏缓存重下、文件完整性、账号/会话切换隔离、重复点击保护，以及同意、驳回、撤回、转交、加签、退回、催办等动作在离线或任务版本变化时的提交保护。

## 证据边界

- 真机本轮附件已在此前运行中缓存，因此点击后直接打开，未重新显示首次下载进度；首次下载进度由当前实现和自动化用例证明，不能冒充本轮真机截图证据。
- 本轮没有执行同意、驳回或更多操作，未改变远端审批数据。
- OA 节点完成规则和退回语义仍依赖服务端能力，需在相应服务端契约明确后再完成跨节点真机验收。
- iOS 真机尚未验收。
