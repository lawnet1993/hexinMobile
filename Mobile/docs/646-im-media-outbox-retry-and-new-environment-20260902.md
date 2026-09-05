# IM 媒体待发送、重试与断网验收

时间：2026-09-02 17:44–18:04（Asia/Shanghai）。结论：**部分通过**。本地媒体预览、待发送持久化和原记录重试已实测；图片和视频请求返回 HTTP 500，未完成跨端交付，完整 IM/OA 目标仍未完成。

## 环境与边界

- 当前桌面 1.0.87 的授权会话用于只读 GET 核对，控制面 `http://api.sfhkh.com`。本轮没有桌面窗口点击证据，不以旧桌面源码替代最新窗口验收。
- M1：realme RMX3366 / Android 14 / test01；M2：Android 16 模拟器 / test02。M2 显示 UTC，M1 为 UTC+8。
- 唯一发送目标为两账号既有单聊 `a164a0c0-4cad-44b0-9ece-e095371b2f91`。不操作其他会话中新增的消息。
- 本轮累计新增 1 条本地视频、1 条本地图片记录，均未获服务端消息确认；未直接修改数据库、服务器或现有流程。
- M1 原有 OA 附件待同步继续保留，未重复提交。应用图标仅保留设计稿，未混入本轮安装包配置。

## 问题与改动

待发送媒体已有预览，但旧版长按没有反馈，无法了解失败原因或主动重试。

1. 本人未确认消息长按打开紧凑底部抽屉，显示“等待发送”或“发送失败”，只有“立即重试”一项。复用原 `clientMessageId`，不调用新建消息入口。
2. 本地未确认消息不暴露回复、转发、撤回、收藏、置顶、已读等服务端动作。关闭抽屉不丢弃原记录。
3. 时间旁保留待发送时钟；读屏说明改为“发送中，等待确认，长按可重试”，避免 HTTP 500 被误述为断网，更不会误画成功勾选。
4. 按已知请求路径把 HTTP 失败安全投影为“视频上传 / 图片发送 / 媒体消息提交”等阶段；旧错误仅识别固定类别或 HTTP 状态，不直接渲染异常全文、URL、Header、Token 或响应内容。
5. 本轮不改变已有 5xx 自动重试、永久 4xx 分类和队列顺序规则。

相关代码：`chat_page.dart` 的 `_showMessageActions`、`imOutboxStatusText` 与 `_MessageMeta`；`collaboration_repositories.dart` 的 `imOutboxFailureText`。

## 真实操作与证据

下列文件位于 [test/evidence](../test/evidence/)，共同前缀为 `media-new-environment-20260902-`。

| 用例 | 实际结果 | 证据 |
| --- | --- | --- |
| M2 通过系统文件选择器选择 2 秒 AI-UAT 测试录屏 | 出现真实首帧和播放按钮，无重复可见文件名；只有一条本地待发送视频 | [after-video](../test/evidence/media-new-environment-20260902-after-video.png)、picker.xml |
| 更新最终包后长按原视频 → 立即重试 → 再长按 | 明确显示“视频上传失败（HTTP 500）”；原时间 09:45 保留，仍一条待发送视频 | [final-video-retry](../test/evidence/media-new-environment-20260902-final-video-retry.png) 及同名 XML |
| M2 关闭 Wi-Fi/移动数据，确认无默认网络，强停冷启动再进单聊 | 首帧和待发送时钟仍在；对方为“状态未知”，已有真实已读标记仍保留 | [final-offline-video](../test/evidence/media-new-environment-20260902-final-offline-video.png) 及 XML |
| 真断网点击原视频 | 系统 Google Photos 播放器打开本地视频；不是远程下载成功，也不是内置播放器验收 | [final-offline-player](../test/evidence/media-new-environment-20260902-final-offline-player.png) 及 XML |
| M1 图片 → 系统照片选择器 → 浏览 → 下载 → 精确选择本次 AI-UAT PNG | 生成一条图片待发送记录，显示实际蓝白图标缩略图 | [real-image-pending](../test/evidence/media-new-environment-20260902-real-image-pending.png) |
| M1 长按图片 | “图片发送失败（HTTP 500）”，未显示成功 | [real-image-retry](../test/evidence/media-new-environment-20260902-real-image-retry.png) 及 XML |
| M1 强停冷启动 → 打开同一单聊 | 同一 18:01 图片仍在，未重复插入，缩略图仍可见 | [real-image-restart](../test/evidence/media-new-environment-20260902-real-image-restart.png) 及 XML |
| M1 点击重启后的图片 | 应用内黑底全屏展示实际图片，返回恢复聊天 | [real-image-fullscreen](../test/evidence/media-new-environment-20260902-real-image-fullscreen.png) 及 XML |
| 18:03:46 桌面既有会话只读核对 | Bootstrap 与事件 GET 200；目标单聊 latest/read 均为 6、未读 0，没有媒体确认导致的新序号 | [server-check.json](../test/evidence/media-new-environment-20260902-server-check.json) |

视频播放器截图展示的是录屏中的旧聊天内容，因此其中的时间、在线标记与消息不能作为当前应用状态证据；当前前台组件实际为 `com.google.android.apps.photos/.pager.HostPhotoPagerActivity`。当前聊天离线状态以 `final-offline-video` 为准。

图片文件为 `AI-UAT-20260902-175500-image-preview.png`，927,479 B；名称为准备时标记，实际选择发送约 18:01。视频为 `AI-UAT-20260902-175000-video-preview.mp4`，23,692 B，约 17:45 入队。测试文件名前缀不用于推断精确发生时间。

真实界面证明当前窗口没有新增重复气泡；稳定 ID 重试和重放幂等还由现有仓储/SQLite 测试覆盖。本轮没有把“事件已落库、ACK 前杀进程”的专项故障注入伪称为已执行。

## 阻塞清单

### P1：视频上传请求返回 HTTP 500

- 复现：M2 打开既有单聊，附件 → 视频，选上述非空 23 KB 测试 MP4；等待或长按立即重试。
- 预期：上传确认后提交媒体消息，替换临时记录，M1 收到同一消息。
- 实际：`POST /api/im/upload/video` 阶段返回 500，尚未进入成功的媒体消息提交；抽屉显示安全阶段说明，继续保留队列。
- 影响：视频跨端发送、远端播放和已读不能验收。
- 证据：final-video-retry。请求编号和响应体未采集；不能据此断言具体服务器异常类型，需要联查当前接口契约与服务端日志。

### P1：图片发送请求返回 HTTP 500

- 复现：M1 同一单聊，附件 → 图片，通过系统文件选择器选择上述 0.93 MB PNG。
- 预期：服务端确认后 M2 出现图片，发送端结束等待状态。
- 实际：`POST /api/im/conversations/{conversationId}/images` 返回 500；仅本地缓存与预览成功。M2 没有收到该图片。
- 影响：图片跨端交付与远端图片缓存验收被阻断。
- 证据：real-image-retry、server-check.json。请求编号和响应体未采集；没有输出敏感请求数据。

### P1：历史与群接收仍未通过

18:03 的 GET 核对中，目标单聊和测试群历史均为 405、Allow POST；未把历史读取擅自改成消息发送 POST。测试群仍 latest 84/read 0/未读 84，与此前接收端缺群创建事件的阻塞一致。该复核不能证明未读 84 条已被接收端落库。

## 回归与安装

- 新增 3 项测试覆盖待发送抽屉动作边界、历史错误安全投影、固定路由阶段诊断；既有排队媒体重启和稳定 ID 测试继续运行。
- 本轮重新运行全量 **342/342** 测试，静态分析 **0 问题**。
- 最终 Profile APK：`build/app/outputs/flutter-apk/app-profile.apk`，82,544,963 B，版本 1.0.1 / code 2。
- SHA-256：`F4992D91AD198896FEA3C39F0EE2135A168577B908EF567D2B1A041B531416CC`。
- 真机安装时间 17:58:35；模拟器 09:58:37 UTC（17:58:37 UTC+8）。两端实际 base.apk 的 SHA-256 均与上述一致。
- [final-runtime.json](../test/evidence/media-new-environment-20260902-final-runtime.json)：两端当前进程 `FATAL EXCEPTION / Unhandled Exception / RenderFlex overflowed` 匹配为 0，仅代表该进程已保留日志窗口。
- M2 网络已恢复为原 Wi-Fi/移动数据 1/1，默认网络 104。M1 当时正在共享网络，本轮未切断其网络，维持 Wi-Fi 0/移动数据 1。两端最终前台均为移动应用。

## 未执行与下一步

- 图片/视频最终交付、对端下载、对端冷启动缓存、媒体已读：未通过当前 500 阻塞，不以本地预览代替。
- 普通文件和音频的新环境真实发送：本轮未执行，避免在两端已有待发送媒体后继续堆积测试队列；不能从图片/视频结果推断它们必然失败。
- M1 真断网图片预览：没有执行，避免打断当前网络共享；仅完成在线冷启动后的本地记录与预览恢复。
- 双公式、跨部门复杂审批、全部会签/或签、完整桌面交互和第二桌面替换等仍未完成，见现有对齐清单。
- 保留 1 条 M2 视频、1 条 M1 图片及此前 1 条 M1 OA 附件待同步；服务修复后用原记录继续验收，不重新创建副本。
