# 831 · 移动端账号展示收口与真机复验

日期：2026-09-09（Asia/Shanghai）  
设备：realme RMX3366，Android 14

## 调整

- 通讯录外部账号搜索结果、聊天联系人名片、新会话、群提及、群成员、群管理员、建群和审批选人列表不再把登录账号作为普通副标题展示。
- 保留按账号搜索能力；个人资料和账户安全详情仍可显示本人的账号信息。
- 没有部门信息时不再渲染空副标题，也不使用“群成员”等无效占位文本撑高列表。
- 姓名、部门、本人/群角色以及服务端 Presence 状态保持不变，未改变单聊/群聊边界。

## 验证

- 通讯录真机首屏默认只显示组织节点，没有展开人员。
- 展开“公司总部”后显示成员姓名、本人标记与真实在线/最近上线状态；原生布局树包含成员姓名且不包含 `test01` 等登录账号。
- [折叠状态截图](../test/evidence/main-tabs-20260909/real-device-account-privacy-contacts.png)
- [展开状态截图](../test/evidence/main-tabs-20260909/real-device-account-privacy-contacts-expanded.png)
- [折叠状态布局树](../test/evidence/main-tabs-20260909/real-device-account-privacy-contacts.xml)
- [展开状态布局树](../test/evidence/main-tabs-20260909/real-device-account-privacy-contacts-expanded.xml)
- 相关页面回归 130/130 通过；最新全量 Flutter 回归 1421/1421 通过；相关文件静态检查 0 issue。
- 最新 Profile APK 已覆盖安装真机，SHA-256 `1398696D1EAA0CF6060C97644977C0725FD0C862E2483B2C7050373D4BF2D213`。

## 边界

服务端仍返回账号用于授权、精确搜索和身份解析，本轮只收口移动端普通列表的可见展示。未修改服务端数据、好友关系或群成员关系。
