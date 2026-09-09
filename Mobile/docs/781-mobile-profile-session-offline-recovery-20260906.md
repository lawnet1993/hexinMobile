# 781 · “我的”、自动登录与断网恢复实测

> 日期：2026-09-06  
> 结论：Profile 包在 Android 模拟器强停后冷启动保留登录态，主框架恢复后 heartbeat=204，IM/OA 游标健康；通知设置能在断网时显示“连接恢复后同步”，恢复网络后自动回到“实时同步”，全程不要求重新登录。“我的”及二级页未暴露设备 ID、TUN 或站点网络状态。

## 自动登录冷启动

1. 在已登录状态强制停止应用，确认旧进程结束。
2. 使用 MainActivity 冷启动，Android 报告 Activity `TotalTime=2781ms`。
3. UIAutomator 在 7274ms 观测上界内读到五个主入口；该时间包含等待和语义树生成，不等同于纯首帧时长。
4. 页面没有账号、密码输入框，原账号与本地数据域均保留。
5. 启动后的健康上报为：
   - heartbeat：204；
   - IM：`http_long_poll`，applied/ACK=4616/4616，pending ACK=0；
   - OA：`http_long_poll`，applied=743，待同步命令=0，待读回执=0。

本次冷启动后“登录设备”仍只有一个当前 Android 设备，没有因重启生成第二个移动设备记录，说明安装级设备身份在该样本中保持稳定。

## “我的”页面巡检

- 主页面只显示账户与安全、通知设置、登录设备、外观与语言、帮助与反馈、关于及退出登录。
- 账号只在“账户与安全”二级页展示；主页面和通讯录不重复暴露账号。
- “账户与安全”显示设备名称、系统版本和真实登录状态，不显示原始设备 ID。
- “登录设备”区分当前 Android 设备和其他 Windows 设备；未执行撤销，避免改变现有授权。
- 页面未出现 TUN、隧道、站点网络或“网络不可用”等与 IM/OA 无关的状态。

两台 AVD 最初使用 GMT，导致截图中的设备活动时间比上海时间少 8 小时。核对客户端代码已经调用 `toLocal()`，确认不是应用解析缺陷；随后通过 Android 系统时区服务把两台模拟器统一为 `Asia/Shanghai`。重新进入页面后，当前设备活动时间与系统本地时间一致。

## 断网与恢复

1. 保持通知设置页打开，在单台模拟器启用飞行模式。
2. 同步状态自动从“实时同步”变为“连接恢复后同步”；没有退出账号，也没有弹出重复错误。
3. 恢复网络后，捕获到新的 heartbeat=204；IM/OA 游标保持健康，没有待 ACK 或待同步命令。
4. 页面无需手动刷新自动恢复为“实时同步”。

## 修改密码交互

- 从账户与安全页打开“修改登录密码”，使用向上展开的底部抽屉，不跳到笨重的整页表单。
- 当前密码、新密码、再次输入新密码三个输入框保持紧凑，密码可见性按钮位于输入框右侧；确认按钮在内容无效时禁用。
- 聚焦当前密码后，抽屉随键盘上移，三个输入框、说明和确认按钮仍完整可见。
- 第一次系统返回只关闭键盘，抽屉保持；第二次系统返回关闭抽屉并返回账户与安全页。
- 本轮没有输入、显示或提交任何密码，账号状态未改变。

## 证据

- [“我的”主页面](../test/evidence/main-shell-touch-targets-20260906-1510/05-profile.png)
- [账户与安全](../test/evidence/main-shell-touch-targets-20260906-1510/06-account-security.png)
- [通知设置在线状态](../test/evidence/main-shell-touch-targets-20260906-1510/07-notification-settings.png)
- [登录设备（模拟器原 GMT 环境）](../test/evidence/main-shell-touch-targets-20260906-1510/08-login-devices.png)
- [强停后冷启动恢复主框架](../test/evidence/main-shell-touch-targets-20260906-1510/09-cold-start-session.png)
- [修正测试环境时区后的登录设备](../test/evidence/main-shell-touch-targets-20260906-1510/10-login-devices-local-time.png)
- [断网状态](../test/evidence/main-shell-touch-targets-20260906-1510/11-notification-offline.png)
- [网络恢复后的实时同步状态](../test/evidence/main-shell-touch-targets-20260906-1510/12-notification-recovered.png)
- [修改密码底部抽屉](../test/evidence/main-shell-touch-targets-20260906-1510/13-change-password.png)
- [键盘弹出后的抽屉布局](../test/evidence/main-shell-touch-targets-20260906-1510/14-change-password-keyboard.png)
- [第一次返回后抽屉仍保留](../test/evidence/main-shell-touch-targets-20260906-1510/15-change-password-after-keyboard-back.png)
- [第二次返回后停留在账户与安全页](../test/evidence/main-shell-touch-targets-20260906-1510/16-change-password-after-sheet-back.png)
- [结构化结果](../test/evidence/main-shell-touch-targets-20260906-1510/profile-session-result.json)

## 判定边界

- 已登录应用强停后自动恢复：**通过（Android 模拟器）**。
- 临时断网保留会话、恢复后自动重连：**通过（Android 模拟器）**。
- IM/OA 前台同步健康状态：**通过**。
- Profile 页面信息范围和设备标识隐藏：**通过**。
- 修改密码抽屉、键盘和系统返回层级：**通过（未提交密码）**。
- realme 真机冷启动、键盘、返回手势与厂商后台限制：**尚未通过**；设备仍锁屏休眠。
- 厂商推送唤醒已杀进程：**尚未通过**；不能用本次主动冷启动代替。
