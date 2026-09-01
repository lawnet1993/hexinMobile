# 595 模拟器 OA 真实交互与操作抽屉密度

## 当前结论

已在 1080×2400、420 dpi Android 模拟器上使用隔离 Demo Profile 包完成 OA 待办、审批详情、筛选、新建请假表单、下拉选择和日期选择的真实点击、滚动、返回、截图与 UI 层级检查。Demo 模式不使用线上账号，也未保存草稿、提交申请或处理审批。

本轮修复审批详情仅有一至两个次要操作时仍使用宽松图标宫格的问题：少量操作改为紧凑选择抽屉，较多操作继续使用图标宫格；加签方式同步复用统一移动端选择抽屉。实际只有“转交”时，抽屉高度和信息密度已明显收敛。

## 实际操作覆盖

- 待办：六分类、搜索、筛选和真实列表布局可操作；筛选抽屉覆盖底部主 Tab。
- 审批详情：隔离数据实际渲染出的表单值、附件、流程节点、处理记录、抄送未读/已读和底部操作栏均可滚动查看。
- 审批流程：直接在详情和发起页内展开，节点显示审批类型、实际人员、部门以及会签/或签方式。
- 更多操作：单个“转交”使用紧凑列表抽屉，不再占用不必要的图标宫格高度。
- 筛选：事项类型等筛选项使用底部抽屉；二级“全部类型/任务/审批”选择继续向上展开。
- 新建请假：申请人、部门、版本、请假类型、开始/结束时间、请假事由和审批流程均在同页呈现。
- 表单数据边界：页面没有把“自动计算、只读、单位天”等后台可视化配置串当作业务值显示。
- 下拉选择：请假类型使用底部选择抽屉，显示年假、事假、病假。
- 日期选择：开始时间使用底部日历抽屉，不弹出居中对话框。
- 运行日志：本轮清理后未发现 `FATAL EXCEPTION`、`E/flutter` 或 `Unhandled Exception`。

## 关键证据

- [待办列表](evidence/595-emulator-oa-runtime/01-todos-before-detail.png)
- [审批详情顶部](evidence/595-emulator-oa-runtime/02-approval-detail-top.png)
- [审批流程与处理记录](evidence/595-emulator-oa-runtime/03-approval-detail-bottom.png)
- [修改前的单操作宫格](evidence/595-emulator-oa-runtime/04-approval-more-sheet.png)
- [修改后的紧凑单操作抽屉](evidence/595-emulator-oa-runtime/05-approval-more-compact.png)
- [审批筛选抽屉](evidence/595-emulator-oa-runtime/06-approval-filter-sheet.png)
- [事项类型二级选择](evidence/595-emulator-oa-runtime/07-filter-choice-sheet.png)
- [工作台入口](evidence/595-emulator-oa-runtime/09-workbench.png)
- [新建请假表单与直接展开流程](evidence/595-emulator-oa-runtime/10-request-form-top.png)
- [请假类型选择抽屉](evidence/595-emulator-oa-runtime/11-leave-type-choice.png)
- [开始日期选择抽屉](evidence/595-emulator-oa-runtime/12-start-time-picker.png)

关键 PNG 均保留对应 XML 层级文件，可复核可点击元素、控件边界、字段内容和抽屉层级。

## 验证结果

| 项目 | 结果 |
| --- | --- |
| 模拟器 OA 真实交互 | 11 组关键截图及对应 XML 证据 |
| 完整自动化 | 213/213 通过 |
| Golden | 12/12 通过 |
| 静态检查 | `flutter analyze`，0 个问题 |
| 生产 Profile APK | 构建成功，67,131,199 bytes |
| 生产 APK SHA-256 | `803A4990D898A83E7E2297DF7C7D623ECE5F892890A8A0897867DEE0843076F1` |
| realme 覆盖安装 | `adb install -r` 成功 |
| 真机状态 | `Keyguard showing=true`、`mInputRestricted=true` |

## 未完成项

最新生产包已覆盖安装到 realme 真机，但真机仍被系统锁屏限制。解锁后还需使用真机当前登录会话重复审批详情、筛选、新建表单、请假类型和日期选择的只读链路，并采集真实数据截图和日志；默认不保存草稿、不提交申请、不处理审批。
