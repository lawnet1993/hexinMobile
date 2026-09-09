# 844 · 移动端头像库、系统选择与裁剪取消实测

时间：2026-09-09（Asia/Shanghai）  
环境：Android 16 模拟器；当前 Profile APK

## 结果

- “我的”首页个人卡片保持姓名、部门和头像的紧凑展示，不暴露登录账号。
- 点击个人卡片进入“个人资料”，昵称为单行紧凑输入，个性签名为有限高度多行输入，保存按钮只有数据变化后才可用。
- 点击头像进入居中头像库：5 个内置头像和 1 个“相册”入口组成 3×2 视觉网格，没有使用占满页面的底部抽屉。
- “相册”调用 Android 系统文件选择器；应用没有请求读取整个相册的权限。
- 选择项目自带的测试头像后进入圆形裁剪页，支持缩放和旋转，并提供明确取消与确认操作。
- 本轮选择取消：返回个人资料后仍显示原头像，保存按钮保持禁用，没有上传或修改线上资料。
- 应用缓存目录为空，没有遗留 `mobile-image-source-*` 临时原图。
- `AI-UAT-avatar-crop-test.jpg` 已从模拟器公共相册删除并触发媒体索引更新。

## 证据

- `test/evidence/main-tabs-20260909/emulator-5556-profile-avatar-audit-01.png`
- `test/evidence/main-tabs-20260909/emulator-5556-profile-avatar-audit-02-edit.png`
- `test/evidence/main-tabs-20260909/emulator-5556-profile-avatar-audit-03-library.png`
- `test/evidence/main-tabs-20260909/emulator-5556-profile-avatar-audit-04-system-picker.png`
- `test/evidence/main-tabs-20260909/emulator-5556-profile-avatar-audit-05-picker-search.png`
- `test/evidence/main-tabs-20260909/emulator-5556-profile-avatar-audit-06-crop.png`
- `test/evidence/main-tabs-20260909/emulator-5556-profile-avatar-audit-07-cancelled.png`

## 边界

- 本轮有意不确认裁剪，避免修改当前测试账号头像；真实确认后的 WebP 压缩与服务端更新由已有自动测试和历史真机上传证据覆盖。
- realme 真机本轮处于锁屏休眠状态，没有绕过锁屏；因此当前交互截图来自 Android 16 模拟器。
- iOS PHPicker 和裁剪页仍待 iOS 真机验证。
