# 575 动态表单数据边界与待办密度验收

## 结论

本轮通过。移动端继续直接解释后台可视化表单的 schema；`calculation`、`readOnly`、`unit` 和时长配置只控制控件行为、单位与说明，不作为业务值展示。待办页顶部改为可横向滑动的紧凑分类，搜索类输入统一收至 34dp，普通单行输入沿用约 36dp 的全局规格，数字徽标固定为 16dp，不再被系统字体缩放撑高。

## 修复内容

- 审批详情的 schema 字段和值分离：配置对象或序列化的“自动计算，只读，单位…”不会进入申请信息正文；真实表单数据仍正常显示。
- 发起页兼容旧草稿、再次发起和旧接口中被错误保存为字符串的配置描述，渲染前剔除，不回填只读输入框。
- 待办六分类改为自然宽度横向滑动，不再把文字和角标压进同一行；1.3 倍字体下无溢出。
- 搜索与筛选合并为 34dp 工具行，移除输入框描边；空状态上移并减小图标层级。
- 通用普通输入框减少上下内边距和前后图标占位；消息、通讯录、登录、全部应用等设计基线同步复核。

## 真机证据

- 设备：realme RMX3366，Android 14，1080×2400。
- 待办首屏：[575-todos-compact-final.png](device-acceptance/575-todos-compact-final.png)
- 待办横滑终态：[575-todos-verified.png](device-acceptance/575-todos-verified.png)
- 待办 UI 树：[575-todos-verified.xml](device-acceptance/575-todos-verified.xml)
- 后台动态请假表单：[575-dynamic-form-verified.png](device-acceptance/575-dynamic-form-verified.png)
- 动态表单 UI 树：[575-dynamic-form-verified.xml](device-acceptance/575-dynamic-form-verified.xml)

真机只读打开既有请假草稿。页面显示“请假天数”和“根据起止时间自动计算自然日”，UI 树不存在“自动计算，只读，单位天”或独立“单位天”配置文本；未填写字段、删除附件、保存草稿或提交申请。待办横滑后“草稿箱 1 / 待同步 7”均完整可见，计数为小型圆角徽标；关键崩溃、ANR、Flutter 布局异常匹配 0 条。

## 回归

- `flutter analyze`：0 问题。
- OA 与消息专项：42/42 通过。
- 完整自动化：204/204 通过。
- 12 张设计 Golden 已按本轮明确的紧凑输入规格更新并再次通过。
- Profile APK SHA-256：`E9E6597ADB244F7ADDAB6C34214A8EF1243A29B76E9702FAF1A176EAB3B53C77`，真机覆盖安装成功。

## 未执行

- 未提交真实审批或修改线上表单数据；本轮目标是只读核对后台 schema 渲染与页面密度。
- 未处理现有 7 条待同步记录和 1 条草稿，避免改变测试环境既有数据。
