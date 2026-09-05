# 714 心跳生命周期与真机前台恢复

2026-09-04，Asia/Shanghai。阶段进展；整体 IM/OA 对齐目标尚未完成。

## 实际复现与修复

本轮检查自动续期所在的心跳协调器，受控回归在修改前出现 6 项失败、7 项通过：

1. 停止后重新启动，旧维护任务的同步锁会跳过新一轮即时心跳。
2. 并发恢复调用提前返回，而不是等待正在进行的心跳。
3. 停止没有取消正在等待的 HTTP 心跳。
4. 旧启动任务完成后可能再次安装定时器；停止只能取消其中一条。
5. 旧失效处理的迟到返回可能停止已重新启动的循环。
6. Provider 已销毁后，保留的对象引用仍可安装无效定时器。

修复使用代次校验、同一代共享 Future、可取消 HTTP 请求及永久 dispose 状态。停止时先移除旧句柄再取消请求，旧完成回调不能清除新句柄；终止结果也需要检查代次。心跳间隔仍为 30 秒，保持原有会话刷新、明确 401/会话替换校验及网络错误重试规则。

本轮没有调整服务端有效期、加入密码重登或隐藏真实失效。受控竞态是本地复现，未宣称捕获了用户历史掉线时的同一根因。

## 测试与构建

- 新增 [13 项生命周期测试](../test/mobile_presence_lifecycle_test.dart)，本地真实 HTTP 服务器、真实 Dio 取消、Mock 安全存储、受控 Auth 回调、手动 30 秒定时器。
- [修改前 6 失败/7 通过](../test/evidence/presence-lifecycle-20260904/before-corrected.log)。最初夹具未过滤辅助请求，已纠正为只统计 `/api/client/heartbeat`；不使用初始 before.log 作为可靠基线。
- [最终新增测试 13/13](../test/evidence/presence-lifecycle-20260904/lifecycle-final.log)。
- [心跳、主动续期与旧响应隔离专项 45/45](../test/evidence/presence-lifecycle-20260904/focused.log)。
- [全量 1255/1255](../test/evidence/presence-lifecycle-20260904/full-tests.log)。全量期间随后只移除测试夹具无行为覆盖方法，最终夹具单独 13/13 再验。
- [静态分析 0](../test/evidence/presence-lifecycle-20260904/analyze-final.log)；[普通 Profile 构建成功](../test/evidence/presence-lifecycle-20260904/build.log)，35.4 秒，lib/main.dart，arm64+x64。
- 本地产物与真机 base.apk SHA256 一致：`A76B917099815E132AAE172818F45C0240DF058160D3505CD2B3CD6EE2B7FBEF`。secure_tunnel 的未来 Kotlin 迁移警告仍在，本次不影响构建。

## 真机操作

RMX3366、test01，保留数据覆盖安装，没有卸载或清数据，没有操作手机热点/系统网络，没有发送消息、修改密码或审批。

- 新包首次启动恢复 Test Terminal 01 工作台。
- 连续三次 Home → 返回应用，三次均保留原账号工作台，未输入凭据。
- [通讯录首次打开](../test/evidence/presence-lifecycle-20260904/contacts.png)：公司总部 8 人及其他联系人 2 人均默认折叠，未平铺全部人员。
- 展开公司总部后出现人员，当前用户显示在线，其他联系人按当前投影显示最近上线时间。点击 Test Terminal 02 的头像，打开 [对应单聊](../test/evidence/presence-lifecycle-20260904/contact-chat.png)，标题、历史文字、图片、头像及回执可见；未发送消息。这不是性能基准测试。
- 强停后冷启动，23:31:08 再次恢复原账号工作台。[截图](../test/evidence/presence-lifecycle-20260904/cold-restored.png)。当前进程日志采样 FATAL、Unhandled Exception、RenderFlex overflow 均为 0。
- 当前进程未捕获 MOBILE_SESSION_AUTH/REFRESH 事件，不能据此声称已经真实触发自然续期或跨令牌到期时间。

## 继续事项

- 真机跨实际令牌到期、长时间后台和隔夜续期尚未完成；短测只证明恢复路径。
- 通讯录部分人员显示“最近上线 01-01”，需核对实际数据是否为默认/无效时间，并统一联系人与聊天头部展示。单凭日期不能判定具体原始值，本轮未编造在线状态或修改后台数据。
- 当前工具仍缺少 Windows 电脑控制技能所需 node_repl，正在运行的最新桌面窗口对照未执行。
- 完整桌面/多移动端替换矩阵、高级 OA 分支与多人处理、推送和长期性能仍待验收，不因局部测试通过而缩小目标。
