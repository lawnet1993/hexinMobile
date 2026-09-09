# 753 · 移动端 OA PDF 附件真机闭环

日期：2026-09-06，Asia/Shanghai。结论：PDF 选择、流式上传、审批提交、服务端回下载和系统打开路由已形成真实闭环；PDF 内容渲染仍不能判定通过，因为真机可用的首选阅读器要求把文件上传到厂商云端，本轮按安全要求拒绝授权。

## 基准与环境

- 桌面端版本基准更新为 v1.0.94；版本信息来自当前桌面更新界面，本轮没有把桌面窗口截图当作自动化执行证据。
- 真机：realme RMX3366，Android；应用 1.0.1+2，arm64 Profile。
- 账号：test01 / Test Terminal 01。
- 新建申请：`OA-20260906-24DD3C`，标题 `AI-UAT-20260906-013930-PDF-PREVIEW`，状态为审批中。
- 测试文件：`AI-UAT-20260906-mobile-preview.pdf`，有效 A4 单页 PDF，2404 B，不含业务或个人数据。

## 执行结果

1. Android 文件选择器能够显示并选中 PDF；移动端表单显示文件名、2.3 KB 大小和删除入口。
2. 表单字段和附件自动保存为草稿；提交后服务端返回申请编号，详情页显示动态表单内容、附件及真实会签人员。
3. OA 已存储附件通过 `MultipartFile.fromStream` 和 `FormData` 提交到 `/api/oa/attachments`，不是 Base64 表单字段。
4. 清除 App 内该附件的临时打开缓存后，用户再次点击才重新生成本地文件；未点击时没有新下载。
5. 回下载文件大小为 2404 B，SHA-256 为 `6760DDE97F34D3BA823AE70C9A04D80AFF2D2D2E8BCEB02A0B594519C2B21DC9`，与上传源一致。
6. 下载完成后进入 Android `ResolverActivity`，移动端没有内置 Office/PDF 引擎，符合当前产品决定。
7. 真机自带“文件随心开”首次打开提示会联网并将文件上传到云端处理；本轮未同意，也未把测试附件交给第三方。

## 证据

- [服务端动态请假表单](../test/evidence/oa-attachment-formats-20260906/01-leave-form.png)
- [PDF 选中并进入草稿](../test/evidence/oa-attachment-formats-20260906/03-pdf-selected-draft.png)
- [完整表单与附件](../test/evidence/oa-attachment-formats-20260906/04-pdf-filled-draft.png)
- [提交后的申请与附件](../test/evidence/oa-attachment-formats-20260906/05-submitted-pdf-approval.png)
- [服务端回下载后进入系统打开器](../test/evidence/oa-attachment-formats-20260906/06-server-redownload-resolver.png)
- [第三方云端阅读器授权页，未同意](../test/evidence/oa-attachment-formats-20260906/07-pdf-viewer-result.png)

## 验收边界

- 通过：PDF 文件选择、附件元数据展示、真实提交、服务端回下载、文件完整性、系统打开路由。
- 部分通过：下载进度。2.3 KB 文件下载过快，未形成肉眼可见的进度过程；代码和大文件真机仍需专项验证。
- 未通过：PDF 实际内容渲染；未安装经批准的纯本地 PDF 阅读器，现有厂商阅读器会上传云端。
- Word、Excel、PPT 的标准 MIME、真机本地内容渲染以及三种格式的 OA 服务端上传/回下载闭环已在 [755 Office 真机验证](755-mobile-office-mime-local-render-real-device-20260906.md) 通过。
- 大文件下载进度、断网中断、失败清理、恢复重试和哈希一致性已在 [754 多设备实测](754-mobile-oa-boundary-multi-device-real-device-20260906.md) 通过。
- 未执行：Windows v1.0.94 对该申请、附件和审批状态的跨端核对；当前任务没有可调用的 Windows UI 自动化入口。
