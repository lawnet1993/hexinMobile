# 移动端 OA 提交进程中断与幽灵草稿恢复复验（2026-09-06）

## 结论

本轮已修复并通过 OA 提交在进程中断后的恢复边界：当申请已经进入本地 Outbox、HTTP 响应尚未返回且源草稿仍存在时，强制结束 App；冷启动恢复后 Outbox 成功交付并清除源草稿，服务端只生成一条申请。

真实申请：`OA-20260906-5997C3`，事由 `AI-UAT-OA-INFLIGHT-RECOVERY-FIX-20260906-1716`。

| 检查点 | Outbox | 草稿 | 服务端结果 |
| --- | ---: | ---: | --- |
| 提交前 | 0 | 1 | 无新增申请 |
| 点击提交后约 350 ms 强制停止 | 1 | 1 | 请求响应尚未被客户端消费 |
| 恢复正常网络并冷启动 | 0 | 0 | 新增 1 条申请、1 条通知事件 |

## 原因与修复

原行为只在审批页面等待提交成功后删除草稿。进程如果在 Outbox 已落库、页面尚未收到提交结果时被终止，恢复循环可以交付申请并删除 Outbox，却不知道该命令来源于哪一条草稿，因而遗留“幽灵草稿”。

现在由页面把源草稿 ID 作为本地投递元数据交给 Repository：

- Outbox payload 使用本地字段 `_sourceDraftId` 关联源草稿；
- HTTP 请求发送前移除该字段，不改变服务端协议；
- 立即提交成功和冷启动 `flushOutbox` 成功都删除源草稿；
- 草稿关联的本地加密附件副本随草稿一起清理；
- 仍在失败或等待重试的命令不会提前删除草稿。

## 真实复验

### 1. 立即成功路径

申请 `OA-20260906-A642CC` 在正常网络下提交成功，最终 Outbox 0、草稿 0。由于服务端响应快于进程终止，本样本只证明立即成功清理路径，不作为进程恢复证据。

### 2. 断网队列恢复

在 Android 包级网络禁止状态下提交 `AI-UAT-OA-OFFLINE-RECOVERY-FIX-20260906-1712` 并结束进程：停止后 Outbox 1；恢复网络和冷启动后 Outbox 0、草稿 0，并收到对应 `approval.submitted` 与 `oa.notification.created` 事件。该样本证明离线队列持久化和恢复交付。

### 3. 请求在途时强制停止

为避免“接口响应过快”造成假通过，在模拟器链路上固定 4000 ms 延迟：

1. 打开真实后台下发的请假表单并等待自动保存，确认 Outbox 0、草稿 1；
2. 点击提交，约 350 ms 后执行 `force-stop`，确认目标进程不存在；
3. 停止状态只读检查得到 Outbox 1、草稿 1，这是本缺陷的精确前置状态；
4. 还原 0 ms 延迟并冷启动；
5. 本地游标从 1016 前进到 1024，收到一组新的 `approval.submitted` 与 `oa.notification.created`；
6. 恢复后 Outbox 0、草稿 0；
7. “我发起的”只出现一条 17:17 的新请假申请，详情申请号为 `OA-20260906-5997C3`，事由和时间与本次测试一致。

测试结束后已把模拟网络恢复为 0 ms、包级网络恢复为 allow，并关闭临时 Android 测试链路。

## 自动化验证

- `oa_outbox_session_isolation_test.dart`：12/12 通过；新增“恢复投递清除源草稿且本地元数据不上送”用例。
- `oa_offline_attachment_submission_test.dart`、`oa_attachment_stream_storage_test.dart`：合计 5/5 通过。
- 当前完整 Flutter 测试集：1406/1406 通过。
- `flutter analyze`：0 error、0 warning；仅保留 7 条仓库已有 style info。
- Profile APK 构建通过并已安装到 M3 执行上述真实复验。

Windows 上 Gradle 9.3.1 出现 Kotlin DSL 初始化异常；将 wrapper 升级到 9.4.1 后恢复构建。该变更只修复构建工具链，不改变移动端业务协议。

## 证据

- [在途提交前表单](../test/evidence/oa-process-death-fixed-20260906-1710/inflight-ready-attempt.png)
- [强制停止记录](../test/evidence/oa-process-death-fixed-20260906-1710/inflight-force-stop.json)
- [停止后 Outbox 1、草稿 1](../test/evidence/oa-process-death-fixed-20260906-1710/inflight-after-force-stop.json)
- [恢复后 Outbox 0、草稿 0](../test/evidence/oa-process-death-fixed-20260906-1710/inflight-after-recovery.json)
- [冷启动恢复页面](../test/evidence/oa-process-death-fixed-20260906-1710/inflight-after-recovery.png)
- [我发起的列表只新增一条 17:17 申请](../test/evidence/oa-process-death-fixed-20260906-1710/inflight-my-started.png)
- [恢复申请详情与申请号](../test/evidence/oa-process-death-fixed-20260906-1710/inflight-detail.png)
- [包级断网停止快照](../test/evidence/oa-process-death-fixed-20260906-1710/denied-after-force-stop.json)
- [包级断网恢复快照](../test/evidence/oa-process-death-fixed-20260906-1710/denied-after-recovery.json)

## 仍未通过的相关边界

- OA “退回”仍受服务端已发布流程未下发 `return` 权限阻塞，不能由移动端绕过权限实现，见 [774](774-mobile-oa-return-published-flow-live-verification-20260906.md)。
- 本轮通过的是 Android AVD 的进程死亡/离线恢复；厂商真机后台冻结、系统回收与推送唤醒仍应在服务端稳定后继续覆盖。
- IM 群聊实时唤醒仍存在约 20 秒级长尾，且不可见会话被服务端提前标记已读，见 [792](792-mobile-four-avd-im-latency-read-semantics-20260906.md)。
