# 672 群成员状态、可见页面刷新与最后在线缓存

日期：2026-09-03，Asia/Shanghai。上一目标轮 671 为 progress；本轮继续真实在线状态、交互与离线恢复，整体目标仍未完成。

## 当前基准和复现

- 已安装 Windows 1.0.87/test01 仍运行，受保护会话只读 IM/OA bootstrap 均 200。[核对记录](../test/evidence/member-presence-20260903/desktop-health.json)。这不是 Windows 窗口操作证据；没有用旧桌面源码代替最新客户端界面。
- M3/emulator-5556、test03 的群成员抽屉在线时显示本人在线、test01 最后在线。断网后文字均变成“状态未知”，但本人头像仍有绿色在线点。[修改前截图](../test/evidence/member-presence-20260903/05-offline-before.png)。新增用例也复现该不一致。
- 代码核对：群成员抽屉手工绘制状态点，未受传输可用性约束；通讯录每 30 秒刷新但未识别 IndexedStack 中的不可见 Tab；群详情与成员抽屉没有可见期间刷新。群在线总人数失败时被第一页成员计数替代，不能代表完整群。
- 成员模型解析 `lastSeenAt`，SQLite 的通讯录/会话成员写入与读取却遗漏该字段。成员接口写库也缺少完整会话校验，迟到响应存在污染旧缓存的风险。

## 实现

- 共用 `VisibleRefreshScheduler`：仅当前可见路由、启用的 TickerMode、前台状态执行 30 秒轮询；可见/恢复前台触发刷新；同一调度器不并发重入；隐藏、后台、销毁停止定时器。已发出的请求不伪装为取消，仍由会话校验拦截过期响应。
- 通讯录刷新成功后才显示本次在线快照，失败时保留组织/成员但状态未知；维持组织默认折叠及原有窗口加载。可见性变化不重建、清空整个通讯录。
- 群详情刷新当前成员页及群 presence，群成员抽屉只刷新当前分页；搜索/翻页重新请求对应页，不全量拉取成员。群在线总人数只取有效的群 presence，不把第一页在线人数当全群人数。
- 成员头像与文字使用同一可用状态，加载、失败或断网不继续显示旧绿点。使用现有统一头像组件，不另画独立状态点。
- 实际新包测试又发现：慢请求/依赖重算时列表被加载动画替换。[中间包截图](../test/evidence/member-presence-20260903/11-offline-new.png)。补充等待中的回归，先复现再修复：同账号保留已加载行及分页，在线标记暂未知；切换账号不复用旧行。不是仅以立即失败的单元测试代替真实网络场景。
- SQLite 13→14 为两张成员表增加可空 `last_seen_at`，统一存 UTC、读取为本地时间。已有未知值保留 null，不用当前时间补造最后在线。消息、已读、Outbox 表未改变。
- 全量成员和分页成员 GET 固定使用发起请求时的会话，写入缓存前进行原子当前会话校验；分页 provider 也随账号、设备和完整令牌变化重新加载。
- 诊断脚本新增可选 `--member-presence`，只导出限定会话最多 100 条的 ID、在线布尔值与时间，不导出头像地址、消息正文或凭据。

## 自动化

新增 19 项：最后在线缓存与版本迁移 2、可见/前后台/失败调度 3、成员接口迟到响应隔离 8、群抽屉/人数/等待请求 5、通讯录实际组件切换与失败恢复 1。

- [644/644 全量](../test/evidence/member-presence-20260903/full-final.log)，[静态检查 0](../test/evidence/member-presence-20260903/analyze-final.log)。本轮未更新 Golden。
- [首次头像问题复现](../test/evidence/member-presence-20260903/before-tests.log)；同份日志中缓存新用例先有 fixture 重复当前成员的问题，随后更正，不将该异常描述为生产缺陷。
- [等待请求修改前](../test/evidence/member-presence-20260903/pending-before.log) / [修改后](../test/evidence/member-presence-20260903/pending-final.log)：同账号保留、跨账号隔离。
- 中间测试还纠正了 UTC/本地时间断言、前台测试调度、固定在线 fixture 和测试账号选取；没有删掉失败用例或降低断言来取得通过。

## 数据核对与范围

- 正常包实际启动后 SQLite 已为 14，IM applied/acked 游标仍 207。[迁移后元数据](../test/evidence/member-presence-20260903/im-migrated.json)。
- 初始诊断沿用了旧群 ID `c4906953-10bd-4671-b984-c50ed3951349`，因此筛选后的消息明细为空；不能据此推断消息丢失，也不能以空数组比较证明完整消息不变。
- 已由本机所有会话元数据定位本轮实际群 `bd15cbb6-ab8e-4cf2-9d62-fdb6f37ce90a`，现有 11 条消息。所有会话的消息数量、最后消息/已读序号与安装前一致；这证明这些元数据不变，不是逐条正文的完整性审计。
- [纠正群 ID 后的缓存记录](../test/evidence/member-presence-20260903/im-corrected-group.json) 已保存真实最后在线时间。记录同时显示通讯录旧快照 test01 在线、更新的群成员快照离线，采样时间不同；本轮不能宣称已经解决所有来源的全局新鲜度。
- 仅操作独立 M3；M1 真机与 M2 未点击、未安装，没有创建业务消息或审批。

## 最终正常包实测

- 正常 `lib/main.dart`、Profile、arm64+x64，最终构建 54.7 秒；安装包与设备 base.apk 哈希一致：`CF8BA9AEE52E551064F6EB0A2C113B3549844593DE1053CD14321B4C4C4C85DB`。[安装记录](../test/evidence/member-presence-20260903/installed-final.json)。未保留诊断入口运行。
- 00:33:10 关闭 M3 网络，00:34:04 截图仍保留两位成员、姓名、头像、部门、角色及“共 2 人 / 1 / 1”分页；双方状态未知、均无在线点，没有以加载动画替换列表。[最终断网截图](../test/evidence/member-presence-20260903/18-final-offline.png) / [XML](../test/evidence/member-presence-20260903/18-final-offline.xml)。与修改前“未知 + 绿点”和中间包大面积加载动画分别对照，不只看代码通过。
- 00:34:04 恢复网络，没有点击刷新，00:34:32 已自动恢复本人在线、test01 最近上线；28 秒为观察检查点上界，不声称即时恢复。[恢复截图](../test/evidence/member-presence-20260903/19-final-recovered.png)。
- 返回通讯录，组织仍默认折叠；展开“其他联系人”才显示人员，test01 的最后在线与群成员一致，无账号副标题。[默认折叠](../test/evidence/member-presence-20260903/21-contacts.png) / [展开](../test/evidence/member-presence-20260903/22-contacts-expanded.png)。本次进入页面刷新后对齐，不等于已解决跨来源陈旧缓存。
- [最终核对](../test/evidence/member-presence-20260903/final-verification.json)：安装前后所有会话元数据、IM 游标及 Outbox 不变，纠正群 ID 后的 11 条消息账本亦不变；两条 OA 草稿、已读回执、Outbox、游标 355 不变。00:38 核实 M3 进程运行、WiFi/数据均为 1，当前进程采样 64 行日志中 FATAL EXCEPTION 与 E/flutter 均为 0；这不是无限时长无崩溃证明。

## 待继续

- 统一通讯录、单聊与群成员的有时效状态来源；采样较旧的通讯录数据不应覆盖更新的成员观察。未打开页面的全局状态刷新还需完善。
- 明确、紧凑的断网/重连反馈；大群真实分页与性能；自然会话到期；M1 新包、D2/M2 替换；高级 OA 分支、会签/或签、通知/推送以及服务端遗留问题均未判通过。
