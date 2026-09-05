# 684：媒体气泡留白修复与真实预览回归

## 结论

**媒体布局修复通过，完整 IM/OA 目标继续。** 解决图片、视频、音频气泡被时间/状态行撑宽，以及图片网格继承页面底部安全区造成的额外空白。新增 **15 项**布局回归，全量 **809/809**、静态分析 **0 问题**，正常 Profile 包已在独立 M3 安装并核对哈希。

真实操作确认图片放大/返回、待发图片长按抽屉、视频打开播放器/暂停/返回及群历史滚动均可用；原消息、两条待发媒体、2 草稿和 9 回执保留。媒体上传仍 HTTP 500，**本地可预览不等于已经送达**。

## 环境与范围

- 时间：2026-09-03 03:35—03:44，Asia/Shanghai。
- 接续 [683 会话进入及断网实测](683-contact-chat-timing-and-offline-20260903.md) 的进展；本轮根据当前截图和组件复现修改布局，没有把小会话的计时结果外推到大群性能。
- 项目 `E:\SecureAccess-client-source-20260824-151204\Client\Mobile`，M3 `emulator-5556` / test03。只操作 M3，未接管 M1、M2 或 Windows 窗口，未依据旧桌面源码修改业务协议。
- 使用原单聊、原测试群、原待发图片和视频；没有新发消息、删除队列、变更审批、改密码或直接写数据库；保留既有未提交更改，无提交或推送。

## P2-684-01：媒体内容窄，气泡却被撑满

### 复现及根因

打开含图片、音频或视频的消息。媒体内容宽度为 200/210/240dp，但底部时间/发送状态包在 `Align` 中，默认扩展到父级最大宽度，整张气泡成为 292dp。单图和音频相对内容多 82dp，视频多 92dp，其中大部分不是设计边距。

新增断言使用实际渲染框尺寸：媒体外壳与内容之间只允许既有左右 padding 19dp，收到消息另加 2dp 边框。原实现 **8 项宽度测试全部失败**，见[有效红灯日志](../test/evidence/im-media-layout-20260903/red-layout-verified.log)。首次测试夹具缺少必填字段曾编译失败，已修正；不把编译失败当作缺陷复现证据。

### 修改

[chat_page.dart](../lib/features/messages/presentation/chat_page.dart) 统一媒体内容宽度，并限制外壳最大宽度为内容加 padding/边框；保留窄屏父约束。没有通过 `IntrinsicWidth` 对惰性图片网格做额外固有尺寸布局，没有缩小既有缩略图、去掉时间或隐瞒发送状态。

| 媒体 | 内容宽度 dp | 原气泡上限 dp | 新气泡上限：发出 / 收到 dp |
| --- | ---: | ---: | ---: |
| 单图、音频 | 210 | 292 | 229 / 231 |
| 多图网格 | 240 | 292 | 259 / 261 |
| 视频 | 200 | 292 | 219 / 221 |

长群成员名称限制一行省略，引用仍保留；撤回消息使用文字分支，不强套媒体宽度。宽度数字为组件逻辑像素验证，不冒充从设备 UI hierarchy 测得的气泡像素宽度。

## P2-684-02：图片网格重复应用安全区

图片 `GridView.builder` 未指定 padding，继承了页面底部安全区。组件注入底部 28dp 时，单图网格实际高度 **208dp**，而缩略图行高为 **180dp**；第 9 项红灯明确复现。

修复为网格 `padding: EdgeInsets.zero`，安全区仍由页面处理。新实现网格高度 180dp；M3 同一待发图片消息行在相同起点下由 **633px 降至 570px**，见[实际行高](../test/evidence/im-media-layout-20260903/image-row-height.json)。这 63px 是设备界面测得的行高差，不代表所有设备都有相同安全区。

真实前后对照：[图片修复前](../test/evidence/im-media-layout-20260903/01-image-before.png) → [图片修复后](../test/evidence/im-media-layout-20260903/07-image-after.png)；[群视频修复前](../test/evidence/im-media-layout-20260903/04-group-video-before.png) → [群视频修复后](../test/evidence/im-media-layout-20260903/12-group-video-after.png)。

## 实际操作验收

1. 正常 Profile 安装后恢复原 test03，[工作台](../test/evidence/im-media-layout-20260903/05-new-profile-home.png)和[消息列表](../test/evidence/im-media-layout-20260903/06-message-list-after.png)均有真实截图；单聊和群聊标识未混用。
2. 点击原待发图片进入[全屏预览](../test/evidence/im-media-layout-20260903/08-image-fullscreen.png)，返回后原会话仍在；长按图片显示[等待发送/立即重试抽屉](../test/evidence/im-media-layout-20260903/10-pending-image-actions.png)，真实错误为 HTTP 500。本轮只查看并取消，没有点击重试或新发送。
3. 群内视频卡片有缩略图和单个播放图标，没有额外可见文件名；时间与待发时钟仍在。点击后系统播放器短暂加载，随后显示原 2 秒视频画面。
4. 播放器控件由 [Pause](../test/evidence/im-media-layout-20260903/15-video-controls.png) 经真实点击变为 [Play](../test/evidence/im-media-layout-20260903/16-video-paused.png)，时长 0:02 可见；[返回原群](../test/evidence/im-media-layout-20260903/17-video-player-return.png)后卡片和待发状态保留。视频内容是既有测试录屏，**录屏内的在线状态和旧消息不是本轮双端同步证据**；没有点分享、投屏等外部动作。
5. 手势滚到[较早群消息](../test/evidence/im-media-layout-20260903/18-group-earlier-messages.png)，原 @ 提及和连续发送者分组存在；再[滚回末条视频](../test/evidence/im-media-layout-20260903/19-group-return-latest.png)，未增加重复视频或改变发送状态。群聊只有聊天/文件，单聊保留任务入口。

## 自动回归与数据保护

- [新增测试](../test/chat_page_type_test.dart)：单图/四图/视频/音频 × 收到/发出共 8 项宽度、1 项安全区、图片/视频/音频 × 收到/发出共 6 项 300dp 窄屏 + 1.6 倍字体 + 长群成员名 + 引用，共 **15 项**。
- [红转绿](../test/evidence/im-media-layout-20260903/green-layout.log)：前 9 项通过；[聊天专项](../test/evidence/im-media-layout-20260903/chat-regression.log) **69/69**；[全量](../test/evidence/im-media-layout-20260903/full-final.log) **809/809**；[分析](../test/evidence/im-media-layout-20260903/analyze-final.log) 0；未更新 Golden 来掩盖失败。
- [正常构建](../test/evidence/im-media-layout-20260903/build-final.log)使用 `lib/main.dart`。APK SHA-256 `15A15059C1AC4E6837BE282180D2A494CEB68F8A9A0604AC22CFF06EDF823A1B`，[本地与设备一致](../test/evidence/im-media-layout-20260903/installed-final.json)。
- [当前应用进程检查](../test/evidence/im-media-layout-20260903/runtime-errors.json)：Unhandled Exception、RenderFlex overflow、FATAL EXCEPTION 匹配计数均 0；不是全系统/所有错误类型的穷尽审计。
- [只读保护核对](../test/evidence/im-media-layout-20260903/preservation-final.json)：消息台账、群消息、原两条 Outbox 标识、草稿与回执保持；IM applied/acked 236、OA 游标 449。媒体最近失败摘要仍 HTTP 500，没有删除或重建来制造成功。

## 未完成

多图、音频、长群成员名及 1.6 倍字体本轮为真实组件回归，尚未逐项在真机执行；本次设备交互覆盖原单图和群视频。当前 Windows 窗口完整对照、真机、大群/长历史性能、高级 OA 接收人处理、完整多端/推送矩阵及既有服务端问题仍需继续，整体目标不完成。
