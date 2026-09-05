# 708：首条未读定位、双向分页与真实消息回归

日期：2026-09-03。结论：真实验收发现并修复刷新跳页问题，修正后的60条剩余未读、后续分页及回执复验通过；首次失败证据保留，完整 IM/OA 目标仍未完成。

## 实现范围

- 会话存在真实未读游标时，围绕 `lastReadSequence + 1` 读取至多 80 条初始窗口，末端最多到目标后 39 条。超过一页的未读不再默认跳到最后一条。
- 复用已有 `GET messages?beforeSequence=...&take=80`，不增加后台协议。SQLite 范围读排除更新消息及 sequence0 的待发记录；缓存连续性包含删除墓碑，稀疏旧行不等于已覆盖目标区间。
- 消息实际定位完成前禁止提交已读；已删除目标定位下一条实际存在的消息。保留服务端“最高已读序号”的累计语义，不宣称每一条历史都被逐条阅读。
- 上滑接近当前窗口底部自动接续后面的未读页，保留滚动位置；向历史方向继续使用已有自动分页。显式“回到最新”可退出未读窗口。
- 迟到分页不能在返回最新后重新拉回旧窗口；同一时间只执行一个方向的分页。加载失败保留明确重试，不能以缓存为空或 bootstrap 错误推断全部已读。
- 另一端在定位期间提交已读，会更新目标；用户已经开始阅读后，另一端已读不强行改变其滚动位置。
- 新增测试抓到后台完成加载后回前台一直等待的问题：现在恢复前台/路由可见时主动恢复定位，不依赖下一次消息事件。
- 原生验收进一步发现同账号依赖刷新会暂时卸载 ListView，使恢复时误判为新进入并滚到页尾。现在仅在同账号已有数据时保留布局；换账号的异步加载仍隐藏旧消息。150ms 延迟刷新能稳定复现旧行为，修正后位置保持。

实现：`chat_page.dart`、`collaboration_repositories.dart`、`im_local_store.dart`。登录/心跳、事件落库与 ACK、后台业务数据未作协议变更。

## 本地证据

- [14 项首条未读相关 widget 场景](../test/chat_page_type_test.dart)：第 1/151 条、等待与显式返回、向后分页、跨端已读、失败重试与迟到结果、大字体不等高消息、bootstrap 失败、后台/隐藏恢复、删除序号、手机尺寸的长短消息延迟刷新、换账号不残留旧画面。
- 历史会话隔离测试由上一轮79项增至105项，增加锚定读取：账号切换、重登、退出、HTTP200/401/409/500、解码期会话变化、稀疏缓存、错误会话/序号响应、未读投影不被读取修改。
- [最终全量 1163/1163](../test/evidence/im-unread-navigation-20260903/full-reload-fixed.log)，[最终静态分析 0 问题](../test/evidence/im-unread-navigation-20260903/analyze-reload-fixed.log)。
- [后台恢复红测](../test/evidence/im-unread-navigation-20260903/visibility.log)与[修复后绿测](../test/evidence/im-unread-navigation-20260903/visibility-fixed.log)。
- [延迟刷新跳页红测](../test/evidence/im-unread-navigation-20260903/mixed-delayed.log)、[修复绿测](../test/evidence/im-unread-navigation-20260903/mixed-fixed-final.log)、[换账号隔离](../test/evidence/im-unread-navigation-20260903/account-layout.log)。
- 原聊天 Golden 保持不变；其固定预览未读数与任意合成消息不匹配，已改为明确的已读会话 fixture，未以更新图片掩盖加载错误。其他组件/分页测试同样显式区分普通消息与未读场景。

## 原生测试记录

M3=test03、M4=test04；原测试群 `AI-UAT-20260903-IM-BATCH-701` 中既有 510 条均已读。

通过[原生点击脚本](../scripts/uat-im-unread-send-708.ps1)发送 100 条唯一前缀 `AI-UAT-20260903-094154-UNREAD-` 新测试消息；M3 保持工作台，不主动进入群聊。原始点击日志位于 `test/evidence/im-unread-navigation-20260903/native-send.json`。不通过 API 发消息，不改数据库，不重跑上一轮的 510 条夹具。

第 34 条后脚本发现下一条输入未保留，立即停止，没有对第 35 条执行发送点击。[M4 画面](../test/evidence/im-unread-navigation-20260903/m4-composer-interrupted.png)显示末条 0034、空输入框；双方 SQLite 账本确认各有 544 条、M3 read510/unread34、M4 Outbox0。人工核对证据后，恢复脚本重新读取双方账本，只从未点击的第 35 条继续，并等待上一次输入框清空后才键入下一条。**这是测试驱动保护，不是应用快速输入问题已修复。**

100 条最终都真实发送并同步至双方，账本各 610 条；[接收端](../test/evidence/im-unread-navigation-20260903/m3-unread.json) read510/unread100，[发送端](../test/evidence/im-unread-navigation-20260903/m4-sent.json) read610/unread0、对方回执仍510。没有重发前34条。

### 首次原生定位失败（保留，不计为通过）

[首次截图](../test/evidence/im-unread-navigation-20260903/m3-first-unread.png)停在新增消息0030–0040，而非0001；[零次滑动记录](../test/evidence/im-unread-navigation-20260903/native-scroll.json)及[SQLite](../test/evidence/im-unread-navigation-20260903/m3-partial.json)确认 read550/unread60，对端回执550。脚本在继续滑动前停止。这说明之前1161项绿测不足以证明真实定位正确。

根因是同账号消息 revision 引起的异步 reload 卸载了列表，恢复时 `hasClients=false` 被当作接近底部。新增150ms延迟、短旧消息与长新消息、手机尺寸回归后复现并修复。没有回退服务端或本地已读，也没有重新制造原来的100条未读；复验使用剩下的真实60条。

### 修正包与首次定位复验

[最终正常入口构建](../test/evidence/im-unread-navigation-20260903/build-reload-fixed.log)及[两端实装](../test/evidence/im-unread-navigation-20260903/install-reload-fixed.json)：

`normal-708-reload-fixed.apk`，SHA256 `F18430699B1ACBEE68DF6C5952665A14DFC2BD28B4B78405432574CEF8562B47`。

M3 PID15906、M4 PID12715，保留数据安装。此前 `normal-708.apk` 和 `normal-708-final.apk` 是被替代的中间包，不是交付验证版本。既有 secure_tunnel Kotlin 插件未来迁移警告仍在，不影响本次构建。

[复验首次画面](../test/evidence/im-unread-navigation-20260903/m3-recheck-first-unread.png)：分隔线下第一条为0041，即序号551。当前可见到0051；[本地游标](../test/evidence/im-unread-navigation-20260903/m3-recheck-partial.json)只前移到561，保留49条未读；[M4回执](../test/evidence/im-unread-navigation-20260903/m4-recheck-partial.json)也为561。UI层级仍包含被裁剪的0040，原脚本的“最小层级序号必须等于首条未读”误报；实际截图和游标证据确认定位正确，之后按可见目标存在和边界核对继续，不改原截图或原始层级记录。

### 连续滑动、最终状态与数据保留

[真实滑动记录](../test/evidence/im-unread-navigation-20260903/native-recheck-scroll.json)共7次向后阅读手势，无“加载更多”点击。两次后见0062–0073，四次后见0080–0091，六次到0100，第七次确认末条完整进入可见区域。[最终接收端](../test/evidence/im-unread-navigation-20260903/m3-recheck-latest.png)与[发送端双勾](../test/evidence/im-unread-navigation-20260903/m4-final-receipts.png)已实际查看。

最终双方 `lastMessageSequence=610 / lastReadSequence=610 / unreadCount=0`，M4 对方回执610。双方各610条唯一服务端ID和clientMessageId，序号1–610连续，原510条账本未变；M3原2条媒体Outbox、2份OA草稿、10条通知已读记录保留，M4没有新增未确认Outbox。

[只读证据核对12/12](../test/evidence/im-unread-navigation-20260903/verification.json)由[核对脚本](../scripts/verify-im-unread-708.mjs)完成。这里的12/12是证据一致性检查，包含对首次失败确实保留的检查，**不是原始100条未读定位一次性通过率，更不是全部IM/OA通过率**。

[运行数据](../test/evidence/im-unread-navigation-20260903/runtime.json)：两端实际APK哈希、PID与第三版安装记录一致，采样未见 FATAL、未处理异常、RenderFlex溢出。M3首个读取窗口80条；21次读取共1580行、复用1480行、实际解码100行，最大窗口100条，而非一次拉入全部610条。该统计含后台最新窗口核对，不代表帧率、整机内存或所有渲染成本已经达标。

复验采用缓存中已同步的真实消息。缺页HTTP、安全隔离、后台恢复等边界有本地可控HTTP/SQLite/widget证据；本轮没有声称在线强制制造缺页、原生切账号竞态或重新执行完整断网矩阵。原生脚本的两次启动问题（PowerShell保留变量、带角标Tab的匹配）在进入会话前停止并已修正，不是应用业务错误。

## 新发现待处理

P2：快速连续输入时下一条草稿可能被前一次发送完成回调清空。当前 `_send` 在 await 仓库发送完成后无条件 `_controller.clear()`，与上述原生现象吻合；仍需可控延迟回归确认精确竞态并修复，不能把等待输入框清空的脚本改动当成产品修复。

## 整体未完成边界

真机仍锁屏，本轮未绕过锁屏或操作真机。已完整读取电脑控制技能入口与运行指引，并重新检索工具；当前没有其要求的 `node_repl`/`@oai/sky` 调用入口，不使用旧源码冒充最新桌面窗口。桌面端真实对照仍待执行。

快速输入草稿、长时间大群性能/增量列表、完整桌面及多移动端替换/密码矩阵、真实推送/iOS、安全存储、媒体上传500、高级 OA 金额分支/会签/或签/多人办理付款/公式附件/全状态通知仍是开放项。本轮不代表整个移动端已验收通过。
