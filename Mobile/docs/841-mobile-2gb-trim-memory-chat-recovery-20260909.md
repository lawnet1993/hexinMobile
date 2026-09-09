# 841 · 2 GB Android 模拟器内存回收后会话恢复

时间：2026-09-09（Asia/Shanghai）  
环境：Android 16、约 2 GB RAM 模拟器；当前 Profile APK

## 过程与结论

1. 启动已登录移动端并清空本次图形统计样本。
2. 对前台应用发送 Android `RUNNING_CRITICAL` 内存回收通知。
3. 重新进入消息页及已有长群聊。
4. 核对当前 Activity、页面内容、登录态和进程内存。

结果：应用未崩溃、未返回登录页，长群聊正常恢复；消息顺序、群/单聊视觉边界、头像聚合、日期分隔及输入栏均保持可用。采样时 `TOTAL PSS` 约 205,571 KB、`TOTAL RSS` 约 291,592 KB、Swap PSS 653 KB。

## 证据

- `test/evidence/main-tabs-20260909/emulator-5556-trim-memory-chat.png`
- `test/evidence/main-tabs-20260909/emulator-5556-trim-memory-chat-gfxinfo.txt`

## 证据边界

- Android `gfxinfo` 在本次 Flutter Surface 样本中报告 0 个可统计帧，百分位为无效占位值，因此不以它宣称帧率或打开延迟通过。
- 本轮证明的是 2 GB 模拟器收到系统内存回收通知后的功能恢复，不等于真实低内存手机上的 10–20 MB 图片解码峰值通过。
- 真实大图成功路径和 realme 内存 A/B 继续以 [819](819-mobile-image-stream-native-compression-20260909.md) 为准。
