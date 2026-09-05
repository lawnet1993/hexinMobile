# 700 头像按显示尺寸解码与真实页面回归

日期：2026-09-03，Asia/Shanghai。结论：**修复头像全尺寸解码，降低单个解码位图占用；不能判定整体聊天卡顿已解决。** 大 PNG 首次解码存在额外缩放成本，下面完整保留测量结果。

## 问题与实现

接续 [699 消息窗口查询](699-im-window-index-and-contact-runtime-20260903.md)，检查发现共用 `InitialAvatar` 把 base64 转成 MemoryImage 后直接按原图解码，与头像的显示大小无关。红灯测试实际得到2048×2048，而该头像只需要96×96像素；同一图片不同头像大小也共享原尺寸缓存。

- 新增 [AvatarMemoryImage](../lib/shared/widgets/avatar_memory_image.dart)：按逻辑半径×2×设备像素比计算目标直径，16像素分档，目标直径不超过512。
- 根据原图固有尺寸保持宽高比，短边满足原有 CircleAvatar cover 裁剪，不把长方形人像拉伸成正方形；不放大小图。极端长图再限制最长边1024，允许此类极端比例的裁剪区域分辨率低于目标，以保证解码像素有上限。
- [InitialAvatar 接入](../lib/shared/widgets/mobile_primitives.dart)：联系人、单聊/群聊、个人页、OA申请人共用。继续复用已有64项原始字节缓存，解码缓存键增加尺寸；相同内容、相同尺寸复用，不同尺寸/不同内容区分。
- 不改头像来源优先级、人物身份、头像合并位置、在线状态、业务接口或表单内容。没有删掉头像来减少绘制工作，也没有改成假在线。
- 实现参考本机 Flutter 3.47.0 ImageProvider/MemoryImage 源码以及 [解码尺寸回调](https://api.flutter.dev/flutter/dart-ui/instantiateImageCodecWithSize.html)、[ImageProvider 缓存键协议](https://api.flutter.dev/flutter/painting/ImageProvider-class.html)。这不是对整进程内存、原始base64缓存或GPU分配的验收结论。

## 自动化回归

[新增8项](../test/avatar_decode_size_test.dart)：真实图片codec解码尺寸、横竖图比例、禁止放大小图、极端比例上限、非法尺寸/DPR、分档、同图复用、不同大小/图片缓存隔离。原有头像来源、未知头像回退、聊天分组、真实在线状态、OA头像来源测试全部保留。

- [改动前红灯](../test/evidence/avatar-decode-performance-20260903/red-test.log)：4项中3项失败，1项原有缓存复用通过，确认不是仅检查构造参数。
- [专项](../test/evidence/avatar-decode-performance-20260903/targeted-final.log)：171/171，包含聊天、通讯录、OA页面。
- [全量](../test/evidence/avatar-decode-performance-20260903/full-test.log)：1004/1004。
- [静态分析](../test/evidence/avatar-decode-performance-20260903/analyze-final.log)：0问题。

## Android模拟器实际解码对照

M3 Android16，以独立 [测试入口](../tool/avatar_decode_benchmark_main.dart) Profile构建运行两轮；不打开账号安全存储、真实数据库或网络，不写入线上测试头像。数据为项目内置头像和代码绘制的合成PNG。每种原图/缩小解码均移除对应缓存后采样5次，记录实际ImageInfo尺寸和完整耗时。测试入口不被正常main引用，release禁止执行。

| 图片 | 原尺寸→解码尺寸 | 原RGBA字节→新RGBA字节 | 首轮冷resolve中位数 ms | 第二轮冷resolve中位数 ms |
| --- | --- | ---: | ---: | ---: |
| 项目内置JPEG头像 | 256×256→96×96 | 262144→36864 | 3.509→2.306 | 16.742→15.524 |
| 合成正方形PNG | 2048×2048→96×96 | 16777216→36864 | 30.490→53.145 | 31.229→53.401 |
| 合成横图PNG | 4096×2048→192×96 | 33554432→73728 | 62.092→94.269 | 62.483→94.900 |
| 合成竖图PNG | 2048×4096→96×192 | 33554432→73728 | 62.734→77.647 | 61.560→92.056 |

RGBA字节是实际解码宽×高×4，并非进程PSS或GPU内存实测。内置头像单个位图约256KiB→36KiB；大正方形约16MiB→36KiB。多个尺寸仍可能各占缓存，原始图片字节也仍存在，不将单图比例外推为整个应用内存降幅。

**明确代价**：首次resolve在本轮大PNG上慢约20–33ms；这项延迟仍需继续优化。重采样是后续需拆分测量的环节，仅凭此数据不能确定codec内部各环节的耗时来源。保留尺寸限制是为避免小头像长期持有16–32MiB解码图，并减少后续绘制的像素量，不宣称所有图片加载变快。测试也没有证明长列表帧率因此改善。

证据：[第一轮](../test/evidence/avatar-decode-performance-20260903/android-benchmark.json)、[第二轮](../test/evidence/avatar-decode-performance-20260903/android-benchmark-repeat.json)、[原图/缩小解码并列截图](../test/evidence/avatar-decode-performance-20260903/benchmark-comparison.png)。截图已实际查看，内置人像与横竖图裁剪未变形；视觉对照按128像素解码，计时对照按96像素，不能混用尺寸指标。

## 正常应用实际检查

最终M3/test03、M4/test04均安装正常 `lib/main.dart` Profile包，93.2MB。SHA256：`E974479A56167A6C81C747E739343022FB2D047927BF3396A0E02BF2EA5E11C6`。没有清除数据，没有修改密码，没有手动重发旧失败附件。

- [正常包核对](../test/evidence/avatar-decode-performance-20260903/normal-runtime.json)：两台base.apk与构建hash相同，采样时FATAL/Unhandled/RenderFlex overflow/头像测试入口日志均0；[页面操作后的复核](../test/evidence/avatar-decode-performance-20260903/normal-runtime-final.json)这些计数及图片解码错误计数均0。
- 实际打开、操作并查看截图：[通讯录展开](../test/evidence/avatar-decode-performance-20260903/m3-normal-expanded.png)、[单聊](../test/evidence/avatar-decode-performance-20260903/m3-normal-direct.png)、[群聊](../test/evidence/avatar-decode-performance-20260903/m4-normal-group.png)、[我的](../test/evidence/avatar-decode-performance-20260903/m4-normal-profile.png)、[OA请假表单](../test/evidence/avatar-decode-performance-20260903/m3-oa-request.png)。人像、群消息头像合并、在线圆点和申请人头像仍显示。
- OA打开时恢复原有草稿，仅查看后返回，没有保存、提交或删除。[返回后核对](../test/evidence/avatar-decode-performance-20260903/oa-final-retention.json)：仍2草稿、10已读回执、0本地待提交，三项内容与进入前一致。
- [可复现核对脚本](../scripts/verify-avatar-decode.mjs)读取实际快照与codec结果，[23/23通过](../test/evidence/avatar-decode-performance-20260903/verification.json)：schema15、完整性、消息数量/序号、群已读、当前账号分区、旧待发媒体、OA数据保留。M3仍28条本地消息、2条待发媒体，测试群仍seq6/read6/unread0，M4中账号03/04分区未混用。
- 5次修改前、5次修改后都通过新UI层级定位头像→聊天→一次返回通讯录。修改前5次均热缓存，布局45.500–64.255ms；修改后首次非热缓存66.070ms，后4次热缓存29.734–52.711ms。它们不是物理触摸到出光时延，也不是头像解码时延；前后进程、预热、主机负载不同，不作因果提速结论。
- 修改后raster p95仍有27.302–64.480ms，因此**绘制卡顿仍是开放项**。[计时回调](https://api.flutter.dev/flutter/scheduler/SchedulerBinding/addTimingsCallback.html)本身批量交付帧信息，后续细粒度定位还需准确区分页面过渡和稳定页面帧，不能只按一个p95判断瓶颈。

入口验证与分段证据：[修改前5次](../test/evidence/avatar-decode-performance-20260903/before-avatar.json)、[前分段，末5条为本轮](../test/evidence/avatar-decode-performance-20260903/before-avatar-timing.json)、[修改后5次](../test/evidence/avatar-decode-performance-20260903/after-avatar.json)、[后分段](../test/evidence/avatar-decode-performance-20260903/after-avatar-timing.json)。此前进程记录未删除。

## 尚未通过的范围

1. [真机状态](../test/evidence/avatar-decode-performance-20260903/physical-device-status.json)：RMX3366/Android14，ADB已授权但锁屏，已非阻塞询问用户解锁，本轮未安装或操作真机，不能算真机头像/性能验收。另一个模拟器未改动。
2. 桌面工具当前仍无Windows UI控制能力；[已安装桌面只读状态](../test/evidence/avatar-decode-performance-20260903/desktop-final.json)仅验证进程及IM/OA接口，不冒充桌面UI操作。不能以旧桌面源码代替当前运行的业务基准。
3. 大PNG首次解码、真实大群/长会话滑动帧率、长期内存、多尺寸头像累计缓存、原始图片字节成本和可用真机仍需测量；目前没有消除整体raster高耗时。
4. 原媒体上传500、实际离线推送SDK/配置、iOS原生安全存储、完整D2/改密/多端矩阵、批量追平/更多崩溃窗口、高级OA分支/会签/公式/附件/状态通知仍未完成。它们没有被本轮1004项测试替代。

本轮未提交/推送代码，未变更远端业务流程。目标保持进行中。
