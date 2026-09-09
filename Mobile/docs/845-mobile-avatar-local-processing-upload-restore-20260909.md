# 845 · 移动端头像本机处理、上传与恢复验证

时间：2026-09-09（Asia/Shanghai）  
设备：Android 模拟器 `emulator-5556`（测试账号）

## 结论

头像“相册选择 → 1:1 圆形裁剪 → 本机压缩 → 上传 → 页面回显”真实链路通过。测试结束后已恢复原内置头像，且只删除了本次 `AI-UAT-avatar-upload-test.jpg` 测试文件，未修改昵称、签名或其他资料。

本轮还发现并修复了裁剪器输出文件在成功上传后残留于应用缓存的问题。新构建在上传完成后再次检查，`cache` 下无本次裁剪 JPG；成功、失败和提前返回均通过 `finally` 执行尽力清理，相册原文件不在删除范围内。

## 上传规则

- 可压缩图片在移动端先做方向/尺寸处理与压缩，再上传最终产物。
- 普通 IM、OA 图片和文件不转 Base64，继续使用文件流或 `multipart/form-data`。
- 头像属于服务端现有小图片协议的明确例外：裁剪和压缩后限制在 290 KB 内，再按现有头像字段提交。
- 文档、音频、视频和无法安全重编码的文件不伪装成图片压缩；大文件不能仅因体积大而一律禁止选择。

## 真实步骤与证据

1. 从系统相册选择测试 JPG，进入系统裁剪页并显示圆形 1:1 裁剪框。
2. 确认裁剪后返回个人资料页，新头像即时回显。
3. 打开头像库，恢复第一项内置头像“阿晨”，个人资料页回显恢复成功。
4. 新构建重复以上路径后，应用 `cache` 目录未发现 `image_cropper_*.jpg`。

截图位于 `test/evidence/main-tabs-20260909/`：

- `emulator-5556-avatar-current.png`
- `emulator-5556-avatar-upload-02-result.png`
- `emulator-5556-avatar-upload-04-restored.png`
- `emulator-5556-avatar-upload-07-cleanup-pass.png`
- `emulator-5556-avatar-upload-08-final-restored.png`

## 验证

- 相关静态分析：0 issue。
- 图片压缩与上传策略测试：13/13 通过。
- Android Profile APK：81.8 MB，SHA-256 `65662601CF42F36F3EF7911EB95925AFAD885745A1FA7455BEFF925B4CBB6F67`。

## 边界

- Android 模拟器成功路径已通过；本轮 realme 真机处于锁屏状态，未绕过锁屏重复写入测试资料。
- iOS 的 PhotoKit/ImageIO 裁剪、权限拒绝与内存边界仍需 iOS 真机验证。

