# 840 · 移动端图片与附件权限及最终 APK 审计

时间：2026-09-09（Asia/Shanghai）  
对象：当前 Profile APK、realme Android 真机

## 结论

移动端图片、视频、音频和普通附件均通过 Android 系统选择器取得单文件访问授权，不需要读取整个相册或外部存储。最终 APK 权限清单已核对：

- `android.permission.INTERNET`
- `android.permission.ACCESS_NETWORK_STATE`
- `android.permission.WAKE_LOCK`
- `android.permission.POST_NOTIFICATIONS`

最终安装包不包含以下广泛媒体权限：

- `READ_EXTERNAL_STORAGE`
- `READ_MEDIA_IMAGES`
- `READ_MEDIA_VIDEO`
- `READ_MEDIA_AUDIO`

因此图片/附件选择与系统通知授权相互独立。用户未开启通知权限时只影响系统通知，不影响 IM、OA、图片压缩或系统文件选择器。

## 失败处理

- 系统选择器取消：保持当前页面和已有附件，不显示错误。
- 文件授权在读取前被撤销：统一提示“无法访问所选文件，请重新选择或检查系统照片与文件权限”。
- 图片原生编码全部失败：提示“图片处理失败，请重新选择或换一张图片”。
- 文件失败不会被归类为网络不可用，也不会创建不完整的附件记录。
- 图片临时原图保存在应用私有缓存，成功或失败都执行清理；普通附件进入账号/环境隔离的加密暂存。

## 验证

- 使用 Android Build Tools `aapt dump permissions` 检查最终 APK，确认仅包含上述四类系统权限及应用动态接收器内部权限。
- 使用真机 `dumpsys package` 检查当前用户运行时权限，只存在系统通知权限；本轮其状态为已授权。
- 文件权限撤销和错误文案自动测试通过。
- 图片压缩异常及上传策略测试 13/13 通过。
- 当前全量 Flutter 回归 1424/1424 通过。

## 边界

- Android 系统选择器由系统拥有，厂商 ROM 的文案和入口可能不同，但应用不依赖厂商相册的全局读取权限。
- iOS 仍需在真机核对 PHPicker、有限照片权限和用户撤销授权后的实际提示。
