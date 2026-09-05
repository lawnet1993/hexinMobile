# 686 · OA 公式精度与保存往返

## 结论

**部分通过，整体目标继续。** 本轮在当前工作区复现并修复计算字段的二进制浮点误差、精度边界漏检和大整数 JSON 数字传递风险。新增 **31 项**测试，计算/表单/SQLite 专项 **40/40**，全量 **860/860**、静态检查 0 问题。

这些是计算器、真实表单组件及隔离 SQLite 的执行证据，**不是线上双公式请款或复杂分支流程通过**。当前 M3 财顺模板没有公式字段；未发布新流程、未修改后台模板，也不以旧桌面源码作为最新行为基准。

## 实际复现与修复

原计算器先将字段和常量转换为 double，运算后乘以小数位系数取整，附加的固定 epsilon 不能消除不同量级的误差。

| 用例 | 原结果 | 正确结果与回归 |
| --- | --- | --- |
| `1.005`，half_up，2 位 | 1.00 | 1.01 |
| `-1.005`，half_up，2 位 | -1.00 | -1.01 |
| `4.015`，half_up，2 位 | 4.01 | 4.02 |
| `0.29 × 100`，floor 或 truncate，0 位 | 28 | 29 |
| `(0.1 + 0.2) × 10`，ceiling，0 位 | 4 | 3 |
| 原始值 1.005 → 金额保留 2 位 → 成本为金额 × 3 | 上游舍入错误影响下游 | 金额 1.01、成本 3.03 |
| Decimal 上限本身或比上限多 1 | 常量/引用未经过完整边界检查，double 还会改变末位 | 合法上限精确保留；超界拒绝且移除旧计算值 |

[初始红测](../test/evidence/oa-calculation-precision-20260903/red.log)共 26 项，其中 **14 项失败、12 项通过**；包含既有 3 项测试，没有编译失败冒充红测。初次表单保存夹具没有配置允许草稿的目录项，导致 3 项保存断言为 null；已修正测试目录，生产草稿功能未因此修改。

### P1-686-01：金额运算及依赖字段不准确

[计算实现](../lib/features/todos/domain/approval_form_calculation.dart)现在从十进制文本直接构造约分分数，使用 BigInt 分子/分母完成四则运算，仅在每个计算字段的配置小数位上取整；下一字段使用上游已舍入结果。普通数值 JSON 保持兼容，不能无损往返的值以十进制文本保留，表单已有的文本金额路径不会再经过 double 转换。

BigInt 支持字符串直接解析大整数，而从浮点数构造无法找回已损失的十进制位；本实现不通过浮点数构造分子。[Dart 官方 API](https://api.dart.dev/dart-core/BigInt-class.html)

保留现有 `half_up`、`floor`、`ceiling`、`truncate`、最多 8 位配置语义；增加量值及舍入后有效系数检查，范围使用精确的 `79228162514264337593543950335`，对应 Decimal 最大值。[Microsoft 官方说明](https://learn.microsoft.com/en-us/dotnet/api/system.decimal.maxvalue?view=net-10.0)

这不意味着完整模拟服务端每一步 Decimal 运算，也不意味着已验证所有服务端表达式规则。仍保留原公式语法、循环/删除字段校验；输入长度/指数和分数位数设有边界，避免恶意或错误配置导致无界大整数工作。

### P2-686-02：JSON 大整数跨二进制数字消费者丢位

原始 native Dart 的 64 位整数能保存 `9007199254740993`，但 JSON 数字交给 JavaScript 后变成 `9007199254740992`。本机 Node 已实际复现：[JavaScript 对照](../test/evidence/oa-calculation-precision-20260903/javascript-roundtrip.json)，不是桌面窗口操作证据。

新增断言最初只检查返回类型，随后补成消费者数值差异，[有效红测](../test/evidence/oa-calculation-precision-20260903/red-json-integer-verified.log)实际相差 1。现在数字输出必须先通过 double 的十进制往返检查，否则保存为字符串。普通 1.01、3.03 等仍是数字；大额 `90071992547409.93` 和上述大整数保留为精确文本。

## 覆盖层次

1. [计算回归](../test/approval_form_calculation_test.dart)：正负中点、不同舍入方式、极小值、科学记数输入、依赖顺序、常量/引用/运算溢出、有效系数上限、非法输入、复杂度边界；另在一个用例内比较 572 个整数毫单位生成的 half_up 样本。
2. [表单往返](../test/oa_calculation_roundtrip_test.dart)：实际 `ApprovalRequestPage` 组件显示 1.01/3.03，保持只读和 USDT/CNY 字段单位；捕获草稿和流程预览参数并 JSON 往返；大金额恢复后不丢位，减回原始值仍为 0.01；溢出清除旧计算结果，修改源值后错误消失。
3. [SQLite](../test/oa_local_store_test.dart)：隔离临时库使用 AES-GCM 保护草稿，确认原始列已加密且不含金额明文；关闭并重开后，金额文本与依赖结果一致，其他账号读不到草稿。测试密钥为本地合成数据，不读取真实设备密钥。
4. [专项 40/40](../test/evidence/oa-calculation-precision-20260903/roundtrip-complete.log)、[全量 860/860](../test/evidence/oa-calculation-precision-20260903/full-final.log)、[分析 0](../test/evidence/oa-calculation-precision-20260903/analyze-final2.log)。早期曾有一条花括号风格提示，已修正，不隐去失败日志；未更新 Golden。

## 最终正常包与真实安装回归

上一目标轮属于**进展**：生产计算实现、红绿测试及最终构建发生了实际变化。恢复执行时原进程句柄 55843 已不存在，但[最终构建日志](../test/evidence/oa-calculation-precision-20260903/build-final.log)明确完成，APK 修改时间晚于最终源文件及测试修改时间，因此没有重复启动构建。

2026-09-03 04:17—04:19（主机 Asia/Shanghai），仅对独立 **M3 / emulator-5556 / test03** 执行正常 Profile 包覆盖安装，保留应用数据；不是注入合成表单的诊断包。`adb install -r` 返回 Success，[安装核对](../test/evidence/oa-calculation-precision-20260903/install-final.json)本地与设备 APK SHA256 均为 `A66CE63CAD4F321CBEBA4EE12D0682659463AA1107EC9860AF5ED3ADD9DEAB40`。

真实 UI 路径：

1. 冷启动进入[首页](../test/evidence/oa-calculation-precision-20260903/02-final-home.png)，仍为 Test Terminal 03，通知数 **31**，未回到登录页。
2. 点击右上通知进入[通知中心](../test/evidence/oa-calculation-precision-20260903/03-final-notifications.png)，全部 43 / 未读 31；打开上一轮已读的审批结果，不操作“全部标为已读”。
3. [实际详情](../test/evidence/oa-calculation-precision-20260903/04-final-approved-detail.png)仍是 **OA-20260902-2C342E**，金额 **100.25**、类型“其他”、期望付款日期 2026-09-04、状态“已通过”；原提交、同意记录及测试说明保留，申请人与处理人头像可见，没有新提交或再次审批。

[安装前后只读核对](../test/evidence/oa-calculation-precision-20260903/preservation-final.json)：原 2 条草稿、10 条已读回执完全一致，OA 游标 458、待同步 0；单聊账本和群消息一致，IM applied/acked 均为 236。两条原待发媒体的 clientMessageId、会话、类型和创建时间保持，未删队列或伪造发送成功。原始安全快照为 [OA 前](../test/evidence/oa-calculation-precision-20260903/oa-preinstall.json)、[OA 后](../test/evidence/oa-calculation-precision-20260903/oa-postinstall.json)、[IM 前](../test/evidence/oa-calculation-precision-20260903/im-preinstall.json)、[IM 后](../test/evidence/oa-calculation-precision-20260903/im-postinstall.json)。

[当前进程检查](../test/evidence/oa-calculation-precision-20260903/runtime-final.json)PID 17829 的保留日志中，Unhandled Exception、RenderFlex overflow、FATAL EXCEPTION 三项计数均 0；仅是本次观察范围，不能代表完整稳定性或性能验收。本轮没有切换网络，检查 Wi-Fi / 数据均为 1。

[当前桌面会话只读核对](../test/evidence/oa-calculation-precision-20260903/desktop-session-final.json)：已安装 1.0.87 正在运行，test01 的 IM/OA GET 均 200。**这不是 Windows 窗口真实操作，也不证明跨账号审批通过。** 设备画面与业务记录时间采用设备现有时区，未用不同设备时间相减得出性能结论。

## 验收边界

线上计算模板、分级金额分支、跨账号节点和大额文本提交后被服务端及当前桌面窗口正确解析仍未实测。服务端若已经以丢失精度的数值发送字段，客户端无法恢复丢失的原始位数，需要协议与上游共同验证。上述本地 JSON/SQLite 通过不替代端到端证据。

真机接管尚待确认，电脑控制入口本轮检索仍不可用；M1/M2 未操作。既有媒体 500、群事件/读投影、高级 OA 终态、完整多端/推送/性能问题继续保留。
