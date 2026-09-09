# 824 · OA 大附件缓存复用与真机回归

日期：2026-09-09（Asia/Shanghai）  
桌面功能基线：真实运行窗口 **v1.0.105**

## 发现与修复

真机打开同一份 `AI-UAT-OA-20M-EXACT-20260909.txt` 时，旧实现每次点击都会创建新的 `open-*` 目录并重新下载完整 20 MB 文件。连续两次操作留下两份内容相同的短期缓存，既浪费流量，也会放大磁盘占用和二次打开延迟。

移动端现改为：

1. 仍由用户点击附件后才开始下载，不在列表后台偷跑。
2. 按环境、账号、附件 ID、文件名、大小和服务端 SHA-256 生成隔离的稳定对象缓存。
3. 首次下载写入独立 `download-*` 临时目录，完成后原子移动到 `cache-*`；中断、退出页面或会话变化不会把半文件当成缓存。
4. 再次打开先验证文件存在、长度和服务端 SHA-256；摘要使用文件流计算，不把大文件整体读入内存。验证通过后直接交给系统打开方式，不重新请求服务端。
5. 新下载的文件如果无法交给系统查看器会被删除；成功缓存及临时下载目录继续接受 24 小时回收。
6. 普通文件、音频和视频仍保持文件流传输，不转 Base64，也不做有损压缩；图片上传的本机压缩策略不受影响。

## 真机证据

- 首次点击真实 20 MB TXT：页面显示 `下载 3%` 及圆形进度，下载完成后出现 Android 系统“打开方式”。
- 第二次点击：不到 0.7 秒直接出现系统“打开方式”，未再次显示下载百分比。
- 第二次打开复用同一路径，未新增第二个稳定缓存对象。
- 加入摘要验证后的真机包再次执行同一 20 MB 用例，第二次点击 0.8 秒内直接出现系统打开方式；旧的仅大小缓存未被误用。
- 修复前本轮测试产生的两个精确 `open-*` 20 MB 副本已在关闭查看器后删除；新的稳定缓存和其他业务缓存保留。

截图：

- `Mobile/test/evidence/session-matrix-20260909/oa-detail-current.png`
- `Mobile/test/evidence/session-matrix-20260909/oa-attachment-progress.png`
- `Mobile/test/evidence/session-matrix-20260909/oa-attachment-after.png`
- `Mobile/test/evidence/session-matrix-20260909/oa-attachment-cache-hit.png`
- `Mobile/test/evidence/session-matrix-20260909/oa-attachment-sha-cache-hit.png`

## 自动化与构建

- OA 外部打开、缓存复用、同尺寸损坏识别和回收专项：**57/57 通过**；此前含流式存储组合：**59/59 通过**。
- 定向静态分析：**0 issue**。
- 最终合入后全量 Flutter 回归：**1416/1416 通过**；全量静态分析：**0 issue**。
- 最新 Profile APK 构建并覆盖安装真机成功；SHA-256：`2CF1E66DF6A4C361EF7FA9F43E475CF7A45F11AF7C56C05A02DC7B6870AA1CBE`。

## 当前边界

- 本轮验证的是 Android 真机、TXT 和系统查看器；PDF/Office 的系统应用选择、查看器兼容性仍取决于设备安装的软件。
- 桌面 v1.0.105 的附件行为尚未在当前线程直接操作，不以移动端结果代替桌面实测。
- 同平台 `session_replaced` 仍等待 M3 屏幕完成一次 test01 密码输入，见 [823](823-mobile-session-replacement-and-auto-login-runtime-20260909.md)。
