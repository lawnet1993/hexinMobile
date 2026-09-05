# 664 全部应用密度、当前目录图标与真实入口回归

时间：2026-09-02 22:14–22:24（中国时间）。结论：本项完成，完整 IM/OA 目标继续，不能据此判定全功能验收通过。

## 当前基准与问题

- 使用已安装 Windows 1.0.87 的 test01 现有会话，只读 GET `/api/oa/app-catalog`，22:14:49 返回 HTTP 200。目录版本为 `de205a597fd565e84b8b33f989ca3b15c89b51f7a49b1a9857fd087d0815a084`，10 项。此项是当前会话接口核对，不是桌面 UI 操作证据。
- 真正目录的图标键包括 `payments`、`account_balance_wallet`、`shopping_cart` 等，旧移动端未映射，变成相同九宫格；首页还依赖中文标题猜图标，和全部应用不一致。
- 每个分类内部的 shrinkWrap GridView 没有显式 padding，重复继承底部安全区。旧黄金图没有安全区，无法发现设备上的多余空白。

| 目录键 | 名称 | 后台图标键 |
| --- | --- | --- |
| attendance.punch | 打卡 | access_time |
| attendance.leave | 请假审批 | event_busy |
| attendance.overtime | 加班审批 | more_time |
| attendance.business_trip | 出差审批 | flight_takeoff |
| expense.reimbursement | 报销审批 | receipt_long |
| attendance.punch_correction | 补卡审批 | event_repeat |
| finance.payment_request | 请款审批 | payments |
| finance.advance_request | 借支审批 | account_balance_wallet |
| procurement.purchase_request | 采购申请 | shopping_cart |
| administration.seal_use | 用印申请 | approval |

以上 10 项均无自定义图片。保留后台顺序、名称、分类和模板路由；没有修改线上配置。

## 修改

- 分类 GridView 明确 `padding: EdgeInsets.zero`、`primary: false`；保留五列、32dp 图标、20dp 字形和最多三行名称，大字号时按文字高度增加格子高度。
- 补充当前目录键的 TDesign 语义图标。钱包字形使用本机官方 `tdesign_flutter-0.2.7` 字体映射 `0xE818`，未另造图形。
- 首页和全部应用使用同一 `MobileAppIcon`，优先保留后台自定义图片/emoji/识别到的图标；通用 approval/未知配置的核心应用按稳定 applicationKey 兜底，不再按标题猜测。
- 未安装或替换用户刚索取的品牌启动图标；那是独立 PNG 交付，不属于本项。

## 自动化证据

证据目录：`test/evidence/app-catalog-density-20260902/`。

- 新增 `app_catalog_density_test.dart` 5 项：当前图标键、360/411dp 加真实安全区、1.5 倍字体长名称及原模板路由、改名后首页/全部应用共享自定义图标。修复前 5 项失败；修复后与图标/页面专项合跑 **38/38**。
- `flutter analyze`：0 问题，`analyze.log`。
- 初次全量：506 通过、2 张黄金图差异（02 首页及 13 更新抽屉背后的首页）。检查差异图，仅预期的两枚首页图标变化；只更新这两张基线，03 全部应用原基线未改。
- 最终 `flutter test`：**508/508**，`full-tests-after.log`。
- `git diff --check`：退出码 0。现有 LF/CRLF 提醒保留，不批量格式化用户改动。
- 黄金图仍存在历史字体未完整装载的方框问题，本轮不能将它视为所有中文字形/图标正确的证明；实际字形使用下述正常 APK 截图核验。此测试基建问题待补。

## 独立模拟器真实验证

仅操作 M3 / emulator-5556 / test03 / Android 16 / 1080×2400 / density 420；M1 真机、M2 未安装、未点击、未切网络。模拟器时区 UTC，截图约 14:22，对应中国时间 22:22。

1. 663 原包拍摄 `01-before-home`、`02-before-catalog` PNG/XML。
2. 安装正常 profile 包、真实冷启动；第一次立即 dump 遇到 `null root node`，不重装、不重启模拟器，随后重新观察成功。
3. `03-after-home`、`04-after-catalog`：十个应用可见，钱款/钱包/购物车/用印等字形正常，首页和全部应用一致。
4. 请款分类入口 → 真正“请款审批”模板、财顺 v1、部门负责人 Test Terminal 03；打开“请款类型”是底部抽屉，有合同付款/采购付款/服务付款/其他，关闭后未选择值。证据 `05-payment-route`、`06-payment-loaded`、`07-payment-type-sheet`。
5. 返回目录 → 借支入口 → 真正“借支审批”，包含币种/借支用途/预计归还日期，审批人正常。证据 `08-return-catalog`、`09-advance-route`。
6. 返回首页 `10-final-home.xml`，Wi-Fi=1、移动数据=1、默认网络 120。未提交审批、未选择文件、未新增草稿。只读 SQLite 元数据确认 Outbox 仍空、原请假草稿 ID 和时间未变（`final-oa-metadata.json`）。

### 相同设备像素对比

| 测量项 | 修改前 | 修改后 |
| --- | --- | --- |
| 分类卡片范围 | y=299…1898，高1599px | y=299…1583，高1284px |
| 报销格顶部 | 683px | 620px |
| 请款格顶部 | 1000px | 874px |
| 采购格顶部 | 1318px | 1129px |
| 用印格顶部 | 1635px | 1383px |

总高度减少315px，即120dp；每个分类去掉24dp重复安全区，图标与触控格本身未缩小。

正常包：`flutter build apk --profile --target lib/main.dart --target-platform android-arm64,android-x64` 成功，84,396,355 字节。构建包与已安装 base.apk SHA256 一致：

`AFAB4BB40861BE2A7F5CBCEBBF0A43EB099BB378025F7CD198112ED171E324A3`

## 未完成及后续

- 全部应用初次加载/失败/真正空目录仍共用“暂无匹配应用”，需区分并增加重试；本项不掩盖该问题。
- 大字体长名称已做 widget 回归，未改真实服务器标题或用户设备字体。没有证明所有字体/窄屏组合通过。
- 本轮未提交请款/借支，不能作为公式、复杂分支、多审批人、通知全链路通过证据。
- OA 其他详情/处理/通知已读 flush 会话归属、服务端群消息/未读投影 P1、自然过期续期、推送、完整桌面与多设备/性能验收继续保留。真机更新需避免打断用户操作。
