# 565 OA 动态表单默认值、校验与附件契约验收

## 结论

本轮通过。移动端审批发起页继续以后台可视化表单下发的 `formSchemaJson` 为唯一字段契约，不根据字段名称补造规则，也不把 `calculation`、`readOnly`、`unit` 等配置原样输出为正文或字段值；单位只作为输入框尾缀，公式与只读只控制字段行为。后续按当前桌面 v1.0.80 复核结果，时长字段补充了面向用户的“根据起止时间自动计算自然日/小时”，详见 566 号验收记录。

## 实现范围

- 支持人员默认值 `requester`、部门默认值 `requester_department`、日期 `today`、日期时间 `now`、日期范围 `today` 和后台固定默认值。
- 默认值只填充空字段，不覆盖已恢复草稿、再次发起数据或用户已经编辑的内容。
- 文本字段按 schema 执行最小长度、最大长度和 TRON 地址格式校验。
- 提交前遍历完整 schema 校验，即使字段因长列表滚出屏幕并已卸载，仍不会漏过必填项或格式错误。
- 附件字段按 `multiple`、`maxCount`、`imagePreview` 控制单选替换、数量上限和图片预览；不再统一硬编码为 20 个或强制生成图片缩略图。
- 字段服务器错误和客户端错误按字段绑定；编辑、重新选择或删除附件后只清除对应错误。

## 真机只读结果

- 设备：realme RMX3366，Android 14，1080×2400。
- 应用：`com.hexing.zhilian.hexing_terminal_mobile`，v1.0.1 (2)。
- Profile APK SHA-256：`09BE717FD3C4553CA9B044B4E7EBDD31C9D36DB36F91032DF97DADA838FEFB97`。
- 线上“测试 · 分级请款审批”v1 自动带出当前业务部门“测试”和请款人“Codex 测试终端”；申请日期仍显示“请选择”，说明当前发布 schema 未下发可解析的当天默认值，移动端没有擅自补值。
- 线上“请假审批”v1 的只读时长字段不会把“自动计算”“只读”“单位天”作为独立配置文本或字段值展示；当前版本已按桌面端补充自然日/小时的完整用户说明。
- 分级请款金额、成本等字段没有被移动端按名称臆测为公式字段；是否计算、是否只读以及单位均继续由当前发布 schema 决定。
- 只执行打开、滚动、截图和返回；未输入、选择、上传、删除、保存或提交任何业务数据，现有请假草稿和附件未改动。

## 证据

- 分级请款表单顶部：[02-tiered-top.png](device-acceptance/dynamic-form-contract-20260831/02-tiered-top.png)
- 分级请款 UI 树：[02-tiered-top.xml](device-acceptance/dynamic-form-contract-20260831/02-tiered-top.xml)
- 计算字段区域：[03-tiered-calculation.png](device-acceptance/dynamic-form-contract-20260831/03-tiered-calculation.png)
- 计算字段 UI 树：[03-tiered-calculation.xml](device-acceptance/dynamic-form-contract-20260831/03-tiered-calculation.xml)
- 请假表单字段：[04-leave-top.png](device-acceptance/dynamic-form-contract-20260831/04-leave-top.png)
- 请假表单 UI 树：[04-leave-top.xml](device-acceptance/dynamic-form-contract-20260831/04-leave-top.xml)

## 回归

- `flutter analyze`：0 问题。
- `flutter test`：191/191 通过。
- 覆盖后台公式只读与单位尾缀、配置说明不暴露、人员/部门/日期默认值、固定默认值、文本/TRON 校验、附件上限与预览策略，以及滚出屏幕后完整 schema 校验。
- Profile 构建和真机覆盖安装成功；工作台、全部应用、分级请款和请假审批均可正常打开、滚动和返回。
- 关键崩溃日志匹配 0 条。
