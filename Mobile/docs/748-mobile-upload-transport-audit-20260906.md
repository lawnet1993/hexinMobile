# 748 · 移动端上传传输与临时文件审计

日期：2026-09-06（Asia/Shanghai）  
结论：**大文件传输实现通过源码审计；完整真机跨端验收未通过**

## 桌面端基准

桌面端选择文件后把路径交给 Rust，由 Rust 使用 `multipart/form-data` 文件流上传；OA 服务把正文流转交 File Service 或本地文件存储，业务数据库只保存对象编号、名称、类型、大小和摘要等元数据。

移动端没有可长期保存的桌面文件路径。正确等价实现是：读取 Android/iOS 系统选择器输入流，先复制到账号和环境隔离的应用私有加密 Outbox，再从加密文件流构造 multipart。数据库只保存本地不透明 token 和服务端对象元数据。

## 当前上传矩阵

| 场景 | 选择后本地处理 | 网络请求 | Base64 新写入 | 当前判定 |
| --- | --- | --- | --- | --- |
| OA 普通附件 | 输入流直接写入分块加密文件 | `MultipartFile.fromStream` | 无 | 本地真机通过；服务端提交待验收 |
| OA 图片 | 原图压缩、生成小缩略图后写入分块加密文件 | `MultipartFile.fromStream` | 无 | 传输通过；超大图内存峰值待验收 |
| IM 普通文件 | 输入流直接写入分块加密 Outbox | `MultipartFile.fromStream` | 无 | 小文件真机发送通过；大文件与跨端待验收 |
| IM 视频/音频 | 输入流直接写入分块加密 Outbox | 对象上传 multipart，消息只提交对象元数据 | 无 | 源码通过；弱网续传待验收 |
| IM 图片 | 压缩结果写入分块加密 Outbox | `MultipartFile.fromStream` | 无 | 传输通过；多张大图内存待验收 |
| 自定义头像 | 裁剪为 256 px、小体积图片 | 现有资料接口的 Data URL | 有 | 用户确认小头像可保留，不列为大文件阻塞 |

`im_outbox.attachment_bytes_base64` 是旧数据库兼容列。当前 text、file、image、video、audio、contact 新记录均写空字符串；正文存放在加密 Outbox 文件中，不是 Base64。

## 本轮修正

1. IM 文件、图片、视频和音频选择结束后调用 `FilePicker.clearTemporaryFiles()`，避免系统选择器缓存与加密 Outbox 各保留一份。
2. 头像完成裁剪、压缩和更新后同样尽力清理选择器副本；平台不支持清理时不把已经完成的业务操作改判为失败。
3. OA 已有相同清理策略：选择器副本、系统查看器明文交接文件和最终加密附件分别按各自生命周期清理。

## 已有证据

- OA 19 MiB 普通文件在 Android 真机完成选择、草稿保存、覆盖升级、系统打开与删除清理；见 [747](747-oa-attachment-binary-stream-verification-20260905.md)。
- IM/OA 新加密文件使用 `IMOBX002` 256 KiB 分块认证容器，旧 `IMOBX001` 仍可读取。
- IM 文件、图片、媒体最终上传统一调用 `_storedMultipart()`，由 `MultipartFile.fromStream` 从加密 Outbox 解密流读取。
- 视频/音频对象上传成功后，消息 JSON 只包含 `objectId`、名称、类型、大小、SHA-256、尺寸和时长等元数据。
- 最终 Profile APK SHA-256 为 `99ED88D0FCA965065EF5BFA173158FD0783F2928064A0B08461B6B59121C8FB1`，覆盖安装后保持登录并进入真实单聊。
- 后续媒体下载内存与群提及一致性改造最终 Profile APK SHA-256 为 `8073432C9745CAC023866443B6C1582762AC40C25D5DF61383DD693C594031E5`；远端视频首次播放改为文件流写入和流式摘要校验，真机缓存未命中重新下载与播放通过，详见 [751](751-mobile-media-stream-download-real-device-20260906.md)。
- 真机向 Test Terminal 03 发送 `AI-UAT-20260902-165500-leave-proof.txt`：移动端显示“已发送”，FilePicker 缓存为空，当前测试文件不再留在 Outbox，移动端进程关键崩溃匹配 0 条。
- [真机文件消息已发送](../test/evidence/im-upload-stream-20260906/01-mobile-file-sent.png)
- 更新前 Windows 的 `collaboration-cache.sqlite3` 在本轮发送后立即及等待 20 秒后未检出目标消息；采样为 424 条、最大 sequence 20840、最后更新时间 2026-09-05 23:56:05。后续真实窗口已确认升级至 v1.0.94，打开该会话能看到旧目标文件和摘要；新版即时双端同步仍需用新消息复验，不能沿用更新前的失败结论。详细时间线见 [749](749-windows-im-sync-live-finding-20260906.md)。
- Windows 当前日志同时持续出现 IM realtime `transport error` 重试和 `im realtime events could not be persisted: collaboration event id is missing`，具体分析和整改提示词见 [749](749-windows-im-sync-live-finding-20260906.md)。

## 尚未通过

1. IM 小文件真机流式发送已经通过；仍需分别发送接近上限的 IM 图片、普通文件、视频和音频，记录选择、入队、断网、恢复、进度、取消、重试、落盘清理和内存曲线。
2. v1.0.94 已完成新文本即时双向复验；手机回复能自然进入桌面打开的聊天区，但桌面列表摘要至少 86 秒未更新。桌面打开一个有效历史视频仍报 404，而手机缓存未命中可重新下载同一对象并播放。仍需用另一移动端及桌面打开同一批新上传对象，核对摘要、大小、音频、视频和下载进度。
3. IM/OA 大文件目前是单请求流式 multipart，不等于断点续传；若服务端没有分片会话、Range/offset ACK 和续传协议，应用进程终止后只能以同一 `clientMessageId` 幂等重传整对象。
4. OA 图片和 IM 图片压缩前仍会读取原图字节。上传正文没有 Base64，但 80 MB 原图和 9 张大图的峰值内存仍需优化并实测。

## 交给服务端/桌面端的核对提示词

```text
请只读核对当前测试环境和正在运行的 Windows 客户端的 IM/OA 文件传输协议。先确认界面显示版本与主程序 FileVersion、ProductVersion、构建版本一致；不修改业务数据，不输出 Token、Cookie、设备 ID、文件真实地址或消息正文。

1. 确认 OA /api/oa/attachments、IM 普通文件、/api/im/upload/picture、/api/im/upload/video、/api/im/upload/audio 都接收 multipart 文件流，文件正文不会编码为 Base64 或写入业务数据库。
2. 确认响应稳定返回 objectId、fileName、contentType、size、sha256；数据库只保存对象编号与元数据，File Service/对象存储保存正文。
3. 确认同一 clientMessageId 或上传幂等键重试不会生成重复对象、重复消息；上传成功但消息提交失败时有孤儿对象清理策略。
4. 核对大文件是否真正支持分片、取消、HTTP Range 和断点续传。若只支持单请求 multipart，请明确返回当前能力，不能把流式上传表述成断点续传。
5. 用核验过真实构建版本的 Windows 客户端打开移动端上传的图片、普通文件、视频和音频，核对摘要、大小、播放、下载进度与本地缓存清理。

输出接口、方法、Content-Type、请求字段、响应字段、幂等语义、大小上限、证据位置和未完成项。没有真实请求或源码证据的项目标记未通过。
```
