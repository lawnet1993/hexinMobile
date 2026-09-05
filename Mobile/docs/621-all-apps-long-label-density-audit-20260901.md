# 移动端“全部应用”长名称与密度验收

## 问题

真机和模拟器的“全部应用”页均把服务端长应用名省略为“外站通道…”、“分级请款…”，用户无法确认具体业务入口。首页常用应用仍应保持单行紧凑，但完整目录页应优先展示真实名称。

## 修正

- 保持五列目录和 32dp 图标不变。
- 应用格高度由 58dp 调整为 72dp。
- 标签支持最多三行，完整保留服务端名称；极端超长内容才使用省略。
- 分类、显示顺序和真实路由来源不变。
- 搜索框和页面返回交互不变。

## 证据

修正前：

- `Mobile/test/evidence/85-all-apps-real.png`
- `Mobile/test/evidence/86-all-apps-emulator.png`

最终：

- `Mobile/test/evidence/92-all-apps-compact-final-real.png`
- `Mobile/test/evidence/93-all-apps-compact-final-emulator.png`

真机 360dp 级宽度下，“外站通道及数据费用请款”和“分级请款审批”均完整显示；模拟器 411dp 级宽度下保持两行紧凑显示。两端进程存活，清空日志后未出现新的 AndroidRuntime 或 Flutter 错误。

## 回归

- `flutter analyze`：通过。
- 全量 `flutter test`：274/274 通过。
- `03-all-apps` 视觉基准已按批准后的三行高密度布局更新。
- `flutter build apk --profile`：通过，并重新安装真机和模拟器。
