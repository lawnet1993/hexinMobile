# 613 · 真机通知中心与个人待办密度回归

时间：2026-09-01

## 结果

- realme 真机通知中心真实返回 `全部 31 / 未读 2`；审批、单聊、群聊、考勤和巡检使用独立来源标签，没有把应用内通知与手机系统通知混为一类。
- 31 条真实记录连续上滑正常，页面没有“加载更多”按钮；切换未读后只显示两条真实未读审批，全部数量仍保持 31，没有被当前筛选结果覆盖。
- 本轮没有打开未读记录或点击“全部已读”，因此没有改变服务端已读状态。
- 修复“我发起的”列表中个人待办同时显示复选框与状态图标的问题：现在使用单个 40dp 完成控件，审批申请仍使用各自应用图标，标题获得更多横向空间。
- 完成态保留删除线和“已完成”状态，点击整行/复选框的完成切换语义不变；读屏只保留一条完整事项语义，不重复朗读内部复选框。

## 验证

- OA 定向：45/45 通过。
- 全量自动化：235/235 通过。
- Golden：13/13 通过。
- `flutter analyze`：0 项问题。
- 干净 Production Profile APK：65,819,519 bytes。
- SHA-256：`8F9BC12BB0BCC5264DB5261D7B0EA0CB0FE2BEE9789A48D5C5A4367E0D53996C`。
- 真机安装后的 `base.apk` 大小和哈希与构建包完全一致。
- 清空日志、覆盖安装、冷启动并重放待办/通知路径后，没有应用崩溃或 `E/flutter`。

## 数据边界

- 只读查看通知中心、切换全部/未读、滚动列表，以及查看既有“我发起的”事项。
- 没有标记通知已读、完成/恢复个人待办、提交审批或发送消息。
- 当前真实通知只有 31 条，小于接口单页上限；超过 100 条的真实自动分页仍没有现成数据，第二页、短首屏补齐和失败重试继续由自动化覆盖。

## 证据

- `docs/evidence/612-real-device-oa-regression/13-notifications-all.png`
- `docs/evidence/612-real-device-oa-regression/14-notifications-scrolled.png`
- `docs/evidence/612-real-device-oa-regression/15-notifications-unread.png`
- `docs/evidence/612-real-device-oa-regression/16-initiated-single-control.png`
- `docs/evidence/612-real-device-oa-regression/17-final-notifications.png`

