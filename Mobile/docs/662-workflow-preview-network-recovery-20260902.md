# 662 审批流程预览断网自动恢复

时间：2026-09-02 21:56–22:03（北京时间）。环境：`api.sfhkh.com`，独立模拟器 M3/test03。结论：本项修复已实际复验；核心 IM/OA 完整验收仍未完成。

## 问题与修复

661 正常包中，Wi-Fi/数据恢复且服务已可用，已打开的草稿仍永久显示“网络不可用，表单与草稿已保留”。点重试立即能解析真实审批人，说明不是表单不可用。原因是相同表单指纹的失败结果被持续复用，页面没有监听 OA 恢复。

现在监听 OA 同步从非可用到可用的变化，对连接错误、超时和服务端临时错误重新解析当前表单。每次恢复最多自动重试一次；请求未结束时发生恢复，也会在旧请求失败后补一次。取消、401、普通业务冲突及字段校验失败不自动重试，手动重试仍保留。页面关闭会取消延迟请求，不重置用户输入。

修改：[审批申请页](../lib/features/todos/presentation/approval_request_page.dart)。

## 自动回归

[新增 10 项用例](../test/oa_workflow_recovery_test.dart)覆盖网络与 503 恢复、400/401/409/422/取消不重试、请求中途恢复、失败后不循环且保留手动重试、关闭页面取消重试、表单值不变。修复前 4 项失败、6 项对照通过，修复后全部通过。

- [修复前](../test/evidence/oa-preview-recovery-20260902/before.log)
- [修复后](../test/evidence/oa-preview-recovery-20260902/after.log)
- [全量最终结果](../test/evidence/oa-preview-recovery-20260902/full-tests.log)：**466/466**。
- [最终静态检查](../test/evidence/oa-preview-recovery-20260902/analyze-final.log)：**0 问题**。首次检查发现一处测试代码缺少花括号，已修正。
- [构建](../test/evidence/oa-preview-recovery-20260902/build.log)：正常 `lib/main.dart` Profile，arm64+x64，1.0.1+2。既有第三方 Built-in Kotlin 迁移警告仍在。

本地与 M3 实际安装 APK SHA256 一致：`0F3F63C68E9E7F5FB85B5268D44C6503ADC2FBAF73D3E7B3F5CF803237497724`；84,396,355 字节。正常冷启动 8.927 秒、离线冷启动 6.354 秒仅为单次观测，**不是性能验收通过**。

## 真实操作与截图

1. 新包安装后关闭 M3 的 Wi-Fi/移动数据，确认两项均为 0、默认网络 `none`，强制停止再冷启动。
2. 从工作台打开请假审批，恢复原草稿：类型“事假”，事由 `AI-UAT-20260902-215300-OA-DRAFT-SESSION`，起止日期仍未选择。审批流程为离线状态。[离线截图](../test/evidence/oa-preview-recovery-20260902/03-offline-draft.png)
3. **22:02:13** 恢复 Wi-Fi/数据，后续没有点击页面、重试或重新打开。**22:02:29** 检查点仍为离线提示；**22:02:45** 检查点已经自动显示 `部门负责人审批 / Test Terminal 03 / 财顺 / v1`，事假和完整事由保留。[自动恢复截图](../test/evidence/oa-preview-recovery-20260902/06-auto-recovered.png)、[对应 XML](../test/evidence/oa-preview-recovery-20260902/06-recovery-check.xml)
4. 实际打开开始日期上拉抽屉并取消，回到原表单后开始/结束时间依然“请选择”，原事由和流程不变。[日期抽屉](../test/evidence/oa-preview-recovery-20260902/07-date-sheet.png)、[取消后 XML](../test/evidence/oa-preview-recovery-20260902/08-date-cancelled.xml)

这次只读取流程与保留本地草稿，**没有点击提交，没有新建远端申请**。最终 M3 Wi-Fi/数据均 1、默认网络 118。当前进程一次最近 300 行日志检查中 Fatal、E/flutter、overflow 均为 0，不等同于长期稳定性验证。模拟器时区为 UTC，截图比北京时间早 8 小时。

## 剩余事项

- 自动恢复已经发生，但目前受 OA 同步循环影响，只能证明在约 32 秒检查点前恢复，不能声称即时恢复或精确耗时。恢复延迟仍需优化。
- 真机可能由用户操作，本轮未安装/点击；M2 也未操作。没有新的桌面 UI 验收证据。
- OA 事件/目录/详情的会话隔离、服务器群已读投影、群事件缺项、附件失败、自然续期、完整审批分支/会签及多端/性能矩阵仍未完成。
- 本次不改服务端，不删除既有业务数据或待同步队列。完整对齐目标保持进行中。
