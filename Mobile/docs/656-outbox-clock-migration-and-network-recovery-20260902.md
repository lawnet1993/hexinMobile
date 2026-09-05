# Outbox 时钟排序、升级保留与真实断网恢复

时间：2026-09-02 20:40–20:53，Asia/Shanghai。结论：**部分通过**；发送 FIFO 与旧库升级验证通过，发现未打开会话却清未读的 P1，不能判定 IM 验收通过。

## 代码与本地验证

上轮偶发失败已确定为时间字符串排序缺陷：Dart ISO 输出的毫秒值 `.123Z` 按字符串排序晚于 `.123001Z`，使立即查询漏掉新入队项，也可能将后入队消息排在前面。新增可注入时钟，以固定微秒重现，不靠延时或重跑掩盖。

- 所有 Outbox 创建/到期时间统一 UTC、六位小数；数据库版本 12→13，仅规范队列调度时间，保留 clientMessageId、正文、附件、重试次数和账号隔离。旧时间非法时不破坏原值。
- 新增四项时钟/迁移测试，修复前四项实际失败，修复后通过；未删旧测试或放宽 FIFO 规则。
- 网络接口恢复只作为唤醒信号，取消旧长轮询、立即校对会话；接着先零等待拉事件再补正文。接口在线不等于服务健康，不据此退出登录或标记消息已读。
- 新增真实本地 HTTP 服务的网络恢复测试：被挂起的 25 秒轮询取消后，先零等待拉取再将正文落 SQLite；重复网络通知不重复校对，停止后取消订阅。
- 全量 **411/411**，[测试日志](../test/evidence/im-outbox-recovery-20260902/full-tests.log)；[静态分析](../test/evidence/im-outbox-recovery-20260902/analyze-final.log) 0 问题，`git diff --check` 通过。未更新 golden。

## 安装与边界

正常入口 `lib/main.dart`，Profile 1.0.1+2，arm64+x64；82,610,499 字节；SHA256 `A385266CA890D71E76F81BBF3AE7767B165C9673FA66D1A451C5AB9D31B75783`。[构建日志](../test/evidence/im-outbox-recovery-20260902/build.log)。

M1 真机 test01 与 M3 独立模拟器 test03 均覆盖安装，base.apk 哈希一致；冷启动分别 1267 ms / 7985 ms，模拟器离线软件渲染值不能用作性能合格依据。M2 未操作；M1 热点/网络未改；M3 最终 Wi-Fi=1、数据=1、默认网络 108。无远端数据库/源代码修改，不删除已有业务或失败上传。

## 真实操作与消息账本

沿用仅两名测试成员的群 `AI-UAT-20260902-202100-M1-M3-GROUP`，ID `bd15cbb6-ab8e-4cf2-9d62-fdb6f37ce90a`。M3 屏幕时间为 UTC，比北京时间少 8 小时。

1. 在旧 v12 包的 M3 群页真正断网（默认网络 none），通过输入框发送两条，再强制停止应用。
2. 离线覆盖安装 v13 并冷启动。仍保留 test03、两条原 clientMessageId、原排队次序；没有清库或重新发送。
3. M1 通过 UI 发来一条新消息。20:50:00.721 恢复 M3 网络，M3 停留首页，未打开群、未下拉、未手动重试。
4. 20:50:12.088 检查，收到 seq5，read=4/unread=1，两条待发仍在。约 12 秒是检查点上界，不是精确延迟测量。
5. 20:51:01 两条自动按序确认，原 clientMessageId 不变、临时行被替换、Outbox 清空。两端最终各 7 条，服务端 ID、客户端 ID、发送者和序号一致，无重复。

| seq | 场景 / 文本后缀 | clientMessageId | 服务端 ID | 服务端北京时间 |
| --- | --- | --- | --- | --- |
| 5 | M1 新来消息 `205000-RECOVERY-INCOMING` | e323dd11-0997-4b6b-8782-39cba7aa3170 | 65186481-dfcb-4b8a-8ebc-498896a62e77 | 20:50:01.717795 |
| 6 | M3 离线 `204800-OUTBOX-GROUP-01` | 48418c87-4707-427d-995a-6b06a59de8f2 | 4bf08d16-2698-49d0-8c71-23f8b34d5ecf | 20:51:01.495451 |
| 7 | M3 离线 `204800-OUTBOX-GROUP-02` | e13817e4-0e40-44c3-8152-8e89203a0820 | 7f973268-cb70-4a45-b4db-4c192cdfa2c1 | 20:51:01.704060 |

完整文本统一 `AI-UAT-20260902-` 前缀。seq1–4 见 655 报告。

证据：[旧队列](../test/evidence/im-outbox-recovery-20260902/02-before-version-12.json)、[升级后](../test/evidence/im-outbox-recovery-20260902/03-after-version-13-offline.json)、[首次恢复](../test/evidence/im-outbox-recovery-20260902/05-first-reconnected.json)、[首页未读 1](../test/evidence/im-outbox-recovery-20260902/06-home-incoming-unread.png)、[M1 最终账本](../test/evidence/im-outbox-recovery-20260902/11-m1-final.json)、[M3 最终账本](../test/evidence/im-outbox-recovery-20260902/11-m3-final-unopened.json)。M1 旧图片 500 队列仍保留。

## 不通过 / 未完成

### P1：补发后未打开群的未读被清零

- 复现：以上步骤 1–5，M3 始终不打开群，只从首页切到消息列表。
- 预期：seq5 没有真正进入可见聊天区域，read 应保持 4、unread=1；自动补发自己的 seq6/7 不可替用户阅读。
- 实际：20:51:06 前后只读快照仍 read=4/unread=1；随后截图和 20:51:45 快照为 read=7/unread=0。
- **证据时序更正：** `07-auto-sent-keeps-incoming-unread.json` 捕获较早的 1，同名 PNG/XML 捕获稍后的 0。不能根据文件名宣称截图证明未读保留。
- [随后清零快照](../test/evidence/im-outbox-recovery-20260902/09-unopened-unread-cleared-later.json)、[未打开的消息列表](../test/evidence/im-outbox-recovery-20260902/07-auto-sent-keeps-incoming-unread.png)。当前成员确认为 test03，不是账号混用。
- [D1 只读事件核对](../test/evidence/im-outbox-recovery-20260902/10-desktop-read-events.json)：200，43 条、latestSequence=192；最后读事件是 test01 读到 7，未看到 test03 读到 7。D1 与 M1 是同账号，M1 实际已阅读，不能用其读到 7 推导 M3 已阅读。
- 根因尚需 M3 原始摘要/读事件来源证据；不通过忽略同账号读事件来规避，否则破坏跨端已读协议。HTTP 响应未提供请求编号。

### P2：恢复网络仍等待已排定的离线重试

第一个离线项 attempts=4，next_retry_at=12:50:56.168019Z；联网后仍沿用该退避，约 61 秒才成功发出。本轮只改善接收唤醒，未改变既有 Outbox 退避规则，不能报告为即时补发。下一步应区分网络失败与服务端 429/500，避免恢复网络时激进重试所有失败上传。

### 保留的整体缺口

D1 目标群持久事件仍缺少 message.created，正文依赖校对补齐；真实桌面窗口、系统推送、ACK 前精准杀进程、大批量重放、媒体/附件 500、完整高级 OA/权限/通知矩阵和性能指标仍未通过。保持原目标进行中。
