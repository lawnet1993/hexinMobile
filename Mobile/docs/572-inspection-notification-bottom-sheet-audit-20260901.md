# 572 在岗巡检通知与底部抽屉验收

## 结论

本轮通过当前可验证范围。移动端不再把 `inspection` 通知误当审批通知；点击后进入考勤打卡页并即时读取真实活动巡检。启动时的在岗确认也已从居中 `AlertDialog` 统一为移动端底部抽屉。

## 实现

- 仅依据服务端 `category/type=inspection...` 识别巡检，不解析标题或正文。
- 巡检通知显示独立“巡检”类型和巡检图标，固定路由到 `/punch?inspection=active`。
- 通知进入后调用现有 `/api/oa/inspections/active` 查询真实待确认项。
- 存在待确认项时展示“确认在岗 / 暂时无法响应”底部选择抽屉；关闭抽屉不会提交响应，后续回到前台仍可再次提示。
- 不存在活动巡检时展示明确的底部消息抽屉，不再点击无反应。
- 使用进程级互斥避免冷启动通知路由与 Shell 自动巡检同时弹出两层抽屉。

## 真机证据

- 设备：realme RMX3366，Android 14，1080×2400。
- Profile APK SHA-256：`E541B10A7253D170F1990280E8013C5A6FD286D5EEC30F68FAD3B6A5A6D9DB3E`。
- 通知列表已把两条真实“在岗确认”标记为“巡检”，而不是审批。
- 点击 08-29 的旧通知后进入真实考勤打卡页；服务端当前没有活动巡检，页面从底部展开“当前没有待确认的在岗巡检”。
- [通知列表截图](device-acceptance/inspection-notification-20260901-scrolled.png)
- [通知列表 UI 树](device-acceptance/inspection-notification-20260901-scrolled.xml)
- [无活动巡检底部抽屉截图](device-acceptance/inspection-notification-20260901-result.png)
- [无活动巡检 UI 树](device-acceptance/inspection-notification-20260901-result.xml)

## 回归与边界

- `flutter analyze`：0 问题。
- 专项：6/6 通过，覆盖巡检通知路由、底部选择抽屉和考勤异常既有路由。
- 完整自动化：199/199 通过。
- 真机关键崩溃日志匹配 0 条。
- 当前服务端没有活动巡检，因此真实“确认在岗 / 暂时无法响应”抽屉由组件测试证明；未伪造服务端活动巡检，也未调用打开或响应写接口。
- 全程未点击任何巡检响应选项，未修改线上业务数据。
