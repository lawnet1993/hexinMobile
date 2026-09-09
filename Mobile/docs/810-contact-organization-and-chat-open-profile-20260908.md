# 通讯录组织折叠与会话打开性能复验（2026-09-08）

> 2026-09-09 真机增量：此前“真机锁屏”和模拟器 Raster 风险已经补测。realme 真机、Test Terminal 01、同一 80 条消息单聊窗口：首次打开消息可用 87 ms、最新消息布局 204 ms，热打开分别 11 ms、93 ms；两轮 Raster 超预算均为 **0 帧**。通讯录已显示服务端返回的“最近上线 昨天”和“离线”，会话标题显示“离线 · 09-08 21:31”，没有伪造在线状态。当前真机边界通过，模拟器宿主 GPU 的旧风险不再作为真机阻塞。

## 结论

- 当前桌面功能基准按用户实际运行窗口记为 **v1.0.105**；旧文档中的 v1.0.91/v1.0.93/v1.0.94 仅代表当时历史样本。
- Android 模拟器 `emulator-5554`（Test Terminal 02）安装当前 Profile APK 后，通讯录默认只显示组织，不平铺人员；公司总部和其他联系人均默认为收起状态。
- 展开公司总部后才显示成员；成员账号未展示，列表右侧没有重复的联系图标。点击成员头像可直接打开既有单聊，单聊/群聊入口没有混用。
- 首次打开已有单聊时，路由首帧约 23 ms、消息可用约 47 ms、最新消息完成布局约 164 ms；热打开时分别约 23 ms、16 ms、98 ms。热打开命中 80 条本地消息缓存，没有重新请求后才显示整页历史。
- 当前模拟器帧采样仍出现 Raster 超预算：首次 14 帧、热打开 12 帧；这是可感知卡顿风险，不能只凭首屏已出现判定性能完全通过，后续需要继续压缩头像解码、消息气泡绘制和首屏栅格负担。

## 实测证据

- `contacts-default-org-current.png`：默认组织折叠。
- `contacts-org-expanded-current.png`：展开后显示成员，账号隐藏，成员行无右侧聊天按钮。
- `contact-avatar-chat-open-current.png`：点击头像进入已有单聊。
- `contact-avatar-chat-hot-reopen-current.png`：返回后再次进入，命中本地消息缓存。

证据目录：`Mobile/test/evidence/real-device-main-pages-20260908/`。

## 性能样本

| 样本 | cacheHit | 消息数 | routeFrame | messagesAvailable | latestMessageLaidOut | build 超预算 | raster 超预算 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 首次打开 | false | 80 | 23 ms | 47 ms | 164 ms | 1 | 14 |
| 热打开 | true | 80 | 23 ms | 16 ms | 98 ms | 0 | 12 |

`MOBILE_CHAT_OPEN` 的 3 秒窗口总时长是固定采样窗口，不是页面打开耗时；交互判断应看分阶段耗时和帧指标。

## 尚未通过

- 成员状态本轮显示“状态未知”。页面没有伪造在线/离线，但服务端真实 Presence 仍未返回可判定状态，在线状态验收未通过。
- Raster 超预算仍明显，联系人到会话的性能只能判为部分通过。
- 真机本轮处于锁屏状态，最新 Profile 包虽已安装，但上述新一轮性能采样来自已登录模拟器；仍需解锁后补真机冷/热打开对照。

以上三项是 2026-09-08 的历史结论。2026-09-09 当前 Profile APK 真机复验结果如下：

| 真机样本 | cacheHit | 消息数 | routeFrame | messagesAvailable | latestMessageLaidOut | build 超预算 | raster 超预算 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 首次打开 | false | 80 | 26 ms | 87 ms | 204 ms | 2 | 0 |
| 热打开 | true | 80 | 30 ms | 11 ms | 93 ms | 2 | 0 |

仍有少量 Build/totalSpan 超预算，但用户指出的“联系人进入会话特别卡”在本轮真机没有复现；Raster 最大值分别为 13.5 ms 和 8.5 ms，低于真机 60 Hz 的 16.7 ms 帧预算。Presence 当前也已返回可解释的服务端状态，因此本报告的真机联系人进入会话和真实状态两项改判通过。

新增证据：

- [真机通讯录真实状态](../test/evidence/real-device-contact-chat-performance-20260909/01-contact-presence.png)
- [真机热打开 80 条消息会话](../test/evidence/real-device-contact-chat-performance-20260909/02-chat-hot-open.png)

## 自动回归

- 通讯录虚拟化、自动连续加载、折叠状态、头像/成员行单次导航、键盘收起与路由防重：**26/26 通过**。
- 聊天缓存热打开、历史上滑自动加载、510 条消息连续追溯、首条未读定位、群聊/单聊隔离、连续消息头像合并、媒体布局与发送状态：**97/97 通过**。
- 一次错误地把 PowerShell 通配符直接作为 Flutter 测试路径，Flutter 在 Windows 上报 `Illegal character in path`；改用明确测试文件后正常通过。该工具调用错误不是应用缺陷。
