# 604 · 群管理自动分页与模拟器实操

时间：2026-09-01

## 结果

- 群管理的禁言成员、入群申请、管理员和操作记录四个列表全部移除“加载更多”按钮。
- 距列表底部 240dp 时自动请求下一页；首屏不足或第一页为空但服务端总数仍有数据时自动补页。
- 四个标签维护独立的页码、总数和数据集合；切换标签会使旧请求结果失效并回到顶部，避免跨分类混入。
- 分页继续按成员或业务记录 ID 去重；页码不前进或下一页没有新增数据时停止，防止请求循环。
- 临时失败保留已有列表并暂停自动请求，只显示“重新加载”；新上滑手势或按钮可恢复。
- 群成员在线状态、头像、群主/管理员身份和服务端管理权限保持原逻辑。

## 自动化

- 新增 4 个群管理组件用例：
  - 长禁言列表滚到底自动请求第二页；
  - 空首屏自动补页；
  - 分页失败保留内容并允许重试；
  - 禁言、入群、管理员、记录使用各自独立加载器。
- 群管理定向测试：4/4 通过。
- 全量测试：228/228 通过。
- `flutter analyze`：0 项问题。

## 模拟器实操

- 设备：Android 模拟器，1080×2400，隔离 Demo 配置。
- 实际链路：通讯录 → 群聊 → 华南运营协作 → 群聊详情 → 群管理。
- 真实切换禁言、入群、管理员、记录和高级五个标签；UI 树没有“加载更多”，原有解除、审核、身份和危险操作权限入口保持。
- 应用进程关键异常为 0。
- Flutter 调试连接在安装后断开，但 Android 进程 `14788` 仍存活并完成全部 ADB 实操；没有因 DevFS 断开重启应用。

证据：

- `docs/evidence/604-group-management-auto-paging/01-muted.png`
- `docs/evidence/604-group-management-auto-paging/01-muted.xml`
- `docs/evidence/604-group-management-auto-paging/02-requests.png`
- `docs/evidence/604-group-management-auto-paging/02-requests.xml`
- `docs/evidence/604-group-management-auto-paging/03-managers.png`
- `docs/evidence/604-group-management-auto-paging/03-managers.xml`
- `docs/evidence/604-group-management-auto-paging/04-notices.png`
- `docs/evidence/604-group-management-auto-paging/04-notices.xml`
- `docs/evidence/604-group-management-auto-paging/05-advanced.png`
- `docs/evidence/604-group-management-auto-paging/05-advanced.xml`

## 构建与真机边界

- Production Profile APK：79,725,862 bytes。
- SHA-256：`7D3CB222D12EEF3539C5240695961C3DF1C947AFB864BB2912213A98B1256C36`。
- 已覆盖安装到 realme 真机，设备端 APK 哈希一致。
- 真机仍处于系统锁屏：`Keyguard showing=true / InputRestricted=true`。未绕过锁屏；真实群管理分页需要解锁后在有超过 50 条记录的测试群补充触控与接口证据。
