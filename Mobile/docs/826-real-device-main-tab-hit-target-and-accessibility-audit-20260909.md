# Android 真机主入口点击区域与无障碍树抽查

日期：2026-09-09（Asia/Shanghai）  
设备：realme RMX3366，Android 14，1080 × 2400

## 结论

当前 Profile APK 在真机依次打开工作台、消息、待办、通讯录和“我的”，五个底部 Tab、标题栏动作、筛选项和主要列表行均能进入 Android 原生布局树。抽样的独立动作点击区域均不小于 48dp；列表整行点击区域较大是移动端整行导航设计，不是视觉按钮被放大。

## 证据

- [工作台截图](../test/evidence/main-tabs-20260909/workbench.png)
- [消息截图](../test/evidence/main-tabs-20260909/messages.png)
- [待办截图](../test/evidence/main-tabs-20260909/todos.png)
- [通讯录截图](../test/evidence/main-tabs-20260909/contacts.png)
- [我的截图](../test/evidence/main-tabs-20260909/profile.png)
- 同目录保存五个页面的 `uiautomator` XML，保留实际边界、可点击状态、单聊/群聊描述及在线/离线描述。

## 发现与处理

消息页搜索框视觉占位为“搜索联系人、群组或消息”，但 Android `uiautomator` 把 Flutter `EditText` 标记为 `NAF=true`，未在 XML 的 `content-desc` 中公开名称。先后验证外层 `Semantics`、非浮动 label 和 `MergeSemantics`：Flutter 测试语义树可获得标签，但 Android 桥接后的 XML 仍为空；非浮动 label 还造成消息、通讯录和全部应用视觉基准变化。

上述三种外层语义尝试均未保留。随后改为让搜索框内部的 `TextEditingController.buildTextSpan` 直接提供用途语义，不改变 `InputDecoration`，因此不会增加可见标签或改变输入框高度。当前 Profile APK 在模拟器和 realme 真机的 Android 原生布局树中，`android.widget.EditText` 已同时提供 `text`、`hint="搜索联系人、群组或消息"`，且不再出现 `NAF=true`；页面 Golden 无变化。原生节点命名边界改判通过，TalkBack 实际朗读顺序仍单列为待测。

## 回归

- 完整 `flutter analyze`：0 issue。
- 当前完整 Flutter 回归：1420/1420 通过。
- 回退无效尝试后，13 张主页面 Golden 及 4 项附加页面行为：17/17 通过。
- 最终 Profile APK 已重新覆盖安装，登录状态和主页面恢复正常。
- [真机页面](../test/evidence/main-tabs-20260909/real-device-search-sem-final.png)与[原生布局树](../test/evidence/main-tabs-20260909/real-device-search-sem-final.xml)已留证。
