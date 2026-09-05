# 695：图片/视频上传 500 的安全取证

日期：2026-09-03，约 06:25–06:35（Asia/Shanghai）。**结论：媒体发送仍未通过，但已取得两次真实失败的服务端 traceId，可继续做后端关联排查。** 本轮不是上传修复，不将诊断、重试或本地预览当作成功送达。

## 1. 当前证据与下一步

原图片和原视频分别原生点击一次重试，均得到结构化 JSON HTTP 500，不是连接超时；没有重新选择附件或创建重复消息。响应头中可用的请求编号为空，但 JSON `traceId` 存在。

| 项目 | 图片 | 视频 |
| --- | --- | --- |
| 请求 | `POST /api/im/conversations/2a2ea21f-2ad6-49b3-b3da-407d1e7e4136/images` | `POST /api/im/upload/video` |
| clientMessageId | `13dc7539-f758-450e-a45d-ae151c846e14` | `4bd94d7a-d990-44d8-9b72-4edc3fc4925c` |
| 原生重试点击（主机时间） | `2026-09-03T06:30:41.0607990+08:00` | `2026-09-03T06:31:47.6729748+08:00` |
| 客户端实际构造表单 | multipart：clientMessageId、caption、files | multipart：file |
| 文件字节数 | 1,526,148 | 23,692 |
| 响应 | 500，JSON 对象 | 500，JSON 对象 |
| 原队列 attempts | 48 → 49 | 48 → 49 |
| 最终消息状态 | 原本地 ID、seq0、pending | 原本地 ID、seq0、pending |

服务端关联编号：

- 图片 `traceId`：`00-7693702ab9f087e9f49b579a68e38a2e-9ef20c197d6196d4-00`。
- 视频 `traceId`：`00-545401707d34d270b5ec6c8cb68eddfe-4aa8c0ab620cb11d-00`。

权威取证：[两次响应白名单记录](../test/evidence/im-upload-diagnostics-20260903/media-response-diagnostics.json)、[图片原生点击](../test/evidence/im-upload-diagnostics-20260903/image-retry-once.json)、[视频原生点击](../test/evidence/im-upload-diagnostics-20260903/video-retry-once.json)、[图片操作抽屉](../test/evidence/im-upload-diagnostics-20260903/m3-image-retry-menu.png)、[视频重试后的错误抽屉](../test/evidence/im-upload-diagnostics-20260903/m3-video-current-error.png)。

**下一步需要后端按上述 traceId 查询异常日志，并核对当前部署的 multipart 绑定、媒体服务和存储调用。** 当前没有后端访问方式，已向用户询问。白名单错误代码/类别没有命中，不代表响应原文一定无内容，也不能据此确认是存储、权限、代理或移动端协议错误。在日志/协议得到新证据前，不继续手工重复同样的 500 重试；其他 IM/OA 页面与流程不受此调查阻塞。

## 2. 协议核对的边界

- `/swagger/v1/swagger.json` 和 `/openapi/v1.json` 都返回管理端 HTML，而非接口文档。[再次探测记录](../test/evidence/im-upload-diagnostics-20260903/openapi-probe.json)为 200、text/html、857 字节、管理端入口脚本。因此不能把 HTTP 200 当作“取得上传规范”。
- 实际 multipart 字段和长度来自当前移动端 Dio 请求对象；这是请求构造证据，不代表已经核实服务端最新接受的字段定义。没有凭猜测将 `files` 改成 `file`、换上传地址或绕过认证。
- 当前 Windows 1.0.87/test01 仍运行，已安装客户端会话的只读 IM/OA 检查均 200，见 [桌面记录](../test/evidence/im-upload-diagnostics-20260903/desktop-health.json)。这不是 Windows 原生媒体操作证据，亦不证明桌面上传正常；仍未使用旧源码作为最新行为基准。

## 3. 本轮改动：可关闭的安全上传诊断

[ImUploadDiagnostics](../lib/features/collaboration/data/im_upload_diagnostics.dart) 接在 [原队列失败及可选封面失败路径](../lib/features/collaboration/data/collaboration_repositories.dart)，只对上传/媒体发送操作生效。

- 默认关闭；必须显式 `MOBILE_IM_UPLOAD_DIAGNOSTICS=true`，且仅 debug/profile，release 硬关闭。
- 只输出固定操作枚举、HTTP 状态、错误类型、允许的表单字段名、文件长度、响应形状及格式校验过的关联编号。
- 不输出原始 URL、附件地址、文件名、消息内容、任意响应原文、密码、令牌、Cookie、设备标识或指纹；未知错误代码不输出。
- 已知错误语句只映射成固定类别，类别是排查线索而非根因结论。本轮两次类别均为空。
- 诊断异常、重复响应头、输出通道异常不能改变待发队列重试行为。原账号隔离、稳定 clientMessageId、失败重试规则保持不变。

[日志采集脚本](../scripts/read-im-upload-diagnostics.ps1) 只在内存读取当前应用 PID 的 logcat；再次验证固定字段、枚举、长度及编号格式，只保存合格 JSON，不保存原始日志。拒绝覆盖现有证据文件。

## 4. 测试、安装与恢复

[新增诊断测试](../test/im_upload_diagnostics_test.dart) 12 项，覆盖默认关闭、非上传请求过滤、字段白名单、敏感字符串/URL/JWT/换行拒绝、已知错误分类、超时区分、重复响应头和输出异常。

| 验证 | 结果 | 证据 |
| --- | --- | --- |
| 诊断 + 694 会话隔离 + 媒体专项 | 54/54 | [专项日志](../test/evidence/im-upload-diagnostics-20260903/targeted.log) |
| 全量测试 | 966/966 | [全量日志](../test/evidence/im-upload-diagnostics-20260903/full-test.log) |
| 静态分析 | 0 问题 | [分析日志](../test/evidence/im-upload-diagnostics-20260903/analyze.log) |
| 临时诊断包 | 仅 M3/test03，正常 main 入口加诊断开关 | [临时安装记录](../test/evidence/im-upload-diagnostics-20260903/diagnostic-install.json) |
| 正常包恢复 | M3/test03 与 M4/test04 均安装成功，保留数据、设备 APK 哈希一致 | [正常安装记录](../test/evidence/im-upload-diagnostics-20260903/normal-install.json) |

正常包构建成功，93.2 MB、Gradle 53.4s，[构建日志](../test/evidence/im-upload-diagnostics-20260903/normal-build.log)。最终 SHA256：`5021590ADF094F2033089DAD1C31FDE3325C958EB828984BEC614DEA9DF6C89A`。不再是临时诊断包 `42D4E8C4...`。

最终两台当前进程 [M3 诊断记录为空](../test/evidence/im-upload-diagnostics-20260903/m3-normal-diagnostic-check.json)、[M4 诊断记录为空](../test/evidence/im-upload-diagnostics-20260903/m4-normal-diagnostic-check.json)。[运行记录](../test/evidence/im-upload-diagnostics-20260903/runtime-final.json)中 PID 为 14728/28165、网络均 1/1，未观察到当前进程 Unhandled/FATAL/RenderFlex overflow。这是当前窗口检查，不等于完整性能或长期稳定性结论。

## 5. 原数据保留和取证修正

- [17 项元数据核对](../test/evidence/im-upload-diagnostics-20260903/final-checks.json)全部通过：两端账号、五条群消息完整账本、各会话元数据、已读/确认游标、两条旧媒体待发 ID，以及 M3 两份 OA 草稿、十条阅读回执均保留。M4 待发为空，无新 OA 提交。
- 图片 [重试前](../test/evidence/im-upload-diagnostics-20260903/image-before.json)/[重试后](../test/evidence/im-upload-diagnostics-20260903/image-after.json)，视频 [重试前](../test/evidence/im-upload-diagnostics-20260903/video-before.json)/[重试后](../test/evidence/im-upload-diagnostics-20260903/video-after.json)均是只读 DB+WAL 元数据快照，没有手工改写原数据库。
- 正常恢复后的 [M3 账本](../test/evidence/im-upload-diagnostics-20260903/m3-im-final.json)、[M4 账本](../test/evidence/im-upload-diagnostics-20260903/m4-im-final.json)、[OA 快照](../test/evidence/im-upload-diagnostics-20260903/m3-oa-final.json)保存供后续继续，不重新创建这些测试数据。
- 首次采集器的 JSON 日期自动转换导致 UTC 后缀丢失并重复应用 Windows 时区。已改用 `ConvertFrom-Json -DateKind String`，用 [UTC 精度与时区测试](../test/evidence/im-upload-diagnostics-20260903/collector-utc-check.json)验证并重新读取同一进程记录。旧 `image-response-diagnostic.json` 的 sampledAt 无效；以 `image-response-diagnostic-verified.json` 及最终两条 `media-response-diagnostics.json` 为准。Android 与主机钟域本身仍不同，不据此计算网络时延。
- 最终 M3 停在[消息全部列表](../test/evidence/im-upload-diagnostics-20260903/m3-final-list.png)，M4 停在[工作台](../test/evidence/im-upload-diagnostics-20260903/m4-normal-home.png)。没有操作真机/M2、退出测试账号、清除缓存、提交审批或改变服务端配置。

## 6. 未完成项

P1 媒体实际送达及根因仍未完成，现等待服务端日志/当前上传契约用于下一步；无需因此暂停其它移动端工作。完整同账号桌面/手机会话替换、真机和 Windows 原生 UI、高级 OA 分支角色与操作、推送、大批量同步和真实性能仍按 [总对齐清单](DESKTOP-MOBILE-FUNCTION-ALIGNMENT.md)继续。目标不标完成，不将本轮取证算作媒体功能通过。
