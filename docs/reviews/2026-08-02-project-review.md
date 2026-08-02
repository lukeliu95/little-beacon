# 小灯塔项目审查（2026-08-02）

## 结论先说

项目的底子是好的：核心规则有纯逻辑测试，远程规则有版本保护，旧数据兼容被认真对待，隐私边界也不是写在海报上就下班了。当前 `main` 能完成 Swift、TypeScript、后端测试、plist 校验和 release 打包。

但“孩子端不可普通退出”和“提醒一定出现在最前面”这两件事，目前代码并没有兑现。现有 25 分钟番茄钟只是主窗口里的可关闭提示，状态存在内存里；窗口关了、应用正常退出了、进程重启了，它也就像下班以后不接电话的同事，联系不上。

因此，新功能不能只把按钮文案从“知道了”改成“确认”。它需要独立状态机、独立 AppKit 遮罩窗口、持久化恢复、退出门禁和真实的多屏 / 全屏验证。

## 本次检查范围

- 仓库结构、Git 基线和发布入口；
- SwiftUI 应用入口、家长端 / 孩子端 UI；
- 1 秒活动监测、25 分钟提醒、违规提醒和坐姿提醒链路；
- 本地状态、钥匙串、30 秒规则同步和后端规则兼容；
- 登录启动、异常恢复、退出入口和打包签名；
- 实际打包应用的设置页与应用菜单；
- 本机 macOS SDK 提供的窗口层级和退出拦截能力。

未执行线上生产部署、数据库写入、GitHub Release 或远端 `main` 实时核对。本次审查不包含发布授权，别趁我不注意把火箭也点了。

## 当前架构

| 层 | 当前职责 | 评价 |
| --- | --- | --- |
| `LittleBeaconCore` | 分类、周计划、违规状态机、使用时长、番茄钟、坐姿判断 | 纯逻辑比例不错，适合继续放状态机 |
| `LittleBeaconApp` | SwiftUI、前台活动、AppleScript、摄像头、声音、通知、持久化、同步 | `AppModel` 已经偏大；强制遮罩不应再塞成一个普通 `activeAlert` |
| `backend` | Vercel API、鉴权、规则、状态、事件、申请 | 权限边界清楚；新规则字段需要继续做旧客户端保留 |
| `packaging` / `scripts` | ad-hoc 签名、Sparkle、LaunchAgent、发布 | 家庭测试链路完整，公开分发仍缺 Developer ID 与公证 |

## 验证结果

- 审查起点：本地 `main`，`HEAD=99024c9`，工作树起初干净，本地记录为 `main...origin/main`。
- `./scripts/run-checks.sh`：通过。
  - Swift Testing：23 项通过；
  - 后端 Node 测试：12 项通过；
  - TypeScript `tsc --noEmit`：通过；
  - 两份 plist：通过。
- `./scripts/package-app.sh`：release 构建、资源复制、ad-hoc codesign 和严格签名校验通过。
- 实际打开打包 App：设置页明确写着现有番茄钟“孩子一键即可关闭”；应用菜单实际存在“隐藏小灯塔”和“退出小灯塔”。

构建绿了，值得高兴三秒。三秒以后还是得看行为，因为构建系统对产品承诺没有道德责任。

## 发现

### P1：文档说“没有普通退出入口”，实际 App 菜单可以正常退出

- `Sources/LittleBeaconApp/LittleBeaconApp.swift:15-20` 只追加了“检查更新”，没有替换系统的退出 / 隐藏命令。
- 实际 UI 中存在“隐藏小灯塔”和“退出小灯塔”。
- `packaging/launch-agent.plist:13-17` 只在 `SuccessfulExit=false` 时恢复；正常退出成功后不会重启。
- `docs/PRODUCT-BRIEF.md:52` 和 ADR-0009 的承诺因此比实现更强。

影响：孩子端可以在提醒出现前正常退出，整个本地执行链路停掉；强制番茄钟更不可能成立。

处理：新功能必须加入活动期退出门禁、移除可见的隐藏 / 退出路径，并验证 LaunchAgent 恢复。整个孩子端“永不普通退出”的旧承诺是否要一并补齐，应作为同一批 P1 修复处理。

### P1：现有提醒不是系统级前台提醒，只是主窗口内部的一层 SwiftUI

- `Sources/LittleBeaconApp/Views.swift:357-359` 只在 `ChildDashboardView` 的 `ZStack` 中绘制提醒。
- `Sources/LittleBeaconApp/Views.swift:445-469` 的遮罩只覆盖这一扇窗口。
- 主窗口关闭、最小化、被其他 App 挡住或当前位于另一个 Space 时，提醒不会主动出现在最前面。

影响：无法满足“盖住其他所有应用”，也没有多显示器保证。

处理：新增独立 AppKit `NSPanel` / `NSWindowController`，每块屏幕一个无边框窗口；普通 `ChildAlert` 继续服务一般提醒，不承担强制休息。

### P1：番茄钟和提醒状态不持久，重启就是失忆

- `Sources/LittleBeaconApp/AppModel.swift:62` 的 `PomodoroTimer` 只在内存中。
- `Sources/LittleBeaconApp/AppModel.swift:98-108` 重选配置会直接清空计时器与提醒。
- `Sources/LittleBeaconApp/Persistence.swift:82-86` 对任何读取 / 解码失败都静默回退到全新快照。
- 状态文件位于孩子用户自己的 Application Support，普通 App 无法把它变成真正防终端篡改的受保护策略存储。

影响：崩溃、更新、重启或状态损坏会让 25 分钟进度和已经触发的休息消失。把强制状态继续塞进整份 `state.json`，只会让鸡蛋和锅一起掉地上。

处理：为强制休息建立独立、版本化、原子写入并带 last-known-good 备份的本地 session store；先落盘，再展示。对熟练终端篡改的抵抗仍需要特权 helper 或 MDM，不能在普通 App 层假装解决。

### P1：现有计时链路不适合作为“精确且不可绕过”的 25+5 分钟依据

- `Sources/LittleBeaconApp/AppModel.swift:400-402` 使用主线程 `Timer` 每秒触发。
- `Sources/LittleBeaconApp/AppModel.swift:410-414` 把一次间隔上限截到 5 秒。
- 同一个主线程 tick 会同步执行前台观察；Safari / Chrome 观察内部使用同步 AppleScript。
- 睡眠、App Nap、主线程阻塞和进程重启都会造成计时缺口。

影响：25 分钟工作累计可以继续采用“活跃秒数”，但确认后的 5 分钟必须使用持久化的绝对截止时间，而不是再数 300 次 tick。

处理：纯状态机接收可注入时钟；工作期用活跃时间，强制休息期用 `acknowledgedAt + 300s`，唤醒 / 重启后重新计算。

### P2：所有提醒共用一个槽位，后来的提醒会覆盖前面的提醒

`Sources/LittleBeaconApp/AppModel.swift:46` 只有一个 `activeAlert`。违规、番茄钟、每日用机和坐姿提醒都会写它；`presentAlert` 没有队列、优先级或不可替换语义。

影响：强制休息若复用这个槽位，可能被下一条普通提醒换掉。

处理：强制休息使用独立状态和独立窗口，优先级高于普通提醒；普通提醒在强制窗口存在时只发系统通知或排队。

### P2：每秒同步写整份 JSON，而且写失败没有可观测性

- `Sources/LittleBeaconApp/AppModel.swift:469` 每个 monitor tick 都调用 `persist()`。
- `Sources/LittleBeaconApp/Persistence.swift:94-106` 每次编码并替换整个文件，最终错误被吞掉。

影响：不必要的磁盘写入、主线程抖动，以及最坏情况下“UI 以为保存了，磁盘其实没听见”。强制状态不能依赖这种含糊成功。

处理：强制 session 转换时立即持久化；普通计数按节流间隔保存。存储 API 返回明确结果，活动强制状态保存失败时不允许静默撤掉遮罩。

### P2：产品文档没有跟上现有番茄钟

`RuleSet`、家长设置和测试已经包含 25 分钟温和提醒，但 README、产品简报和领域词汇没有把它写进产品边界。

影响：现在把它升级成强制休息时，很容易把旧用户的“温和提醒已开启”偷偷解释成“下次更新直接铺满屏幕”。这不是升级，是伏击。

处理：增加明确的 `off / gentle / enforced` 模式；旧数据迁移为 `gentle`，强制模式由家长显式选择。

### P2：公开分发能力仍有已知缺口

当前包通过 ad-hoc 签名，README 也明确说明没有 Developer ID 和公证。家庭内测试可行，但如果以后把强制遮罩公开分发，Gatekeeper、更新授权和信任说明都需要重新验收。

## 值得保留的部分

- `ViolationMachine`、`PomodoroTimer`、`ViewingDistanceJudge` 都是可测试的纯逻辑方向。
- 规则 revision 单调保护和旧 JSON `decodeIfPresent` 已经建立了兼容习惯。
- 后端把家长 / 孩子凭据分权，客户端不直连数据库。
- 摄像头数据只在内存处理，边界写进了 ADR 和 UI。
- 发布脚本会检查分支、工作树、版本号、构建号、测试、签名和 appcast；这条链路挺踏实，不花哨，像一把用了很多年的螺丝刀。

## 审查后的决定

1. 不修改普通 `ChildAlertOverlay` 来假装完成需求。
2. 新建独立的强制番茄钟状态机、持久化 session、声音控制器和多屏遮罩控制器。
3. 旧温和模式不能在升级后静默变成强制模式。
4. “不可关闭”定义为孩子标准账户中的普通 UI / 应用生命周期不可关闭；系统安全界面、管理员恢复、Safe Mode、MDM 和主动终端对抗不在普通 App 保证内。
5. 本次只产出审查、SPEC 与开发计划，不修改业务代码、不提交、不发布。

## 后续处理记录

用户随后明确授权开发与发布。v0.6.0 实现已处理本审查列出的强制番茄钟 P1/P2：三态兼容规则、独立 session、内置声音、多屏 AppKit 遮罩、活动期退出门禁、后端字段保留以及产品文档均已纳入发布候选。审查原文仍保留当时证据，免得历史被修完以后装成从没摔过跤。
