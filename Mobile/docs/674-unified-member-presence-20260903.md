# 674 统一人员在线状态与快照时效

日期：2026-09-03，Asia/Shanghai。上一轮 673 有实际修复、回归和安装证据，判定 progress；本轮继续真实在线状态的一致性，整体目标仍未完成。

## 问题与实施范围

672 的实际 SQLite 记录曾同时存在“旧通讯录在线、新群成员离线”；固定优先某张表并不能保证新鲜度。673 完成了隐藏页面的轮询与已读保护，但各页面仍直接使用自己的成员布尔值，冷启动亦可能把旧缓存显示成当前在线。

本轮新增按人员 ID 共享的 `ImMemberPresenceProjection`，仅保存短期状态，不替代 SQLite 的账号、姓名、头像、角色或最后在线历史：

- 所有请求在发起时取得递增序号。成员页、通讯录和单聊状态按这个序号更新同一人员，迟到的旧响应不覆盖后发请求。`lastSeenAt` 是服务端活动时间，不能用来给两条“离线”观察排序；该历史值只保留已知较新值，不合成当前时间。
- 60 秒有效期从请求发起计时，慢响应不能得到新的完整 60 秒。过期、缺字段、无当前在线证据或断网均显示未知；已登录并不意味着缓存中的每个人仍在线。
- 按当前账号/设备/完整访问会话隔离，重登录、退出和访问令牌变更后清空；旧请求不能重新填充下一会话。
- 最多 2048 人员和 128 批请求；每批一个定时器，不是每人定时器或每行 HTTP 请求。展示通过状态选择器订阅，姓名、头像、聊天正文不随状态重新拉取。
- 接入普通/事件 bootstrap、完整与分页成员、单聊 presence、账号搜索、群管理员及禁言成员查询。接受结果时校验请求会话；bootstrap 调用方原有迟到事件丢弃语义保持。
- 单聊 presence 只有在本地成员身份能唯一定位对方、且包含当前本人时才写入人员状态；群在线总数不映射为任何一个人的状态，身份不明确时不猜测。
- 通讯录、会话列表、聊天头部、个人资料、群详情/成员抽屉、选人页、批量接收人、“我的”和账户状态改用统一来源。缓存本身仍可展示姓名/头像/最后在线，但旧在线布尔值不作为实时证据。预览模式和视觉夹具显式提供预览状态，不对真实环境放宽。
- 缺少或无效的 `isOnline`/`peerOnline` 字段保留“未知”，不再因默认 false 伪装离线。本轮没有修改数据库结构或发送/ACK/Outbox 协议。

## 自动化证据

新增 23 项：状态层 10、真实本地 HTTP 与 SQLite 仓库 12、实际页面跨列表/通讯录 1。

- [状态与仓库 22 项](../test/evidence/unified-member-presence-20260903/core-final.log)：迟到 bootstrap 在 SQLite 中仍可能留下旧字段，但不能覆盖共享的较新成员观察；分别覆盖完整和分页接口、单聊与群边界、模糊成员身份、账号搜索、管理员/禁言成员、迟到会话结果。
- 页面测试从真实 `MessagesPage` 切换至 `ContactsPage`，旧数据不变而共享人员状态改变，验证离线→在线→过期未知，并断言会话 presence 的逐行 HTTP 请求数为 0。其首次失败是未知人数计数包含当前本人，随后将断言限定到目标人员行，不削弱状态断言。
- [最终全量 672/672](../test/evidence/unified-member-presence-20260903/full-final.log)，[静态检查 0](../test/evidence/unified-member-presence-20260903/analyze-final.log)，差异空白检查 0。
- [首次全量](../test/evidence/unified-member-presence-20260903/full-first.log) 的 16 项失败已逐项处理：视觉/页面测试补显式已确认状态样本，冷缓存测试现在要求未知；新 bootstrap 观察不能改变原来两项旧会话事件丢弃行为，已恢复该控制流并复验。**没有更新任何 Golden 图来吸收差异。**

## 正常包与真实页面

标准 `lib/main.dart` Profile arm64+x64 构建 55.3 秒，仅安装 M3/emulator-5556/test03；设备 base.apk 与本地产物哈希一致：`AD0B64E93A90EA378959043026943D011264EBD5439359FA98C279E51CBCEA86`。[安装记录](../test/evidence/unified-member-presence-20260903/installed.json)。未启用诊断入口，没有替换用户另行索取的应用图标。

- 通讯录仍默认只展示折叠组织，展开后 test01 显示最近上线 16:24；消息列表为对方离线，单聊头部为离线及相同最后在线时间。[组织](../test/evidence/unified-member-presence-20260903/02-contacts.png) / [人员](../test/evidence/unified-member-presence-20260903/03-contact-expanded.png) / [列表](../test/evidence/unified-member-presence-20260903/04-list.png) / [单聊](../test/evidence/unified-member-presence-20260903/05-direct.png)。手机显示时间与 Windows 时区不同，截图中的 16:24 为设备当前格式，不修改设备时区。
- 群成员抽屉本人在线、test01 最近上线 16:24，与上述身份和状态一致；成员数/分页和群主角色正常。[群成员](../test/evidence/unified-member-presence-20260903/08-members-online.png)。
- 00:59:48 仅关闭 M3 WiFi 和移动数据，[断网开始](../test/evidence/unified-member-presence-20260903/offline-start.json)。成员行、头像和分页保留，两人均显示状态未知、无绿点：[断网截图](../test/evidence/unified-member-presence-20260903/09-members-offline.png)。01:00:35 恢复网络后没有点击刷新；01:02:52 检查时已自动恢复本人在线、对方最后在线：[恢复截图](../test/evidence/unified-member-presence-20260903/10-members-recovered.png) / [网络恢复时间](../test/evidence/unified-member-presence-20260903/network-restored.json)。这是检查点前已恢复的证据，不是精确恢复耗时。

## 数据与运行收尾

对比 673 收尾元数据，群消息 11 条、单聊 6 条，消息标识与序号不变，已读均追平且未读为 0；IM applied/acked 仍为 207，Outbox 为空。OA 两份草稿的 ID 和修改时间、两条已发送已读回执、游标 355 和空 Outbox 均未变。[逐项对比](../test/evidence/unified-member-presence-20260903/data-comparison.json) / [IM 元数据](../test/evidence/unified-member-presence-20260903/im-after.json) / [OA 元数据](../test/evidence/unified-member-presence-20260903/oa-after.json)。状态与目录刷新时间允许前进，不把正常刷新误判业务数据变化。

最终网络 WiFi/移动数据均开启，当前应用进程运行；采样最近 2000 条该进程日志，FATAL EXCEPTION 与 E/flutter 计数均为 0，仅输出计数，不保存原始日志。[运行记录](../test/evidence/unified-member-presence-20260903/runtime-final.json)。

## 未完成与边界

上述线上样本验证当前页面一致，并不是刻意制造服务端相互矛盾的响应；跨来源乱序竞争的精确证据来自实际本地 HTTP/SQLite 回归。在线证据是服务器返回的短期观察，不代表绕过服务器可以独立判断对方网络。

本轮没有发送消息/提交审批，没有操作 M1/M2；Windows 客户端进程仍运行，当前工具仍没有可调用的 Windows 桌面控制工具，未用旧源码代替桌面窗口验收。真实跨端未读、自然会话到期、手机新版、D2/M2 替换、高级 OA 分支/会签/或签、通知推送、群读/事件/媒体服务端问题和大群性能仍未整体通过。统一来源解决了页面各用旧标记的结构问题，但不意味着这些剩余项目或全量真实在线矩阵已经验收通过。
