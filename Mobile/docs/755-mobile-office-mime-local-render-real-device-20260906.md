# 755 · 移动端 Office MIME 与真机本地渲染验证

日期：2026-09-06，Asia/Shanghai。结论：发现并修复了 PPT/PPTX 上传类型错误；DOCX、XLSX、PPTX 已完成“模拟器上传 → 服务端存储 → test01 真机回下载 → 标准 MIME 打开”的真实闭环，三份回下载文件与上传原件的字节数和 SHA-256 均完全一致。设备本地 WPS 内容渲染也已有独立证据。

## 发现与修复

- OA 附件和 IM 文件原来各维护一份扩展名映射，均缺少 `ppt`、`pptx`，会以 `application/octet-stream` 上传。
- 新增共享 `mobileFileContentType`，OA 和 IM 统一使用同一份映射。
- 补齐 Word、Excel、PowerPoint、PDF、常见图片、音视频、CSV、RTF、JSON、XML、ZIP、RAR 和 7z 类型；未知类型仍安全回退为 `application/octet-stream`。
- PowerPoint 现在分别使用：
  - `.ppt`：`application/vnd.ms-powerpoint`
  - `.pptx`：`application/vnd.openxmlformats-officedocument.presentationml.presentation`

## 真机验证

- 真机：realme RMX3366；保留数据覆盖安装新 arm64 Profile APK 后，test01 登录态和工作台数据保留。
- 生成三个只含 `AI-UAT` 文本的有效本地测试文件：DOCX 36,685 B、XLSX 4,903 B、PPTX 28,311 B。
- Android 包管理器确认本机 WPS 组件声明支持三种标准 MIME。
- 使用标准 `ACTION_VIEW`、只读 `content://` URI 和对应 MIME 调用本地 WPS 入口：
  - DOCX 正确显示标题和正文；
  - XLSX 正确显示工作表、表头与数据；
  - PPTX 正确显示幻灯片标题、项目符号和播放入口。
- 系统通用 Resolver 能列出多个查看器，但没有把已安装的 WPS Lite 暴露为默认候选；直接调用 WPS 声明的本地入口可以正常渲染。移动端不应硬编码某个厂商应用。

## 当前边界

- 通过：OA/IM 共用 MIME 映射、PPT/PPTX 标准类型、arm64 构建与覆盖安装、真机本地 DOCX/XLSX/PPTX 内容渲染，以及三种格式的 OA 服务端往返闭环。
- 真实申请：`OA-20260906-507E72`，发起端 test02（AOSP `emulator-5554`），接收端 test01（realme RMX3366）。表单一次携带三份附件，提交后真机工作台无需重新登录即出现待办。
- 下载交互：DOCX 捕获到 63% 进度，XLSX/PPTX 均捕获到“正在下载”；完成后分别以 Word、Excel、PowerPoint 的标准 MIME 拉起 Android Resolver。
- 完整性结果：
  - DOCX：36,680 B，SHA-256 `F85A3B8D5AE0829C3194070451C124788BD4AB622836F28324F2588AA885253F`；
  - XLSX：4,876 B，SHA-256 `298369CE78C8D0893F89A5E125BF2458E546A17BDA0DA839BDB036B819CC5A6B`；
  - PPTX：28,291 B，SHA-256 `E13F3EB3183D6A8B337C3AF7AD00E602949509384E0468F24A1DDA68190B1FBA`。
- 真机系统 DocumentsUI 的“文档”搜索仍会由 `com.android.providers.downloads` 抛出 `UnsupportedOperationException: Search not supported`，所以改用 AOSP 模拟器选取文件。这是 OEM 文件选择器问题，不是移动端扩展名限制。
- 真机自带“文件随心开”首次使用声明会将部分文件上传到厂商云端处理，本轮未代替用户同意。移动端按既定方案不内置 Office 引擎；系统查看器的隐私策略属于外部应用边界。
- PDF 已有独立的上传、服务端回下载和系统打开闭环；大附件已有断网恢复与哈希一致性证据。

## 自动化与构建

- 新增文件类型测试 2 项；连同 OA、聊天页面定向测试共 192/192 通过。
- 修改后的完整移动端测试集：1395/1395 通过。
- `flutter analyze`：0 error、0 warning；仅有 7 条仓库已有的大括号风格 info。
- arm64 Profile APK：69,497,080 字节。
- APK SHA-256：`4007EF04E67DDA18D5B2080B1F0DDC2776BB406ACE839536F6FF3C01C754C700`。

## 证据

- [系统通用打开器识别 DOCX](../test/evidence/oa-attachment-formats-20260906/08-docx-local-render.png)
- [DOCX 本地内容渲染](../test/evidence/oa-attachment-formats-20260906/10-docx-wps-result.png)
- [XLSX 本地内容渲染](../test/evidence/oa-attachment-formats-20260906/11-xlsx-wps-result.png)
- [PPTX 本地内容渲染](../test/evidence/oa-attachment-formats-20260906/12-pptx-wps-result.png)
- [三种 Office 文件提交前表单](../test/evidence/oa-action-boundaries-20260906/continuation-20260906/emulator-5554-ready-submit.png)
- [服务端返回后的申请详情](../test/evidence/oa-action-boundaries-20260906/continuation-20260906/emulator-5554-office-submit-result.png)
- [test01 真机收到的审批详情](../test/evidence/oa-action-boundaries-20260906/continuation-20260906/physical-office-detail.png)
- [DOCX 下载 63%](../test/evidence/oa-action-boundaries-20260906/continuation-20260906/physical-docx-download-progress.png)
- [XLSX 下载中](../test/evidence/oa-action-boundaries-20260906/continuation-20260906/physical-xlsx-download-progress.png)
- [PPTX 下载中](../test/evidence/oa-action-boundaries-20260906/continuation-20260906/physical-pptx-download-progress.png)
- [DOCX 系统打开器](../test/evidence/oa-action-boundaries-20260906/continuation-20260906/physical-docx-open.png)
- [XLSX 系统打开器](../test/evidence/oa-action-boundaries-20260906/continuation-20260906/physical-xlsx-resolver.png)
- [PPTX 系统打开器](../test/evidence/oa-action-boundaries-20260906/continuation-20260906/physical-pptx-resolver.png)
