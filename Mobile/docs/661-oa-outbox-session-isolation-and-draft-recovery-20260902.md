# 661 OA 待同步会话隔离与真实草稿恢复

时间：2026-09-02，测试环境 `api.sfhkh.com`。结论：局部通过，完整 OA/IM 目标仍未完成。

## 修复及本地证据

- 上传附件后和队列任务之间重新读取当前凭据，可能让旧账号的申请使用新账号身份发送；旧请求的迟到结果也可能错误删除或失败化旧队列。
- 申请提交全过程绑定原始会话快照。网络阶段前后校验会话；队列写入、上传进度及成功/失败落库使用 `withCurrentSession` 短事务保护。切号、同账号重登或退出后停止旧链，不处理后续任务，不使用新凭据重发旧申请。
- 当前会话 `401` / `409 + session_replaced` 保留 pending 并停止当前批次；重新登录后可用原 `clientRequestId` 重试。普通业务 `409` 仍按业务失败处理。
- 本地 HTTP + SQLite 用例：提交/补传 × 切号/重登/退出共 6 项，迟到成功/500 两项；修复前 8 项失败。另两项认证失败保留用例修复前失败，业务冲突对照通过。最终新用例 11 项、联合附件/通知回归 **21/21**，全量 **456/456**，静态检查 **0 问题**。

测试：[会话隔离测试](../test/oa_outbox_session_isolation_test.dart)。日志：[首次失败](../test/evidence/oa-session-20260902/outbox-before.log)、[认证失败复现](../test/evidence/oa-session-20260902/auth-before.log)、[联合回归](../test/evidence/oa-session-20260902/targeted-tests.log)、[全量最终回归](../test/evidence/oa-session-20260902/full-tests-final.log)、[分析](../test/evidence/oa-session-20260902/analyze-final.log)。

## 正常包与真实操作

正常 `lib/main.dart` Profile 双架构包 1.0.1+2，大小 84,396,355 字节。构建及 M3 安装 APK SHA256 均为 `63A4DA9F6CF0CB5E7AC86591AEF8E8F7FB43D120148B2AEB7023F5D694B7F61D`。

仅独立模拟器 M3/test03 安装。真机和 M2 未更新或操作；真机操作权询问尚未回复。

1. 真实请假审批，类型以上拉抽屉选择“事假”。事由输入 `AI-UAT-20260902-215300-OA-DRAFT-SESSION`，点击保存草稿。
2. 关闭 M3 Wi-Fi/数据，确认无默认网络，强制停止并重开正常应用，重新进入请假审批。
3. 显示“已恢复上次草稿”，事假及上述完整事由仍在。审批流程显示离线提示，未退出登录。起止时间留空，**没有点击提交，没有新建远端申请**。
4. 恢复 Wi-Fi/数据，默认网络 116。网络恢复后页面仍显示旧离线状态；手动点“重新解析审批流程”才显示 `部门负责人审批 → Test Terminal 03 · 财顺`。该自动恢复缺陷进入后续处理，不能将本轮列为断网恢复全通过。

截图：[选择抽屉](../test/evidence/oa-session-20260902/02-type-drawer.png)、[保存](../test/evidence/oa-session-20260902/04-draft-saved.png)、[断网杀进程后恢复](../test/evidence/oa-session-20260902/05-offline-draft-restored.png)、[联网仍残留错误](../test/evidence/oa-session-20260902/06-network-restored.png)、[手动重试恢复](../test/evidence/oa-session-20260902/07-manual-preview-recovered.png)。同目录 XML 可复核实际值。M3 使用 UTC，截图时间比北京时间早 8 小时。

## 不能据此宣称通过的项目

- 跨账号发送隔离由本地 HTTP/SQLite 复现并验证，不是线上实际切号发起审批验收。
- 服务器可能已接受切号前的上传或提交。保留原申请键依赖服务端幂等；真实服务端重放未验证，上传可能留下孤立文件，未擅自清理。
- OA 事件拉取、目录、通知及其他详情路径尚未全部完成会话竞争审计。
- 当前桌面仅已有 GET 核对，非本轮桌面 UI 操作证据。全部金额分支、会签/或签、多角色通知、附件交付、完整桌面与多端矩阵及性能均未整体验收。

