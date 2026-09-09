# 移动端 OA 大附件上传强杀恢复实测

> 日期：2026-09-09  
> 设备：Android 模拟器 `emulator-5556`  
> 客户端：Profile APK，SHA-256 `9A1265A1E10BF720291E165D32621458B729D86572BDA8A0ACBA0F8348E99A97`

## 结论

通过本轮边界测试：19.0 MB OA 附件在受限网络中开始 multipart 文件流上传后强制终止应用，恢复网络并重启后，申请最终仅生成一次，附件仍可打开，本地待上传文件完成清理，原有草稿未被覆盖。

## 实测步骤

1. 在“请款审批”中填写 `AI-UAT-OA-MULTIPART-KILL-20260909`，添加 19.0 MB 文本附件。
2. 将模拟器上传、下载带宽限制为 14,400 bit/s，并启用 GPRS 延迟。
3. 点击提交；6 秒后页面仍显示“正在提交申请”，系统 TCP 状态存在到测试服务的已建立连接。按该带宽，19 MB 文件不可能在 6 秒内完成，因此可以确认终止发生在上传过程内。
4. 使用系统 `force-stop` 强制终止客户端，随后恢复不限速网络并重新启动。
5. 核对“我发起的”“草稿箱”、申请详情和应用私有附件目录。

## 恢复结果

- “我发起的”仅出现一条对应申请：`OA-20260908-81868D`。
- 申请状态为“审批中”，金额、类型、日期和说明均正确。
- 19.0 MB 附件名称和大小正确，详情显示“点击打开”。
- 应用私有 `files/oa-queued-attachments` 下只剩空的账户/会话目录，没有残留正文、预览或 `.imq.tmp` 文件。
- “草稿箱”仍为 1 条原有请假草稿，测试请款草稿没有残留或重复。
- 应用重启后进程保持存活。
- 公共 Download 中本轮创建的 19 MB 测试源文件已删除。

## 证据

- `Mobile/test/evidence/initiated-window-20260909.png`：恢复后的“我发起的”列表。
- `Mobile/test/evidence/initiated-window-20260909.xml`：列表语义树，仅有一条 23:04 的对应申请。
- `Mobile/test/evidence/oa-multipart-kill-detail-20260909.png`：恢复后的申请详情。
- `Mobile/test/evidence/oa-multipart-kill-detail-20260909.xml`：金额、说明、附件、状态和流程语义。
- `Mobile/test/evidence/draft-window-20260909.png`：恢复后的草稿箱。
- `Mobile/test/evidence/draft-window-20260909.xml`：原有请假草稿仍在，测试草稿未残留。

## 边界说明

本轮证明 Android 客户端在大附件 multipart 上传中断后的本地恢复、幂等提交和清理行为；不据此推断 iOS、服务端跨节点故障或代理层重复转发已经通过。
