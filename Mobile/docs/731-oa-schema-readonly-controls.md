# 731 后台只读配置在移动端选择器与附件上生效

时间：2026-09-05 01:46–01:52（Asia/Shanghai）。本轮修复客户端可视化表单配置执行缺口，不修改后台模板或审批数据。整体目标仍未完成。

## 问题与修正

`approval_request_page.dart` 已解析字段 `readOnly`，但以前仅在最后的文本/数字渲染分支使用。checkbox、select、multiSelect、person、department、date、datetime、dateRange 提前返回，仍保留修改回调；attachment/file 另走附件编辑器，仍显示替换和删除入口。

本轮统一使用现有 `field.isReadOnly`：

- 只读勾选框禁用修改；只读下拉、多选、人员、部门和日期控件不再打开选择器。
- 只读选择器移除下拉/选择图标，保留当前值和校验，避免暗示还能修改。不新增“只读”等占位值。
- 只读附件隐藏添加/替换、删除入口，保留查看入口与原附件数据；不把整个附件行禁用。
- 可编辑字段原交互、必填要求、日期计算、公式、草稿保存和附件查看方式不变。
- 没有新增独立申请标题框：保留现有自动标题与后台配置的字段集合，避免为了测试擅自改变表单布局。

这是 UI 对配置的遵守，不是安全权限边界；服务端仍应校验字段与操作权限。

## 测试

新增 `test/oa_readonly_controls_test.dart`，10 种类型各测试只读/可编辑，共 20 项。

- 修正前：10 个只读用例失败、10 个可编辑用例通过，复现真实代码分支缺口。
- 修正后：20/20。验证修改回调是否存在、只读点击不打开抽屉、可编辑点击能打开并取消；保存后原值不变。附件检查可查看入口保留、修改入口消失、原附件 ID/字节仍写入草稿。
- 全量 `flutter test --reporter compact`：**1359/1359**，1:07。
- 改动生产 Dart 文件和新测试定向 `flutter analyze`：无问题。全仓 analyze 未在本轮重跑。
- 更新后的只读后台核对脚本 PowerShell 语法检查 0 错误。

## 构建与设备

正常 `lib/main.dart` Profile 双架构（arm64/x64）构建 59.0 秒，80.7 MB。

SHA256：`C6102F49C8320070947F0BE6978B7F39D39E214980B0BC1951F205EA90C43BCB`。

安装前两端均在首页、无输入框；真机 dd00d66d 与 M3 emulator-5556 均 `adb install -r` 成功。未清数据、卸载、切换账号或修改手机热点。secure_tunnel 的未来 Kotlin 插件兼容警告仍不阻止构建。

### 真机 test01

- 自动恢复账号；从首页打开请假审批，恢复原 `AI-UAT-20260905-012200-OA-DATE-728` 草稿。
- 原事假、09/06 01:21 至 09/07 01:21、自动 2 天和事由完整保留：[草稿](../test/evidence/oa-readonly-731/phone-draft.png)。
- 点击请假类型，真实底部选择器正常打开；取消后值仍为事假：[类型选择](../test/evidence/oa-readonly-731/phone-type-picker.png)。
- 点击结束日期，真实日期抽屉正常打开，选中 09/07；取消，不改日期：[日期选择](../test/evidence/oa-readonly-731/phone-date-picker.png)。
- 只读 SQLite 元数据核对同一草稿 ID `e6d827f3-04bc-4591-a641-57812cf90647`，最后保存时间仍为 `2026-09-04T17:32:17.52171Z`，OA Outbox 为空。本轮未新增草稿写入或提交。

### M3 test03

- 自动恢复账号；打开请假表单，原 `AI-UAT-20260902-215300-OA-DRAFT-SESSION` 草稿保留：[表单](../test/evidence/oa-readonly-731/m3-form.png)。没有修改、提交或覆盖它。
- 当前预览显示财顺 v1、Test Terminal 03 一人审批。此处只是后台预览，不是该流程真实完成证据。

两端均返回工作台并验证选中态；当前进程真机 4617、M3 20239，可用日志中 FATAL EXCEPTION、Unhandled Exception、RenderFlex overflowed 各 0。

## 线上配置与验收边界

`inspect-desktop-oa-uat.ps1 -InspectFormSchemas` 新增只读字段元数据检查：只取已登录 test01 的 OA bootstrap，输出模板 ID/版本、字段 ID/标签/type/readOnly/required，不输出原始配置、默认值、业务正文或凭据。初次取了错误属性 templates，发现空结果后按模型确认实际协议为 approvalTemplates，已修正并重新查询。

[当前配置证据](../test/evidence/oa-readonly-731/live-schema-metadata.json)：GET 200，test01 可见 9 个模板，均无显式 `readOnly=true` 字段。计算字段仍可由既有 calculation/duration 配置隐式只读。**因此本轮设备操作证明普通表单未回归，不冒充线上只读选择器已被真实触发**；10 类显式只读差异由受控 Widget 测试证明，未为取证篡改正式模板。

未完成：完整高级 OA 流转与跨端通知、服务器字段权限验证、新版桌面入站同步问题与 Push Gateway 契约、长时性能等。附件仍保留原有图片预览/系统打开策略，不重新引入已暂停的内置 Office 引擎。
