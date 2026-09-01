# 576 移动端输入密度与 IM 抽屉验收

## 结论

本轮通过。通用单行编辑输入框由 Material 默认的 48dp 收紧为 36dp，不再依赖外层主题才能保持移动端密度。根据真机首轮视觉反馈，编辑抽屉又去除了强蓝色描边，改为浅灰无边框输入区，标题与操作对象分成主副两级，取消/保存紧凑右对齐。通讯录好友操作、备注编辑、好友申请问候语、消息编辑、已读回执、群名称/公告编辑及确认操作统一使用底部抽屉，不再使用居中对话框或悬浮菜单。

## 实现与边界

- 新增可复用的紧凑文本输入抽屉：单行 36dp，多行保留自适应高度，错误文字在输入框下方独立展示，避免将 36dp 控件再次撑高。
- 好友操作替换为底部动作抽屉，“发消息”和“修改备注”保持为独立操作，没有混入群聊语义。
- 消息已读列表改为最高占屏 45% 的可滚动抽屉，保留真实已读人数、成员和时间。
- 图片查看仍保留全屏预览；这是媒体沉浸式交互，不属于应改为底部抽屉的表单操作。

## 真机证据

- 设备：realme RMX3366，Android 14，1080×2400。
- 通讯录首屏：[576-contacts.png](device-acceptance/576-contacts.png)
- 好友列表：[576-friends.png](device-acceptance/576-friends.png)
- 好友操作抽屉：[576-friend-actions-sheet.png](device-acceptance/576-friend-actions-sheet.png)
- 好友备注输入抽屉终版：[576-remark-input-redesign.png](device-acceptance/576-remark-input-redesign.png)
- UI 树：[576-friend-actions-sheet.xml](device-acceptance/576-friend-actions-sheet.xml)、[576-remark-input-redesign.xml](device-acceptance/576-remark-input-redesign.xml)

真机 UI 树证明通讯录搜索框高 102px（34dp），备注单行输入框高 108px（36dp）。本轮只打开动作抽屉和备注编辑界面，然后点击“取消”；未输入、保存、发消息或修改线上数据。

## 回归

- `flutter analyze`：0 问题。
- 通讯录与 OA 密度专项：51/51 通过。
- 完整自动化：204/204 通过。
- Profile APK SHA-256：`8EBF4A8F329623A90D097F0DB7CD44931EF12B63C64587534BA93EF915675A0B`，真机覆盖安装成功。

## 未执行

- 未点击备注保存，未修改好友数据。
- 未在真实消息上执行“编辑消息”，避免修改已有会话内容；抽屉组件和页面编译已由自动化与全量回归覆盖。
- 已读回执仅做代码、编译和回归核对；当前未找到不需要修改业务数据且可显示已读人员的现有消息。
