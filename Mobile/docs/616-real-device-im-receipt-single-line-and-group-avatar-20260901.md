# 616 真机 IM 回执单行与群聊头像验收

## 结论

- 通过：自己发送的消息仅显示双勾已读入口，不再显示“回执”文字；双勾与消息气泡保持同一视觉行，没有折到气泡下方。
- 通过：点击双勾后才请求并打开已读详情，realme 真机返回真实 `已读 1/1`、成员与时间。
- 通过：消息列表中的群聊使用明确群组图标，单聊继续使用真实成员头像和服务端在线/离线点；群聊与单聊不再共用首字母头像体系。
- 通过：真实群聊仍显示 `2 位成员 · 1 人在线`，视频消息保留首帧、播放按钮与时长，文件名没有在视频气泡内重复出现。
- 通过：群聊滑到历史顶部后仍自动处理更早消息，没有“加载更早/加载更多”按钮。

## 真机证据

- [消息列表群聊头像](evidence/616-real-device-im-single-line/02-messages-group-avatar.png)
- [单聊双勾与气泡同行](evidence/616-real-device-im-single-line/03-direct-receipt-single-line.png)
- [真实已读 1/1 抽屉](evidence/616-real-device-im-single-line/04-read-receipt-sheet.png)
- [群聊、在线人数与视频预览](evidence/616-real-device-im-single-line/05-group-chat.png)
- [群聊历史顶部自动加载终态](evidence/616-real-device-im-single-line/06-group-history-top-auto.png)

## 回归约束

- 新增几何断言：双勾中心与消息正文中心的纵向差小于 12dp，防止回执入口再次换行。
- 新增会话类型断言：群聊存在 `message-group-avatar-*`，单聊存在 `message-direct-avatar-*`。
- `flutter analyze`：0 issue。
- IM 定向测试：31/31 通过。
- 完整自动化：235/235 通过。
- Golden：13/13 通过；`04-messages.png` 已在查看新旧同状态截图后更新为群组图标终态。

## 构建与运行

- 设备：realme RMX3366，Android 14，ADB `dd00d66d`。
- 构建：清理后的 Profile APK，65,819,519 bytes。
- SHA-256：`46E5ECAC03BD42AC511312086262970DB5BC95F3AADF1740924121F56EAE3A57`；设备端 `base.apk` 哈希一致。
- 当前进程最近日志：崩溃、未处理 Flutter 异常、RenderFlex 溢出、ANR、OOM 关键命中 0 条。
- 本轮只读打开既有会话与已读详情，未发送消息、未提交审批、未修改线上业务数据。
