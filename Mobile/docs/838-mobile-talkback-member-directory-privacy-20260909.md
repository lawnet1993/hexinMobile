# 838 · TalkBack 焦点与群成员账号隐私复验

时间：2026-09-09（Asia/Shanghai）  
环境：Android 16、2 GB 内存模拟器；当前 Profile APK

## 发现与修复

启用 TalkBack 后首次打开的是此前停留的群成员抽屉，旧安装包仍显示账号并使用“搜索姓名或账号”提示。覆盖安装当前构建后：

- 群成员搜索提示改为“搜索成员”，不再向普通成员目录暴露账号概念。
- 后台仍可把输入关键字用于账号匹配，不降低管理员或用户的检索能力。
- 当前群成员行只展示姓名、部门、真实在线状态和群角色；原生布局树中不存在 `test01`、`test03`。
- TalkBack 焦点可通过硬件 Tab 顺序移动到工作台应用入口，焦点框与点击目标一致；底部五个 Tab 在原生语义树中分别标注名称、序号、总数和选中状态。

## 验证结果

- 群聊定向组件测试：99/99 通过。
- 相关静态检查：0 issue。
- 全量 Flutter 测试：1422/1422 通过。
- Profile APK：85,792,566 bytes。
- 当轮成员隐私构建 SHA-256：`E8DDE79E1C244F416D51CE5836B49BCD860CF09371D1B054692DE769FE232C03`；后续图片异常处理构建见 [839](839-mobile-image-compression-failure-recovery-20260909.md)。
- 已覆盖安装 Android 模拟器和 realme 真机；真机登录态保留，直接恢复工作台。

## 证据

- `test/evidence/main-tabs-20260909/emulator-5556-talkback-after-current-install.png`
- `test/evidence/main-tabs-20260909/emulator-5556-talkback-tab5.png`
- `test/evidence/main-tabs-20260909/emulator-5556-member-directory-current.png`
- `test/evidence/main-tabs-20260909/emulator-5556-member-directory-current.xml`
- `test/evidence/main-tabs-20260909/real-device-post-member-fix.xml`

## 边界

- 已验证 Android TalkBack 焦点移动和原生语义，不把截图推断成实际语音内容验收。
- 尚未由真人完整听读所有页面，也未覆盖 iOS VoiceOver；这两项继续保持未完成。
- 测试结束后已关闭两台测试模拟器的 TalkBack 服务，没有修改真机无障碍设置。
