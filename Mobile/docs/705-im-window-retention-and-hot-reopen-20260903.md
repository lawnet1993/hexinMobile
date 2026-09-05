# 705：历史窗口重复缓存与热重开回归

日期：2026-09-03，Asia/Shanghai。结论：重复历史窗口缓存已修复，正常包已在M3/M4保留数据安装并回归；完整IM/OA和整体性能仍未全部验收。

## 当前证据与问题

承接704已通过的510条消息、真实500+10事件页及顶部上滑专项，本轮进一步检查长历史资源占用。旧 `conversationMessageWindowProvider` 按 `(conversationId, take)` 分别保留30分钟，分页产生80、160、240、320、400、480、510七份重叠列表，离开页面后仍全部保留。

[有效红测](../test/evidence/im-window-retention-20260903/red-confirmed.log) 用真实Riverpod容器逐页打开/关闭，预期只保留510，实际七个provider全部存在，共2190个列表条目。这是列表条目数，不是唯一消息数、实际堆大小或进程内存。初版测试遗漏必需createdAt而未编译，修正后才得到上述有效红测；原日志保留，不能把编译失败当作缺陷复现。

## 实际修改

[窗口保留策略](../lib/features/collaboration/data/im_message_window_retention.dart) 与 [provider接入](../lib/features/collaboration/data/collaboration_repositories.dart)：

- 同一会话新窗口替代旧窗口的keep-alive，只缓存最近使用的一份；实际仍有订阅的页面继续保有数据，不强制销毁正在阅读的内容。
- LRU最多32个保留窗口、合计4096个缓存消息条目。超预算释放keep-alive，不删除SQLite，不截断当前历史。超大窗口离开后可能重新读取，这是有限缓存的明确代价。
- 无人订阅时才计30分钟过期；恢复订阅取消计时并更新LRU。
- 失败窗口不保留错误，重新进入可重试；旧请求迟到不能替换新窗口，释放/过期幂等。
- 账号变化清空保留策略；[聊天窗口范围记忆](../lib/features/messages/presentation/chat_page.dart) 同时按账号重建，避免另一个账号继承已加载条数/历史耗尽标记。
- Profile诊断仅记录窗口数、消息条目数，每个账号缓存实例最多80条，不包含账号/设备标识、正文、附件地址或令牌；release没有该诊断回调。

没有修改消息业务协议、已读提交、单聊/群聊判定、在线状态、后台流程或服务端数据。

## 本地验证

[8项新增测试](../test/im_message_window_retention_test.dart)：510条分页只保留最新、热重开与会话更新；仍被监听的旧窗口安全；LRU；消息预算且5000条活动历史不被截断；旧加载迟到；失败重试；账号变化与范围记忆；闲置TTL/恢复/幂等释放。

- [首次相关回归78/78](../test/evidence/im-window-retention-20260903/targeted-first.log)，含原聊天类型、历史、已读显示及同步精确失效测试。
- [最终源码8/8](../test/evidence/im-window-retention-20260903/retention-final-source.log)。中间扩展测试时导入语句插入位置错误，已修正；对应失败日志保留，不计业务失败。
- [全量1033/1033](../test/evidence/im-window-retention-20260903/full-test.log)。
- [静态检查0问题](../test/evidence/im-window-retention-20260903/analyze-final.log)。首次仅一处集合字面量风格提示，修正并重新构建、复测专项。
- [最终正常入口构建](../test/evidence/im-window-retention-20260903/build-final.log)：profile、arm64+x64、lib/main.dart。既有secure_tunnel未来Kotlin迁移警告仍存在。

## 真实模拟器验证

M3为emulator-5556/test03，M4为emulator-5558/test04。两端 [实际安装与进程](../test/evidence/im-window-retention-20260903/install.json) 的base.apk哈希均为：

`11D2DFD5F714D8E48C717ADC229A4A70A48884D40EA5E0A93AB437AD2061D251`

正常包位于 `test/evidence/im-window-retention-20260903/normal-705.apk`，不是独立观察入口。M3 PID29648、M4 PID23636在整个验收中未变化；保留数据安装，没有清空、卸载或切换测试账号。

使用既有两人测试群 `AI-UAT-20260903-IM-BATCH-701`，本轮没有新增或重发业务消息。工作台→消息→该群→连续上滑，[24次同向手势到第1条](../test/evidence/im-window-retention-20260903/native-history.json)，[第1条截图](../test/evidence/im-window-retention-20260903/m3-history-06.png)。原生脚本正确处理首条消息与姓名/日期合并后的多行语义标签，没有复用704的错误行首解析。

[原生缓存记录](../test/evidence/im-window-retention-20260903/m3-expanded-cache.json) 共20条、无拒绝字段：有效加载条目数依次80/160/240/320/400/480/510，保留窗口数始终不超过1，最后为1份510条，不是七份2190条。旧数值来自受控红测，新策略同时有本地测试与原生观测；没有做新旧APK的等条件堆内存A/B测量，不能换算为MB或整体内存下降百分比。

返回消息列表后连续3次重开，均实际显示最新510：

- [第1次界面](../test/evidence/im-window-retention-20260903/m3-hot-1.png) / [缓存记录](../test/evidence/im-window-retention-20260903/m3-hot-cache-1.json)。
- [第2次界面](../test/evidence/im-window-retention-20260903/m3-hot-2.png) / [缓存记录](../test/evidence/im-window-retention-20260903/m3-hot-cache-2.json)。
- [第3次界面](../test/evidence/im-window-retention-20260903/m3-hot-3.png) / [缓存记录](../test/evidence/im-window-retention-20260903/m3-hot-cache-3.json)。

三次均为同PID、相同20条诊断记录、同一510条窗口，远未到80条采样上限，因此不是日志限额掩盖后续重建。没有新窗口获取/加载记录；新路由仍正常构建可见Flutter控件，不声称完全不绘制UI。[M4最新消息及双勾](../test/evidence/im-window-retention-20260903/m4-group-latest.png) 也正常，M4当前只保留一份80条窗口。

[最终只读核对11/11](../test/evidence/im-window-retention-20260903/verification.json)，由 [证据核对脚本](../scripts/verify-im-window-retention-705.mjs) 实际执行：两端完整510条账本、会话状态、read510/unread0、对方阅读回执与原会话均同升级前；M3原2媒体Outbox未删除，2份OA草稿/10条通知回执保留。当前进程日志白名单未见FATAL、未处理异常、RenderFlex溢出或701观察入口标记。网络设置保持原1/1。

## 未完成项与下一步

本轮真机只读核对ADB可用但锁屏（showing/inputRestricted为true），没有操作或安装；Windows控制工具仍未提供可调用接口，未把后台数据当桌面窗口实测。仍需真机、Windows真实窗口与完整多端矩阵。

本轮解决的是重复保留，不是所有分页CPU成本：每次扩展目前仍重新读取/解密更大的窗口；应继续检查增量窗口与滚动锚点，避免长历史扩展重复处理旧消息。未提供触摸延迟/持续帧率或长期泄漏结论，5000条仅是本地订阅安全用例，不是线上5000条原生验收。

首条未读定位、真实推送、上传500、高级OA条件/会签/或签/办理付款/公式附件/通知状态等继续开放。完整目标保持活动，不以此次缓存专项替代剩余验收。
