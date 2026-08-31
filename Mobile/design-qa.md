# 移动端设计 QA

## 对照基准

- 桌面端信息结构与 OA/IM 真实功能范围。
- 用户确认的移动端信息密度参考：[59-user-mobile-density-reference.png](docs/device-acceptance/evidence/59-user-mobile-density-reference.png)。
- 当前实现：[60-all-apps-density-20260831.png](docs/device-acceptance/evidence/60-all-apps-density-20260831.png)。
- 全视图合并对照：[61-all-apps-reference-comparison-20260831.png](docs/device-acceptance/evidence/61-all-apps-reference-comparison-20260831.png)。
- 应用网格局部对照：[62-app-grid-focused-comparison-20260831.png](docs/device-acceptance/evidence/62-app-grid-focused-comparison-20260831.png)。

## 本轮状态与尺寸

- 页面状态：工作台进入“全部应用”，服务端目录使用真实可路由入口；搜索空结果也完成运行验证。
- 模拟器：Android 16 API 36，物理视口 1080 × 2400，density 420（约 2.625），截图未经缩放保存。
- 参考图：856 × 1836；它是首页方向稿，不是“全部应用”同状态页面，因此只用于五列网格、信息密度与标签尺寸的局部对照，不据此要求复制渐变图标或首页结构。
- Golden：390 × 844 CSS 逻辑视口，devicePixelRatio 2；`03-all-apps.png` 已按本轮实现更新并重新通过。

## 五项视觉检查

- 字体与层级：沿用项目中文字体栈；页面标题、14.5px 分类标题和 11.5px 应用标签层级清楚，无换行、裁切或过重说明文字。
- 间距与节奏：页面左右 12dp，搜索框 38dp，区块间距 6dp，分类标题 28dp，应用网格固定 52dp；单分类区块测试约束不超过 84dp。
- 色彩与令牌：继续使用现有 `AppColors`、主题 Surface 和语义图标色，没有引入新的渐变、阴影或边框体系。
- 图标与资源：使用现有 Material/TDesign 风格图标映射，并优先渲染服务端 `iconDataUrl`；没有使用字符、Emoji 或自绘图形替代 UI 图标。
- 文案与内容：应用名称、分类和路由均来自真实目录或既有内置能力；搜索时不残留“我的常用”，无结果只显示“暂无匹配应用”。

## Findings

- [已修复 P2] 单入口分类形成多张大空白卡片。
  - 位置：全部应用分类区。
  - 修复：把分类整合到一个无边框 Surface，保留分类与五列网格，压缩标题、网格和区块间距。
  - 复核：同屏可看到考勤、费用、审批、协作和安全；没有横向滚动或底部控件遮挡。
- [已修复 P2] 搜索后常用区仍显示无关入口。
  - 位置：全部应用搜索。
  - 修复：输入搜索词后隐藏常用区，只显示真实匹配分类；零匹配进入明确紧凑空态。
  - 复核：Widget 测试和模拟器输入 `1` 的真实空结果均通过。
- [接受的差异 P3] 参考方向稿使用彩色渐变方形图标，当前实现继续使用桌面端语义色和 TDesign 风格线性图标。
  - 原因：用户后续明确要求以桌面端为功能基准并采用 TDesign Flutter；不复制方向稿中未对应真实应用的数据和视觉装饰。

## 比较历史

1. 初始实现：每个分类独立卡片，单入口也占据完整块高，页面需要更多滚动。
2. 第一次修正：分类标题 38→32dp、网格改为固定 62dp，仍存在重复卡片造成的视觉松散。
3. 最终修正：分类标题 28dp、网格 52dp、区块 6dp，并将所有业务分类合并为一个无边框分组面；新增搜索过滤与空态测试。

## 交互与稳定性

- 已实际操作：工作台→全部应用、应用入口返回、搜索聚焦、输入与空结果。
- 自动化覆盖：分类区高度、真实路由压栈/返回、搜索过滤和空结果、Golden 基线。
- 当前页面未观察到 Flutter 异常、溢出、裁切或不可点击入口。

## 后续验收边界

- 本轮页面设计 QA 已通过；它不替代真实账号下的服务端目录、权限和路由正向验收。
- 物理真机当前未被 ADB 识别，真机验收仍属于活动目标的未完成项。

## 2026-08-31 审批详情与个人页复核

- 调整前审批详情：[72-audit-approval-detail-20260831.png](docs/device-acceptance/evidence/72-audit-approval-detail-20260831.png)。
- 调整后审批详情：[76-approval-detail-compact-20260831.png](docs/device-acceptance/evidence/76-approval-detail-compact-20260831.png)。
- 同状态合并对照：[77-approval-detail-before-after-20260831.png](docs/device-acceptance/evidence/77-approval-detail-before-after-20260831.png)。
- 个人页合并对照：[78-profile-before-after-20260831.png](docs/device-acceptance/evidence/78-profile-before-after-20260831.png)。
- 视口与状态：两轮均为 Android 16 模拟器、1080 × 2400、density 420；同一“请假审批”申请、同一待处理节点和同一底部操作状态。

### Findings

- [已修复 P2] 审批详情首屏信息密度过低。
  - 证据：调整前首屏在第二个审批节点处截断，处理记录不可见；调整后同一视口完整显示表单、附件、两个审批节点、处理记录和固定操作栏。
  - 修复：申请人头像 29→24dp、章节标题 18→16dp、字段行最小高度 50→44dp、流程头像 20→17dp、底部按钮 42dp，并同步压缩区块间距。
- [已修复 P2] 个人页标题下重复解释页面用途。
  - 证据：调整前“我的”下方再次显示“账户、安全与客户端设置”；调整后直接进入用户资料，列表里的真实状态说明继续保留。
- [接受的差异 P3] 审批详情保留细分字段分隔线。
  - 原因：这些线用于区分动态表单字段，不是用户此前指出的通讯录列表黑线；颜色继续使用主题弱边框。

### 五项视觉检查

- 字体：标题、字段、流程节点和时间层级仍清晰，长事由没有裁切。
- 间距：同一视口的信息量明显提升，底部操作栏没有遮挡处理记录。
- 色彩：状态蓝、通过绿、驳回红继续使用原有语义色。
- 图标：附件、流程状态和审批动作均使用项目现有图标库，没有新增自绘资产。
- 文案：未添加新说明，移除了个人页重复说明；桌面端字段、附件和流程名称全部保留。

### 交互与稳定性

- 模拟器实际完成：工作台→待办→审批详情、返回→个人页→账户与安全。
- 自动化新增约束：申请人头像 24dp，驳回/同意按钮 42dp；高级操作菜单原有转交、加签、退回、催办和撤回仍全部可见。
- 页面热重载、路由切换和截图期间未观察到 Flutter 异常、溢出或裁切。

## 2026-08-31 通知与群聊详情复核

- 通知中心调整前：[81-audit-notifications-20260831.png](docs/device-acceptance/evidence/81-audit-notifications-20260831.png)。
- 通知中心调整后：[86-notifications-compact-20260831.png](docs/device-acceptance/evidence/86-notifications-compact-20260831.png)。
- 群聊详情调整前：[84-audit-group-detail-20260831.png](docs/device-acceptance/evidence/84-audit-group-detail-20260831.png)。
- 群聊详情调整后：[87-group-detail-compact-20260831.png](docs/device-acceptance/evidence/87-group-detail-compact-20260831.png)。
- 消息通知设置调整后：[88-message-settings-compact-20260831.png](docs/device-acceptance/evidence/88-message-settings-compact-20260831.png)。
- 单聊资料调整后：[90-direct-detail-compact-final-20260831.png](docs/device-acceptance/evidence/90-direct-detail-compact-final-20260831.png)。

### Findings

- [已修复 P2] 通知类型与未读状态占用两排筛选区。
  - 修复：在不改变“业务 / 公告 / 好友”和“全部 / 未读”逻辑的前提下改为单排，筛选区高度约束不超过 52dp。
- [已修复 P2] 群聊详情头图、成员区、功能行和开关偏大。
  - 修复：群头图 58→48dp、成员头像 22→20dp、成员格高度 82→74dp、操作行最小高度 54→48dp、通用紧凑开关 40×28→36×24dp。
  - 结果：同一首屏从只显示群权限，提升到同时显示置顶和免打扰入口；群聊专属功能保留，单聊页没有引入群功能。
- [已修复 P2] 单聊资料页个人头部和账号字段行过高。
  - 修复：头像 32→26dp、标题 20→18dp、资料行 52→48dp，开关与群聊详情共用同一紧凑尺寸。
  - 结果：账号、部门、发起群聊、会话设置和删除单聊在首屏完整显示。
- [已修复 P3] 消息通知页在“当前设备未注册”状态重复解释同步和 Android 系统行为。
  - 修复：只保留当前真实状态，不再添加额外说明。

### 交互与稳定性

- 模拟器实际完成：工作台→通知、消息→群聊→群聊详情、我的→消息通知。
- 自动化新增约束：通知筛选区不超过 52dp，通用紧凑开关为 36 × 24dp。
- Golden：`11-direct-detail.png` 和 `12-group-detail.png` 已更新到本轮运行态并通过重放。
- 完整验证：`flutter analyze` 无问题，`flutter test` 107/107 通过；测试临时目录已切换到 E 盘，避免 C 盘空间不足造成假失败。
- 同状态前后对比未发现文字裁切、控件重叠、路由丢失或群聊/单聊边界回归。

## 2026-08-31 通讯录、待办与设备设置复核

- 通讯录当前态：[92-audit-contacts-20260831.png](docs/device-acceptance/evidence/92-audit-contacts-20260831.png)。
- 单聊身份修复后：[95-contact-chat-identity-fixed-final-20260831.png](docs/device-acceptance/evidence/95-contact-chat-identity-fixed-final-20260831.png)。
- 待办列表与筛选：[96-audit-todos-current-20260831.png](docs/device-acceptance/evidence/96-audit-todos-current-20260831.png)、[97-audit-todo-filter-20260831.png](docs/device-acceptance/evidence/97-audit-todo-filter-20260831.png)。
- 登录设备调整前后：[98-audit-login-devices-20260831.png](docs/device-acceptance/evidence/98-audit-login-devices-20260831.png)、[99-login-devices-compact-20260831.png](docs/device-acceptance/evidence/99-login-devices-compact-20260831.png)。
- 网络与安全调整前后：[100-audit-network-security-20260831.png](docs/device-acceptance/evidence/100-audit-network-security-20260831.png)、[102-network-security-compact-final-20260831.png](docs/device-acceptance/evidence/102-network-security-compact-final-20260831.png)。
- 退出演示模式后的真实登录态：[103-normal-mode-login-20260831.png](docs/device-acceptance/evidence/103-normal-mode-login-20260831.png)。

### Findings

- [已修复 P1] 从通讯录点击“冯逸”后，新建单聊错误显示为“会话 / 唐泽”。
  - 根因：演示数据返回了新会话 ID，但聊天页和成员消息预览未按 ID 解析被选中的联系人。
  - 修复：新建单聊按 `demo-direct-{memberId}` 恢复真实联系人标题、账号、在线态、成员与消息发送人；不影响群聊路径。
  - 模拟器复验：冯逸页头显示“深圳运营部 · term.sz02 · 在线”，消息发送人与内容一致。
- [已通过] 通讯录在线/离线为每个人的独立真实状态，列表无黑色分隔线，部门与人员行保持紧凑。
- [已通过] 待办六个状态标签同屏完整，搜索、筛选、条目和底部筛选面板尺寸符合移动端，本轮无需修改。
- [已修复 P2] 登录设备空态按钮和卡片偏大，下方存在重复管理说明。
  - 修复：按钮高度 40dp，图标 18dp，空态内边距 12dp；登录设备行高下限 54dp，移除重复说明。
- [已修复 P2] 网络与安全页状态卡和说明文字过大、过多。
  - 修复：状态图标 38dp，信息行纵向间距 5dp，检测/重试按钮改为紧凑尺寸；移除“系统自动维护”通用说明。
  - 真实错误没有隐藏：“当前安装包未包含受信任的 mihomo 内核”收入连接状态内，只显示一次；空的核心版本统一显示 `-`。

### 交互与稳定性

- 模拟器实际完成：通讯录→冯逸单聊、待办→筛选、我的→登录设备、我的→网络与安全。
- 演示新单聊身份自动化测试已新增；登录设备相关页面测试 9/9 通过；网络与安全 Golden 已更新并通过。
- 完整验证：`flutter analyze` 无问题，`flutter test` 108/108 通过。含特殊字符的原始工作路径会触发 Flutter Analysis Server LSP 输入截断，已使用同一工作区的短路径 `C:\codex-work\hexing-client\Mobile` 重跑并通过，不是代码分析错误。
- 当前仍只识别到 Android 模拟器；物理真机与真实账号流程不在本轮“已通过”范围内。

## 2026-08-31 工作台与请假申请流程复核

- 工作台当前态：[104-current-workbench-audit-20260831.png](docs/device-acceptance/evidence/104-current-workbench-audit-20260831.png)。
- 请假表单调整前后：[105-current-approval-form-audit-20260831.png](docs/device-acceptance/evidence/105-current-approval-form-audit-20260831.png)、[106-approval-form-compact-20260831.png](docs/device-acceptance/evidence/106-approval-form-compact-20260831.png)。
- 中文日期选择器：[108-date-picker-zh-20260831.png](docs/device-acceptance/evidence/108-date-picker-zh-20260831.png)。
- 工作台标签修复：[110-workbench-label-fixed-20260831.png](docs/device-acceptance/evidence/110-workbench-label-fixed-20260831.png)。
- 登录设备入口路由：[112-login-devices-route-final-20260831.png](docs/device-acceptance/evidence/112-login-devices-route-final-20260831.png)。
- 草稿保存与恢复：[117-draft-save-success-20260831.png](docs/device-acceptance/evidence/117-draft-save-success-20260831.png)、[118-draft-reopened-success-20260831.png](docs/device-acceptance/evidence/118-draft-reopened-success-20260831.png)。
- 流程预览调整前后：[120-workflow-preview-open-20260831.png](docs/device-acceptance/evidence/120-workflow-preview-open-20260831.png)、[122-workflow-preview-compact-final-20260831.png](docs/device-acceptance/evidence/122-workflow-preview-compact-final-20260831.png)。
- 日期时间友好格式：[123-approval-datetime-formatted-20260831.png](docs/device-acceptance/evidence/123-approval-datetime-formatted-20260831.png)。
- 退出演示模式后的最终真实登录态：[124-normal-mode-final-20260831.png](docs/device-acceptance/evidence/124-normal-mode-final-20260831.png)。

### Findings

- [已修复 P2] 请假表单单个控件尺寸尚可，但字段间距、标题计数器、流程按钮和底部操作栏叠加后导致信息密度过低。
  - 修复：表单内边距 12dp、字段间距 10dp、通用字段视觉高度约 38dp、流程按钮 40dp、草稿/提交按钮 42dp；移除始终占一行的字符计数器，多行事由默认 2 行。
  - 结果：表单主卡片在同一模拟器视口减少约 109dp，字段、流程入口和底部操作仍完整可用。
- [已修复 P1] 工作台将“审批中心”同时删除“审批”后显示成语义不明的“中心”。
  - 修复：只对以“申请”结尾的快捷入口做短标签，“审批中心”保留完整名称。
- [已修复 P1] “登录设备”和“网络诊断”原本都跳转网络与安全页。
  - 修复：登录设备指向 `/login-devices`，网络诊断保留 `/network-security`；模拟器完整重启后已验证两个入口不再混用。
- [已修复 P2] 日期/时间选择器显示英文星期和 `Cancel/OK`，已加入 Flutter 中文本地化配置，运行态显示“选择日期 / 取消 / 确定”。
- [已修复 P2] 字段保存 ISO 时间后直接向用户显示 `2026-08-30T19:35:00.000`。
  - 修复：内部仍保留 ISO 数据传输，页面统一显示 `yyyy/MM/dd HH:mm`。
- [已修复 P1] 演示自动登录只更新了界面认证状态，OA/IM 本地存储仍读取不到会话，导致保存草稿报“登录状态已失效”。
  - 修复：演示模式的 OA/IM 仓库共用同一演示会话，草稿可保存并在退出、重新进入后恢复。
- [已修复 P2] 只有 2 个节点时，流程预览仍强制占用 72% 屏高，大量空白。
  - 修复：预览弹层按节点数量自适应高度，超过 72% 屏高才滚动；演示模式提供可解析的负责人与人事复核节点，用于真实交互验收。

### 交互与稳定性

- 模拟器实际完成：工作台→登录设备、工作台→请假申请→类型选择→日期时间选择→草稿保存/重新打开→流程预览。
- 请假表单尺寸约束、登录设备/网络路由分离和 OA/IM 本地存储均已纳入自动化回归。
- 完整验证：`flutter analyze` 无问题，`flutter test` 109/109 通过；工作台 Golden 已更新并重放通过。
- 结论仅覆盖模拟器与演示数据；真实终端账号、真实审批节点与物理真机仍需单独验收。

## 2026-08-31 桌面端聊天资源与移动端会话详情对齐

- 群聊详情与群内审批入口：[125-group-detail-resource-alignment.png](docs/device-acceptance/evidence/125-group-detail-resource-alignment.png)。
- 单聊聊天资源标签：[126-direct-chat-resource-tabs.png](docs/device-acceptance/evidence/126-direct-chat-resource-tabs.png)。
- 会话文件页：[127-direct-chat-files.png](docs/device-acceptance/evidence/127-direct-chat-files.png)。
- 共同任务页：[128-direct-chat-tasks.png](docs/device-acceptance/evidence/128-direct-chat-tasks.png)。
- 单聊详情资源入口：[129-direct-detail-resources.png](docs/device-acceptance/evidence/129-direct-detail-resources.png)。
- 恢复真实登录模式：[130-normal-mode-final-20260831.png](docs/device-acceptance/evidence/130-normal-mode-final-20260831.png)。

### Findings

- [已修复 P1] 移动端聊天页缺少桌面端已有的“聊天 / 文件 / 任务”资源切换。
  - 修复：单聊显示聊天、文件、任务；群聊只显示聊天、文件，避免把单聊共同任务混入群聊。
  - 文件和任务计数来自当前会话真实数据；文件页不显示消息输入栏，任务页提供 34dp 新建入口。
- [已修复 P1] 移动端会话详情缺少共享文件、关联审批、共同任务和群内审批入口。
  - 修复：单聊详情增加共享文件、关联审批、共同任务三条紧凑资源行；群聊详情增加群内审批行；点击资源后返回当前聊天并选中对应标签。
- [已修复 P1] 首次关闭“新建共同任务”弹层时触发 `TextEditingController was used after being disposed` 和 `_dependents.isEmpty` 断言。
  - 根因：弹层退出动画结束前释放了局部输入控制器。
  - 修复：改为无控制器的短生命周期输入状态；完整重启后重复打开、取消，页面稳定且日志无新异常。
- [已修复 P2] 从会话详情通过全局路由打开文件页后，聊天页丢失返回箭头。
  - 修复：详情通过结果返回原聊天页并切换资源标签，保留消息列表返回栈。

### 交互与稳定性

- 当前运行中的 Windows 桌面端已真实核对：单聊详情包含共享文件、关联审批、共同任务；群聊详情包含群成员、群公告、群内审批和会话设置；发起会话明确区分单聊与建群。
- 模拟器实际完成：消息→单聊→聊天/文件/任务→新建共同任务→取消→个人资料→共享文件→返回消息列表；消息→群聊→群聊详情。
- 组件约束：资源标签栏 38dp，新建任务按钮 34dp，弹层操作按钮 40dp；群聊没有任务标签，单聊没有群管理操作。
- Golden 已更新：`05-chat.png`、`11-direct-detail.png`、`12-group-detail.png`；当前 `flutter analyze` 无问题，`flutter test` 110/110 通过。
- 当前设备列表仍只有 `emulator-5554`，没有识别到物理 Android 真机；真实账号、真实文件下载、真实共同任务创建和审批联动仍待真机连接后验收。

final result: simulator passed; physical device pending

## 2026-08-31 群发助手、收藏、群管理与通知已读复核

- 群发助手接收人全选：[131-message-assistant-select-all.png](docs/device-acceptance/evidence/131-message-assistant-select-all.png)。
- 群管理员与真实在线点：[132-group-management-managers.png](docs/device-acceptance/evidence/132-group-management-managers.png)。
- 通知打开后的已读状态：[133-notification-read-state.png](docs/device-acceptance/evidence/133-notification-read-state.png)。

### Findings

- [已修复 P1] 消息首页缺少桌面端“我的收藏”入口，批量发送仍使用“消息助手”和机器人图标。
  - 修复：增加全局收藏入口；批量发送统一为“群发助手”和广播图标，不与智能机器人能力混淆。
- [已修复 P1] 群发助手缺少接收人搜索、全选/清空、头像和在线状态。
  - 修复：支持按姓名、账号和部门搜索，列表先显示在线联系人；头像使用真实 `isOnline` 状态点，复选框、搜索框和提交按钮保持移动端紧凑尺寸。
- [已修复 P1] 收藏列表只能取消收藏，无法返回原会话。
  - 修复：列表行和“打开会话”按钮均按消息真实 `conversationId` 打开对应单聊或群聊；不把群消息定位到单聊。
- [已修复 P1] 演示模式群管理和通知已读仍访问远端或不更新状态，无法完成真实交互验收。
  - 修复：演示数据覆盖禁言、入群申请、管理员、操作记录和高级权限；打开通知后同步更新未读点、未读计数和列表背景。
- [已修复 P2] 群管理分隔线和操作按钮视觉偏重。
  - 修复：列表统一使用浅色边界；解除、拒绝和通过按钮压缩；管理员页显示真实在线点，五个页签在 390dp 宽度完整显示。
- [已通过] 待办继续与桌面端保持六个视图：待处理、我发起的、抄送、已完成、草稿、待同步；搜索、筛选和列表密度在模拟器无需再次修改。

### 交互与稳定性

- 模拟器实际完成：消息→群发助手→全选；消息→我的收藏→打开原群聊；群聊详情→群管理→禁言/入群/管理员/记录/高级；工作台→通知→审批详情→返回并核对已读状态。
- 新增自动化覆盖群发搜索、全选、清空、40dp 提交按钮、收藏打开原会话，以及演示模式的解除禁言、处理入群申请、通知已读和群发取消状态；消息页 Golden 已按新增收藏/群发入口更新。
- 完整验证：`flutter analyze` 无问题，`flutter test` 113/113 通过；演示交互状态专项测试在 `DEMO_MODE=true` 下 1/1 通过；模拟器未出现 Flutter 异常、溢出或路由丢失。
- 当前 Windows 桌面端被 v1.0.79 强制更新弹窗遮挡，本轮未执行未经确认的下载安装；辅助页面以同版本桌面端源码和此前运行证据为基准核对。
- 当前设备列表仍只有 `emulator-5554`；物理真机、真实账号群发、真实收藏定位、真实群管理权限和真实通知持久化仍待真机连接后验收。
- 已恢复普通登录模式并保留运行会话；最终登录页证据：[134-normal-mode-final-20260831.png](docs/device-acceptance/evidence/134-normal-mode-final-20260831.png)。

## 2026-08-31 个人待办与审批主页面功能对齐

- 对齐前个人待办缺失：[135-todos-missing-personal-items.png](docs/device-acceptance/evidence/135-todos-missing-personal-items.png)。
- 合并展示后的待处理页：[136-todos-personal-items-aligned.png](docs/device-acceptance/evidence/136-todos-personal-items-aligned.png)。
- 紧凑新建弹层：[137-todo-create-sheet.png](docs/device-acceptance/evidence/137-todo-create-sheet.png)。
- 模拟器新建成功：[140-todo-created-after-fix.png](docs/device-acceptance/evidence/140-todo-created-after-fix.png)。
- 完成后从待处理移除：[141-todo-completed-removed-from-pending.png](docs/device-acceptance/evidence/141-todo-completed-removed-from-pending.png)。
- 已完成页保留原待办：[142-todo-visible-in-completed.png](docs/device-acceptance/evidence/142-todo-visible-in-completed.png)。
- 新建待办/发起审批双入口：[143-todo-create-actions.png](docs/device-acceptance/evidence/143-todo-create-actions.png)。
- 事项类型筛选：[144-todo-type-filter.png](docs/device-acceptance/evidence/144-todo-type-filter.png)、[146-todo-personal-type-filter-applied.png](docs/device-acceptance/evidence/146-todo-personal-type-filter-applied.png)。

### Findings

- [已修复 P1] 工作台“今日日程”显示个人待办，但进入底部“待办”后只显示审批，和桌面端统一待办模型不一致。
  - 修复：待处理、我发起的、已完成按桌面端规则合并个人待办与审批；抄送仍只处理审批，草稿和待同步逻辑不变。
  - 状态：待处理角标同时统计未完成个人待办和可操作审批；个人待办支持搜索、时间/状态筛选，审批应用筛选时不会混入个人待办。
- [已修复 P1] 移动端待办主页面缺少桌面端已有的个人待办创建和完成切换。
  - 修复：右上角增加新建入口，弹层只保留标题与普通/高/紧急优先级，输入框 44dp、提交按钮 40dp；列表使用紧凑复选框和真实优先级语义色。
  - 交互：新建后立即进入待处理；勾选后从待处理消失并出现在已完成，恢复操作沿用同一状态接口。
- [已修复 P2] 合并个人待办后仍缺少桌面端的事项类型筛选和发起审批入口。
  - 修复：筛选面板增加全部事项/个人待办/审批；单个加号以紧凑菜单承载新建待办和发起审批，不在标题栏堆叠两个大按钮。
  - 复核：已完成页选择个人待办后只保留真实个人待办，筛选角标显示 1；发起审批进入现有真实应用目录，不新增重复页面。
- [已修复 P0] 首次真实提交新建弹层时发生 `TextEditingController was used after being disposed`，随后触发 `_dependents.isEmpty` 断言并进入红屏。
  - 证据：[138-todo-create-crash-caught.png](docs/device-acceptance/evidence/138-todo-create-crash-caught.png)。
  - 根因：底部弹层退场动画结束前通过 `whenComplete` 释放输入控制器。
  - 修复：改为无控制器的短生命周期输入状态；完整热重启后重复新建、关闭、完成切换均未再出现异常。

### 交互与稳定性

- 模拟器真实完成：待办→新建→输入标题→选择高优先级→创建→勾选完成→已完成页核对；运行数据确实发生变化，不是静态样式演示。
- 模型补齐 `createdAt` / `updatedAt`，移动端可以按桌面端规则排序和执行时间筛选；演示仓库的创建与更新会修改同一运行态数据源。
- 新增自动化覆盖个人待办与审批的合并展示，以及演示模式创建/完成状态变更；`06-todos.png` 已更新为新的统一列表基线。
- 完整验证：`flutter analyze` 无问题，`flutter test` 114/114 通过；`DEMO_MODE=true` 交互状态专项测试 1/1 通过。
- 当前设备列表仍只有 `emulator-5554`；物理真机和真实账号个人待办接口仍属于活动目标的未完成验收项。
- 演示验收结束后已恢复普通登录模式并重新安装运行，最终状态：[147-normal-mode-final-20260831.png](docs/device-acceptance/evidence/147-normal-mode-final-20260831.png)。

## 2026-08-31 弹层稳定性、好友状态与日程密度复核

- 好友模式与真实在线点：[150-contact-friends-demo-aligned.png](docs/device-acceptance/evidence/150-contact-friends-demo-aligned.png)。
- 好友专属操作菜单：[151-contact-action-menu.png](docs/device-acceptance/evidence/151-contact-action-menu.png)。
- 备注弹层与稳定退出：[152-contact-remark-dialog.png](docs/device-acceptance/evidence/152-contact-remark-dialog.png)、[153-contact-remark-cancel-stable.png](docs/device-acceptance/evidence/153-contact-remark-cancel-stable.png)。
- 备注保存与再次打开：[158-contact-remark-saved-stable.png](docs/device-acceptance/evidence/158-contact-remark-saved-stable.png)、[159-contact-remark-persisted.png](docs/device-acceptance/evidence/159-contact-remark-persisted.png)。
- 审批驳回弹层稳定退出：[156-approval-reject-sheet.png](docs/device-acceptance/evidence/156-approval-reject-sheet.png)、[157-approval-reject-cancel-stable.png](docs/device-acceptance/evidence/157-approval-reject-cancel-stable.png)。
- 日程待办紧凑连续列表：[163-schedule-compact-list.png](docs/device-acceptance/evidence/163-schedule-compact-list.png)。
- 日程编辑弹层与真实退出：[164-schedule-editor-open-final.png](docs/device-acceptance/evidence/164-schedule-editor-open-final.png)、[165-schedule-editor-cancel-stable-final.png](docs/device-acceptance/evidence/165-schedule-editor-cancel-stable-final.png)。

### Findings

- [已修复 P0] 联系人备注、好友申请、消息编辑、审批处理、审批成员选择、补卡、审批引用、群文本编辑和日程编辑等弹层仍存在与待办红屏相同的控制器提前释放风险。
  - 根因：`Navigator.pop` 完成时退场动画仍可能重建输入框，立即 `dispose` 会触发 `TextEditingController was used after being disposed`。
  - 修复：统一通过路由退场安全释放方法延迟释放弹层局部控制器；审批驳回、补卡、联系人备注和日程编辑均加入打开、取消、完全退出的自动化回归。
- [已修复 P1] 演示通讯录没有好友，无法真实验证好友备注和好友专属操作；组织、好友两种联系人语义无法在模拟器复核。
  - 修复：演示数据明确标记两名好友；好友页只显示好友，组织页仍保留全部组织成员；备注通过同一演示仓库写入并在再次打开时读取，不把群聊和单聊混用。
  - 状态：在线点继续来自联系人 `isOnline` 字段；好友标记不会伪造在线状态。
- [已修复 P2] 日程页每条待办使用独立大卡片，三条事项占用大半屏，与桌面端列表模型和移动端高信息密度要求不符。
  - 修复：改为一个容器内的 58dp 连续行，使用浅分隔线；完成、标题、单行元数据和编辑入口仍完整保留，可点击区不小于 40dp。
- [证据纠正] 旧的日程“取消稳定”截图实际只收起了系统键盘，弹层仍在，未作为通过证据。新证据按 Android 返回层级先收起键盘、再退出弹层，退出后运行日志无 Flutter 异常。

### 交互与稳定性

- 模拟器实际完成：通讯录→好友→修改备注→取消/保存→再次打开核对；待办→审批详情→驳回→取消；日程→新增→系统返回收起键盘→再次返回退出。
- 通讯录 Golden 已按预期的好友专属更多菜单更新；更新前后同视口比对，差异仅来自好友行操作图标。
- 完整验证：`flutter analyze` 无问题，`flutter test` 116/116 通过；`DEMO_MODE=true` 交互状态专项测试 1/1 通过；模拟器运行日志无 Flutter 异常。
- 当前设备列表只有 `emulator-5554`，物理 Android 真机仍未识别；真实账号在线状态、真实好友备注持久化和真实 OA 接口留在活动目标中继续验收。
- 演示验收结束后已恢复普通登录模式并保留运行会话；最终状态：[166-normal-mode-final-20260831.png](docs/device-acceptance/evidence/166-normal-mode-final-20260831.png)。

## 2026-08-31 全部应用名称、图标与信息密度对齐

- 本轮首页运行态：[167-workbench-current-audit.png](docs/device-acceptance/evidence/167-workbench-current-audit.png)。
- 调整前全部应用：[168-all-apps-current-audit.png](docs/device-acceptance/evidence/168-all-apps-current-audit.png)。
- 同轮对照页面：[169-profile-current-audit.png](docs/device-acceptance/evidence/169-profile-current-audit.png)、[170-account-security-current-audit.png](docs/device-acceptance/evidence/170-account-security-current-audit.png)、[171-todos-current-audit.png](docs/device-acceptance/evidence/171-todos-current-audit.png)、[172-approval-detail-current-audit.png](docs/device-acceptance/evidence/172-approval-detail-current-audit.png)。
- 调整后全部应用：[173-all-apps-compact-aligned.png](docs/device-acceptance/evidence/173-all-apps-compact-aligned.png)。
- 日程入口打开与返回：[174-all-apps-open-schedule.png](docs/device-acceptance/evidence/174-all-apps-open-schedule.png)、[175-all-apps-return-stable.png](docs/device-acceptance/evidence/175-all-apps-return-stable.png)。

### Findings

- [已修复 P2] 全部应用页重复展示首页已有的“我的常用”，首屏先出现一遍快捷入口，再按类别重复同一批应用。
  - 修复：全部应用只保留搜索和按服务端类别分组的完整目录；首页继续承担常用入口，不额外发明收藏逻辑。
  - 结果：首屏减少一个完整区块，同一应用只出现一次，分类目录从搜索框下方直接开始。
- [已修复 P1] 全部应用使用 `replaceAll('申请', '')` 改写服务端业务名称，导致“请假申请”“报销申请”等与桌面端和流程目录不一致。
  - 修复：目录页完整显示服务端应用名称；首页快捷区仍只对“申请”后缀做移动端短标签，两种场景不再混用。
- [已修复 P2] 全部应用使用裸线性图标，和首页 32dp 彩色图标底不一致，应用识别依赖图标线条颜色。
  - 修复：统一为 32dp、8dp 圆角的语义色图标底，内图标 20dp；仍保留服务端自定义图片和 emoji 的真实渲染路径。

### 交互、可访问性与稳定性

- 模拟器实际完成：首页→全部应用→日程→返回全部应用；分类位置和页面状态稳定，日志无 Flutter 异常。
- 应用单元高度 56dp、图标 32dp，整格仍保持大于 44dp 的可点击区域；完整业务名称同时作为 Flutter 语义节点暴露。
- 搜索过滤、无结果状态、完整业务名称、图标尺寸和应用路由均有组件回归覆盖；`03-all-apps.png` 已按同视口前后对比更新。
- 完整验证：`flutter analyze` 无问题，`flutter test` 116/116 通过；`DEMO_MODE=true` 交互状态专项测试 1/1 通过。
- 截图可验证布局、名称和点击路径，不能证明读屏顺序或动态字体放大；这些仍需物理真机和辅助功能验收。
- 演示验收结束后已恢复普通登录模式并保留运行会话；最终状态：[176-normal-mode-final-20260831.png](docs/device-acceptance/evidence/176-normal-mode-final-20260831.png)。

## 2026-08-31 审批节点人员与通知中心对齐

- 当前桌面端通知基准：[358-desktop-notifications-approval-current.png](docs/device-acceptance/evidence/358-desktop-notifications-approval-current.png)。
- 移动审批进度调整前：[359-mobile-approval-timeline-before.png](docs/device-acceptance/evidence/359-mobile-approval-timeline-before.png)。
- 移动审批进度调整后：[360-mobile-approval-timeline-directory-enriched.png](docs/device-acceptance/evidence/360-mobile-approval-timeline-directory-enriched.png)。
- 同视口前后对照：[361-mobile-approval-timeline-before-after.png](docs/device-acceptance/evidence/361-mobile-approval-timeline-before-after.png)。
- 移动通知全部/未读：[362-mobile-notification-center-desktop-aligned.png](docs/device-acceptance/evidence/362-mobile-notification-center-desktop-aligned.png)、[363-mobile-notification-unread-filter.png](docs/device-acceptance/evidence/363-mobile-notification-unread-filter.png)。

### Findings

- [已修复 P1] 审批节点只显示接口返回的处理人名称和状态，无法核对终端账号与实际部门，“当前用户”也不是可审计的真实人员信息。
  - 修复：用任务 `assigneeId` 对照 IM bootstrap 的当前成员与组织联系人，展示真实姓名、终端账号和部门；找不到成员时安全回退到任务名称，不猜测岗位或身份。
- [已修复 P2] 初版把人员、账号、部门和状态全部放在同一行，小视口 Golden 出现换行；状态移到标题行后又与外侧完成时间挤压。
  - 修复：节点标题、状态和完成时间共享同一受约束标题行，人员信息独占 12.5sp 单行，审批意见与超时信息维持原层级；390dp Golden 和 1080×2400 模拟器均无裁切、重叠或高度膨胀。
- [已通过] 通知中心继续复用桌面端合并信息流，但移动端用明确的“群聊 / 单聊”标签和不同图标保持会话边界；OA 审批仍指向审批详情，未读筛选与数量真实切换。

### 交互与稳定性

- 桌面端只读核对通知中心，没有点击未读条目、全部已读或审批操作。模拟器实际完成审批详情查看、通知中心打开和未读筛选切换，所有写操作均未触发。
- 完整验证：`flutter analyze` 0 issue，`flutter test --concurrency=1` 139/139 通过；审批详情 Golden 更新后复跑 12/12 通过。
- 普通模式 APK SHA-256 为 `B2194D78FE39CDD381816450A9B98DE0A292FF03F3EAE3DE2034B9AD5854B9DC`；覆盖安装后最终停留在无预填凭据登录页，应用进程关键崩溃 0 条。
- 当前 `adb devices -l` 仅识别 `emulator-5554`；物理真机、真实账号审批节点目录映射、真实通知读取/离线恢复仍是活动目标的未完成验收项。

## 2026-08-31 审批状态与通知连续交互复核

- 初始审批详情：[370-demo-approval-initial-detail.png](docs/device-acceptance/evidence/370-demo-approval-initial-detail.png)。
- 中间节点真实流转：[372-demo-approval-intermediate-success.png](docs/device-acceptance/evidence/372-demo-approval-intermediate-success.png)。
- 下一节点通知：[373-demo-approval-next-node-notification.png](docs/device-acceptance/evidence/373-demo-approval-next-node-notification.png)。
- 最终审批通过：[374-demo-approval-final-success.png](docs/device-acceptance/evidence/374-demo-approval-final-success.png)。
- 最终通知与工作台：[375-demo-approval-final-notification-state.png](docs/device-acceptance/evidence/375-demo-approval-final-notification-state.png)、[376-demo-approval-final-workbench.png](docs/device-acceptance/evidence/376-demo-approval-final-workbench.png)。

### Findings

- [已修复 P1] 演示模式点击审批会访问远端，导致页面只能验证文案，不能验证真实状态迁移。
  - 修复：增加两级可连续操作的演示流程，仓库在本地完成任务版本校验、当前节点完成、下一节点激活、最终状态收敛和重复提交拒绝。
- [已修复 P1] 审批节点完成后，通知缺少与当前任务一致的投影。
  - 修复：复用同一通知记录；中间节点显示下一节点待处理，最终节点显示已处理并转为已读，没有为同一事件叠加重复 OA 条目。
- [已通过] 增加财务复核后，审批时间线仍采用单列紧凑布局；状态和时间共用受约束标题行，人员账号与部门单行显示，底部操作维持 42dp。

### 交互、可访问性与稳定性

- 模拟器用真实点击连续完成两次审批。第一次 Snackbar 和语义树均为“当前节点已同意，审批继续流转”，第二次均为“审批已通过”；最终状态不再暴露同意/驳回操作。
- 通知中心回查证明 OA 条目从待处理更新为已处理，合并信息流中的群聊/单聊标签和未读状态不受影响；工作台“待我处理”由 1 变为 0。
- `flutter analyze` 0 issue，完整测试 140/140，Golden 12/12，演示状态专项 2/2；模拟器审批进程关键异常 0 条。
- 已恢复普通模式并覆盖安装，最终登录页无预填账号和密码：[378-ordinary-approval-state-restored.png](docs/device-acceptance/evidence/378-ordinary-approval-state-restored.png)。当前设备仅有模拟器，物理真机和真实账号通知持久化仍待继续验收。

## 2026-08-31 审批驳回交互复核

- 驳回弹层：[381-demo-rejection-sheet.png](docs/device-acceptance/evidence/381-demo-rejection-sheet.png)。
- 必填错误状态：[382-demo-rejection-validation.png](docs/device-acceptance/evidence/382-demo-rejection-validation.png)。
- 驳回详情终态：[383-demo-rejection-success.png](docs/device-acceptance/evidence/383-demo-rejection-success.png)。
- 工作台与通知并排状态：[386-demo-rejection-workbench-notification.png](docs/device-acceptance/evidence/386-demo-rejection-workbench-notification.png)。

### Findings

- [已通过] 驳回弹层只保留标题、原因输入、主操作和取消，输入框与按钮沿用现有移动端尺寸，没有新增解释区或放大控件。
- [已通过] 空原因错误直接显示在输入框下方，弹层不退出；用户可以在原位置补充原因后继续，不需要重新打开流程。
- [已通过] 驳回终态使用红色状态语义，当前节点保留原因，后续节点使用灰色“已取消”；节点顺序和人物信息没有被重新排版或混淆。
- [已通过] 返回工作台后待办区显示紧凑空态，通知中心仍保持 OA、群聊和单聊三类图标与标签边界。

### 交互、可访问性与稳定性

- 真实点击路径完整覆盖驳回弹层、必填错误恢复、终态详情、工作台和通知中心；语义树暴露“请填写驳回原因”“审批已驳回”“已取消”和“待我处理 0”。
- 截图可确认错误颜色、层级、点击结果和信息密度，不能代替物理真机读屏顺序、动态字体和软键盘遮挡测试。
- `flutter analyze` 0 issue，完整测试 141/141，Golden 12/12，演示状态专项 3/3；运行日志关键异常 0 条。
- 普通模式已覆盖安装并恢复到无预填登录页：[388-ordinary-rejection-regression-login.png](docs/device-acceptance/evidence/388-ordinary-rejection-regression-login.png)。物理真机和真实账号驳回通知仍待继续验收。

## 2026-08-31 审批转交移动交互复核

- 选人与必填错误：[398b-compact-member-picker.png](docs/device-acceptance/evidence/398b-compact-member-picker.png)、[400-transfer-reason-required.png](docs/device-acceptance/evidence/400-transfer-reason-required.png)。
- 转交节点与通知：[402-transfer-complete.png](docs/device-acceptance/evidence/402-transfer-complete.png)、[404-transfer-notification.png](docs/device-acceptance/evidence/404-transfer-notification.png)。
- 四步总览：[405-transfer-flow-montage.png](docs/device-acceptance/evidence/405-transfer-flow-montage.png)。

### Findings

- [已通过] “更多操作”使用单个紧凑图标入口，转交动作使用 36dp 图标容器和 64dp 单项，没有挤压同意/驳回主操作，也没有新增说明卡片。
- [已修复 P2] 固定 440dp 的选人弹层在三名成员场景留下大块空白；现按结果数量动态计算高度，搜索框、约 58dp 成员行和底部安全区完整保留。
- [已通过] 转交原因错误就地显示，输入框与确认按钮没有放大；选择叶青后时间线清晰分开原处理人与新处理人，状态分别为“已转交”和“待处理”，财务复核仍为“等待中”。
- [已通过] 当前用户失去处理权限后底部操作栏消失，工作台待办归零；通知中心只更新 OA 行，群聊和单聊边界不受影响。

### 交互、可访问性与稳定性

- 模拟器真实点击覆盖选人、空原因、补充原因、转交、返回工作台与通知中心；语义树暴露实际姓名、终端账号、部门、节点状态和“待我处理 0”。
- `flutter analyze` 0 issue，完整测试 142/142，Golden 12/12；普通模式已覆盖安装并恢复到无预填登录页：[406-ordinary-transfer-login.png](docs/device-acceptance/evidence/406-ordinary-transfer-login.png)，关键崩溃与 ANR 为 0。
- 当前只连接模拟器；物理真机的软键盘遮挡、触控热区、读屏顺序与真实服务端转交通知仍待补验。

## 2026-08-31 realme 真机头像与 IM 信息密度复核

- 真机调整前：[通讯录](docs/device-acceptance/evidence/410-real-device-contacts.png)、[群聊消息](docs/device-acceptance/evidence/412-real-device-group-chat.png)。
- 真机调整后：[通讯录](docs/device-acceptance/evidence/415-real-device-avatar-contacts-fixed.png)、[群聊消息](docs/device-acceptance/evidence/416-real-device-avatar-group-chat-fixed.png)、[前后对照](docs/device-acceptance/evidence/417-real-device-avatar-before-after.png)。

### Findings

- [已修复 P1] 用户已有真实自定义头像，但通讯录和聊天气泡只显示首字母。根因不是图片缺失或解码失败，而是页面调用没有把成员模型的 `avatarDataUrl` 交给统一头像组件。
- [已通过] 修复后真实头像保持原有 34–40dp 头像尺寸，在线绿点继续位于右下角；没有扩大成员行、搜索框、底部 Tab 或消息输入区。
- [已通过] 无头像的两个离线测试成员继续显示首字母和灰色状态点，避免使用伪造图片；群聊头像和用户头像语义继续分开。
- [已通过] realme 480dpi 真机上，工作台、消息、通讯录和群聊没有文字裁切、异常黑线或触控控件过大；群聊与单聊标签、在线/离线状态保持真实数据边界。

### 验证

- `flutter analyze` 0 issue，完整测试 143/143，Golden 12/12；真机关键崩溃、ANR 和图片解码异常均为 0。
- 本轮只读打开真实页面，没有发送消息、处理审批、修改头像或清除真机应用数据。

## 2026-08-31 真机待办与审批详情密度复核

- 调整前：[待办](docs/device-acceptance/evidence/419-real-device-todos.png)、[审批详情](docs/device-acceptance/evidence/421-real-device-approval-detail.png)。
- 调整后：[待办](docs/device-acceptance/evidence/423-real-device-todos-tabs-final.png)、[审批详情](docs/device-acceptance/evidence/424-real-device-approval-detail-fixed.png)、[前后对照](docs/device-acceptance/evidence/425-real-device-oa-density-before-after.png)。

### Findings

- [已修复 P2] 六个待办页签在 360dp 真机上横向溢出；现按字数压缩为 50–58dp，12.5sp 文字和 16dp 独立角标在同一首屏完整显示。
- [已修复 P1] 日期时间去除 `T` 与毫秒，统一为 `yyyy-MM-dd HH:mm`，真实请假起止时间不再像接口调试值。
- [已修复 P2] 处理记录由三列挤压布局改为两层：处理人和时间一行，动作和意见一行；真实长姓名不再拆成两行。
- [已通过] 表单行、附件行、节点头像、状态、底部更多操作和搜索/筛选高度均保持原移动尺寸，没有为容纳信息放大按钮或输入框。

### 验证

- 真实账号只读打开三条我发起的记录和一条审批中详情，没有触发远端业务写入。
- `flutter analyze` 0 issue，完整测试 144/144，Golden 12/12；真机关键崩溃、ANR 和图片解码异常为 0。

## 2026-08-31 真机失败申请恢复交互复核

- 终态：[列表](docs/device-acceptance/evidence/430-real-device-outbox-recovery.png)、[菜单](docs/device-acceptance/evidence/431-real-device-outbox-recovery-menu.png)、[预填表单](docs/device-acceptance/evidence/432-real-device-outbox-prefill.png)。
- [已修复 P1] “表单校验失败”属于内容问题，不再与网络失败共用“重试”；行内给出“需修改后重提”，菜单仅保留“修改后重提 / 放弃记录”。
- [已通过] 恢复操作使用原有紧凑菜单和表单控件，没有扩大列表行、按钮或输入框；请假标题、类型、时间、天数和事由在真机上成功恢复。
- [已通过] 只打开预填页面，不提交、不重试、不删除；历史失败记录保持不变。`flutter analyze` 0 issue，完整测试 145/145，Golden 12/12，关键崩溃 0。

## 2026-08-31 真机通知恢复状态复核

- [已通过] 应用强制停止并重新启动后，IM、OA 通知和工作台数据会主动刷新；通讯录在线状态投影也获得新的服务端更新时间。
- [已修复 P1] 通知设置不再仅依赖服务端旧设备登记判断“已启用”，必须同时存在当前安装包的真实运行时推送 Token。
- [阻塞 P1] 当前 APK 没有厂商推送 Service 和 Token，不能在进程被杀后接收实时系统通知；设置页如实显示“未注册”，并说明打开应用后自动同步。
- 保持原有紧凑设置行，没有新增大开关或大段产品说明。`flutter analyze` 0 issue，完整测试 146/146，Golden 12/12。
