# v0.6.1 启动兼容性修复记录

- 用户症状：孩子端启动后由 macOS 报告“小灯塔 quit unexpectedly”，重新安装没有恢复。
- 当前限制：尚未取得孩子 Mac 的 `.ips` crash report，因此不能把某一条堆栈声明成已证实根因。
- 已证实发布缺陷：`v0.6.0` 正式 ZIP 的主程序只有 `arm64`；发布流程没有阻止单架构 App 出包。
- 对照：`v0.5.0` 也只有 `arm64`，所以这不是 `v0.6.0` 新引入的回归，但会让 Intel 孩子 Mac 无法运行所有这些发布包。

## v0.6.1 修复

- `scripts/package-app.sh` 同时为 `arm64` 与 `x86_64` 构建，并复制 SwiftPM 生成的 Universal 2 主程序。
- `scripts/verify-app-bundle.sh` 在最终 App 边界强制检查两个架构、番茄钟声音资源、plist 与严格代码签名；CI、tag build 和正式发布都复用这条门禁。
- 版本更新为 `0.6.1 (6001)`。

## 本机证据

- 修复前架构门禁失败：`LittleBeacon must be Universal 2; found architectures: arm64`。
- 修复后门禁通过：`Verified Universal 2 app bundle: x86_64 arm64`。
- Apple Silicon 原生切片可以使用旧孩子端配置启动。
- 通过 Rosetta 强制运行 `x86_64` 切片，旧孩子端配置下连续存活 5 秒。
- `v0.6.0` 的旧孩子配置、活动强制休息恢复、24:59 到遮罩触发路径在本机也均可启动；若 `v0.6.1` 在同一孩子 Mac 仍崩溃，必须以真实 crash report 继续定位，不把 Universal 2 修复冒充万能药。
