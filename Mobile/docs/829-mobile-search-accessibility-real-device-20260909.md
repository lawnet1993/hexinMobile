# 移动端搜索框无障碍名称真机复验

日期：2026-09-09（Asia/Shanghai）  
设备：realme RMX3366，Android 14；Android 模拟器

## 问题

消息页搜索框视觉上有“搜索联系人、群组或消息”，但 Android 原生无障碍树中的 `android.widget.EditText` 没有名称，并被标记为 `NAF=true`。此前外层 `Semantics`、`MergeSemantics` 和可见 label 的方案要么未进入原生输入节点，要么改变页面视觉。

## 调整

`MobileSearchField` 使用 `MobileSearchTextController` 为可编辑文本的 `TextSpan` 提供用途语义：空值时为搜索用途，输入后为“用途，输入值”。组件未传控制器时自动创建；需要自行管理控制器的底部选项、群成员和审批成员页面改为直接持有同类型控制器，不引入双控制器代理。可见 `InputDecoration`、34dp 高度、字号、颜色和间距均未改变。

## 验证

- Flutter 语义用例确认空搜索框可按用途名称定位。
- 13 张主页面 Golden 全部通过，视觉像素基准未变化。
- 模拟器及 realme 真机主搜索框原生布局树均显示 `class="android.widget.EditText"`、`text="搜索联系人、群组或消息"`、`hint="搜索联系人、群组或消息"`，且没有 `NAF=true`。
- 模拟器群成员目录的路由自持控制器搜索框同样显示 `text="搜索姓名或账号"`、`hint="搜索姓名或账号"`，没有 `NAF=true`；输入同步定向用例通过。
- [真机截图](../test/evidence/main-tabs-20260909/real-device-search-sem-final.png)
- [真机原生布局树](../test/evidence/main-tabs-20260909/real-device-search-sem-final.xml)
- [模拟器群成员搜索布局树](../test/evidence/main-tabs-20260909/emulator-external-controller-search.xml)
- [真机群成员搜索布局树](../test/evidence/main-tabs-20260909/real-device-member-account-hidden.xml)
- 全量测试 1420/1420 通过；完整 `flutter analyze` 0 issue。
- Profile APK 已覆盖安装真机，登录状态保留；85,792,566 bytes，SHA-256 `F3BC82C29C3622EE0CEA21F901DBFA5CFFAEEE3810031F1BDC114D0F54437556`。

## 边界

当前证明 Android 主搜索框及抽样的群成员选择器搜索框原生节点命名和视觉不回归。模拟器曾启用 TalkBack，但首次运行被 Android Accessibility Suite 自身的通知授权及初始化页面截断，无法形成有效的应用内朗读样本；测试后已恢复无障碍服务原设置。实际朗读顺序、输入后播报、完整焦点遍历以及 iOS VoiceOver 仍不判通过。
