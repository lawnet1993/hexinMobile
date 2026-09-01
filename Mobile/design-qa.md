# 移动端设计 QA

## 对照基准

- 当前已登录、正在运行且已更新到最新版本的 Windows 桌面窗口，是桌面端信息结构、OA/IM 功能范围、交互状态和视觉层级的唯一产品基准。
- `Desktop/Windows` 源码不是最新版本，只用于辅助查接口或字段；不得依据旧源码判断页面应该如何设计、功能是否存在或移动端是否完成。
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
- 当前 Windows 桌面端被 v1.0.79 → v1.0.80 强制更新弹窗遮挡，本轮未执行未经确认的下载安装；旧源码与此前 v1.0.79 运行证据只能作为历史线索，不能替代最新窗口复核。
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

## 2026-08-31 消息页标题栏状态语义复核

- 桌面参考：[452-current-desktop-messages-reference.png](docs/device-acceptance/evidence/452-current-desktop-messages-reference.png)。
- 真机调整前后：[444-current-mobile-messages-audit.png](docs/device-acceptance/evidence/444-current-mobile-messages-audit.png)、[450-real-device-messages-header-final.png](docs/device-acceptance/evidence/450-real-device-messages-header-final.png)。

### Findings

- [已修复 P1] 消息页的橙色断网图标实际表示安全隧道内核缺失，不代表 IM 离线；移除后不会再与联系人灰色离线点、聊天内“最后在线”或群聊在线人数产生语义冲突。
- [已通过] 桌面端同页的搜索、筛选、收藏和发起会话映射仍完整；移动端只做标题栏收敛，没有增加说明文字、放大按钮或改变单聊/群聊边界。
- [已通过] 真机 360dp 逻辑宽度下标题、收藏和新增操作留有稳定间距，搜索框、四个筛选和会话行均无位移或溢出。

### 验证

- Golden 差异仅为被移除图标，114px（0.03%）；更新后 Golden 12/12。
- `flutter analyze` 0 issue，完整测试 148/148；最终 APK 已覆盖安装，真机日志关键异常 0。

## 2026-08-31 真机视频消息预览与重复信息收敛

- 真机终态：[首次打开](docs/device-acceptance/480-video-no-duplicate-name.png)、[退出会话后重进](docs/device-acceptance/481-video-cache-reopen.png)。

### Findings

- [已修复 P1] 视频消息原先同时显示封面播放按钮和下方文件名/播放入口，同一动作与名称重复占用两行空间；封面可用时现仅保留真实首帧、居中播放按钮和右下角时长。
- [已通过] 封面生成或下载失败时仍回退为文件名、大小和打开入口，不会因收敛正常状态而丢失失败状态的可操作性；音频消息保持独立文件名与打开入口。
- [已通过] 退出群聊后重新进入，预览直接复用应用私有目录中的稳定 JPEG；文件大小 3820 字节、修改时间仍为 15:35，没有重新下载或重新生成封面。
- [已通过] 视频预览保持 200×112dp，播放按钮 38dp，时长使用紧凑角标；没有增加说明文字、放大消息气泡或混用音频/视频表现。

### 验证

- 新增组件断言：真实预览存在时渲染封面和 `0:18` 时长，但不可见文本中不再出现视频文件名；视频上传、封面上传和消息元数据契约测试继续通过。
- `flutter analyze` 0 issue，完整测试 151/151，Golden 12/12；最新 Debug APK SHA-256 为 `745839B6C491FBA68D15154C0DA72E8B3F24C059DC2789D1AD02CEC4AEEAFB85`，已覆盖安装到 realme 真机，最近 1200 行日志关键异常 0。

## 2026-08-31 IM 会话重进与滚动性能

- 性能记录：[486-im-performance-profile-20260831.md](docs/device-acceptance/486-im-performance-profile-20260831.md)。
- 真机终态：[Profile 快速重进](docs/device-acceptance/483-profile-fast-reopen-cached.png)、[最终 Debug 稳定页](docs/device-acceptance/485-final-debug-chat-stable.png)。

### Findings

- [已修复 P1] 消息窗口只读取最新 80 条，历史按 80 条向前分页，并在加载后保持原滚动位置；列表继续使用惰性构建，不因进入会话一次创建全部消息控件。
- [已修复 P2] 消息窗口和视频预览离开页面后保留 5 分钟，短时间返回并重新进入直接复用；超时自动释放，避免把访问过的所有会话永久留在内存。
- [已通过] Profile 冷启动 660ms；连续快速退出/重进 8 次后封面立即显示，私有缓存仍为 3820 字节、15:35，没有重新生成。
- [已通过] SurfaceFlinger 连续滚动采样 127 帧：P99 16.62ms，最大活跃帧间隔 16.66ms，超过 25ms 的活跃帧 0；`gfxinfo` 的宿主视图单帧结果已排除，不作为结论。

### 验证

- `flutter analyze` 0 issue，完整测试 151/151，Golden 12/12；Profile APK SHA-256 为 `248E51CE387C7018FB65C2E5A7896C145437CB15CD50ACAB186CB8ED57D05B83`。
- 最终 Debug APK SHA-256 为 `619684A79785C648512BFF7EBF45D5D041A9532619D6C2F3B343519814D21986`，已恢复覆盖安装到 realme 真机；最终稳定页无加载态，最近 1200 行关键异常 0。

## 2026-08-31 OA 待办与审批底栏对照

- 完整对照：[496-oa-desktop-mobile-audit-20260831.md](docs/device-acceptance/496-oa-desktop-mobile-audit-20260831.md)。
- 桌面基准：[487-current-desktop-todos-audit.png](docs/device-acceptance/487-current-desktop-todos-audit.png)。
- 真机终态：[待办](docs/device-acceptance/488-current-mobile-todos-audit.png)、[审批详情底栏](docs/device-acceptance/494-mobile-approval-more-button-final.png)、[更多操作](docs/device-acceptance/495-mobile-approval-more-sheet-final.png)。

### Findings

- [已通过] 待我处理、我发起的、抄送我的、已完成、草稿箱和待同步六视图，与桌面端搜索及类型/应用/状态/时间筛选语义一致；新建待办和新建申请保持独立。
- [已修复 P2] 审批详情底栏原来只显示孤立“…”；真实催办和撤回虽然可用，但入口像未完成占位。现改为 80×42dp“更多”描边按钮，和驳回/同意同高，不扩大底栏。
- [已通过] 点击“更多”仍只展示服务端允许的真实动作；本轮账号为催办、撤回，没有伪造转交、加签或审批权限。
- [已通过] Android 语义名称为“更多”，按钮边界 80×42dp；页面无横向溢出。TalkBack 阅读顺序和动态字体仍不能由截图单独证明。

### 验证

- `flutter analyze` 0 issue，OA 定向测试 25/25，Golden 12/12；真机最近 1200 行关键异常 0。
- 最新 Debug APK SHA-256 为 `23296DA71234DF0C7F3F71A8BF5EAFCD4B31E9ECF93F3D73D815C8CF9312639D`，已覆盖安装到 realme 真机；本轮只读打开菜单，没有执行任何远端操作。

## 2026-08-31 审批发起页内联流程

- 完整对照：[505-approval-inline-flow-audit-20260831.md](docs/device-acceptance/505-approval-inline-flow-audit-20260831.md)。
- 桌面基准只采用当前已登录、正在运行的 v1.0.79 窗口：[桌面请假审批](docs/device-acceptance/502-current-desktop-leave-form-inline-flow.jpg)；旧桌面源码不作为视觉或功能真值。
- 真机终态：[移动端内联流程](docs/device-acceptance/504-mobile-inline-workflow-real.png)。

### Findings

- [已修复 P2] 移动端不再通过“查看审批流程”按钮打开二次底部弹层；流程直接位于表单和附件下方，与当前桌面窗口一致。
- [已通过] 手机端以紧凑节点轴展示部门、版本、节点、真实人员、部门及会签/或签；表单字段变化后防抖刷新，加载时不清空已显示节点。
- [已通过] 真机真实接口返回“测试 · v1 / 部门负责人审批 / 测试-管理员测试 · 测试”，语义树中没有“查看审批流程”，页面无溢出和异常大按钮。

### 验证

- `flutter analyze` 0 issue，完整测试 151/151，Golden 12/12；Debug APK SHA-256 为 `9399CF469BE0FC99DEFAF444296331D185427A51CFCE55C4FFEEB71E62097E02`，已覆盖安装到 realme 真机。
- 最近 1000 行真机日志关键异常 0；本轮只读打开表单，没有填写、保存草稿、选择附件或提交申请。

## 2026-08-31 OA 附件预览与草稿恢复

- 完整验收：[516-oa-attachment-draft-audit-20260831.md](docs/device-acceptance/516-oa-attachment-draft-audit-20260831.md)。
- 当前桌面基准：[附件与草稿操作](docs/device-acceptance/506-current-desktop-attachment-draft-reference.jpg)；真机终态：[附件行](docs/device-acceptance/512-mobile-attachment-row-saved.png)、[全屏预览](docs/device-acceptance/513-mobile-attachment-preview.png)、[重启恢复](docs/device-acceptance/515-mobile-draft-restored.png)。

### Findings

- [已修复 P1] 表单按模板恢复本地草稿，标题、动态字段和本地附件均保留，并用 30dp 状态条显示“已恢复上次草稿”；快速返回会先保存最新快照，不等待防抖计时器。
- [已修复 P2] 图片附件改为 40×40dp 真实缩略图、文件名、大小和独立删除动作；整行 54dp、无多余边框，点击进入支持缩放的全屏预览。
- [已通过] realme 真机选择本地 `AI-UAT` 图片、自动保存、全屏预览、强制结束应用、重新启动并再次进入请假审批后，附件计数、缩略图和草稿状态完整恢复。
- [已通过] 本轮未提交申请或上传附件，线上业务数据没有变化；当前已登录桌面窗口仍是唯一产品基准，旧桌面源码不用于判断完成度。

### 验证

- `flutter analyze` 0 issue，完整测试 153/153，Golden 12/12；Debug APK SHA-256 为 `1E5EA23E2197BE89504A6C2F5B3B823E5606B64E8E0B39A3A42B0267B6FAD731`，已覆盖安装到 realme 真机。
- 最近 1200 行当前应用进程日志的应用关键异常命中为 0；TalkBack、动态字体和非图片系统应用兼容性继续保留为专项验收项。

## 2026-08-31 通知持久化与离线恢复

- 完整验收：[525-notification-offline-recovery-audit-20260831.md](docs/device-acceptance/525-notification-offline-recovery-audit-20260831.md)。
- 真机证据：[在线基线](docs/device-acceptance/520-mobile-notifications-online.png)、[断网重启](docs/device-acceptance/522-mobile-notifications-offline-restart.png)、[重连刷新](docs/device-acceptance/523-mobile-notifications-reconnected.png)、[真实已读](docs/device-acceptance/526-mobile-notification-read-online.png)、[已读离线保持](docs/device-acceptance/527-mobile-notification-read-offline-restart.png)。

### Findings

- [已修复 P1] 通知首屏不再依赖即时网络；通知内容、未读状态、下一页游标和是否还有下一页均按账号持久化，断网杀进程后仍可立即恢复。
- [已修复 P1] 已读成功后不再删除通知缓存，而是同步更新普通列表、分页快照和 bootstrap 投影；OA 事件刷新与事件游标同一事务落库。
- [已修复 P2] 顶部与下拉刷新改为真实拉取服务端第一页；失败时保留列表并提示继续显示本机通知。
- [已通过] realme 真机关闭蜂窝数据、确认网络不可达、强制结束和冷启动后，通知中心仍显示 28 条 / 21 条未读；网络已恢复，刷新后数据一致。
- [已通过] 在线打开一条真实未读通知后未读数从 21 降为 20；再次断网、杀进程和冷启动后仍为 20，已读状态没有随页面或进程结束回滚。

### 验证

- `flutter analyze` 0 issue，完整测试 155/155，Golden 12/12；Debug APK SHA-256 为 `9BF3E42462E3FBA5CA125D1B14D20216A151F3E285E50F404452EB8A84BCFCA0`，已覆盖安装到 realme 真机。
- 最近 1600 行当前应用进程日志的关键异常命中为 0；正式系统推送、离线期间新增通知和超过 100 条真实分页继续保留为后续专项。

## 2026-08-31 IM 会话重复进入性能

- 完整验收：[531-im-conversation-reopen-performance-audit-20260831.md](docs/device-acceptance/531-im-conversation-reopen-performance-audit-20260831.md)。
- 真机终态：[群聊热重进](docs/device-acceptance/530-mobile-group-warm-reopen.png)。

### Findings

- [已修复 P1] 任意 IM 同步事件原先会让所有会话的消息、成员和群资料 Provider 同时失效，导致无关会话重新解密消息和重复刷新资料。
- [已修复 P1] 同步失效改为按事件类型与真实 `conversationId` 精确路由；退出后五分钟内重进直接复用原消息窗口，仅当前会话真实变化时重新读取。
- [已修复 P2] 消息行增加按消息 ID 的稳定 Key 与索引回调，加载更早消息时保留已有行和媒体预览元素。
- [已通过] 真机单聊、群聊各连续进入/返回 8 次；P95 分别 6.62 ms、7.87 ms，最大 7.67 ms、8.27 ms，超过 16.7 ms 的渲染就绪帧均为 0，关键异常 0 条。
- [已通过] 群聊重进后仍显示真实 `2 位成员 · 1 人在线`，单聊/群聊边界未改变；视频消息继续直接显示预览和时长，不重复显示文件名。

### 验证

- `flutter analyze` 0 issue，完整测试 158/158，Golden 12/12；Debug APK SHA-256 为 `D02A40ED62BE07F4F48478EF3DCA4AB24A10DE2D56A170FCEBC3C6CFEB920E75`，已覆盖安装到 realme 真机。
- SurfaceFlinger 指标只用于渲染就绪耗时，不替代完整点击响应时间；最新版桌面端仍等待安装确认，因此本轮没有伪造双端新消息同步结论。

## 2026-08-31 IM 媒体缓存与内存稳态

- 完整验收：[533-im-media-memory-audit-20260831.md](docs/device-acceptance/533-im-media-memory-audit-20260831.md)。
- 真机终态：[群聊媒体缓存](docs/device-acceptance/532-mobile-group-media-bounded-cache.png)。

### Findings

- [已修复 P1] 图片与媒体 Provider 原先永久保留完整二进制，历史媒体越多，进程内存越容易持续增长。
- [已修复 P1] 下载缓存改为账号隔离的 48 项 / 32 MB LRU，离屏 Provider 自动释放；账号变化立即清空。
- [已修复 P1] 图片气泡原先按原图分辨率解码；现按 210dp / 78dp 与设备 DPR 解码缩略图，全屏预览仍保留原图。全局解码缓存限制为 120 项 / 48 MB。
- [已通过] 修复前第 21–40 次群聊重进 Graphics 继续增长 60,344 KB；修复后同阶段只增加 24 KB，PSS 只波动 4,187 KB，达到稳态。
- [已通过] 最终构建群聊媒体会话 8 次重进 P95 7.68 ms、最大 11.70 ms，超过 16.7 ms 的帧为 0，关键异常为 0。

### 验证

- `flutter analyze` 0 issue，完整测试 162/162，Golden 12/12；最终 Debug APK SHA-256 为 `9927E836A90425708471A86C6037A6FBB09A8C1DFF8926283E96966813A32F9D`，已覆盖安装到 realme 真机。
- 当前群聊仍显示真实 `2 位成员 · 1 人在线`；图片、音频和视频预览正常，单聊/群聊边界没有改变。

## 2026-08-31 OA 审批详情热重开与附件缓存

- 完整验收：[541-oa-detail-hot-reopen-memory-audit-20260831.md](docs/device-acceptance/541-oa-detail-hot-reopen-memory-audit-20260831.md)。
- 真机证据：[真实审批详情](docs/device-acceptance/536-mobile-real-approval-detail.png)、[真实附件原图预览](docs/device-acceptance/539-mobile-real-approval-attachment-preview.png)。

### Findings

- [已修复 P1] 审批详情原为永久 Provider，浏览不同申请后会一直保留；现离开页面后只保留 5 分钟热重开窗口，到期自动释放，主动刷新和审批业务动作仍精确失效目标申请。
- [已修复 P1] OA 图片缩略图原来永久保留完整下载结果并按原图解码；现离屏自动释放，与 IM 媒体共用账号隔离的 48 项 / 32 MB LRU，并按 32dp × DPR、最大 192px 解码。
- [已通过] 真实含图片附件的请假申请连续重开 40 次，第二组 20 次 PSS 只再增加 3,634 KB；Graphics 仍增加 7,128 KB，因此只判定 PSS 与数据缓存趋稳，不宣称图形内存完全不变。
- [已通过] 8 次热重开 SurfaceFlinger 采样 127 帧，P95 10.08 ms、最大 12.53 ms，超过 16.7 ms 为 0；关键异常为 0。
- [已通过] 附件缩略图、申请字段、审批进度和处理记录保持正常；点击真实附件仍进入全屏原图预览并可返回详情。

### 验证

- `flutter analyze` 0 issue，完整测试 164/164，Golden 12/12；最终 Debug APK SHA-256 为 `2D3103548B15DBAD99D6B49930EE9848E306B8B56864498CC902EE03F418AE84`，已覆盖安装到 realme 真机。
- 仅只读打开现有“我发起的”审批，没有提交、审批、撤回、催办或修改线上数据；最新桌面窗口仍等待更新确认，本轮未用旧桌面源码替代运行窗口。

## 2026-08-31 五个主入口与待办信息密度

- 完整审核：[542-primary-navigation-density-audit-20260831.md](docs/device-acceptance/542-primary-navigation-density-audit-20260831.md)。
- 真机证据：[修复前待办](docs/device-acceptance/primary-nav-audit-20260831/03-todos.png)、[修复后待办](docs/device-acceptance/primary-nav-audit-20260831/07-todos-after.png)、[草稿箱](docs/device-acceptance/primary-nav-audit-20260831/08-drafts-after.png)、[待同步](docs/device-acceptance/primary-nav-audit-20260831/09-outbox-after.png)。

### Findings

- [已修复 P2] 草稿箱和待同步数量原先浮在标签上方，真实 1 / 7 数量形成上下两层焦点并增加动态字体裁切风险；现改为标签右侧 14dp 内联角标。
- [已修复 P3] 待办搜索提示在真机被省略，改为“搜索事项或申请编号”，不增加解释文字，不改变实际检索和筛选能力。
- [已通过] 六个 OA 分类在 360dp 真机同屏完整显示，真实草稿和待同步列表均可进入，底部五项 Tab 不受影响。
- [已通过] 390dp、1.3 倍字体测试确认角标与标签垂直居中且不越界；语义树读作“草稿箱，1 条”“待同步，7 条”。
- [已通过] 五个主入口当前截图确认群聊/单聊边界、通讯录真实在线状态、工作台和个人页结构保持不变。

### 验证

- `flutter analyze` 0 issue，完整测试 165/165，Golden 12/12；最终 Debug APK SHA-256 为 `E509078E47AC22131B7F8D3C64459838137CD849155432F236077A73D81B2EEC`，已覆盖安装到 realme 真机。
- 最近 1500 行日志中崩溃、ANR、OOM、Flutter 异常与 RenderFlex 溢出均为 0；旧桌面源码未作为本轮产品基准。

## 2026-08-31 IM 双端会话与历史恢复

- 完整验收：[543-im-two-endpoint-recovery-audit-20260831.md](docs/device-acceptance/543-im-two-endpoint-recovery-audit-20260831.md)。
- 真机证据：[重新登录后的群聊历史](docs/device-acceptance/dual-mobile-audit-20260831/11-real-history-reconciled.png)。

### Findings

- [已修复 P1] 同账号多设备若服务端不向发送者的其他设备回送消息事件，第二端会一直停留在缓存；当前会话现以 12 秒、最多 50 条元数据做有界差异校准，只有真实变化才精确刷新当前会话。
- [已修复 P2] IM 后台出站失败原先不会触发目标会话失效；现会及时显示“发送失败，点此重试”，不把本地乐观气泡误报为已送达。
- [已通过] 测试消息由服务端持久化；真机旧缓存中没有该消息，重新登录进入原群后恢复成功。视频首帧、播放按钮和时长仍正常，文件名没有重复显示。
- [阻塞 P1] 同一终端账号在第二台设备登录会使第一台真实接口返回登录失效，所以同账号并发观察无效；不同账号的双端互发仍需第二员工账号的安全本地凭据。
- [约束] 旧桌面源码不再作为功能或设计基准；只以当前已登录桌面窗口为准。窗口仍被强制更新和未保存表单确认遮挡，本轮未擅自安装或放弃内容。

### 验证

- `flutter analyze` 0 issue，完整测试 167/167，Golden 12/12；最终 Debug APK SHA-256 为 `77F8FD521A1CF33DC57FB24AEB3806B857AE6A87986C41FDCC47D20BDE0E7755`，已覆盖安装到真机和模拟器。
- 校准只在聊天页存活时运行；无变化不写 SQLite、不失效 Provider、不重新滚动消息列表。

## 2026-08-31 工作台应用目录桌面/移动端对齐

- 完整验收：[544-workbench-app-catalog-alignment-20260831.md](docs/device-acceptance/544-workbench-app-catalog-alignment-20260831.md)。
- 对照证据：[当前桌面 v1.0.80 工作台](docs/device-acceptance/mobile-core-audit-20260831-current/desktop-v1080-workbench.png)、[移动端修复前](docs/device-acceptance/mobile-core-audit-20260831-current/07-application-catalog.png)、[移动端修复后](docs/device-acceptance/mobile-core-audit-20260831-current/11-all-apps-final.png)。

### Findings

- [已修复 P1] “全部应用”原先将服务端应用按本地分类重新编排，并额外混入日程、公告、工作群组、审批中心、登录设备和网络诊断等移动端固定入口，与当前桌面工作台的数据边界不一致。
- [已修复 P1] 空服务端目录原先会回退展示本地可路由应用，可能向无权限账号暴露不可提交入口；现改为真实空态。
- [已通过] 当前服务端应用名称、图标、顺序、权限和申请路由保持不变；移动端仅采用紧凑五列宫格，长名称支持两行完整显示。
- [边界] 桌面端与移动端当前登录账号不同，实际授权应用数量允许不同；本轮没有把桌面账号的应用硬编码到移动端。

### 验证

- `flutter analyze` 0 issue，完整测试 167/167，Golden 12/12；最终 Debug APK SHA-256 为 `AA534D627D59CECF5C56FF0D07C1661E3B169EFB571C537F24B949CD548291B6`，已覆盖安装到 realme 真机。
- 当前登录桌面 v1.0.80 运行窗口作为唯一桌面产品基准，旧桌面源码未参与功能或视觉判定。

## 2026-08-31 审批发起页桌面/移动端对齐

- 完整验收：[545-approval-request-desktop-alignment-audit-20260831.md](docs/device-acceptance/545-approval-request-desktop-alignment-audit-20260831.md)。
- 对照证据：[移动端修复前](docs/device-acceptance/home-approval-audit-20260831/04-leave-form-before.png)、[当前桌面表单](docs/device-acceptance/home-approval-audit-20260831/05-desktop-leave-form.jpg)、[移动端修复后](docs/device-acceptance/home-approval-audit-20260831/07-leave-form-after.png)、[同屏对照](docs/device-acceptance/home-approval-audit-20260831/08-desktop-mobile-form-comparison.jpg)。

### Findings

- [已修复 P1] 当前桌面 v1.0.80 已不再编辑“申请标题”，移动端仍多占一整行；现按桌面业务结构移除，系统默认标题、再次发起标题和旧草稿标题仍在内部安全保留。
- [已修复 P2] 移动端必填字段缺少桌面已有的 `*`，现统一投影服务端 `required` 配置，不增加额外说明。
- [已修复 P2] 提交按钮原先横向填满全部剩余空间；现保存/提交按钮分别限制为 116dp、140dp 并右对齐，42dp 触控高度不再缩小。
- [已通过] 附件、字段和审批流程仍完整显示，审批节点继续在表单下方直接展开；390dp、1.3 倍字体无溢出。

### 验证

- `flutter analyze` 0 issue，完整测试 167/167，Golden 12/12；最终 Debug APK SHA-256 为 `EA6A7CC98337C42CA60B1D1CD46D26C0D150E671F8C00DA0BCEB50EC151DA93A`，已覆盖安装到 realme 真机。
- 真机语义树确认标题字段已消失、必填标识和按钮尺寸符合实现；最近 2000 行日志关键异常 0 条，本轮未提交或修改线上审批数据。

## 2026-08-31 当前设备授权启动同步

- 完整验收：[546-mobile-current-device-auth-audit-20260831.md](docs/device-acceptance/546-mobile-current-device-auth-audit-20260831.md)。
- 真机证据：[修复前错误设备摘要](docs/device-acceptance/continuation-audit-20260831/06-mobile-profile.png)、[修复后冷启动摘要](docs/device-acceptance/continuation-audit-20260831/10-mobile-profile-current-device-fixed.png)。

### Findings

- [已修复 P1] 当前设备授权原来只在打开“登录设备”页时注册，首次进入“我的”会把列表中第一台已授权 Windows 设备误显示为当前设备。
- [已修复 P1] 应用启动和回前台现在主动注册当前移动设备；注册响应直接投影为当前设备，列表短暂延迟时也不会显示其他设备。
- [已修复 P2] 设备 ID 改为大小写不敏感匹配；无法匹配时显示“未登记当前设备”，不再回退到任意授权设备。
- [已通过] realme 真机强制结束、重新启动后未进入设备列表，直接打开“我的”即显示 `realme RMX3366 · android`。

### 验证

- `flutter analyze` 0 issue，完整测试 177/177；Debug APK SHA-256 为 `0275C64D19E33DEBEB683F878CB482E3C18DFD5268A3D442DB4312E2281ED8DF`，已覆盖安装到 realme 真机。
- 当前进程最近 1200 行日志的崩溃、Flutter 未处理异常、RenderFlex、ANR 和 OOM 关键命中为 0。

## 2026-08-31 IM 历史消息上滑自动分页

- 完整验收：[547-im-history-auto-scroll-audit-20260831.md](docs/device-acceptance/547-im-history-auto-scroll-audit-20260831.md)。
- 真机证据：[群聊上滑后顶部终态](docs/device-acceptance/continuation-20260831-b/06-real-group-upward-scroll.png)。

### Findings

- [已修复 P2] 正常历史分页已是上滑自动触发，但失败提示仍保留“重试”按钮，交互语义不一致。现移除手动按钮，失败后保留现有消息，再次上滑自动重试。
- [已通过] 靠近顶部 72dp 才触发，同一时刻只允许一个历史请求；插入更早页后保持原阅读锚点。
- [已通过] 真机冷启动后进入真实群聊并上滑，界面无“加载更早消息”按钮；群聊标识、在线人数和媒体气泡未回归。

### 验证

- `flutter analyze` 0 issue，完整测试 178/178；Debug APK SHA-256 为 `350012BAEF2325632A6750AC2EC6B1B47EFA30C76B40CF791BBA9D3119E9D057`，已覆盖安装到 realme 真机。
- 当前进程最近 1600 行日志中崩溃、Flutter 未处理异常、RenderFlex、ANR 和 OOM 关键命中为 0。

## 2026-08-31 Profile 冷启动与待办标题密度

- 完整验收：[548-mobile-startup-profile-todo-density-audit-20260831.md](docs/device-acceptance/548-mobile-startup-profile-todo-density-audit-20260831.md)。
- 真机证据：[Profile 冷启动工作台](docs/device-acceptance/cold-start-audit-20260831/final-profile-workbench-1000ms.png)、[压缩后待办](docs/device-acceptance/cold-start-audit-20260831/final-profile-todos-compact.png)。

### Findings

- [已查明] Debug APK 冷启动约 2.6 秒仍在 Flutter 调试启动画面，约 3.38 秒才捕获完整工作台；这是调试运行时开销，不是 OA 缓存等待远程接口。
- [已通过] 同一 realme 真机 Profile APK 连续 5 次冷启动，Android Activity `TotalTime` 为 661–691ms，平均 679.6ms；约 1.27–1.29 秒完成的 5 张截图均已显示完整工作台。
- [已通过] 工作台、消息、待办、通讯录、我的五个主入口在一次 0.75–0.90 秒的“点击 + 250ms 等待 + PNG 截图”周期内均已完整渲染；该数值是捕获周期，不冒充精确点击响应时间。
- [已修复 P2] 待办页“统一处理任务与审批”是重复说明，与低说明密度要求冲突。现删除并将顶部工具栏从 58dp 压缩为 50dp，新建入口、六个分类和搜索保持不变。

### 验证

- `flutter analyze` 0 issue，完整测试 178/178，待办 Golden 已按真实紧凑终态更新并通过。
- 最终 Profile APK SHA-256 为 `DC270A95E311C2F33FF7046BF2828F93DC4144684F45206F97597832CC497BDE`，已覆盖安装到 realme 真机。
- 最终冷启动 `TotalTime=673ms`，约 1.304 秒完成的截图已显示完整工作台；最近 1600 行进程日志的崩溃、Flutter 未处理异常、RenderFlex、ANR 和 OOM 命中为 0。

## 2026-08-31 个人页说明层级压缩

- 完整验收：[549-profile-description-density-audit-20260831.md](docs/device-acceptance/549-profile-description-density-audit-20260831.md)。
- 真机终态：[个人页压缩后](docs/device-acceptance/profile-density-audit-20260831/01-profile-compact-final.png)。

### Findings

- [已修复 P2] “账户与安全 / 密码与终端身份”和“消息通知 / 提醒类型与方式”两组文案完全是标题的重复解释，现删除副标题，两行自然恢复紧凑单行高度。
- [已通过] 安全连接、当前登录设备、主题语言、版本号和真实在线状态均属于数据不是说明，保持显示。
- [已通过] realme 冷启动后直接进入“我的”，语义树确认两条冗余文字为空，并仍显示“在线”、“安全连接不可用”、`realme RMX3366 · android`、“浅色·简体中文”和 `v1.0.1`。

### 验证

- `flutter analyze` 0 issue，完整测试 178/178，个人页 Golden 更新后通过；测试额外断言冗余说明消失、三个真实状态入口保留。
- Profile APK SHA-256 为 `31055298997419F37D37FE37E4463B658A5813F79DF22731D05E9F0A05157E2E`，已覆盖安装到 realme 真机。
- 最终冷启动 `TotalTime=662ms`，最近 1600 行进程日志的崩溃、Flutter 未处理异常、RenderFlex、ANR 和 OOM 命中为 0。

## 2026-09-01 IM 回执单行与群聊头像复核

- 参考状态：用户提供的真机截图中，“回执”文字被挤到消息气泡下方并逐条重复。
- 当前终态：[单聊双勾与气泡同行](docs/evidence/616-real-device-im-single-line/03-direct-receipt-single-line.png)、[真实已读抽屉](docs/evidence/616-real-device-im-single-line/04-read-receipt-sheet.png)、[消息列表群聊头像](docs/evidence/616-real-device-im-single-line/02-messages-group-avatar.png)。

### Findings

- [已修复 P2] 回执状态换行并重复显示文字。现在只保留 14dp 双勾，入口与消息气泡处于同一视觉行；长消息只允许气泡正文自身换行。
- [已修复 P2] 消息列表群聊仍使用首字母头像，弱化了单聊/群聊边界。现在与通讯录一致使用 36dp 浅蓝群组图标，单聊保留真实成员头像与在线点。
- [已通过] 双勾仍可点击，真实详情显示 `已读 1/1`；群聊标题、2 位成员、1 人在线、视频预览、时长和输入区均保持正常。

### 五项视觉检查

- 字体：未增加任何解释文案，“回执”文字已移除。
- 间距：双勾复用现有消息行空间，窄屏未产生额外行高。
- 色彩：群组图标使用现有主色与弱蓝底，不新增视觉体系。
- 图标：使用 Material `groups_rounded` 与 `done_all_rounded`，没有字符或自绘图形。
- 内容：已读数量、成员、时间、在线人数和媒体元数据均来自当前真实服务端数据。

### 验证

- 代码增加同行几何断言与群聊/单聊头像类型断言；31/31 IM、235/235 全量、13/13 Golden、0 静态问题通过。
- realme RMX3366 Profile 包覆盖安装后逐页截图，当前进程关键异常 0 条。
- 最终结果：通过。

final result: passed

## 2026-09-01 OA 真实会签流程与详情新鲜度

- 完整验收：[617-oa-cross-account-real-flow-and-detail-freshness-20260901.md](docs/617-oa-cross-account-real-flow-and-detail-freshness-20260901.md)。
- 真实证据：[申请人最终详情](docs/evidence/617-oa-cross-device-flow/22-applicant-final-fresh.png)、[通知与已读同步](docs/evidence/617-oa-cross-device-flow/23-notifications-read-synced.png)。

### Findings

- [已通过] `OA-20260901-8990C6` 经五个真实处理人完成，双人会签在两人都同意前不流转。
- [已通过] 中间节点通知只显示继续流转，最后一个必需节点完成后申请人才收到“审批已通过”。
- [已修复 P1] 审批详情原先永久优先本地快照，跨账号回切后会将最终通过误显示为旧待办。现联网时优先取服务器，仅网络无响应时使用该账号缓存。
- [已通过] 审批结果和抄送通知分别打开后，未读数真实从 14 降到 12。
- [已修复 P2] 34 位请款地址在固定标签列后只剩末字符换行。现在连续长值保持原双栏结构，以紧凑字号在同一行完整缩放显示；异常超长值保持单行省略，不增加卡片高度。

### 验证

- `flutter analyze` 0 issue；完整自动化 240/240 通过（含 13 组 Golden）。
- Profile APK SHA-256 为 `018E96B340763E3C3E66948F88A9E7C73782F49CA5088967E30150DE9FC1D331`，已覆盖安装到模拟器和 realme。
- 真机终态：[长地址同栏单行完整显示](docs/evidence/617-oa-cross-device-flow/25-real-device-long-address-single-line.png)；两台设备关键异常均为 0。Windows 桌面终端当前已登录 `laowang`，但不是本申请审批人，桌面同申请证据仍未冒充完成。

final result: partial pass

## 2026-09-01 IM 已读状态右置与占位压缩

### 对照与证据

- 视觉问题来源：用户真机局部截图 [01-user-reported-receipt-spacing.png](docs/evidence/618-two-device-direct-sync-and-chat-density/01-user-reported-receipt-spacing.png)，543 × 105 px。
- 实现全视图：[03-real-device-compact-receipt.png](docs/evidence/618-two-device-direct-sync-and-chat-density/03-real-device-compact-receipt.png)，realme RMX3366，1080 × 2400 px，Profile 运行态。
- 模拟器全视图：[02-emulator-compact-receipt.png](docs/evidence/618-two-device-direct-sync-and-chat-density/02-emulator-compact-receipt.png)，Android 模拟器，1080 × 2400 px。
- 同屏局部对照：[05-receipt-spacing-before-after.png](docs/evidence/618-two-device-direct-sync-and-chat-density/05-receipt-spacing-before-after.png)，1086 × 121 px；实现区域从 1030 × 230 px 裁切后缩放到 543 × 121 px，参考图只做 8 px 垂直补白，没有拉伸。
- 页面状态：林川与青山的真实双向单聊，两条消息均由服务端持久化；自己发送的消息显示双勾并可打开真实已读详情。

### Findings

- [已修复 P2] 已读入口放在气泡左侧，打断从消息内容到状态的阅读顺序。现改为“气泡 → 双勾 → 自己头像”，不换行、不显示“回执”文字。
- [已修复 P2] 双勾图标只有 14dp，但外层原来占 28 × 28dp，导致视觉上仍留出大段空白。当前外层压缩为 16 × 22dp，图标为 13dp，并移除气泡与状态之间额外 2dp 间隔。
- [已通过] 真机点击压缩后的双勾仍打开底部抽屉，显示真实 `已读 1/1` 和读取时间；没有牺牲业务能力。

### 五项视觉检查

- 字体：状态只使用图标，不增加标签或解释文字；消息正文的字号、行高和换行未改变。
- 间距：状态可见占位由 28dp 降到 16dp，紧贴气泡右侧；长消息仅正文自身换行。
- 色彩：沿用主色双勾、白色本人气泡文字和既有浅色背景，没有新增令牌。
- 图标与资源：继续使用项目现有 `done_all_rounded`，头像仍由真实成员资料加载，没有字符或占位资产。
- 文案与内容：两条 `AI-UAT-*` 测试消息、双方姓名、在线状态和已读数据均来自当前测试环境。

### 比较历史与验证

1. 第一轮将双勾从气泡左侧移到右侧，但 28dp 点击容器仍产生明显空档。
2. 第二轮按用户真机截图继续压缩到 16 × 22dp，并在相同真实会话重新截图；同屏对照不再存在可见的大块留白。
3. 242/242 自动化通过，`flutter analyze` 0 issue；Profile APK SHA-256 为 `8A013FB5F8E6187868FCCD29905766BEACACE0AC92D815D486D63F54172DE872`，已覆盖安装到模拟器和 realme 真机。
4. 真机已读详情：[04-real-device-read-detail.png](docs/evidence/618-two-device-direct-sync-and-chat-density/04-real-device-read-detail.png)；两台设备当前进程日志中崩溃、未处理 Flutter 异常、RenderFlex、ANR 和 OOM 命中均为 0。

当前没有可执行的 P0/P1/P2 视觉差异；本轮不需要额外局部对照。

final result: passed
