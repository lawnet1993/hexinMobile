# 566 OA 时长字段桌面端对齐验收

## 结论

本轮通过。当前已登录 Windows 桌面端 v1.0.80 的请假发起页确认：时长字段显示面向用户的完整说明“根据起止时间自动计算自然日”，但不会把“自动计算”“只读”“单位天”作为独立配置文本或字段值暴露。移动端已按这一真实运行基准对齐。

## 当前实现

- `durationUnit=days`：显示“根据起止时间自动计算自然日”。
- `durationUnit=hours`：显示“根据起止时间自动计算小时”。
- 时长字段继续保持只读、不可获得输入焦点。
- `days/hours` 仍只决定计算和单位尾缀，不显示 schema 属性名。
- 普通计算字段不会凭字段名称生成额外说明。

## 真实运行证据

- 桌面基准：当前已登录“合兴智联”v1.0.80 请假审批窗口，字段顺序为请假类型、开始时间、结束时间、请假天数、请假事由、证明附件；“请假天数”下显示“根据起止时间自动计算自然日”。
- 真机：realme RMX3366，Android 14，1080×2400。
- 应用：`com.hexing.zhilian.hexing_terminal_mobile`，v1.0.1 (2)。
- Profile APK SHA-256：`2083636C4BF0C7F9DCBF5604D618170B3C6B60E6C15CE9D23D7887275756C9CA`。
- 真机截图：[01-leave-helper.png](device-acceptance/duration-helper-alignment-20260831/01-leave-helper.png)
- 真机 UI 树：[01-leave-helper.xml](device-acceptance/duration-helper-alignment-20260831/01-leave-helper.xml)
- UI 树断言：目标完整说明存在；独立“自动计算”、独立“只读”和“单位天”均不存在。

## 回归

- `flutter analyze`：0 问题。
- OA 页面专项测试：33/33 通过。
- 完整自动化：191/191 通过。
- Profile 构建、真机覆盖安装、冷启动、打开请假审批、滚动和返回均正常。
- 关键崩溃日志匹配 0 条。
- 全程未选择字段、删除附件、保存草稿或提交申请，服务端业务数据未改变。
