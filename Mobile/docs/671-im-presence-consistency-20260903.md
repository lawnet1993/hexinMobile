# 671 消息列表与聊天页在线状态一致性

日期：2026-09-02 至 2026-09-03，Asia/Shanghai。本轮为 progress：延续 670 发现的真实状态冲突，完成定位、实现和正常包验证。整体 IM/OA 对齐目标未完成。

## 根因证据

- 670 正常包中，同一 test01 会话的消息列表显示在线，聊天页显示离线，返回列表又显示在线。见 [670 列表](../test/evidence/session-protocol-20260902/04-messages.xml)、[670 聊天页](../test/evidence/session-protocol-20260902/05-chat.xml)、[670 返回列表](../test/evidence/session-protocol-20260902/08-list-return.xml)。
- 671 在独立 M3、test03 的同一个受保护会话中进行只读 GET：IM bootstrap、会话 members、presence 及重复 presence 都为 200，目标 test01 均离线，最后在线均为 `2026-09-02T15:55:01.926903Z`。[脱敏结果](../test/evidence/im-presence-consistency-20260902/real-presence-before.log)。
- 列表优先采用 SQLite 中非空即返回的旧会话成员缓存，没有使用较新的通讯录状态；聊天页独立请求 presence，结果没有与列表共享。不是同一次查询得到两种服务端状态。

## 实现与边界

- 列表、聊天页复用 `resolveDirectPeerPresence`：同 ID 通讯录成员优先于旧会话成员；最新会话 presence 优先于成员缓存。语义标签和头像标记使用同一个结果。
- presence 观察按会话共享，最多保留 128 项，60 秒没有新观察即转为未知；断网时同样不宣称在线。旧服务器时间不能覆盖较新的观察。此处是短期内存状态，不是消息/游标持久化替代品。
- 状态按当前账号、设备和完整会话隔离。请求使用捕获会话，响应落入共享状态前校验当前会话；切换账号、重新登录、退出后的迟到响应不会污染新会话，也不会以旧请求标记新会话断网。
- 沿用聊天页既有 presence 刷新，没有给列表每行添加网络请求。定向测试明确断言列表没有启动 presence GET。
- 未修改服务端、数据库表结构、消息已读协议、Outbox 或业务数据。

## 自动化与截图基线

- 新增 11 项：旧缓存冲突、共享状态与过期、乱序/旧会话、内存上限、单群聊边界、退出/换号/同账号重登迟到响应，以及响应会话 ID/类型校验。
- [64/64 定向](../test/evidence/im-presence-consistency-20260902/targeted-final.log)，[625/625 全量](../test/evidence/im-presence-consistency-20260902/full-final.log)，[分析 0 问题](../test/evidence/im-presence-consistency-20260902/analyze-final.log)。
- 初次全量失败两项：新增 Widget 测试的外置容器定时器未在测试结束前清理，已修正测试收尾；群详情 Golden 有 383 像素差异，核对为三个成员的在线标记。
- 群详情旧 Golden 文本为“3 位成员 · 3 人在线”，头像无在线标记。测试此前未隔离真实 presence 请求与传输状态；本轮明确提供固定 presence/在线 fixture，增加文字与三个头像状态一致性断言，仅更新 `12-group-detail.png`。没有批量重录其他基线，也不将 Golden 当作真实服务端状态证据。

## M3 正常版本

- Profile、正常 `lib/main.dart`、arm64+x64，构建 51.9 秒；已覆盖安装到独立 `emulator-5556`，不包含诊断入口启动行为。
- APK 与已安装 base.apk 的 SHA-256 相同：`CA089C53D1E703575A089CB66ADF543D0F82467A352DA8BFD3488A1DF87B15FA`。
- 00:11 列表→同一单聊→返回列表：全部离线，最后在线 09-02 15:55，截图头像均为灰色标记；群聊仍标为群聊。见 [列表](../test/evidence/im-presence-consistency-20260902/02-list.png)、[聊天页](../test/evidence/im-presence-consistency-20260902/03-chat.png)、[返回列表](../test/evidence/im-presence-consistency-20260902/04-return.png) 及同名 XML。
- M1 真机、M2 未点击、未安装；本轮没有 Windows 窗口操作证据。

## 过期、断网与恢复实测

- 离开聊天页超过 60 秒后，00:12:29 列表语义变为“单聊，状态未知”，在线标记消失，没有回到旧缓存在线。[过期截图](../test/evidence/im-presence-consistency-20260902/05-expiry.png) / [XML](../test/evidence/im-presence-consistency-20260902/05-expiry.xml)。
- 仅关闭 M3 的 Wi-Fi/移动数据，再进入相同聊天：显示“最后在线 09-02 15:55”，已加载的六条消息与头像仍可见，无失效弹窗、无跳转登录；返回列表仍为状态未知。[断网聊天](../test/evidence/im-presence-consistency-20260902/07-offline.png) / [断网列表](../test/evidence/im-presence-consistency-20260902/08-offline-list.xml)。
- 00:13:29 恢复原 Wi-Fi/移动数据后进入会话；00:13:42 仍为最后在线，00:14:07 已重新显示“离线 · 09-02 15:55”，返回列表也为离线。本次恢复观察上界约 38 秒，不能称为瞬时恢复。[恢复聊天](../test/evidence/im-presence-consistency-20260902/10-recovered-final.png) / [最终列表](../test/evidence/im-presence-consistency-20260902/11-final-list.xml)。
- [本地数据前后比较](../test/evidence/im-presence-consistency-20260902/cache-comparison.json)：消息 ID/序号、IM 应用/ACK 游标 207、会话投影、IM/OA Outbox、两个草稿 ID/修改时间、OA 游标 355 和已读回执均未变化。未新增消息或审批。
- 最终正常包保持运行、网络恢复；[限定当前进程的日志核对](../test/evidence/im-presence-consistency-20260902/final-runtime.json) 未发现 Flutter 错误、崩溃或会话失效事件。仅检查观察窗口，不能代替长稳测试。
- [17/17 截图与状态定向复验](../test/evidence/im-presence-consistency-20260902/golden-final.log)，随后包含新增断言的全量再次 625/625、静态检查 0。

## 尚未完成

- 这次只证明该真实单聊冲突已消除，不能据此判定全部在线状态通过。未打开会话的通讯录状态仍缺少完整新鲜度管理；成员缓存的最后在线时间持久化、群详情/群成员状态刷新需要继续处理。
- 断网期间列表/聊天截图未出现专门的连接提示条；目前只有在线状态退为未知/最后在线，连接反馈是否足够明确需要继续核对。未将本次无崩溃当作完整断网体验通过。
- 自然到期续期尚未实测；D2/M2 替换矩阵、真机新包、多分支/会签/或签 OA、推送和大规模性能仍保留。已发现的服务端群消息/已读和附件问题没有被本轮客户端调整掩盖或判通过。
