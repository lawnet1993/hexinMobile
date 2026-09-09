# 766 · 移动端普通附件低存储与主动取消边界追加复验

日期：2026-09-06，Asia/Shanghai。

结论：**Android 模拟器上的普通 IM 附件低存储与主动取消边界通过；真机、iOS 和服务端破坏摘要仍未通过。** 本轮使用第三台 Android 模拟器和真实 64 MiB 附件复现了旧实现残留伪正式文件的问题，随后把普通附件改为 `.part` 流式落盘、成功后原子发布、失败或取消清理，并重新通过 UI 验收。

## 真实样本与初始缺陷

- 发送端：`emulator-5558`，test03；接收会话：Test Terminal 01 单聊。
- 样本：`AI-UAT-LOW-STORAGE-20260906-64M.bin`，67,108,864 B；通过移动端文件选择器和现有 multipart 上传链路发送，不使用 Base64。
- 修复前把 `/data` 压到 0 可用空间后点击下载，缓存中留下 63,913,984 B 的同名“正式文件”，虽然内容不完整却没有 `.part` 后缀。这证明旧实现存在把残件暴露成可打开文件的风险。

## 修复内容

- 普通 IM 文件附件不再先完整读入 Dart 堆；Repository 直接流式写入 `target.part`。
- 仅在下载完成且长度校验通过后原子重命名为正式文件。
- 下载失败、存储不足、会话切换或用户取消时删除 `.part`，不发布正式文件。
- 文件气泡显示实时百分比；下载中再次点击同一气泡即取消。
- Dio 包装的 `FileSystemException` 会继续解包；Android/Linux `ENOSPC` 和 Windows 磁盘满统一显示“设备存储空间不足，请清理后重试”，不回显本地路径。

## 低存储 UI 复验

- 使用专用 `AI-UAT-low-storage-fill*.bin` 文件把第三台模拟器 `/data` 剩余空间降至 14,760 KiB，未影响其他模拟器和真机。
- 点击 64 MiB 附件后，气泡进度真实增长至 21%，随后显示“附件打开失败：设备存储空间不足，请清理后重试”。
- 失败后 `cache/im-file-attachments-test-...` 目录为空，没有 `.part`，也没有正式文件。
- 测试结束已删除三份专用填充文件，`/data` 可用空间恢复至 1,563,068 KiB。

## 用户主动取消复验

- 恢复正常空间后再次点击同一附件，3 秒时气泡显示 4%。
- 再次点击气泡后进度立即消失并恢复下载图标，没有显示误导性的失败提示。
- 取消后缓存目录仍为空，没有 `.part` 或正式文件。

## 自动化、构建与证据

- 错误文案与普通附件流式下载专项：13/13 通过。
- 新增 Repository 用例覆盖完整流式写入、逐字节一致、取消以及最终文件和 `.part` 清理。
- 全量 Flutter 回归：1404/1404 通过。
- `flutter analyze`：0 error、0 warning；仅保留 7 条仓库已有的大括号风格 info。
- 最终 Profile APK：111,236,918 B，SHA-256 `E05DFF9AD19A5A97BD8FA0D9EAA76AF89E8D98DD4950CAA54B2CC1DE8FDB6295`。
- 最终包已保留数据覆盖安装到两台原模拟器和 realme 真机，并逐台核对安装后 `base.apk` 摘要一致；第三台模拟器完成边界测试后已退出，原 `emulator-5556` 已恢复 test03 登录态。
- [低存储下载 7%](../test/evidence/oa-boundary-followup-20260906/06d-enospc-04.png)
- [低存储下载 21%](../test/evidence/oa-boundary-followup-20260906/06d-enospc-08.png)
- [存储不足准确提示](../test/evidence/oa-boundary-followup-20260906/06d-enospc-12.png)
- [主动取消前 4%](../test/evidence/oa-boundary-followup-20260906/07a-user-cancel-progress.png)
- [主动取消后恢复下载图标](../test/evidence/oa-boundary-followup-20260906/07b-user-cancel-after.png)

## 仍未通过

1. realme 真机对未缓存大文件执行下载、主动取消、重试以及真实低存储；当前设备锁屏，不能用模拟器结果替代。
2. 服务端受控返回错误摘要或错误正文时的端到端拒绝证据；客户端确定性摘要测试已通过，但不替代服务端破坏性测试。
3. iOS 真机下载、取消、后台、低存储和系统文件打开。
4. OA `return` 动作：当前桌面 test01 授权会话只读检查 0 条可处理申请，未得到 `allowedActions=return` 的候选流程。
