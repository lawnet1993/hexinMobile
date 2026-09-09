# 864 · 移动端 OA 附件格式打开保护

时间：2026-09-09（Asia/Shanghai）  
范围：Android Flutter 移动端

## 结论

- OA 附件继续允许按后台限制上传，移动端不以“不支持预览”为由禁止业务文件上传。
- 图片使用端内预览；常见文档、压缩包、音频和视频在用户点击后下载，并交给系统已安装应用打开。
- 未知扩展名不会先下载，也不会再以 `application/octet-stream` 交给 Android。后者在测试设备上曾被 Google Pay 错误声明为可处理，虽然 `open_filex` 返回成功，目标应用实际立即退出。
- 对未知格式，附件行在点击前直接显示“请在桌面端查看”和桌面图标，不再使用“点击打开”和右箭头；轻触后仍提示完整原因，避免把系统错误关联误判为成功预览。
- 文件不存在、缺少可用应用、文件访问权限不足和打开失败均使用面向用户的中文提示，不暴露插件原始错误文本。

## 当前端内打开白名单

- 文档：PDF、Word、Excel、CSV、PowerPoint、TXT、Markdown、JSON、XML。
- 压缩包：ZIP、RAR、7Z。
- 音频：MP3、M4A、AAC、WAV、OGG、FLAC。
- 视频：MP4、MOV、MKV、WebM、AVI。

白名单仅控制移动端打开行为，不改变上传格式或文件大小策略。

## 验证证据

- 未知格式、损坏缓存重取、外部打开错误及审批动作保护定向回归：57/57 通过。
- 当前全量 Flutter 回归：1435/1435 通过。
- `flutter analyze`：0 issue。
- Profile APK SHA-256：`EDBF93948DEB2E4FF4CFED91EFBB5F91872B12F106E888922F3F85F48DAEE430`。
- APK 已覆盖安装至 3 台 Android 模拟器和 1 台 realme 真机。
- `emulator-5556` 已登录账号中打开真实测试申请 `AI-UAT-OA-UPLOAD-20260909-0100`，点击 19.0 MiB `.bin` 附件后原生语义树出现预期提示。
- 点击前清空 ActivityTaskManager 日志，点击后没有产生外部 Activity 启动记录，证明未知附件没有误拉起其他应用。
- 截图：`test/evidence/oa-attachment-open-failure-20260909/oa-unknown-format-blocked.png`。
- 改造后的静态状态截图：`test/evidence/oa-attachment-open-failure-20260909/oa-unknown-format-desktop-label.png`。

## 未覆盖边界

- 真机当前锁屏/Doze，未绕过锁屏复验附件点击。
- 各品牌 Android 对白名单中每种格式的实际第三方应用兼容性取决于用户安装的软件；客户端会对未安装处理器给出明确提示。
- iOS 的系统文件预览与第三方应用交接尚未做真机验收。
