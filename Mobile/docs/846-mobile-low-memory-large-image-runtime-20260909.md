# 846 · 2 GB Android 大图本机压缩运行验证

时间：2026-09-09（Asia/Shanghai）  
设备：Android 模拟器 `emulator-5556`，系统内存约 2 GB  
账号：Test Terminal 03

## 结论

12.74 MB、6000×4000 高熵 JPEG 在约 2 GB Android 环境中完成系统选择器读取、本机采样压缩、动态 OA 表单暂存和缩略图显示，输出 533.4 KB。应用进程没有退出或重启，界面保持可操作。

本轮未提交审批。测试附件已从表单界面删除，账号隔离的 `oa-queued-attachments` 目录复核为无文件；模拟器公共测试图片已删除。

## 内存与时间

| 观察点 | PSS |
| --- | ---: |
| 选择前 | 186,642 KB |
| 约 0.7 秒 | 197,610 KB |
| 约 1.3 秒 | 205,295 KB |
| 约 2.0 秒采样峰值 | 214,911 KB |
| 约 2.6 秒 | 197,947 KB |
| 约 17.9 秒 | 197,743 KB |

采样峰值相对基线增加 28,269 KB，约 2.6 秒时已经回落到接近稳定值。模拟器数据用于补充低内存 Android 运行边界，不能替代特定厂商真机内存管理行为。

## 证据

- 样本：临时生成的 6000×4000 JPEG，12,742,910 bytes。
- 表单结果：`emulator-5556-lowmem-image-06-result.png`。
- 删除后界面：`emulator-5556-lowmem-image-07-clean.png`。
- 连续 PSS 采样：`emulator-5556-lowmem-image-memory.txt`。
- 证据目录：`test/evidence/main-tabs-20260909/`。

## 判定边界

- Android 2 GB 模拟器：功能、进程存活、回落和暂存清理通过。
- realme 真机 18.63 MB 样本仍以 [819](819-mobile-image-stream-native-compression-20260909.md) 的约 120 MB 相对峰值为准；模拟器较低增量不能覆盖真机结论。
- iOS ImageIO 大图、HEIC、高压缩比 PNG 和内存告警中断恢复仍未验证。

