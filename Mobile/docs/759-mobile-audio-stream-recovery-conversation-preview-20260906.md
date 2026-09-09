# 759 · 移动端大音频流式上传、下载恢复与会话预览真机验证

日期：2026-09-06，Asia/Shanghai。结论：14.4 MB WAV 已完成“test02 模拟器选择并上传 → 服务端确认 → test01 真机接收 → 缓存未命中下载 → App 内播放 → 下载中断清理 → 恢复重试”的真实闭环。测试同时发现并修复服务端音频预览为空时，移动端会话列表只显示时间的问题。

## 真实链路

- 文件：`AI-UAT-AUDIO-STREAM-20260906.wav`，14,400,078 B，时长 2:30。
- 原始 SHA-256：`27CFB4D7B24AFF55E1F86F6EAC05DC70D60E625DB077441C247BCCD2D1ED9040`。
- test02 从 Android DocumentsUI 选择文件；本地 Outbox 先显示“发送中”，服务端确认后变为已发送。
- 上传代码使用 `MultipartFile.fromStream` 读取按账号隔离的受保护 Outbox 文件，不使用 Base64，也不在数据库保存大文件正文。
- test01 收到音频后，首次点击显示 0%、1%、9% 下载进度，完成后直接进入 App 内音频播放器并显示 `0:01 / 2:30`。
- 真机回下载文件为 14,400,078 B，SHA-256 与原始文件完全一致。

## 中断与恢复

1. 删除本轮测试生成的唯一音频播放缓存，保留消息和其他缓存不变。
2. 再次点击播放，下载开始 300 ms 后关闭真机移动数据。
3. 下载失败后播放器恢复为可点击状态；缓存目录没有最终文件，也没有 `.part` 半文件。
4. 立即恢复移动数据并重试，下载完成、播放成功，SHA-256 再次匹配。

随后线上预览 Range 从历史 500 修复为 206，聊天页接入预览 Manager 后又完成切后台和强杀断点恢复：强杀时保留 4,194,304 B 完整分片，重启从 29% 继续，分片依次增长到 8,388,608、12,582,912、14,400,078 B，最终摘要仍完全一致。详细证据见 [760](760-mobile-preview-resume-legacy-video-real-device-20260906.md)。系统主动取消、磁盘不足和服务端故意错误摘要仍需独立测试，不能由本轮结果外推。

## 会话列表预览修复

服务端会话索引已经把最新序号和时间更新到该音频，但 `lastMessagePreview` 为空，因此修复前 test01 的 Test Terminal 02 会话只有 `04:50`，没有内容摘要。

移动端现在仅在服务端预览为空时，使用同一会话、同一 `lastMessageSequence` 的本地已确认消息生成安全摘要：图片 `[图片]`、视频 `[视频]`、音频 `[语音]`、名片 `[名片]`、文件 `[文件] 文件名`；服务端有非空预览时仍以服务端为准。查询命中现有 `(account_id, conversation_id, sequence)` 索引，不读取媒体字节。

覆盖安装后保持 test01 登录态，Test Terminal 02 会话立即显示 `[语音]`。这也避免把真实消息正文或文件内容复制到额外状态字段。

## “我的”与账户页复验

- “我的”页当前没有 TUN、网络不可用或站点安全连接入口；隧道仍只服务需要访问授权站点的功能。
- “账户与安全”显示账号、`realme RMX3366 · Android 14` 和真实的“已登录”，不再显示旧版“已验证·状态未知”。
- ARM64 Profile 覆盖安装后登录态、首页和 IM 本地数据保留。

## 自动化、分析与构建

- `im_conversation_index_test.dart`、`im_pending_preview_test.dart`、`im_sent_projection_test.dart`：30/30 通过。
- Flutter 完整测试集：1396/1396 通过。
- 修改文件静态分析：0 issue。
- ARM64 Profile APK：69,497,080 B。
- APK SHA-256：`8C13948F1434C244A8F7A9D73570706B9AD13CF5178242B986464F59CC858D10`。

## 证据

- [数字摘要](../test/evidence/mobile-audio-stream-recovery-20260906/summary.json)
- [模拟器上传进入 Outbox](../test/evidence/mobile-audio-stream-recovery-20260906/goal-continuation-m4-audio-upload-early.png)
- [真机接收并显示音频播放器](../test/evidence/mobile-audio-stream-recovery-20260906/goal-continuation-physical-audio-latest.png)
- [下载 0%](../test/evidence/mobile-audio-stream-recovery-20260906/goal-continuation-audio-dl-100.png)
- [下载 1%](../test/evidence/mobile-audio-stream-recovery-20260906/goal-continuation-audio-dl-300.png)
- [下载 9%](../test/evidence/mobile-audio-stream-recovery-20260906/goal-continuation-audio-dl-800.png)
- [移动数据中断后恢复为可重试](../test/evidence/mobile-audio-stream-recovery-20260906/goal-continuation-audio-interrupted.png)
- [恢复网络后的重新下载进度](../test/evidence/mobile-audio-stream-recovery-20260906/goal-continuation-audio-retry-progress.png)
- [修复后会话列表显示语音摘要](../test/evidence/mobile-audio-stream-recovery-20260906/goal-continuation-post-fix-message-list.png)
- [“我的”页不再暴露隧道状态](../test/evidence/mobile-audio-stream-recovery-20260906/goal-continuation-profile-current.png)
- [账户页使用真实登录状态](../test/evidence/mobile-audio-stream-recovery-20260906/goal-continuation-account-security-current.png)
- [强杀后从 29% 断点恢复](../test/evidence/mobile-audio-stream-recovery-20260906/goal-continuation-preview-manager-resume-29.png)
- [恢复后 App 内音频播放](../test/evidence/mobile-audio-stream-recovery-20260906/goal-continuation-preview-manager-playback.png)
- [历史视频 404 兼容后播放](../test/evidence/mobile-audio-stream-recovery-20260906/goal-continuation-legacy-video-fallback.png)
