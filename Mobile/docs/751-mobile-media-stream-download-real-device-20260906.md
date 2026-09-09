# 751 · 移动端媒体流式下载与真机复验

日期：2026-09-06，Asia/Shanghai。结论：移动端远端视频/音频播放下载已由整文件内存缓冲改为文件流；编译、自动化与一个真实视频缓存未命中样本通过。后续 14.4 MB 音频又完成真实上传、缓存未命中、可见进度、断网清理、恢复重试和哈希一致性闭环，见 [759](759-mobile-audio-stream-recovery-conversation-preview-20260906.md)。

## 改造范围

- `ImRepository.downloadMediaAttachmentToFile` 使用 Dio 直接写目标文件并保留 `onReceiveProgress`，远端媒体不再先构造完整 `Uint8List`。
- 播放准备阶段写入同目录 `.part`，完成后核对服务端声明大小，并通过文件流计算 SHA-256；校验成功后原子重命名为正式缓存。
- 下载、长度或摘要校验失败时只清理当前 `.part`，不覆盖旧的有效缓存。
- 本地 Outbox 合成附件仍沿用既有解密字节读取；本轮没有扩大加密存储接口。

## 自动化与构建

- Flutter 3.47.0 / Dart 3.13.0。
- 指定文件静态分析：本次新增警告为 0；仓库大文件仍有 6 条既有 `curly_braces_in_flow_control_structures` info。
- `chat_page_type_test.dart`：98/98 通过；`im_outbox_repository_test.dart`：5/5 通过，合计 103/103。
- `workbench_action_size_test.dart`：2/2 通过；首页“处理”视觉按钮保持 52×28 dp，整行可点击，不继续无依据缩小触控区域。
- arm64 Profile APK 构建成功，大小 69,497,080 字节。
- 最终 arm64 Profile APK SHA-256：`8073432C9745CAC023866443B6C1582762AC40C25D5DF61383DD693C594031E5`。

同一最终包还增加群提及一致性保护：若用户编辑并破坏可见 `@成员` 标签，发送时不再携带隐藏的成员 ID，避免界面看不出提及但对方仍收到 @通知。正常成员选择器链路已在真机发送并正确加粗渲染，截图与边界见 [750](750-windows-1094-real-window-regression-20260906.md)。

## 真机缓存未命中复验

环境：realme RMX3366，保留数据覆盖安装，版本 1.0.1+2，账号 test01。安装后保持登录，首页、待办数量和消息入口正常。

步骤：

1. 在 Test Terminal 03 会话定位 2.0 MB、0:03 的历史视频。
2. 精确备份并移走该视频唯一的 2,134,392 字节播放缓存；未清理目录或其他附件。
3. 点击同一视频消息。
4. 应用重新生成 2,134,392 字节缓存，内容 SHA-256 与备份一致，并进入内置播放器完成 0:03 播放。
5. 删除临时备份，仅保留新下载的有效缓存。

证据：[真机重新下载后播放](../test/evidence/desktop-update-20260906/10-mobile-stream-redownload-playback.png)。本轮日志出现正常的 AVC/AAC 解码器初始化，没有该操作相关 404、FATAL、ANR、Unhandled Exception 或 E/flutter。

## 验收边界

- 2 MB 视频下载完成过快，原测试没有捕捉到百分比；后续 14.4 MB 音频已捕捉 0%、1%、9%，进度 UI 通过真机验收。
- 音频下载中关闭移动数据后没有残留最终文件或 `.part`，恢复网络后重试成功且摘要一致。
- 应用切后台继续下载、强杀后从 4 MiB 已落盘分片恢复、最终大小与 SHA-256 一致，已在 [760 真机断点恢复](760-mobile-preview-resume-legacy-video-real-device-20260906.md) 通过。
- 仍未执行系统主动取消、磁盘不足与服务端故意错误摘要样本。
- Windows v1.0.94 对同一视频仍返回 404，但手机缓存未命中下载已确认服务端对象当前存在；桌面问题与移交提示词见 [750](750-windows-1094-real-window-regression-20260906.md)。
