# 680：真实媒体重试、待发摘要与断网冷启动

## 结论

**部分通过，完整移动端目标仍进行中。** 修复了待发消息没有更新会话列表摘要、时间与顺序的问题；正常 Profile 包在 M3 断网重启、联网后都保留正确的图片/视频摘要及小尺寸等待标记。图片可离线放大，视频可离线交给系统播放器打开并切换播放/暂停。

**真实图片发送、视频上传仍返回 HTTP 500，未送达对端。** 本地预览、SQLite 待发记录和自动重试不能算服务端确认，也不能据此判定媒体跨端验收通过。未修改服务端或伪造成功状态。

前一目标工作有实质进展：真实操作暴露列表缺陷，生产代码修复、红绿回归、正常包构建安装及离线验收已经完成。本次续接核对当前进程、安装哈希、原数据、真实错误界面，并补齐记录；不是仅根据计划或旧总结宣告完成。

## 环境与范围

- 时间：2026-09-03 02:37—02:57，Asia/Shanghai；消息创建时间下文按服务端/数据库 UTC 标示。模拟器状态栏时间与主机不同，未修改时钟，不由截图时钟推断跨端延迟。
- 真实项目：`E:\SecureAccess-client-source-20260824-151204\Client\Mobile`；保留已有未提交改动。
- M3：独立 `emulator-5556`，Android 16，test03。仅对 M3 安装、关闭网络和重启；未操作 M1 真机或 M2。
- D1：当前 Windows 客户端已有 test01 会话；通过现有只读核对助手访问当前测试环境。GET 200 不代替 Windows 窗口真实操作。
- API：`http://api.sfhkh.com`。不再使用已删除的旧测试环境。
- 正常入口 `lib/main.dart`，Profile APK，未装诊断入口；02:49 安装及 02:56 再核对均一致，SHA-256：`87E8ABDE54535CFD3261F0EF21D174B5CA3B7FB367341CB9A02A3B0BD3CD2901`。
- 证据：[安装核对](../test/evidence/im-media-recheck-20260903/installed-final.json)、[当前运行核对](../test/evidence/im-media-recheck-20260903/runtime-rechecked.json)。最终 Wi-Fi/移动数据均开启、存在默认网络，PID 3113；该进程日志检查未发现 Flutter 错误或 FATAL EXCEPTION，不代表全面崩溃/性能验收。

## 两条真实媒体记录

| 场景 | 真实操作与标识 | 实际结果 |
| --- | --- | --- |
| 单聊图片 | Test Terminal 01 → 附件 → 图片 → 系统选择器 Browse/Downloads → `AI-UAT-20260903-023800-image.png`，1,526,148 字节；会话 `2a2ea21f-2ad6-49b3-b3da-407d1e7e4136` | `clientMessageId=13dc7539-f758-450e-a45d-ae151c846e14`；创建 `2026-09-02T18:39:16.487691Z`；seq=0、pending，图片发送 HTTP 500 |
| 测试群视频 | `AI-UAT-20260902-202100-M1-M3-GROUP` → 附件 → 视频 → 系统 Downloads → `AI-UAT-20260903-023800-video.mp4`，23,692 字节、约 2 秒；会话 `bd15cbb6-ab8e-4cf2-9d62-fdb6f37ce90a` | `clientMessageId=4bd94d7a-d990-44d8-9b72-4edc3fc4925c`；创建 `2026-09-02T18:40:32.931022Z`；seq=0、pending，视频上传 HTTP 500 |

图片取自本次应用图标素材，仅另存为测试附件，没有替换启动图标。视频是既有测试录屏文件，播放器画面中的聊天、在线状态和时间均属于录屏内容，不是当前对端状态。

直接证据：[系统选择图片](../test/evidence/im-media-recheck-20260903/09-image-downloads.png)、[原图片失败](../test/evidence/im-media-recheck-20260903/12-image-status.png)、[系统选择视频](../test/evidence/im-media-recheck-20260903/16-video-picker.png)、[视频失败](../test/evidence/im-media-recheck-20260903/19-video-status.png)、[新包当前图片失败](../test/evidence/im-media-recheck-20260903/38-current-image-error.png)。

按实际调用代码，图片走 `POST /api/im/conversations/{conversationId}/images`，视频上传走 `POST /api/im/upload/video`。页面和持久队列核对到 HTTP 500；没有获得上传响应的请求编号及安全响应正文，因此不填造 requestId、内部异常或服务端根因。视频上传失败尚未走完后续媒体消息确认。

## P2-680-01：待发消息未反映到会话列表（已修复）

复现：选择上述文件 → 返回消息列表。聊天内已有待发气泡，但列表仍显示旧文字和旧时间；断网杀进程后依然如此。

预期：最新本地待发内容参与当前账号的列表摘要、时间与排序，显示轻量等待/失败标记；不得增加自己的未读数，也不能虚构服务端 sequence 或已发送状态。

实际原因：待发消息落在 `im_messages`/`im_outbox`，列表只读取服务端 `im_conversations` 摘要。仅在页面内临时修改摘要会在重启或服务端目录刷新时回退。

修复内容：

1. `im_local_store.dart` 在读取列表时按账号关联每个会话最新 Outbox 消息，只取所需字段、不加载媒体字节；服务端摘要字段本身不被待发内容覆盖。
2. 文字和图片、视频、语音、文件、名片生成对应摘要；固定置顶规则，按展示时间排序。单聊/群聊、静音、真实未读、`@我` 与已读序号不变。
3. 同一批离线消息部分确认时，不能用较晚的服务端确认时间遮住更晚入队的消息。用账号/会话隔离的本地确认顺序记录处理 HTTP 确认和同账号事件回声；队列清空后移除批次标记，避免 SQLite rowid 重用影响下一批。
4. `ImConversation.localPreviewStatus` 只来自本地队列，不从服务端 JSON 猜测；列表使用 12dp 等待/失败图标及 Tooltip，不增加大按钮或独立说明行。

证据对照：[修改前](../test/evidence/im-media-recheck-20260903/20-list-before-fix.png)、[修改前断网重启](../test/evidence/im-media-recheck-20260903/22-offline-list-before-fix.png)、[新包断网列表](../test/evidence/im-media-recheck-20260903/24-new-offline-list.png)、[联网稳定列表](../test/evidence/im-media-recheck-20260903/36-list-stable.png)。修复后群聊 `[视频]` 18:40 位于单聊 `[图片]` 18:39 之前，两条都有小等待标记。

## 断网、进程重启与联网补偿

1. 记录两次真实 HTTP 500 后，仅关闭 M3 Wi-Fi 和移动数据；[网络证据](../test/evidence/im-media-recheck-20260903/offline-network.json)确认无默认网络。
2. 强制停止应用并正常重开；随后保留数据安装新包、正常启动。在真实断网下验证列表、图片和视频。
3. [图片全屏](../test/evidence/im-media-recheck-20260903/34-offline-image-fullscreen.png)显示本地原图；视频气泡保留首帧，点击交给 Google Photos，观察到 [Pause/0:00/0:02](../test/evidence/im-media-recheck-20260903/29-offline-video-visible-controls.png)，点击后为 [Play/0:00/0:02](../test/evidence/im-media-recheck-20260903/30-offline-video-paused.png)。仅证明本地打开、帧解码及控制状态，不等于全片播放完成、应用内原生播放器或对端媒体加载通过。
4. 恢复 M3 网络，不点击“立即重试”。比较 [升级前队列](../test/evidence/im-media-recheck-20260903/im-before-upgrade.json)、[离线新包队列](../test/evidence/im-media-recheck-20260903/im-offline-after-upgrade.json)与 [联网队列](../test/evidence/im-media-recheck-20260903/im-direct-final.json)：原 ID 保留、attempts 从 6 增到 8，传输恢复标记解除，实际仍 HTTP 500。自动补偿发生但未发送成功。
5. 02:55 再取证，列表摘要没有回退；02:56 重新打开原图片并长按，仍明确显示 HTTP 500，未点击重试、未重复选择附件。

## 数据保留及对端核对

[逐项比较结果](../test/evidence/im-media-recheck-20260903/preservation-check.json)：

- 原 OA 2 份草稿及更新时间一致、9 条已读回执一致、待同步队列为空、OA 游标仍 449；不是仅比较条数。
- 单聊原 6 条和测试群原 11 条已确认消息的 ID、clientMessageId、sequence、发送人、类型、时间及本地状态逐项一致；分别仅新增 1 条 seq=0 的本地媒体记录。
- Outbox 恰好保留上述两个原 clientMessageId，各目标消息唯一；重启、升级及联网没有复制消息。
- M3 单聊 last/read=6/6，群聊 last/read=11/11，未读均为 0，群聊/单聊类型不变。
- IM applied/acked 从 207 到 226；新增观察到的是 seq217、226 的 `presence.changed`，不能写成“全部游标不变”或当作媒体创建事件。
- D1 在 02:55 现有会话核对 GET 200，单聊仍 6 条、群聊仍 11 条已确认消息，账本未变，两个媒体 clientMessageId 未出现。D1 自己的已读/未读属于 test01，不能与 M3/test03 混作同账号已读同步证据。

原始核对文件：[单聊当前](../test/evidence/im-media-recheck-20260903/im-direct-rechecked.json)、[群聊当前](../test/evidence/im-media-recheck-20260903/im-group-rechecked.json)、[OA 当前](../test/evidence/im-media-recheck-20260903/oa-rechecked.json)、[D1 当前只读接口](../test/evidence/im-media-recheck-20260903/desktop-rechecked.json)。只读助手复制数据库/WAL核对元数据，不直接修改数据库；日志和报告不含凭据、完整 Token、Cookie、指纹及附件地址。

## 自动回归及构建

- 新增 `test/im_pending_preview_test.dart` 17 项：账号隔离、各媒体摘要、置顶/排序、失败重试、目录刷新、更新的远端消息、确认去重、部分确认、同账号回声、队列批次清理、加密冷启动、紧凑 UI 标记及未读不混用。
- 初次测试夹具遗漏 required kind，修正后才执行有效红测；有效首次红测 1 过/12 失败。新增部分确认用例另有 14 过/1 失败，修复后通过。失败日志保留，不把编译失败记作有效缺陷复现。
- 全量首次 766 过/1 失败，定位旧加密测试仍期望服务端摘要覆盖待发正文。更新展示预期，并新增原始服务端列解密仍为原摘要的断言，保留加密前缀和禁止明文检查，未放宽安全要求。
- 最终专项 **38/38**：[日志](../test/evidence/im-media-recheck-20260903/focused-final.log)；全量 **767/767**：[日志](../test/evidence/im-media-recheck-20260903/full-verified.log)；静态分析 **0 问题**：[日志](../test/evidence/im-media-recheck-20260903/analyze-verified.log)。自动用例通过率不替代真实业务验收率。
- [正常 Profile 构建成功](../test/evidence/im-media-recheck-20260903/build-final.log)。安装已返回 Success；随后本地安装路径校验漏掉 `~` 字符造成核对脚本异常，修正校验后直接核对已安装 APK 哈希，没有重复安装或清数据。
- 本次只读桌面助手同时禁止 HTTP 重定向和带 userinfo 的地址，防止核对请求越界；实际只读核对仍为 200。

可重复执行：

```powershell
# 在上述 Mobile 目录执行；先确认设备归属及当前页面，勿在凭据页面截图。
& E:\CodexToolchains\flutter-3.47.0\bin\flutter.bat test test/im_pending_preview_test.dart test/im_local_store_test.dart test/messages_page_type_test.dart --reporter expanded
& E:\CodexToolchains\flutter-3.47.0\bin\flutter.bat analyze
py scripts/inspect-device-im-outbox.py --serial emulator-5556 --conversation-id 2a2ea21f-2ad6-49b3-b3da-407d1e7e4136 --client-message-id 13dc7539-f758-450e-a45d-ae151c846e14 --message-ledger
py scripts/inspect-device-oa-cache.py --serial emulator-5556 --account-id c404c59a-6dc3-4e6b-a1dc-d5d0c20786cc
```

## 未完成与下一步

| 优先级 | 项目 | 现状及下一步 |
| --- | --- | --- |
| P1 | 真实图片/视频上传 HTTP 500 | 原有阻塞本轮再次复现。需要结合服务端上传日志和当前协议定位根因；恢复后用原 Outbox ID 重试并核对对端到达、下载/播放、去重。不能再盲目新建一批媒体记录 |
| P1 | 群已读服务端投影及历史事件缺项 | 本轮未覆盖，不因列表显示修复而关闭 |
| P2 | P2-680-01 待发列表摘要缺失 | 本地修复、新包离线/联网验证通过；完整媒体服务确认链路仍待验收 |
| P2 | 679 前加签撤回后原任务仍 waiting；675 取消通知正文错误 | 保留服务端实际状态，本轮未处理或掩盖 |
| 待验收 | 真机/M2/Windows UI及多端矩阵 | M1接管确认尚未到达，本轮没有接管；当前无可调用的 Windows 电脑控制工具，已有会话 GET 不冒充桌面 UI；同/异平台替换、密码撤销、真实跨端已读和完整离线矩阵继续保留 |
| 待验收 | 高级 OA、原生推送和规模性能 | 金额分支/公式、会签或签、转交接收人完成、前加签回原节点、后加签完成、抄送/付款/附件等未完整验收；本轮只有少量实际消息，不宣称 2000 人群、启动和帧性能达标 |

未删除业务数据、草稿、消息或测试证据；新增媒体仍留在测试账号本地待发队列。目标未完成，也不因上传接口问题而停止其他有意义的移动端工作。
