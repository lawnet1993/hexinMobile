# 612 · 真机 OA 密度与底部抽屉回归

时间：2026-09-01

## 结果

- 待办页六个分类固定为单行同屏：`待我处理 / 我发起的 / 抄送我的 / 已完成 / 草稿箱 / 待同步`，不再留下半截分类，也不要求用户横滑发现入口。
- 数量徽标保留在对应分类同一行内；realme 真机当前真实显示 `待同步 7`，没有换行、遮挡或横向滚动。
- 搜索框保持 34dp，筛选按钮保持 34×34dp，空状态上移；没有重新引入大输入框或大按钮。
- 筛选、筛选项选择、新建入口、请假类型和日期选择均从底部抽屉向上展开，没有使用居中弹窗或悬浮下拉。
- 请假审批真实读取线上 v1 表单：类型、开始时间、结束时间、请假天数、事由和附件均由后台 schema 驱动；审批流程在表单下方直接展开。
- 已通过审批详情只展示真实业务值和处理记录；UI 树未出现 `自动计算`、`只读`、`单位天`、`formula`、`fieldKey` 或 `precision` 等后台可视化配置串。

## 验证

- OA 定向：44/44 通过。
- 全量自动化：234/234 通过。
- Golden：13/13 通过。
- `flutter analyze`：0 项问题。
- 干净 Production Profile APK：65,819,655 bytes。
- SHA-256：`02198EB27A3B0E633FE5993E48B8856FD3BB25462CACC91FC6B08C39CBB64B40`。
- 真机安装后的 `base.apk` 大小和哈希与构建包完全一致。
- 本轮清空日志后重放主路径，未发现应用崩溃或 `E/flutter`。

## 数据边界

- 本轮只读打开筛选、新建入口、请假表单、类型/日期选择和既有已通过审批详情。
- 没有选择表单值、保存草稿、提交申请、处理审批、发送消息或修改线上业务数据。
- 实际消息发送和审批提交仍需在执行前确认具体目标与内容。

## 证据

- `docs/evidence/612-real-device-oa-regression/02-todos-six-tabs.png`
- `docs/evidence/612-real-device-oa-regression/03-todo-filter-sheet.png`
- `docs/evidence/612-real-device-oa-regression/04-filter-type-sheet.png`
- `docs/evidence/612-real-device-oa-regression/05-create-choice-sheet.png`
- `docs/evidence/612-real-device-oa-regression/06-new-request-catalog.png`
- `docs/evidence/612-real-device-oa-regression/07-leave-form-top.png`
- `docs/evidence/612-real-device-oa-regression/08-leave-type-sheet.png`
- `docs/evidence/612-real-device-oa-regression/09-start-time-sheet.png`
- `docs/evidence/612-real-device-oa-regression/10-initiated.png`
- `docs/evidence/612-real-device-oa-regression/11-approval-detail.png`

