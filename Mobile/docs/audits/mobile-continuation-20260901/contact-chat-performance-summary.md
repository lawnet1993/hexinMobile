# 通讯录与会话热打开性能（2026-09-01）

## 设备与方法

- 设备：realme RMX3366，profile APK，60Hz 显示模式。
- 数据来源：Android SurfaceFlinger `--timestats` 中应用 Flutter SurfaceView 层。
- 每轮仅统计一次“列表/通讯录 → 已有会话”的打开过程，页面静止和返回动画不计入。
- SurfaceView 层的 `totalTimelineFrames` 在该设备固件上始终为 0，因此不能只依赖其 jank 分类；同时核对 `droppedFrames`、平均 FPS 和 50ms/150ms 真机截图。

## 结果

| 场景 | 次数 | SurfaceView 帧数 | droppedFrames | 层 jankyFrames | 平均 FPS 范围 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 消息列表 → 2000 人群聊热重开 | 10 | 269 | 0 | 0 | 57.6–62.5 |
| 通讯录搜索结果 → 林川已有单聊（修正前） | 10 | 264 | 0 | 0 | 57.6–60.1 |
| 搜索键盘打开 → 林川已有单聊（主动收键盘后） | 10 | 295 | 0 | 0 | 51.1–60.6 |

修正前，聊天历史在 50ms 已经出现，但搜索键盘继续覆盖聊天页，150ms 仍残留输入法工具条，形成拖影感。修正后点击联系人会先清理输入焦点并向系统发送隐藏输入法指令；50ms 内聊天历史和头像已经出现，150ms 时输入法完全退场。10 次带键盘打开的重复路径没有 SurfaceView 丢帧。

## 证据

- `37-contact-chat-open-50ms-real.png`、`38-contact-chat-open-150ms-real.png`：修正前。
- `40-contact-chat-keyboard-fix-50ms-real.png`、`41-contact-chat-keyboard-fix-150ms-real.png`：修正后。
- `surface-timestats/open-01.txt` 至 `open-10.txt`：消息列表热重开原始数据。
- `contact-chat-timestats/open-01.txt` 至 `open-10.txt`：通讯录已有单聊修正前原始数据。
- `contact-chat-keyboard-fix-timestats/open-01.txt` 至 `open-10.txt`：键盘修正后原始数据。

