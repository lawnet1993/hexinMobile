# 776 · 工作台恢复、加载态与有限重试复验

> 日期：2026-09-06  
> 结论：三 AVD 压力下的前后台恢复本轮通过；此前超过 35 秒的空白加载未复现。已修正无说明加载态和首屏 Provider 的默认无界重试风险，真机仍待解锁后复验。

## 实际复验

- 同时运行三台 Android AVD，M2 保持 `test03` 登录并停留在工作台。
- 连续 6 次执行 Home → 恢复应用；每次首个 UIAutomator 样本均已出现完整工作台，观测上界为 3593–4060 ms。该数字包含 UIAutomator 抓取语义树的约 3 秒开销，不能当作真实首屏渲染耗时。
- 新 APK 覆盖安装到 M2 后冷启动：Android Activity `TotalTime=2886 ms`，首个语义树样本约 4518 ms 已出现完整工作台。
- 新 APK 再执行 3 次 Home → 恢复：首个样本分别为 3487、3261、3183 ms，均完整；IM 测试群仍为 65/65、Outbox=0、游标 applied=acked。
- M2 日志中 FATAL、ANR、OOM 均为 0。

证据：[三 AVD 六次恢复](../test/evidence/resume-stability-20260906-1200/m2-resume-cycles.json)、[新 APK 冷启动结果](../test/evidence/resume-stability-20260906-1200/m2-post-install-result.json)、[新 APK 三次恢复与 IM 连续性](../test/evidence/resume-stability-20260906-1200/m2-post-install-resume.json)、[实际工作台截图](../test/evidence/resume-stability-20260906-1200/m2-post-install-workbench.png)。

## 客户端修正

- 工作台 bootstrap 未完成时不再只显示无说明转圈，改用统一的 20 px `ModuleLoadingState`，明确显示“正在加载工作台”。
- `oaBootstrapProvider`、OA 应用目录、OA 通知、IM bootstrap、组织部门和好友申请统一接入 `mobileReadRetry`。
- 网络超时、连接错误、408、429 和 5xx 最多自动重试两次；401/403、协议错误、取消和其他永久错误不自动重试，页面进入已有错误/手工重试路径。
- 这次调整只限制 Riverpod Provider 的重复请求次数，不改变登录失效、会话替换、离线缓存或后台同步语义。

## 构建与安装

- `module_loading_states_test.dart` 与 `mobile_read_retry_test.dart`：4/4 通过。
- 定向 `flutter analyze`：0 error、0 warning；保留同一大文件中 6 条既有花括号风格 info。
- 默认 Gradle 缓存仍复现既有 `settings.gradle.kts` DSL 解析故障；未修改 Gradle 脚本绕过。
- 使用项目既有独立 `GRADLE_USER_HOME` 后 Profile arm64+x64 构建成功，APK 111,236,918 B。
- M2/test03 与 M3/test04 均保留数据覆盖安装成功；两端 IM 本地数据和游标连续。真机处于熄屏/锁定状态，本轮没有强行覆盖安装并把“安装成功”冒充真机 UI 通过。

## 尚未关闭

1. 此前 M2 在三 AVD 常驻时出现过超过 35 秒的空白工作台，重启模拟器才恢复。本轮只能判定“未复现”，不能宣称根因已经完全消失。
2. 需要在真机解锁后安装同一 APK，执行冷启动、Home 恢复、断网缓存、恢复同步各 5 次。
3. 如再次出现长时间加载，需要同时保留 `MOBILE_OA_SYNC_STAGE`、会话锁等待和 SQLite 事务时间，确认是安全存储锁、OA 缓存还是同步提交阻塞。

