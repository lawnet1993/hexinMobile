# 群成员目录账号隐藏真机复验

日期：2026-09-09（Asia/Shanghai）  
设备：realme RMX3366，Android 14

## 问题

通讯录、群提及成员和其他成员选择器已按移动端要求隐藏终端账号，但“群聊详情—查看全部”仍把 `departmentName` 与 `username` 拼接显示，真机可见 `公司总部 · test01`、`财顺 · test03`，同一身份信息在不同入口表现不一致。

## 调整

- 群成员目录副标题只显示部门，不再显示终端账号。
- 保留姓名、本人标识、群主/管理员角色和服务端 Presence 状态。
- 搜索接口仍可按账号查找，不因隐藏展示值削弱管理查找能力。
- 不改变群成员分页、管理权限或单聊/群聊边界。

## 验证

- 真机重新进入两人测试群的全部成员抽屉，列表只显示“公司总部”“财顺”和“在线”。
- 原生布局树中不存在 `test01`、`test03`，搜索框仍显示“搜索姓名或账号”。
- [真机截图](../test/evidence/main-tabs-20260909/real-device-member-account-hidden.png)
- [真机布局树](../test/evidence/main-tabs-20260909/real-device-member-account-hidden.xml)
- 聊天与搜索控制器定向回归 103/103 通过；全量回归 1420/1420 通过；完整 `flutter analyze` 0 issue。
- Profile APK 已覆盖安装真机，登录状态保留；85,792,566 bytes，SHA-256 `F3BC82C29C3622EE0CEA21F901DBFA5CFFAEEE3810031F1BDC114D0F54437556`。

## 边界

本轮只调整账号的可见展示；服务端仍返回账号用于授权、搜索和身份解析。未修改服务端数据，也未修改群成员关系。
