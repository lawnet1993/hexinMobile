# 706：历史消息解码复用与真实运行回归

日期：2026-09-03；本轮完成缓存性能专项，完整 IM/OA 对齐目标仍未完成。

## 结论

已将未变化的 SQLite 消息行解码结果做有界复用，保留每次 SQLite 最新状态查询。正常入口 Profile 包已保留数据安装到 M3/test03、M4/test04；两端仍在原账号中运行。M3 原生从最新第 510 条连续上滑到第 1 条，再三次返回重开，均正常显示最新消息。

原生观测共 19 次消息查询、2980 次行读取，其中 2470 次复用解码结果、510 次实际行解码；最后一个 510 条窗口全部命中。该数据不是整页帧率、内存 MB 或 UI 提速百分比，也不能证明每个消息 ID 的逐条解码次数（日志刻意不记录身份）。后续仍需处理 SQL/窗口重组与绘制成本。

## 修复与安全边界

- [解码缓存](../lib/features/collaboration/data/im_decoded_message_cache.dart)按账号、会话、消息 ID 区分，只在**新 SQLite 查询返回的全部字段完全相同**时复用；不仅比较 updated_at，还比较密文、撤回/发送状态、附件、回复、提及以及 SQL 计算的 recipient_read。
- 默认上限 4096 条、原始行字符串累计 2 Mi 字符，按最近使用淘汰。字符数不是实际堆内存；超预算单行正常解码但不保留，不截断活动历史。
- 同行并发只执行一次解码，失败不缓存；旧失败不会删掉后来的新结果。账号切换、退出、关闭清理缓存并推进代次，清理前的迟到查询/解码不重新填入缓存。
- [存储入口](../lib/features/collaboration/data/im_local_store.dart)继续使用 canonical SQLite 查询/墓碑过滤/相邻序列连续性与原排序；仅复用解析对象。模型内 images、attachments、mentions 改成不可变列表，调用方仍得到独立的外层消息列表。
- 测试发现 Riverpod 的 store 仅被 ref.read 持有时，普通 ref.listen 可随提供器暂停，导致账号变化未及时清除缓存。已改成随 store 生命周期关闭的 container 订阅；无 UI 监听的真实默认提供器测试覆盖账号切换与退出。
- Profile 诊断只记录 rows/cacheHits/durationMicros 三个数，每个 store 最多 80 条；release 不注入回调。读取脚本只白名单保存这三个字段，不保存原始日志、正文、密钥、令牌、设备指纹或附件地址。

没有修改在线数据库、消息协议、已读业务规则、群聊/单聊边界或 OA 流程；本轮没有发送新的业务消息，没有删除、重试或覆盖原媒体待发送记录。

## 本地回归

[11 项专项测试](../test/im_decoded_message_cache_test.dart)覆盖：扩展窗口不重复解密；同时间戳编辑/撤回/删除；真实 SQLite 收件人已读投影；附件/提及/回复与不可变列表；跨账号密文和篡改验证失败后可恢复；环境/存储实例隔离；并发、全字段比较、LRU/字符预算、超大行、清理/迟到查询、错误恢复与生产提供器退出清理。

- [最初性能红测](../test/evidence/im-row-decode-20260903/red.log)：应保留 640 次受保护字段解密，旧实现扩展后为 1280 次。
- [扩展测试首轮](../test/evidence/im-row-decode-20260903/safety-tests.log)：UTC/本地 DateTime 比较方式及 FFI 默认 factory 初始化问题，修正测试基础设施；未把这两项计为应用缺陷。
- [实际生命周期红测](../test/evidence/im-row-decode-20260903/safety-tests-final.log)：退出后应保留 0，实际 1，修复订阅暂停问题后通过。
- [最终源码专项 11/11](../test/evidence/im-row-decode-20260903/safety-tests-source-final.log)。
- [最终源码全量 1044/1044](../test/evidence/im-row-decode-20260903/full-test-final.log)，前后两轮均通过。
- [静态检查 0 问题](../test/evidence/im-row-decode-20260903/analyze-final.log)。
- [构建成功](../test/evidence/im-row-decode-20260903/build.log)，正常 lib/main.dart、profile、arm64+x64。既有 secure_tunnel 的未来 Kotlin 插件迁移警告仍待单独处理。

## 原生证据

[两端安装记录](../test/evidence/im-row-decode-20260903/install.json)：实际 base.apk SHA256 均为

`778C86DA25C73D4E1E6115AEF6279D2BEAEA36989C323ED0212F747707B70A24`

保留包：`test/evidence/im-row-decode-20260903/normal-706.apk`。整个原生回归中 M3 PID1329、M4 PID26400 未变。安装后工作台仍显示原测试账号，不是登录页；原 UI 登录检测辅助器在聊天页面返回 loggedIn=false、loginScreen=false，不能据此认定掉线，以实际工作台和会话为准。

1. M3 工作台→消息→既有 `AI-UAT-20260903-IM-BATCH-701` 群；[同向 24 次原生手势到第 1 条](../test/evidence/im-row-decode-20260903/native-history.json)，无需“加载更多”点击。[首条截图](../test/evidence/im-row-decode-20260903/m3-history-06.png)可见首条头像、姓名及合并后的后续消息。
2. [19 条解码诊断](../test/evidence/im-row-decode-20260903/m3-expanded-decode.json)没有拒绝字段，远未达到 80 条上限。扩展窗口 160/240/320/400/480/510 均有缓存命中，其中 320/480 各解码 80 条新行，不能宣称每次扩展都零解码。最后 510 行/510 命中，含 SQL/排队/取行/排序的观察耗时 24.372ms；非单独解密耗时，不做跨版本等条件 A/B 延迟结论。
3. 三次[重开 1](../test/evidence/im-row-decode-20260903/m3-hot-1.png)、[重开 2](../test/evidence/im-row-decode-20260903/m3-hot-2.png)、[重开 3](../test/evidence/im-row-decode-20260903/m3-hot-3.png)均可见最新 510。诊断数为 21/22/22，新增加的 50 行状态核对均全部命中；没有重新解码，也没有重新查询完整 510 条窗口。不能说完全没有查询或 UI 重绘。
4. [M4 最新消息与双勾](../test/evidence/im-row-decode-20260903/m4-group-latest.png)、[M4 解码复用](../test/evidence/im-row-decode-20260903/m4-latest-decode.json)正常。
5. [12/12 保存证据核对](../test/evidence/im-row-decode-20260903/verification.json)，由[只读核对脚本](../scripts/verify-im-row-decode-706.mjs)实际执行：双方 510 条唯一消息账本、会话元数据/成员/read510/unread0/对方已读投影不变；M3 原 2 条媒体 Outbox、2 份 OA 草稿、10 条通知回执保留。没有新建或重发业务数据。
6. [运行检查](../test/evidence/im-row-decode-20260903/runtime.json)没有观察到 FATAL、未处理异常、RenderFlex 溢出或旧观察入口标记；两端 Wi-Fi/数据仍为原 1/1。本轮未切断网络，不以本次结果代替断网冷启动或断网新消息矩阵。

## 仍未完成

[真机现状](../test/evidence/im-row-decode-20260903/physical-device-state.json)为已授权但锁屏/inputRestricted，本轮未安装或操作。当前可调用工具仍无 Windows UI 控制接口，不能把模拟器或只读服务端核对当成桌面窗口验收。

继续处理：滚动锚点与增量窗口读取、首条未读定位、持续帧率/长时间内存与真机触摸延迟；完整桌面/多移动端/密码会话矩阵；真实推送配置与到达、iOS 安全存储；媒体上传 500；高级 OA 条件分支、会签/或签、多人办理付款、公式附件及状态通知全过程。目标保持活动，本专项通过不等于整体验收通过。
