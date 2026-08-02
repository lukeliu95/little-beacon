# 强制 25+5 分钟番茄钟开发计划

- 对应 SPEC：`docs/specs/enforced-pomodoro-break.md`
- 审查基线：`docs/reviews/2026-08-02-project-review.md`
- 执行状态：全部开发切片完成，正在进行提交、PR 与发布

## 交付策略

按可验证的纵向切片开发。每一片先固定公开行为测试，再写最少实现，再跑全量门禁；不等到最后一天突然把窗口、声音、计时、恢复全绑在一起，然后大家围着一只无法关闭的全屏 Bug 举行团建。

本计划本身不构成发布授权；用户已在后续指令中明确授权开发、PR、打标签和发布版本。

## 公开测试缝

实现前先同意以下接口边界，测试只通过这些边界观察行为：

- `PomodoroBreakMachine`：纯逻辑状态机；输入活跃 / 空闲时间、确认、刷新、关闭；输出状态与副作用意图。
- `Clock`：提供 wall time 与 monotonic time，测试可冻结 / 跳时钟。
- `PomodoroSessionStore`：版本化读写、last-known-good 恢复和明确错误。
- `BreakShieldPresenting`：展示、更新、撤销所有屏幕遮罩；测试不依赖真实窗口服务器。
- `BreakAlarmPlaying`：开始重复警报、停止、播放完成音。
- `ApplicationTerminationGuarding`：活动 session 是否拒绝正常终止。
- UI `accessibilityIdentifier`：确认、倒计时、关闭、多屏状态的稳定验收点。

这些缝不是为了把代码抽象成一盘意大利面，而是让最危险的行为能在不等 25+5 分钟的情况下被证明。

## Slice 0：冻结基线与测试夹具

目标：保证后续失败真的是新改坏的，不是地板原本就在响。

工作：

- 记录当前 `HEAD`、版本 / 构建号与工作树状态；
- 再跑 `./scripts/run-checks.sh` 和 `./scripts/package-app.sh`；
- 为测试加入可注入时钟与 25 分钟 / 5 分钟常量入口，生产值保持固定；
- 建立 AppKit UI 测试的最小宿主，不接生产 App 状态；
- 把现有温和番茄钟行为写成回归测试，避免迁移时把旧模式顺手踩扁。

完成标准：基线测试绿，测试可以在毫秒内推进 30 分钟逻辑时间。

## Slice 1：规则三态与兼容迁移

目标：先解决“旧温和开关不能自动变强制”这件产品安全问题。

预计文件：

- `Sources/LittleBeaconCore/Models.swift`
- `Tests/LittleBeaconCoreTests/BackwardCompatibilityTests.swift`
- `backend/src/domain.ts`
- `backend/test/domain.test.ts`
- `Sources/LittleBeaconApp/AppModel.swift`
- `Sources/LittleBeaconApp/Views.swift`

红灯测试：

- 旧 `pomodoroEnabled=true/false` 分别迁移为 `gentle/off`；
- 新 `pomodoroMode=enforced` 往返编码不丢失；
- 后端拒绝未知模式；
- 老客户端上传缺少 `pomodoroMode` 时保留服务器现值；
- 家长设置能选三态，孩子端没有本地关闭入口；
- 活动 session 中远程切模式只在下一轮生效。

实现：

- 增加 `PomodoroMode`；
- 暂时保留 `pomodoroEnabled` 兼容镜像；
- 更新默认规则、后端校验和 merge key；
- 修改家长端文案，明确“温和”和“强制 25+5”。

完成标准：旧家庭升级后行为不变，新模式可以安全同步。

建议提交：`Add backward-compatible pomodoro modes`

## Slice 2：纯强制休息状态机

目标：让“确认之前永远不能关、确认后完整等 5 分钟”先在纯逻辑里站住。

预计文件：

- 新增 `Sources/LittleBeaconCore/PomodoroBreak.swift`
- 新增 `Tests/LittleBeaconCoreTests/PomodoroBreakTests.swift`
- 调整 `Sources/LittleBeaconCore/UsageTracking.swift`

红灯测试：

- 24:59 / 25:00 边界；
- 2 分钟自然休息重置；短空闲只暂停；
- 重复 tick 不重复触发；
- 未确认经过任意时间仍不可关闭；
- 确认时间决定 `closeAvailableAt`；
- 4:59.999 不可关，5:00 可关；
- 重复确认和重复刷新幂等；
- 到点不自动完成；
- 只有合法关闭事件回到新工作轮；
- 负 elapsed、时钟回拨和大幅跳时钟的保守行为；
- 活动 session 中规则切换不清状态。

实现：

- `PomodoroBreakState` Codable enum；
- `PomodoroBreakMachine` 只产出 transition / effect，不直接播声音或碰 AppKit；
- 保留温和模式所需的现有计时行为，避免两种模式互相污染。

完成标准：所有产品验收时序都由纯测试证明。

建议提交：`Model enforced pomodoro break lifecycle`

## Slice 3：独立 session 持久化与崩溃恢复

目标：重启不失忆，整份 `state.json` 损坏也不顺带赦免活动休息。

预计文件：

- 新增 `Sources/LittleBeaconApp/PomodoroSessionStore.swift`
- 新增 `Tests/LittleBeaconAppTests/PomodoroSessionStoreTests.swift`
- 调整 `Sources/LittleBeaconApp/Persistence.swift`
- 调整 `Sources/LittleBeaconApp/AppModel.swift`

红灯测试：

- 每个状态编码 / 解码；
- 旧版本 / 缺字段迁移；
- 原子替换成功与失败；
- 主文件损坏时恢复 last-known-good；
- 两份都损坏时返回显式错误，不回退成“从没触发”；
- 触发、确认、完成的落盘顺序；
- 三个阶段模拟重启恢复；
- 普通 LocalSnapshot 解码失败不删除独立 session。

实现：

- 独立 session 文件与备份；
- 存储方法返回结果；
- 只在状态转换和节流计数点写入，停止每秒为番茄钟写整份快照；
- 启动最早阶段读取 session。

完成标准：进程退出 / 重建模型后，状态与关闭资格不发生漂移。

建议提交：`Persist and restore active pomodoro sessions`

## Slice 4：可重复警报声音

目标：声音行为确定、可测、失败不影响遮罩。

预计文件：

- 新增打包资源 `Sources/LittleBeaconApp/Resources/pomodoro-alarm.*`
- 新增打包资源 `Sources/LittleBeaconApp/Resources/pomodoro-complete.*`
- 调整 `Sources/LittleBeaconApp/SystemServices.swift`
- 新增 `Tests/LittleBeaconAppTests/BreakAlarmControllerTests.swift`

红灯测试：

- 触发立即播放；
- 未确认每 30 秒一次；
- 确认后停止；
- 到点只播一次完成音；
- 重复恢复不叠加多个播放器 / 定时器；
- 播放失败只报告错误，不推进状态。

实现：

- `BreakAlarmPlaying` 协议；
- 生产实现用持有型 `AVAudioPlayer`；
- 测试用 spy player；
- 音量服从系统，不修改用户设置。

完成标准：声音副作用与状态机解耦，重复进入 / 恢复无声浪叠罗汉。

建议提交：`Add persistent break alarm playback`

## Slice 5：AppKit 多屏前台遮罩

目标：真正盖住普通应用，不再把希望寄托在主窗口是不是刚好开着。

预计文件：

- 新增 `Sources/LittleBeaconApp/BreakShieldWindowController.swift`
- 新增 `Sources/LittleBeaconApp/BreakShieldView.swift`
- 新增 `Tests/LittleBeaconAppTests/BreakShieldWindowControllerTests.swift`
- 调整 `Package.swift`（如 UI 测试宿主需要）

红灯 / 集成测试：

- 一块屏幕对应一个遮罩窗口；
- 主屏幕有操作按钮，副屏不暴露关闭；
- borderless、无标准按钮、正确 window level 和 collection behavior；
- `windowShouldClose=false`；
- 显示器热插拔重建集合；
- 状态更新不销毁 / 重建所有窗口导致闪烁；
- SwiftUI View 在等待确认、休息、可关闭三态只暴露允许控件；
- accessibility identifier 与 VoiceOver 标签存在。

实现：

- `BreakShieldPresenting` 协议；
- `NSHostingView` 承载 SwiftUI 内容；
- `NSScreenSaverWindowLevel`、所有 Spaces、全屏辅助行为；
- 监听屏幕参数、唤醒与 App 激活事件；
- 不采用 display capture、辅助功能权限或私有 API。

完成标准：主窗口关闭后遮罩仍在；普通窗口、菜单栏、Dock、常规全屏 App 与所有连接屏幕都被覆盖。

建议提交：`Present enforced breaks above all normal app windows`

## Slice 6：App 生命周期、退出门禁与功能协作

目标：把状态机、持久化、窗口和声音接进真实 App，并堵住正常退出路径。

预计文件：

- 新增 `Sources/LittleBeaconApp/ApplicationLifecycleController.swift`
- 调整 `Sources/LittleBeaconApp/LittleBeaconApp.swift`
- 调整 `Sources/LittleBeaconApp/AppModel.swift`
- 调整 `Sources/LittleBeaconApp/Views.swift`
- 评估 `packaging/launch-agent.plist` 与 Sparkle 更新配合

红灯 / 集成测试：

- AppModel 达到阈值后按“持久化 → 遮罩 → 声音”顺序调用；
- 活动 session 中普通 terminate 被拒绝；
- Command-Q、Command-W、Esc、Hide 不撤罩；
- 强制结束后 LaunchAgent 恢复，session 重新展示；
- 主窗口关闭不影响遮罩；
- 普通 `activeAlert` 不能替换强制遮罩；
- 坐姿检查暂停；
- 小灯塔遮罩不计入每日使用；
- 更新请求延迟到 session 完成；
- session 完成后模式已切 `off` 时不开始下一轮。

实现：

- `@NSApplicationDelegateAdaptor` 接入退出判断；
- 在活动 session 中替换 / 禁用 app termination 与 visibility 命令；
- `PomodoroBreakCoordinator` 编排状态、副作用与恢复；
- 把同步 AppleScript 观察与强制 UI 时钟解耦；
- 明确 LaunchAgent、Sparkle 和管理员维护的退出握手。

完成标准：普通 UI 路径不能提前撤销活动 session，更新流程也不会和恢复进程互相踩脚。

建议提交：`Integrate enforced breaks with app lifecycle`

## Slice 7：产品文档与管理员恢复边界

目标：用户看到的不是“温和提醒”旧文案，维护者也知道这东西到底能强到哪里。

预计文件：

- `README.md`
- `docs/PRODUCT-BRIEF.md`
- `CONTEXT.md`
- 新增 `docs/adr/0011-enforce-acknowledged-pomodoro-breaks.md`
- 安装 / 恢复说明

工作：

- 增加番茄钟领域术语和三态模式；
- 写清确认后 5 分钟、永不自动关闭和旧用户迁移；
- 写清普通 App 与 MDM / 特权 helper 的边界；
- 记录家长管理员的故障恢复流程，不在孩子 UI 暴露万能快捷键；
- 更新隐私说明：session 本地保存，不上传确认历史；
- 更新版本号只在确定发布批次时做，不提前拿版本号当装饰品。

完成标准：代码、设置页、产品简报、ADR 和安装说明说的是同一件事。

建议提交：`Document enforced break behavior and recovery boundaries`

## Slice 8：真实运行验收

自动门禁：

```bash
./scripts/run-checks.sh
./scripts/package-app.sh
```

真实 App 验收矩阵：

| 场景 | 必测 |
| --- | --- |
| 单屏普通桌面 | 触发、确认、4:59、5:00、手动关闭 |
| 双屏 / 热插拔 | 两屏无裸露；主副屏角色正确 |
| macOS 全屏 App | 遮罩位于其上且可操作 |
| 多 Space / Mission Control | 切换后遮罩仍存在 |
| 主窗口关闭 / 最小化 | 遮罩不受影响 |
| 键盘逃逸 | Esc、Command-W/Q/H、Return 焦点 |
| 进程恢复 | 三阶段分别 `kill`，LaunchAgent 恢复同状态 |
| 睡眠 / 唤醒 | 确认前后分别测试 |
| 锁屏 / 解锁 | 系统界面优先；回来恢复 |
| 规则同步 | 活动期切 off；完成后停止新轮次 |
| 断网 | 本地完成整轮；恢复网络后不重复触发 |
| 声音异常 | 静音、音量零、输出切换、播放器失败 |
| Sparkle | 活动期更新延迟；完成后可正常更新 |
| VoiceOver / 键盘 | 状态可理解，隐藏按钮不可聚焦 |

需要保存的证据：

- 每个关键阶段的窗口层级 / 多屏截图；
- LaunchAgent 恢复前后进程与 session 状态；
- 自动测试结果；
- release 包版本、codesign 校验与 Info.plist；
- 一份失败项清单，不能把“手测时没碰到”写成“绝不会发生”。

完成标准：SPEC 的 19 条验收标准逐条有自动测试或真实运行证据。

## 风险与处理

| 风险 | 处理 |
| --- | --- |
| 旧用户升级后突然被强制锁前台 | 三态迁移，旧 `true` 只映射 gentle |
| AppKit window level 在系统版本 / 全屏场景表现不同 | macOS 14+ 实机矩阵；只用公开层级；记录系统例外 |
| 进程重启丢状态 | 独立原子 session + last-known-good + 启动最早恢复 |
| 系统时间被改造成提前完成 | 活动会话内结合 monotonic clock；重启后管理员改时列为系统边界 |
| 提醒互相覆盖 | 强制遮罩独立优先级；普通提醒排队 / 通知 |
| LaunchAgent 与 Sparkle 争夺进程 | 明确维护退出握手并做更新实测 |
| 状态文件可被熟练用户篡改 | 不做虚假承诺；若产品要求对抗，另立 privileged helper / MDM 项目 |
| 无关闭路径造成真实故障时困住用户 | 保留系统级家长管理员恢复路径；无孩子 UI 后门；恢复流程实测并文档化 |

## 不在本计划里顺手做的事

- 不重写整个 `AppModel`；只抽离强制休息所需的深模块。
- 不增加番茄钟历史、积分、家长日报或后端遥测。
- 不把固定 25 / 5 分钟做成任意配置。
- 不借机接入 MDM、Screen Time 私有能力或 Accessibility 注入。
- 不自动创建 PR、合并、部署或发布。

## Definition of Done

- 三态规则兼容旧家庭；
- 状态机、持久化、声音、窗口和生命周期各有独立测试；
- 强制 session 在确认前、5 分钟内和可关闭后都能跨重启恢复；
- 所有普通关闭 / 隐藏路径无法提前撤罩；
- 多屏、全屏、Space、睡眠、锁屏、热插拔、更新和恢复均有真实 App 证据；
- 全量检查与 release 打包通过；
- README、产品简报、领域词汇、ADR、UI 文案一致；
- 工作树只包含明确属于本功能的变更；
- 到这里才算“做完”。能编译只是程序会呼吸，不代表它已经会做人。
