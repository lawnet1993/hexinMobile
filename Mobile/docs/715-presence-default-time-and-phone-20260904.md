# 715 上线默认时间与真机状态一致性

2026-09-04，Asia/Shanghai。整体目标仍进行中。

## 证据与原因

真机通讯录中叶青、宋扬、演练账号、程越、陆炳002显示“最近上线 01-01”。只读取得一致的 IM SQLite + WAL 快照，仅查询分组时间和数量：[修改前缓存](../test/evidence/presence-time-20260904/cache-before.json)显示 5 行 `1970-01-01T00:00:00.000Z`。[修改前截图](../test/evidence/presence-time-20260904/contacts-before.png)与此一致。

解析层把 epoch-zero 默认值当成普通 DateTime，成员投影、旧缓存及聊天对端投影也未过滤，于是格式化出误导日期。本轮确认的是本机原始缓存值与展示链路，未直接捕获服务器原始响应，不推断具体服务端字段生成逻辑。

## 修复边界

- 仅 IM 成员和单聊对端的 lastSeen 时间拒绝 epoch-zero 及更早的默认值，返回 null；不修改通用日期解析，不影响 OA 业务日期、申请时间等。
- 旧 SQLite 缓存及在内存中构造的观察也在投影处过滤，无需清数据或直接改数据库。
- 无效新时间不覆盖真实历史时间；真实 2026 年 1 月 1 日仍有效，不按显示的“01-01”文字判断。
- 在线/离线/未知依据保持原逻辑。已知离线、无有效上线记录显示“离线”；断网或观察过期仍为未知，不伪造最近上线时间或在线状态。
- 群组总在线数不用于单聊对端在线判断，既有边界回归仍通过。

## 回归

- 新增 [12 项时间测试](../test/presence_time_sentinel_test.dart)，覆盖 UTC、等价 +08:00、0001 默认日期、旧缓存、历史保留、真实 1 月 1 日与单聊回退。
- [修改前 11 失败、1 通过](../test/evidence/presence-time-20260904/before-corrected.log)。最初 before.log 为夹具缺少必填 isOnline 的编译错误，不作为产品失败证据。
- [状态专项 44/44](../test/evidence/presence-time-20260904/focused.log)；随后补充通讯录 widget 的 epoch 观察断言，并包含在最终 [全量 1267/1267](../test/evidence/presence-time-20260904/full-tests.log)。
- [静态分析 0](../test/evidence/presence-time-20260904/analyze.log)，[普通 Profile 构建成功](../test/evidence/presence-time-20260904/build.log)，45.4 秒，lib/main.dart，arm64+x64。
- 本地 APK 与真机 base.apk SHA256 一致：`06B38621635F2F20E153B22719C00A487513D36EEDB42F7E381296AD994315D6`。

## 真机复验

RMX3366、test01，保留数据覆盖安装。没有注销登录、清数据、切换热点/系统网络、修改后台账号或发送消息。

1. 更新后自动恢复原账号，进入通讯录仍默认折叠组织。
2. 展开公司总部：[修改后截图](../test/evidence/presence-time-20260904/contacts-after.png)中上述 5 人显示离线，当前账号在线，Test Terminal 02 的 09-02 和陆炳的 22:25 真实历史时间保留。
3. [更新后缓存](../test/evidence/presence-time-20260904/cache-after.json)中原 5 行成为 null，由普通应用刷新路径正常写入；检查脚本只读，没有直接改库。
4. 点击叶青头像进入对应单聊：[聊天截图](../test/evidence/presence-time-20260904/chat-after.png)显示“离线”，没有 01-01；头像和“发送第一条消息开始协作”空状态正常。此操作可能通过既有 get-or-create 流程建立空会话，未发送消息或删除会话。
5. 23:36:50 当前进程日志采样 FATAL、Unhandled Exception、RenderFlex overflow 均为 0。

## 未完成项

真机自然续期跨到期、隔夜保持登录未完成；完整桌面/多移动端同步与替换矩阵、高级 OA、多媒体异常恢复、推送及长期性能仍待验收。最新版桌面窗口的直接对照仍受当前电脑控制运行时缺失限制。本次不据局部状态测试宣布整体通过。
