# 610 · 移动主路径视觉审计与全部应用密度修正

时间：2026-09-01

## 审计范围

在 1080×2400 Android 模拟器上重新安装当前 Demo Debug 包，真实操作并截图检查工作台、全部应用、消息、群聊、待办、通讯录和我的。重点检查信息密度、控件尺寸、边框、分组、底部导航、群聊/单聊边界与真实状态表达；截图不能证明完整 TalkBack、键盘焦点和对比度合规。

## 流程与健康度

1. 工作台：健康。公告在常用应用之前，首页没有常用站点和空日程，底部五项导航及角标清晰。
2. 全部应用：修正后健康。修正前后台只有两个应用时，分类标题、网格行和外层卡片累计高度过大，像未加载完成；现保持后台分类、顺序、图标、名称、权限和路由，仅压缩分类间距与网格纵向占用。
3. 消息：健康。全部/未读/@我/群组边界明确，单聊和群聊有独立标签，列表不套大卡片。
4. 群聊：健康。成员总数、在线数、公告、文件标签和输入区层级清楚；截图只证明视觉状态，不证明并发同步。
5. 待办：健康。搜索、筛选、五类状态和审批/个人待办的视觉类型可区分，没有大号空态。
6. 通讯录：健康。组织、好友、群聊、新朋友严格分栏；在线与最近上线状态直接显示，组织列表无奇怪贯穿线。
7. 我的：基本健康。设置列表密度稳定，状态和设备信息来自运行数据；退出登录保留危险操作语义但按钮视觉高度仍是紧凑移动端范围。

## 本轮修改

- “全部应用”的双分类目录表面高度从修正前约 194dp 收敛到 172dp 以内。
- 图标仍为 32dp，未通过缩小图标牺牲识别；压缩来自分类上下留白、网格行高和卡片底部留白。
- 增加目录表面高度断言，避免后续主题或组件默认值再次把稀疏目录撑高。
- 更新 03-all-apps 视觉基线，并在模拟器重新安装后复拍。

截图证据：

- `docs/evidence/610-mobile-visual-audit/01-workbench.png`
- `docs/evidence/610-mobile-visual-audit/02-all-apps.png`
- `docs/evidence/610-mobile-visual-audit/03-messages.png`
- `docs/evidence/610-mobile-visual-audit/04-group-chat.png`
- `docs/evidence/610-mobile-visual-audit/05-todos.png`
- `docs/evidence/610-mobile-visual-audit/06-contacts.png`
- `docs/evidence/610-mobile-visual-audit/07-profile.png`
- `docs/evidence/610-mobile-visual-audit/08-all-apps-after.png`
- `docs/evidence/610-mobile-visual-audit/08-all-apps-after.xml`

## 验证与构建

- `flutter analyze`：0 项问题。
- 工作台/通讯录冒烟：19/19 通过。
- 视觉基线：13/13 通过。
- 全量自动化：234/234 通过。
- 模拟器关键异常：0 条。
- Production Profile 首次增量产物为 79,660,326 bytes；检查发现两个 `libapp.so` 的中央目录偏移指向追加副本，包内存在旧生成内容造成的体积膨胀。只清理 Flutter 生成目录后重建，最终降至 65,819,655 bytes。
- 最终 Production Profile SHA-256：`4953D2C2EC068CCC62C9C9C9A5E873685321927196DF40F1DF8D7D01632CF2F5`。
- 已覆盖安装 realme RMX3366，设备端 APK 哈希一致。
- 真机仍为系统锁屏：`showing=true / mInputRestricted=true / isKeyguardShowing=true`，未绕过锁屏。

## 证据边界

- 当前截图采用受控 Demo 数据，能够检查移动端布局和交互入口，但不能替代生产账号的服务端权限、通知、同步和审批流证据。
- 截图无法证明 TalkBack 阅读顺序、动态字体放大、系统返回手势和真实弱网恢复；这些继续保留在真机验收范围。
- 桌面端仍被 `v1.0.81` 强制更新页阻塞；未在没有明确确认的情况下下载或安装新软件。
