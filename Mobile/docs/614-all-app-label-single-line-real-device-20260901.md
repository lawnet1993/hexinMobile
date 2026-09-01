# 614 · 全部应用名称单行密度真机回归

时间：2026-09-01

## 结果

- 首页常用应用原本已使用单行省略；“全部应用”页同步改为相同规则，五列网格中的应用名称不再折成两行。
- 长名称在网格中显示省略号，完整名称仍保留在语义树和目标页面标题中，不修改服务端目录名称、分类、顺序、图标、权限或路由。
- 真机真实目录中的 `分级请款审批` 现在显示为单行 `分级请款…`；点击后正常进入 `测试 · 分级请款审批` 动态表单。
- 表单未修改直接返回后仍回到“全部应用”，没有退出应用或丢失页面栈。

## 验证

- 应用/通讯录冒烟：19/19 通过。
- 全量自动化：235/235 通过。
- Golden：13/13 通过。
- `flutter analyze`：0 项问题。
- 干净 Production Profile APK：65,819,519 bytes。
- SHA-256：`EE0FD38F8FB71155235D194B3D10C31A6C3B62695615EF71CE5182C2F8B71FE3`。
- 真机安装后的 `base.apk` 哈希与构建包一致；重放进入与返回链路后无应用崩溃或 `E/flutter`。

## 数据边界

- 只读打开全部应用和分级请款表单，然后立即返回。
- 没有输入字段、上传附件、保存草稿或提交审批。

## 证据

- `docs/evidence/612-real-device-oa-regression/18-all-apps-single-line.png`
- `docs/evidence/612-real-device-oa-regression/19-long-app-route.png`
- `docs/evidence/612-real-device-oa-regression/20-all-apps-returned.png`

