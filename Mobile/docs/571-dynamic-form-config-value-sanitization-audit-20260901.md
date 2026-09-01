# 571 OA 动态表单配置值隔离验收

## 结论

本轮通过。移动端继续以后台可视化表单下发的 `formSchemaJson` 为字段契约；`calculation`、`readOnly`、`unit` 只控制计算、输入能力和单位展示，不会进入字段值或正文。另补齐旧草稿、再次发起和旧接口数据的防御：若已保存字段值误为配置对象或不符合字段类型的集合，渲染前直接剔除，不再调用 `toString()` 暴露“自动计算、只读、单位天”等内部配置。

## 桌面与真机对照

- 当前已登录 Windows 桌面端 v1.0.80：请假天数字段下只显示“根据起止时间自动计算自然日”。
- 真机：realme RMX3366，Android 14，1080×2400。
- Profile APK SHA-256：`B59FC33A17D88E5EFA626AC56A945ADF5A2BFC3D134EC976C4205C3750A5485A`。
- 真机 Profile 页与桌面保持一致；UI 树中不存在独立“只读”“单位天”或独立“自动计算”配置项。
- 仅打开、读取和截图，没有选择字段、修改附件、保存草稿或提交申请。

## 证据

- 真机页面：[dynamic-form-schema-20260901-form.png](device-acceptance/dynamic-form-schema-20260901-form.png)
- 真机 UI 树：[dynamic-form-schema-20260901-form.xml](device-acceptance/dynamic-form-schema-20260901-form.xml)
- Profile 启动 UI 树：[dynamic-form-schema-20260901-profile-launch.xml](device-acceptance/dynamic-form-schema-20260901-profile-launch.xml)

## 回归

- `flutter analyze`：0 问题。
- OA 页面专项：34/34 通过。
- 完整自动化：198/198 通过。
- 新增“配置对象不得作为字段值渲染”用例；同时保留后台公式、只读、单位尾缀、精度和桌面时长说明断言。
- Profile 构建和真机覆盖安装成功；关键崩溃日志匹配 0 条。
