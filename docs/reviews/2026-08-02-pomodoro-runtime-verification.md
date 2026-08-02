# v0.6.0 强制番茄钟运行验收记录

- 日期：2026-08-02
- 构建：`0.6.0 (6000)`
- 环境：当前 macOS 图形会话（WindowServer 暴露 1 块屏幕）

## 自动门禁

- `./scripts/run-checks.sh`：43 个 Swift 测试、14 个后端测试、TypeScript 检查和 plist 校验通过。
- `./scripts/package-app.sh`：release 构建、SwiftPM 资源复制、ad-hoc 签名和严格签名校验通过。
- App bundle 内确认存在 `pomodoro-alarm.wav` 与 `pomodoro-complete.wav`。
- 窗口契约测试按 `NSScreen.screens` 验证一屏一面板、screen-saver 层级、无关闭按钮、加入所有 Spaces、支持全屏辅助窗口且失焦不隐藏。
- 状态机测试覆盖 25:00 触发、确认后完整 5:00、未确认不推进、到点不自动关闭、同一次开机墙钟前跳不提前完成、重启后的墙钟回退，以及 session last-known-good 恢复。

## 实际界面验证

- 打开最终打包 App，设置页显示三态选择：关闭 / 温和提醒 / 强制休息；版本显示 `0.6.0（6000）`。
- 用直接复用生产 `BreakShieldWindowController` 的临时验收宿主展示等待确认态：全屏最前方只有 `确认，我现在开始休息`，标识为 `pomodoro.break.acknowledge`，没有关闭按钮。
- 点击确认后页面显示正确的 `4:xx` 倒计时，没有关闭按钮。
- 验收宿主推进到 ready 状态后，才出现 `关闭并开始下一轮`，标识为 `pomodoro.break.close`。
- 先把普通小灯塔窗口进入 macOS 全屏 Space，再启动遮罩；screen-saver 层级遮罩仍成为可见、可操作的最前方 system dialog。
- 实际界面检查曾发现倒计时分钟插值错误和辅助功能标识被父容器覆盖；两项已修复，倒计时另有回归测试。

## 尚未在本机物理验证

当前图形会话没有第二块显示器，因此没有伪造“双屏实机已通过”。多屏创建与窗口属性由自动契约测试覆盖；发布后仍应在一台实际双显示器孩子 Mac 上补做热插拔、主副屏按钮唯一性和全屏 Space 验收。声音资源与播放器链路有自动测试，辅助功能树不能证明扬声器在当前音量下实际可听。
