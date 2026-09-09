# 803 · 真机单聊/群聊与媒体缩略图复验

日期：2026-09-08（Asia/Shanghai）

## 结论

- realme 真机只读打开 Test Terminal 05 单聊和公司总部群聊，顶部身份、在线状态、群成员/在线人数、聊天/文件/任务边界均来自真实数据。
- 单聊与群聊没有混排：单聊顶部使用对端头像和在线状态；群聊使用群图标、成员总数和真实在线人数；群聊不显示单聊任务页。
- 连续同发送者消息只在第一条展示头像，发送方切换或时间组变化后重新展示；群聊消息显示真实发送者姓名，回复引用与正文分层。
- 单聊中的历史图片首次冷加载在 4 秒截图时仍显示加载态，15 秒内完成；再次打开在约 700 ms 观察点已命中账号隔离磁盘缓存并直接显示。说明热开会话没有重复下载/重渲染，但首次原图链路仍受网络和文件大小影响。
- “文件 → 图片/视频”原来只显示通用文件名列表，不符合移动端媒体浏览。现改为三列缩略图网格，图片直接展示缩略图，视频展示封面、播放标识和时间；不再显示重复文件名。原文件仍只在用户点击后打开或下载。
- 真机点击 5:08 MP4 后，约 800 ms 观察点处于全屏播放器初始化状态，随后成功显示真实画面、暂停按钮、当前进度 `0:19` 和总时长 `5:08`；播放链路本轮通过。
- “文件”资源页中的音频不再走系统文件打开链路：点击 `AI-UAT-offline-audio.wav` 后直接在 App 内播放，右侧播放图标切换为暂停；再次点击可暂停并恢复播放图标。两次操作期间前台始终为移动端 `MainActivity`。
- 从会话资源页触发文件或媒体下载时，当前下载项现显示确定/不确定进度环和百分比；再次点击该项即取消。未点击的原文件不启动下载。

## 验证

- 聊天详情专项 Widget 测试：97/97 通过，覆盖消息分组头像、群/单聊边界、媒体几何、视频封面、音频内联播放、历史分页、首次未读定位和本次媒体网格。
- `flutter analyze`：0 issue。
- Android Profile 构建成功并覆盖安装真机；最终 APK 72,014,759 bytes，SHA-256：`4487DE7DBA8C0699FDE28AF03306C38C08BB84F4EF6DCB283C55EBD7279C2E24`。
- 真机媒体网格真实显示 3 张图片和 1 个视频封面，致命异常、内存溢出和未处理异常日志 0 条。

## 证据

- [单聊详情](../test/evidence/real-device-main-pages-20260908/direct-chat-after-15s.png)
- [单聊热开约 700 ms 观察点](../test/evidence/real-device-main-pages-20260908/direct-chat-hot-700ms.png)
- [群聊详情](../test/evidence/real-device-main-pages-20260908/group-chat-readonly.png)
- [改造前媒体文件列表](../test/evidence/real-device-main-pages-20260908/direct-media-tab-readonly.png)
- [改造后媒体缩略图网格](../test/evidence/real-device-main-pages-20260908/direct-media-grid.png)
- [视频点击后初始化](../test/evidence/real-device-main-pages-20260908/video-click-800ms.png)
- [真实视频播放](../test/evidence/real-device-main-pages-20260908/video-click-9s.png)
- [资源页音频播放](../test/evidence/real-device-main-pages-20260908/audio-resource-playing.png)
- [资源页音频暂停](../test/evidence/real-device-main-pages-20260908/audio-resource-paused.png)

## 仍未通过

- 服务端/桌面历史契约只发现原图下载 `/api/im/messages/{messageId}/images/{imageId}`，没有找到接收端专用的小图接口；移动端当前以按需加载、显示尺寸解码、内存缓存和账号隔离磁盘缓存控制重复成本，但首次远端图片仍可能慢。若要稳定首屏，应由 File Service 提供按宽高或质量派生的鉴权缩略图。
- 本轮视频播放和音频资源页内联播放/暂停均已通过；音频下载取消和断点恢复边界仍沿用既有真机证据，本轮未重新制造网络中断。
- Windows v1.0.105 原生窗口仍未能被当前自动化表面直接控制，桌面可见的附件/媒体对照尚未完成。
