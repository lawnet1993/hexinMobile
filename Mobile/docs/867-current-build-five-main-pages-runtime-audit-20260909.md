# 867 · 当前构建五个主页面运行态巡检

时间：2026-09-09（Asia/Shanghai）  
设备：Android 16 模拟器 `emulator-5556`  
账号：Test Terminal 03  
当时巡检 APK SHA-256：`18422DD9AE29F5B5A9CDAEA2B319FC552FD469FD48100DAF2608D56E7019986C`；后续仅增加上传文件头识别的新基线见 [869](869-mobile-extensionless-image-local-processing-20260909.md)。

## 结论

当前 Profile APK 在真实测试数据下重新打开工作台、消息、待办、通讯录和我的五个主页面，页面均可用，底部五个 Tab 的原生语义与选中状态正确。本轮没有发现重新出现的超大按钮、错误空状态、账号明文、单聊/群聊混排或移动端站点入口。

## 页面核对

- 工作台：常用应用、待办摘要和通知入口保持紧凑；原生语义树没有“受控站点”“常用站点”或站点操作入口。
- 消息：单聊行使用人员头像和真实在线/离线语义，群聊行使用群图标及“群聊”标签；两种会话没有混排。
- 待办：分类栏可水平滚动，当前 2 条待处理事项显示标题、编号/发起人、时间和紧凑状态标签。
- 通讯录：默认只显示折叠组织，不展开人员；页面不显示登录账号。“选择部门”是面向大型组织的快速筛选，不是重复的企业通讯录模块。
- 我的：仅保留账户与安全、通知、登录设备、外观语言、帮助、关于和退出；没有站点、隧道或网络安全入口。

## 截图证据

- [工作台](../test/evidence/current-main-workbench-20260909.png)
- [消息](../test/evidence/current-main-messages-20260909.png)
- [待办](../test/evidence/current-main-todos-20260909.png)
- [通讯录](../test/evidence/current-main-contacts-20260909.png)
- [我的](../test/evidence/current-main-profile-20260909.png)

## 边界

- 本轮是 Android 模拟器前台巡检，不替代 Windows v1.0.105 可见窗口、iOS 真机、厂商后台推送和 realme 锁屏/Doze 验收。
- 页面显示的待办、未读和在线状态来自当前测试服响应；本轮没有修改审批或消息业务数据。
