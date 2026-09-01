# 617 · OA 跨账号真实流程与详情新鲜度验收

## 结论

- 真实提交并完整处理一条请款审批，申请编号 `OA-20260901-8990C6`，最终状态为“已通过”。
- 真实处理链路：青山提交 → 林川业务归属负责人审批 → 陈拓运营复核 → 苏敏财务初审 → 许致远、沈清双人会签终审。
- 中间节点只通知“当前节点已同意，审批继续流转”，没有提前显示整单通过。
- 会签第一人许致远同意后，整单仍为“审批中”，沈清仍为“待处理”；沈清同意后才转为“已通过”。
- 申请人收到完整进度通知、最终通过通知和抄送通知；分别打开最终结果与抄送后，未读数从 `14 → 13 → 12`。
- 验收中发现并修复 P1：跨账号切回申请人后，从“审批已通过”通知打开详情会显示本机旧的“审批中”快照。详情现改为联网时优先读取服务器最新状态，只在无 HTTP 响应的网络故障下回退到该账号的最后快照。

## 申请数据

- 应用：集团总部 · 外站通道及数据费用请款 v1。
- 申请人：青山，集团总部，`oa_qingshan_0825`。
- 金额：原始金额 `4999`，结算比例 `1`，汇率 `1`，计算请款金额 `4999 USDT`。
- 测试字段使用 `AI-UAT-20260901-1421-*` 标记；请款地址按后台规则使用合法 34 位 TRON 地址。
- 表单前端真实验证了地址长度和 TRON 格式。同期补充“提交时显示首个错误”，不再只在长表单底部静默失败。

## 证据

- [申请人提交后详情](evidence/617-oa-cross-device-flow/14-approval-submitted.png)
- [林川待处理](evidence/617-oa-cross-device-flow/16-owner-pending.png)
- [林川同意后转陈拓](evidence/617-oa-cross-device-flow/17-owner-approved.png)
- [陈拓同意后转苏敏](evidence/617-oa-cross-device-flow/18-ops-approved.png)
- [会签只完成许致远时仍审批中](evidence/617-oa-cross-device-flow/19-countersign-partial.png)
- [沈清完成后整单已通过](evidence/617-oa-cross-device-flow/20-countersign-complete.png)
- [申请人通知时间流](evidence/617-oa-cross-device-flow/21-applicant-notifications.png)
- [修复后申请人最新详情](evidence/617-oa-cross-device-flow/22-applicant-final-fresh.png)
- [结果与抄送已读同步](evidence/617-oa-cross-device-flow/23-notifications-read-synced.png)
- [真机长地址单行终态](evidence/617-oa-cross-device-flow/25-real-device-long-address-single-line.png)

## 回归与构建

- `flutter analyze`：0 issue。
- 新鲜度、离线回退、热重开、抄送已读和长连续值单行布局均通过；完整自动化 240/240 通过（含 13 组 Golden）。
- Profile APK：78,349,606 bytes，SHA-256 `018E96B340763E3C3E66948F88A9E7C73782F49CA5088967E30150DE9FC1D331`，已覆盖安装到模拟器和 realme。
- 模拟器和 realme 均在最终包上重放同一通知，详情立即显示服务器“已通过”终态；34 位请款地址与标签保持同一行且完整可见。
- 最终两台 Android 设备的进程日志中，崩溃、未处理 Flutter 异常、RenderFlex 溢出、ANR 和 OOM 关键命中均为 0 条。

## 未完成与阻塞

- Windows 桌面终端 `v1.0.81` 当前已登录 `laowang`，但不是该申请的审批人；自动化不代输密码，因此尚未用林川的桌面会话对同一申请补桌面端证据。
- 本轮未执行驳回、转交、加签、退回、撤回及并发幂等性；本报告不宣称整套 OA UAT 完成。
