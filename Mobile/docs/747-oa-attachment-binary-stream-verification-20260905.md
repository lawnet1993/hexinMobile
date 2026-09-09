# 747 · OA 附件二进制存储与流式上传验收

日期：2026-09-05（Asia/Shanghai）  
当前结论：**未通过（整改已落地，完整端到端验收尚未完成）**

## 判定说明

原移动端把 OA 附件和图片缩略图编码为 Base64 后写入 SQLite，再通过内存字节构造 multipart。该方案会额外放大数据库、加密和 JSON 解析开销，也不适合草稿恢复和较大附件，判定不合理，原实现不通过。

本轮已经替换生产写入路径，并完成 19 MiB 普通文件的真机选择、草稿恢复、打开和清理验证；但仍缺少共享测试服真实提交、弱网补传、服务端对象摘要以及桌面端回读证据，因此不提前改判为通过。

## 与桌面端上传链路的对齐基准

桌面端的既有正确链路是：桌面选择得到文件路径，Rust 以 `multipart/form-data` 文件流上传；OA 服务把文件流转交 File Service 或本地文件存储，业务数据库只保存对象编号、名称、类型、大小、摘要等元数据。

移动端遵循同一协议语义。Android 文件选择器通常返回生命周期受限的 `content://` URI，不能把它当成桌面永久路径保存，因此移动端先把选择器输入流写入应用私有、账号隔离的加密文件，再由该文件以 `multipart/form-data` 流式上传到相同 OA/File Service 链路。SQLite 只保存本地不透明文件引用及对象元数据；文件正文不会进入 JSON、SQLite 或 Base64 字段。

## 已完成整改

1. 原附件和 256 px 图片缩略图分别写入应用私有、账号与环境隔离的 AES-GCM 文件。
2. SQLite 只保存不透明 token、长度、SHA-256、内容类型和字段绑定，不写入原文件或缩略图 Base64。
3. 新写入路径若附件字节尚未持久化会直接失败，避免静默生成丢失正文的队列记录。
4. OA 上传改为 `MultipartFile.fromStream`，请求体是 multipart 二进制，不是 Base64 JSON。
5. 草稿删除、队列成功、放弃队列和附件逐项上传完成后清理对应加密文件。
6. 保留旧 `bytesBase64` / `previewBytesBase64` 的只读解析；旧草稿下次保存时迁移成文件引用，新代码不再产生这两个字段。
7. 普通文件从 Android `content://` 输入流直接写入加密存储，不再先执行 `readAsBytes()`；图片保留压缩所需的单独路径。
8. 新文件采用 `IMOBX002` 分块认证容器，每块 256 KiB，解密流不会把整个大文件一次性送入 Dart 堆；旧 `IMOBX001` 文件仍可读取。
9. 草稿重启后，列表只读取独立小缩略图；用户点击普通文件时按流生成临时交接文件并调用系统查看器，回到应用后删除该明文文件。
10. 文件选择完成后清理 FilePicker 临时副本；草稿删除、队列成功、放弃队列和附件逐项删除后继续清理对应加密文件。

## 自动化证据

- Outbox、媒体、附件、OA 草稿、离线补传、会话切换隔离和页面交互组合回归：513/513 通过。
- 最终页面与附件存储聚焦回归：99/99 通过；分块加密与兼容性聚焦回归：7/7 通过。
- 2 MiB 以上旧 Base64 测试附件保存后，原始 SQLite 行包含 `storedFile` 和 `storedPreviewFile`，不包含 `bytesBase64`、`previewBytesBase64` 或原正文 Base64。
- 离线提交捕获的队列 JSON 不含 Base64；恢复后先发送 multipart 附件，再提交审批正文。
- 同一加密附件使用错误 owner 读取失败，证明草稿/队列所有者边界参与认证。
- 19 MiB 测试流写入后，附件模型不保留正文 `bytes`；恢复流总长度一致，单次解密块小于整个文件。
- 使用真实 v1 容器生成旧格式夹具，升级后的 v2 读取器可恢复原文，覆盖存量草稿兼容性。

对应测试：

- `test/oa_attachment_stream_storage_test.dart`
- `test/oa_offline_attachment_submission_test.dart`
- `test/oa_outbox_session_isolation_test.dart`
- `test/oa_local_store_test.dart`
- `test/oa_mobile_pages_test.dart`

## Android 真机证据

构建：正常 `lib/main.dart`，arm64 Profile，1.0.1+2  
APK 大小：69,497,080 字节  
APK SHA-256：`99ED88D0FCA965065EF5BFA173158FD0783F2928064A0B08461B6B59121C8FB1`

1. 从系统文件选择器选择约 906 KB 的测试图片，表单显示真实名称、大小和缩略图，自动草稿保存成功。
2. 应用私有目录生成两个不透明文件：原附件约 928 KB、缩略图约 5.4 KB；路径不含账号、业务文件名或表单内容。
3. 强制停止并重启应用后，页面显示“已恢复上次草稿”，附件数量、名称、大小和缩略图恢复正确。
4. 点击恢复后的附件可打开端内图片预览；关键崩溃、ANR、Unhandled Exception 和 `E/flutter` 匹配 0 条。
5. 通过页面删除测试附件并等待草稿自动保存后，两个加密文件均已清理；随后从草稿箱删除空草稿，未保留本轮测试业务数据。
6. 最终 Profile 包覆盖安装成功且没有清理应用数据；启动后仍保持登录，待办页可用，草稿箱为空，安装后关键崩溃、ANR、Unhandled Exception 和 `E/flutter` 匹配 0 条。
7. 真机选择 19,922,944 字节普通文件后，页面显示 19.0 MB；FilePicker 的旧临时副本被清理，仅保留账号隔离的应用私有密文，文件头为 `IMOBX002`。
8. 旧版本产生的 19 MiB `IMOBX001` 草稿在覆盖升级后可恢复，证明升级兼容；新选择流程的 PSS 峰值约 228,523 KiB，低于旧整文件读入流程的约 265,833 KiB。
9. 点击 19 MiB 附件后正常进入 Android 系统打开器。打开前 PSS 约 234,827 KiB，打开后约 238,700 KiB，增加约 3.8 MiB；生成的临时明文长度与原文件一致，返回应用 5 秒后已删除。
10. 页面删除附件后，`files/oa-queued-attachments` 下无残留文件；设备 Download 中本轮测试源文件也已清理；最终链路关键崩溃、ANR、Unhandled Exception 和 `E/flutter` 匹配 0 条。

截图：

- [附件加入并保存草稿](../test/evidence/mobile-profile-performance-20260905/07-oa-binary-attachment-draft.png)
- [首次端内预览](../test/evidence/mobile-profile-performance-20260905/08-oa-binary-attachment-preview.png)
- [强杀重启后恢复](../test/evidence/mobile-profile-performance-20260905/09-oa-binary-draft-restored.png)
- [19 MiB 新格式附件已选择](../test/evidence/oa-large-attachment-20260905/12-final-v2-large-selected.png)
- [19 MiB 文件交给系统打开器](../test/evidence/oa-large-attachment-20260905/10-large-open-result.png)
- [分块选择内存采样](../test/evidence/oa-large-attachment-20260905/memory-after-chunked-selection.json)
- [分块打开内存采样](../test/evidence/oa-large-attachment-20260905/memory-after-chunked-open.json)

## 未通过项

1. 尚未在共享测试服提交本条草稿：当前表单标题由后台模板生成，不能改成统一 `AI-UAT-日期时间` 前缀；为避免创建不符合测试数据约束的业务记录，本轮没有强行提交。
2. 19 MiB 本地选择、草稿保存、覆盖升级、打开和清理已经通过；共享测试服的实际 multipart 提交、断网后恢复补传、重复重试幂等仍未执行。
3. 图片压缩前仍需由 Flutter 图片压缩插件读取原图字节；正文落盘和网络上传已流式化，但 80 MB 原图的选择/压缩内存峰值仍需单独测量。
4. 服务端与桌面端当前都限制 OA 单附件 20 MB。移动端保持一致；若产品需要更大 OA 附件，必须先统一服务端、桌面端、移动端及对象存储协议，不能只放宽移动端校验。
5. 尚未取得服务端对象编号、SHA-256/摘要和 File Service 落盘核对结果，也未在桌面端打开本轮移动端真实提交的对象；这两项不能用本地打开成功替代。

## 通过门槛

只有以下证据补齐后才改为通过：接近 20 MB 的图片压缩一条；19 MiB 普通文件真实提交一条；真机断网/恢复队列不丢不重；服务端确认 multipart 二进制内容和摘要一致；提交后附件可在移动端与桌面端打开；完成队列后无残留明文或孤儿文件；全程无 Base64 新写入。
