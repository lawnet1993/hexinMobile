# 805 · 真机 OA 技术标识展示修复

日期：2026-09-08（Asia/Shanghai）

## 问题

realme 真机打开真实待办“2026-09-08 缺上班卡补卡”时，“申请内容”把后台考勤异常记录的 UUID 当成业务值展示在“考勤异常”一行。该值是补卡流程用于关联原始异常的内部引用，不是用户可读表单内容。

## 修复

- `attendance.punch_correction` 详情不再展示 `exceptionId` / `attendanceExceptionId` 内部引用字段。
- 继续展示用户需要核对的“补卡时间”和“补卡原因”。
- 同时遵循表单快照中的 `hidden: true` 与 `visible: false`，避免后台明确隐藏的字段在移动端重新暴露。
- 审批路径不再把登录账号夹在人员姓名与部门之间；改为紧凑的“姓名 · 部门”。当前成员接口没有下发岗位字段，因此移动端没有猜测或伪造岗位。
- “转交/加签”成员选择器同步隐藏登录账号，搜索提示收敛为“搜索姓名或部门”；内部仍可用账号检索，不影响既有查找能力。
- 没有修改、提交或处理这条已有审批数据。

## 真机结果

- 修复前：申请内容显示“考勤异常”及完整 UUID。
- 修复后：UUID 和“考勤异常”技术行均消失；仍显示“补卡时间 2026-09-08 09:00”和“补卡原因 忘记打卡”。
- `test01`、`lubing002`、`lubing` 等登录账号从审批路径消失，姓名、真实头像、部门、节点状态和完成时间继续展示。
- 真机打开“更多 → 转交”后，抽屉仅展示头像、姓名和部门，未显示 `test02` / `test03` 等登录账号；本轮未选择人员、未提交转交。
- 审批进度、处理记录、更多、驳回和同意按钮仍正常显示。

## 验证

- 新增专项 Widget 用例：通过。
- OA 页面测试：96/96 通过。
- 完整 Flutter 测试：1407/1407 通过。
- `flutter analyze`：0 issue。
- Android Profile APK：85,792,566 bytes。
- SHA-256：`E52BE7803A5C239468BB20169FF8C27A0F256442538D3DA7B00E4765A35A60C6`。

## 证据

- [修复前真机截图](../test/evidence/real-device-main-pages-20260908/oa-current-detail.png)
- [修复后真机截图](../test/evidence/real-device-main-pages-20260908/oa-detail-no-internal-id.png)
- [审批路径隐藏登录账号](../test/evidence/real-device-main-pages-20260908/oa-detail-no-login-accounts.png)
- [转交成员选择器隐藏登录账号](../test/evidence/real-device-main-pages-20260908/oa-transfer-picker-no-accounts.png)

## 边界

- 本轮只修复可确认的内部引用泄漏，没有猜测或替换其他合法业务编号。
- 若服务端希望详情展示异常类型、日期或班次，应在表单数据中下发 `${fieldId}__display`，移动端会优先展示该可读值。
