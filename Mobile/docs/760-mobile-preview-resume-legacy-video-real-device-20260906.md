# 760 · 移动端预览分片恢复与历史视频兼容真机验证

日期：2026-09-06，Asia/Shanghai。结论：**通过当前可执行边界**。线上预览内容 Range 已恢复为 206；聊天页已接入预览 Manager。14.4 MB 音频完成真实强杀断点恢复，历史视频的预览记录 404 通过窄范围兼容路径恢复 App 内播放。

## 服务端协议复验

- 授权测试账号下，IM 媒体预览创建 200 / `ready`。
- 视频与封面内容请求 `Range: bytes=0-31` 均返回 206、32 B，并带合法 `Content-Range` 和 `Accept-Ranges: bytes`。
- 视频 Range 请求编号：`a871ceb1-6e4f-4bcd-917a-75796b2c44dd`；封面 Range 请求编号：`dd365251-790d-4602-8153-f23a88bc527e`。
- 续期、错误设备、重复创建、关闭幂等和关闭后 410 均符合协议；完整脱敏结果由 `scripts/inspect-attachment-preview-server.ps1` 可重复获得。

## 14.4 MB 音频真实断点恢复

对象：`AI-UAT-AUDIO-STREAM-20260906.wav`，14,400,078 B，SHA-256 `27CFB4D7B24AFF55E1F86F6EAC05DC70D60E625DB077441C247BCCD2D1ED9040`。

1. 真机删除本轮音频对应的唯一完整缓存后点击播放。
2. 下载完成第一个 4 MiB 分片后立即强制停止 App；磁盘保留 `.part` 4,194,304 B。
3. 冷启动回到同一消息再次点击，界面立即从 29% 开始，而不是 0%。
4. 磁盘分片长度依次为 4,194,304、8,388,608、12,582,912、14,400,078 B。
5. 完成后 `.part` 原子发布为正式文件；最终大小和 SHA-256 与上传原件完全一致，并在 App 内播放到 `0:14 / 2:30`。

这证明恢复点来自已落盘的完整分片，不是重启后从零下载得过快造成的假象。

## 切后台

- 另一次下载在已有部分数据时按 Home 键进入后台。
- 5 秒后正式文件完整生成，摘要一致；返回 App 后播放器保持可用并显示 `0:09 / 2:30`。
- 当前 Android Profile 包未因普通切后台取消前台发起的媒体准备任务。

## 历史视频 404 兼容

- 样本：Test Terminal 03 会话中的 0:03 MP4 历史视频。
- Profile 脱敏诊断明确记录 `MOBILE_ATTACHMENT_PREVIEW {"phase":"create","status":404}`，失败发生在预览会话创建，不是 Range 内容读取。
- 客户端现在仅在 `AttachmentPreviewSessionExpired.statusCode == 404` 时退回原有鉴权媒体下载；仍核对服务端声明大小和 SHA-256。
- 同一真机复测进入内置播放器并完整播放到 `0:03 / 0:03`。401、409、410、5xx、摘要不一致等错误仍按原规则失败，不会被兼容分支掩盖。

## 自动化与构建

- 预览 Repository、Manager 与聊天页定向测试：106/106 通过。
- 相关 3 个源文件静态分析仅发现并清理 1 个无用 import，最终 0 issue。
- 最终 arm64 Profile APK 为 69,497,080 B，覆盖安装成功；SHA-256：`D2AB202ED0CE9BE100032C1D0C5A3CE86B181850CF5C50A887DD0A88F98EC0E0`。

## 证据

- [强杀后从 29% 恢复](../test/evidence/mobile-audio-stream-recovery-20260906/goal-continuation-preview-manager-resume-29.png)
- [断点恢复完成](../test/evidence/mobile-audio-stream-recovery-20260906/goal-continuation-preview-manager-resume-complete.png)
- [恢复后 App 内音频播放](../test/evidence/mobile-audio-stream-recovery-20260906/goal-continuation-preview-manager-playback.png)
- [切后台后返回播放](../test/evidence/mobile-audio-stream-recovery-20260906/goal-continuation-background-return.png)
- [历史视频 404 兼容后完整播放](../test/evidence/mobile-audio-stream-recovery-20260906/goal-continuation-legacy-video-fallback.png)

## 仍未通过或未执行

- 客户端主动取消、分片保留续传、错误摘要拒绝和低存储安全文案已在 [764](764-mobile-attachment-cancel-storage-integrity-boundaries-20260906.md) 通过自动化；真实低存储、服务端故意返回错误摘要、真机点击取消和 iOS 真机仍未执行。
- IM 普通文件附件预览缺少独立有效样本。
- 历史视频服务端预览记录缺失仍是服务端数据兼容问题；移动端回退保证可用性，但不能代替服务端补齐或迁移历史索引。
