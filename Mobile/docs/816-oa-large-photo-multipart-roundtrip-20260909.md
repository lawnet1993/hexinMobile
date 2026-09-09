# 816 · OA 大图片压缩、流式上传与端内预览真机验收

时间：2026-09-09（Asia/Shanghai）  
设备：realme 真机 `dd00d66d`  
账号：Test Terminal 01  
桌面功能基准：当前真实运行窗口 v1.0.105

## 结论

本轮通过一条真实请假审批验证了移动端 OA 图片附件的完整链路：系统文件选择器读取 2.80 MB 原图，移动端在提交前压缩为 1.3 MB，使用账号隔离的加密文件队列暂存，再以 `multipart/form-data` 文件流上传。服务端确认后，审批详情只保存并展示附件元数据，点击附件可在应用内打开完整图片预览。上传队列最终为 0，两个加密暂存文件均已删除，没有提交成功后的大文件残留。

该结果证明 **2.80 MB 图片样本**通过，不代表 10 MB 以上照片、20 MB 单文件边界、弱网中断续传或多个附件并发已经通过，这些仍需单独验收。

## 真实执行记录

1. 在 Test Terminal 01 真机进入后台动态表单“请假审批”。页面实际读取并展示请假类型、起止时间、自动计算天数、请假事由、附件和审批流程。
2. 从 Android 系统文件选择器选择 `IMG20251019204602.jpg`，选择器侧原图为 2.80 MB。
3. 客户端生成 1.3 MB 主附件及约 29 KB 缩略图，二者以 `.imq` 加密容器写入账号隔离目录；SQLite/审批表单没有写入原图 Base64。
4. 填写事假、2026-09-10 00:23 至 01:24、事由 `AI-UAT-OA-LARGE-PHOTO-20260909-0027` 后提交。
5. 服务端创建申请编号 `OA-20260909-39AB5B`，状态为“审批中”。详情显示 1.3 MB 附件和当前多人审批节点。
6. 点击附件后在应用内打开全屏图片预览，未跳转第三方在线服务。
7. 提交期间 OA 健康状态曾为 `pending_upload`、`pendingCommandCount=1`；随后事件同步提交成功，最终连续心跳均为 204，OA `appliedSequence=1598`、`pendingCommandCount=0`、状态 `healthy`。
8. 提交完成后真机 `files/oa-queued-attachments/<account>/<owner>/` 目录为空，暂存的主文件和缩略图均已清理。

## 传输与存储核对

- 本地暂存由 `OaAttachmentFileStore` 复用加密流容器，数据库只记录 token、文件名、类型、长度和摘要元数据。
- 已暂存附件通过 `MultipartFile.fromStream` 发往 `/api/oa/attachments`，不是 Base64 JSON。
- 附件上传成功后，审批提交 JSON 使用服务端附件 ID、字段绑定和附件元数据。
- 每个本地附件上传并持久化新的 outbox payload 后立即删除对应加密文件；整单成功后再次执行幂等清理。
- 小附件仍保留兼容性的 `fromBytes` 入口，但网络请求依然是 multipart，不会把内容编码到审批 JSON；真实表单选择文件会先进入加密文件队列并走流式路径。

相关实现：

- `lib/features/collaboration/data/oa_attachment_file_store.dart`
- `lib/features/collaboration/data/collaboration_repositories.dart`

## 自动化回归

执行：

```text
flutter test test/oa_attachment_stream_storage_test.dart test/oa_offline_attachment_submission_test.dart
```

结果：5/5 通过。覆盖加密文件引用、跨 owner 隔离、分块恢复、离线附件提交及成功清理相关路径。

## 截图证据

- [提交后的审批详情](../test/evidence/oa-large-attachment-20260909/15-oa-submitted-detail.png)
- [应用内附件预览](../test/evidence/oa-large-attachment-20260909/16-oa-attachment-in-app-preview.png)

## 尚未通过的边界

- 10 MB 以上真实相机照片的选择、压缩峰值内存和耗时。
- 19 MiB 普通文件流式上传与回下载、精确 20 MiB 上传、20 MiB + 1 字节选择阶段拒绝已经补测通过，见 [817](817-oa-19m-stream-upload-roundtrip-20260909.md)；最多 20 个附件边界仍未验证。
- 上传中断、进程被杀、恢复网络后的续传或幂等重试。
- 多图片、多文件混合选择及并发上传。
- PDF、Word、Excel、PPT 在当前服务端预览链路上的跨端一致性复验。
- iOS 相册/文件权限拒绝、有限照片权限及重新授权流程。

因此，本轮只将“Android 真机 2.80 MB 图片压缩、multipart 流式上传、服务端回显、端内图片预览、成功清理”判定为通过；OA 附件总体能力仍为部分通过。
