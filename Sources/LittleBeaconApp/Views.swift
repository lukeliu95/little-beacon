import SwiftUI
import LittleBeaconCore

private enum ParentSection: String, CaseIterable, Identifiable {
    case overview = "概览"
    case rules = "每周时段"
    case requests = "临时申请"
    case settings = "设置"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .overview: "rectangle.3.group"
        case .rules: "calendar"
        case .requests: "hand.raised"
        case .settings: "gearshape"
        }
    }
}

struct RootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Group {
            switch model.role {
            case .unconfigured:
                RoleSelectionView(model: model)
            case .parent:
                ParentShellView(model: model)
            case .child:
                ChildDashboardView(model: model)
            }
        }
        .frame(minWidth: 820, minHeight: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottomTrailing) {
            if let error = model.lastError {
                ErrorToast(message: error)
                    .padding(20)
            }
        }
    }
}

private struct RoleSelectionView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.indigo.opacity(0.18), Color.cyan.opacity(0.08), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 28) {
                Image(systemName: "light.beacon.max.fill")
                    .font(.system(size: 52, weight: .medium))
                    .foregroundStyle(.indigo)
                VStack(spacing: 8) {
                    Text("小灯塔")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("先讲清规则，再安静地守住它。")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 18) {
                    RoleCard(
                        icon: "person.crop.circle.badge.checkmark",
                        title: "这是家长 Mac",
                        detail: "设置时段、审批申请、接收提醒",
                        tint: .indigo
                    ) { model.configure(role: .parent) }
                    RoleCard(
                        icon: "laptopcomputer",
                        title: "这是孩子 Mac",
                        detail: "显示规则、申请时间、执行提醒",
                        tint: .teal
                    ) { model.configure(role: .child) }
                }
                .frame(maxWidth: 700)
                Text("孩子端始终可见；小灯塔不记录屏幕、按键或聊天内容。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(48)
        }
    }
}

private struct RoleCard: View {
    let icon: String
    let title: String
    let detail: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 30))
                    .foregroundStyle(tint)
                Text(title).font(.title3.bold())
                Text(detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Label("继续", systemImage: "arrow.right")
                    .font(.headline)
                    .foregroundStyle(tint)
            }
            .frame(maxWidth: .infinity, minHeight: 180, alignment: .leading)
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(tint.opacity(0.22), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(detail)
    }
}

private struct ParentShellView: View {
    @ObservedObject var model: AppModel
    @State private var selection: ParentSection? = .overview

    var body: some View {
        NavigationSplitView {
            List(ParentSection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
            }
            .navigationTitle("小灯塔")
            .safeAreaInset(edge: .bottom) {
                ConnectionBadge(text: model.connectionMessage)
                    .padding(12)
            }
        } detail: {
            switch selection ?? .overview {
            case .overview: ParentOverviewView(model: model)
            case .rules: RulesView(model: model)
            case .requests: RequestsView(model: model)
            case .settings: SettingsView(model: model)
            }
        }
    }
}

private struct ParentOverviewView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(title: "家里现在怎样", subtitle: "只显示当前状态，不保存普通活动流水账。")
                HStack(spacing: 16) {
                    StatusCard(status: model.currentStatus)
                    MetricCard(
                        title: "近 30 天违规",
                        value: "\(model.events.count)",
                        detail: model.events.isEmpty ? "安安静静，挺好。" : "事件到期自动删除",
                        icon: "bell.badge",
                        tint: .orange
                    )
                    MetricCard(
                        title: "待处理申请",
                        value: "\(model.requests.filter { $0.status == .pending }.count)",
                        detail: "15 / 30 / 60 分钟",
                        icon: "hand.raised",
                        tint: .indigo
                    )
                }

                HStack {
                    Text("最近事件").font(.title2.bold())
                    Spacer()
                    Button("立即同步") { Task { await model.syncNow() } }
                }

                if model.events.isEmpty {
                    EmptyState(
                        icon: "checkmark.seal",
                        title: "暂时没有违规事件",
                        detail: "合规活动不会出现在这里。空白不是坏事，空白有时很贵。"
                    )
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(model.events.prefix(12)) { event in
                            EventRow(event: event)
                        }
                    }
                }
            }
            .padding(28)
        }
        .navigationTitle("概览")
    }
}

private struct ChildDashboardView: View {
    @ObservedObject var model: AppModel
    @State private var selectedCategory: ActivityCategory = .game
    @State private var selectedDuration = 30

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("小灯塔正在工作")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                        Text("看得见，也说得清。")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    ConnectionBadge(text: model.connectionMessage)
                }

                if let warning = model.warningMessage {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(.orange)
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                }

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("当前前台活动")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            CategoryIcon(category: model.currentActivity.category)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(model.currentActivity.category.displayName)
                                    .font(.title2.bold())
                                Text(model.currentActivity.observation.appName.isEmpty
                                     ? "没有检测到前台应用"
                                     : model.currentActivity.observation.appName)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .cardStyle()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("隐私边界")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Label("不截屏、不记按键", systemImage: "eye.slash")
                        Label("只在违规时生成事件", systemImage: "list.bullet.rectangle")
                        Label("事件 30 天后删除", systemImage: "calendar.badge.minus")
                    }
                    .cardStyle()
                }

                VStack(alignment: .leading, spacing: 16) {
                    Text("申请临时使用").font(.title2.bold())
                    HStack {
                        Picker("类别", selection: $selectedCategory) {
                            Text("游戏").tag(ActivityCategory.game)
                            Text("视频").tag(ActivityCategory.video)
                        }
                        .pickerStyle(.segmented)
                        Picker("时长", selection: $selectedDuration) {
                            Text("15 分钟").tag(15)
                            Text("30 分钟").tag(30)
                            Text("60 分钟").tag(60)
                        }
                        .frame(width: 150)
                        Button("发送申请") {
                            model.requestTemporaryUse(category: selectedCategory, durationMinutes: selectedDuration)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Text("家长批准后立即生效，到期自动恢复原来的每周时段。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .cardStyle()

                ChildRuleSummary(rules: model.rules, lastSyncAt: model.snapshot.lastRulesSyncAt)
                SettingsView(model: model, compact: true)
            }
            .padding(28)
        }
    }
}

private struct RulesView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(title: "每周允许时段", subtitle: "游戏和视频分别设置；时段之外会进入三次提醒流程。")
                RuleSection(category: .game, model: model, tint: .purple)
                RuleSection(category: .video, model: model, tint: .blue)
                OverridesEditor(model: model)
            }
            .padding(28)
        }
        .navigationTitle("每周时段")
    }
}

private struct RuleSection: View {
    let category: ActivityCategory
    @ObservedObject var model: AppModel
    let tint: Color
    private let weekdays = [(2, "周一"), (3, "周二"), (4, "周三"), (5, "周四"), (6, "周五"), (7, "周六"), (1, "周日")]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                CategoryIcon(category: category, tint: tint)
                Text("\(category.displayName)时段").font(.title2.bold())
            }
            ForEach(weekdays, id: \.0) { weekday, name in
                let window = model.rules.activityRules
                    .first(where: { $0.category == category })?
                    .windows.first(where: { $0.weekday == weekday })
                ScheduleDayRow(
                    name: name,
                    category: category,
                    weekday: weekday,
                    initialWindow: window,
                    model: model
                )
            }
        }
        .cardStyle()
    }
}

private struct ScheduleDayRow: View {
    let name: String
    let category: ActivityCategory
    let weekday: Int
    @ObservedObject var model: AppModel
    @State private var enabled: Bool
    @State private var start: Date
    @State private var end: Date

    init(
        name: String,
        category: ActivityCategory,
        weekday: Int,
        initialWindow: ScheduleWindow?,
        model: AppModel
    ) {
        self.name = name
        self.category = category
        self.weekday = weekday
        self.model = model
        _enabled = State(initialValue: initialWindow != nil)
        _start = State(initialValue: Self.date(from: initialWindow?.startMinute ?? 18 * 60))
        _end = State(initialValue: Self.date(from: initialWindow?.endMinute ?? 20 * 60))
    }

    var body: some View {
        HStack {
            Toggle(name, isOn: $enabled)
                .toggleStyle(.switch)
                .frame(width: 120, alignment: .leading)
            Spacer()
            if enabled {
                DatePicker("开始", selection: $start, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                Text("—").foregroundStyle(.tertiary)
                DatePicker("结束", selection: $end, displayedComponents: .hourAndMinute)
                    .labelsHidden()
            } else {
                Text("不允许").foregroundStyle(.secondary)
            }
        }
        .onChange(of: enabled) { _, _ in save() }
        .onChange(of: start) { _, _ in save() }
        .onChange(of: end) { _, _ in save() }
    }

    private func save() {
        model.addOrUpdateWindow(
            category: category,
            weekday: weekday,
            enabled: enabled,
            startMinute: Self.minutes(from: start),
            endMinute: Self.minutes(from: end)
        )
    }

    private static func date(from minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
    }

    private static func minutes(from date: Date) -> Int {
        Calendar.current.component(.hour, from: date) * 60 + Calendar.current.component(.minute, from: date)
    }
}

private struct OverridesEditor: View {
    @ObservedObject var model: AppModel
    @State private var target: OverrideTarget = .domain
    @State private var value = ""
    @State private var category: ActivityCategory = .video

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("家长分类覆盖").font(.title2.bold())
            Text("覆盖优先于内置清单。域名只填主机名，例如 example.com。")
                .foregroundStyle(.secondary)
            HStack {
                Picker("目标", selection: $target) {
                    Text("域名").tag(OverrideTarget.domain)
                    Text("应用 Bundle ID").tag(OverrideTarget.bundleIdentifier)
                }
                .frame(width: 160)
                TextField(target == .domain ? "example.com" : "com.example.app", text: $value)
                Picker("分类", selection: $category) {
                    Text("游戏").tag(ActivityCategory.game)
                    Text("视频").tag(ActivityCategory.video)
                    Text("忽略").tag(ActivityCategory.other)
                }
                .frame(width: 110)
                Button("添加") {
                    model.addOverride(target: target, value: value, category: category)
                    value = ""
                }
                .disabled(value.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ForEach(model.rules.overrides) { item in
                HStack {
                    Label(item.value, systemImage: item.target == .domain ? "globe" : "app")
                    Spacer()
                    Text(item.category.displayName).foregroundStyle(.secondary)
                    Button(role: .destructive) { model.removeOverride(id: item.id) } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .cardStyle()
    }
}

private struct RequestsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(title: "临时申请", subtitle: "批准后立即开始，到期不留尾巴。")
                if model.requests.isEmpty {
                    EmptyState(icon: "hand.raised.slash", title: "没有申请", detail: "有时候安静就是一条消息。")
                } else {
                    ForEach(model.requests) { request in
                        HStack(spacing: 16) {
                            CategoryIcon(category: request.category)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(request.category.displayName) · \(request.durationMinutes) 分钟")
                                    .font(.headline)
                                Text(request.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if request.status == .pending {
                                Button("拒绝") { model.resolveRequest(request, approved: false) }
                                Button("批准") { model.resolveRequest(request, approved: true) }
                                    .buttonStyle(.borderedProminent)
                            } else {
                                Text(request.status == .approved ? "已批准" : "已拒绝")
                                    .foregroundStyle(request.status == .approved ? .green : .secondary)
                            }
                        }
                        .cardStyle()
                    }
                }
            }
            .padding(28)
        }
        .navigationTitle("临时申请")
    }
}

private struct SettingsView: View {
    @ObservedObject var model: AppModel
    @EnvironmentObject private var updates: UpdateController
    var compact = false
    @State private var baseURL = ""
    @State private var setupKey = ""
    @State private var pairCode = ""
    @State private var overrideTarget: OverrideTarget = .domain

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !compact {
                    PageHeader(title: "连接与设备", subtitle: "远程数据库只藏在 API 后面，客户端不碰数据库密码。")
                } else {
                    Text("连接设置").font(.title2.bold())
                }
                VStack(alignment: .leading, spacing: 12) {
                    TextField("https://little-beacon-api.vercel.app", text: $baseURL)
                        .textFieldStyle(.roundedBorder)
                    if model.role == .parent {
                        SecureField("首次部署密钥", text: $setupKey)
                            .textFieldStyle(.roundedBorder)
                        HStack {
                            Button("建立家长端") {
                                Task { await model.bootstrapParent(baseURL: baseURL, setupKey: setupKey) }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(baseURL.isEmpty || setupKey.isEmpty || model.isBusy)
                            Button("生成配对码") { Task { await model.generatePairingCode() } }
                                .disabled(!model.hasRemoteConfiguration || model.isBusy)
                        }
                        if let code = model.pairingCode {
                            HStack {
                                Text(code)
                                    .font(.system(size: 30, weight: .bold, design: .monospaced))
                                if let expires = model.pairingCodeExpiresAt {
                                    Text("有效至 \(expires.formatted(date: .omitted, time: .shortened))")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(12)
                            .background(Color.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                        }
                    } else {
                        TextField("6 位配对码", text: $pairCode)
                            .textFieldStyle(.roundedBorder)
                        Button("连接家长端") {
                            Task { await model.pairChild(baseURL: baseURL, code: pairCode) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(baseURL.isEmpty || pairCode.count != 6 || model.isBusy)
                    }
                    Label(model.connectionMessage, systemImage: model.hasRemoteConfiguration ? "checkmark.circle" : "network.slash")
                        .foregroundStyle(.secondary)
                    Text(model.autoStartMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .cardStyle()

                VStack(alignment: .leading, spacing: 10) {
                    Text("软件更新").font(.headline)
                    Text("当前版本：\(updates.currentVersion)")
                        .foregroundStyle(.secondary)
                    Text("小灯塔会定期检查 GitHub Releases；更新包通过独立签名验证后才会安装。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("检查更新…") { updates.checkForUpdates() }
                        .disabled(!updates.canCheckForUpdates)
                }
                .cardStyle()

                if model.role == .parent {
                    Button("添加演示事件") { model.addDemoEvent() }
                        .help("只写入本地，用于检查家长端界面")
                }
                Button("重新选择这台 Mac 的角色", role: .destructive) {
                    model.resetConfiguration()
                }
            }
            .padding(compact ? 0 : 28)
        }
        .navigationTitle(compact ? "" : "设置")
        .onAppear { baseURL = model.snapshot.apiBaseURL }
    }
}

private struct ChildRuleSummary: View {
    let rules: RuleSet
    let lastSyncAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("今天的规则").font(.title2.bold())
                Spacer()
                Text(syncText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach([ActivityCategory.game, .video]) { category in
                HStack {
                    CategoryIcon(category: category)
                    Text(category.displayName)
                    Spacer()
                    Text(summary(for: category)).foregroundStyle(.secondary)
                }
            }
        }
        .cardStyle()
    }

    private var syncText: String {
        guard let lastSyncAt else { return "本地规则 · 版本 \(rules.revision)" }
        return "版本 \(rules.revision) · \(lastSyncAt.formatted(date: .omitted, time: .shortened)) 同步"
    }

    private func summary(for category: ActivityCategory) -> String {
        let weekday = Calendar.current.component(.weekday, from: Date())
        let windows = rules.activityRules.first(where: { $0.category == category })?.windows
            .filter { $0.weekday == weekday } ?? []
        guard !windows.isEmpty else { return "今天没有允许时段" }
        return windows.map { "\(time($0.startMinute))–\(time($0.endMinute))" }.joined(separator: "，")
    }

    private func time(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }
}

private struct StatusCard: View {
    let status: DeviceStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(status.isOnline ? Color.green : Color.gray)
                    .frame(width: 9, height: 9)
                Text(status.isOnline ? "孩子 Mac 在线" : "孩子 Mac 离线")
                    .font(.caption.weight(.semibold))
            }
            HStack(spacing: 12) {
                CategoryIcon(category: status.category)
                Text(status.category.displayName).font(.system(size: 28, weight: .bold, design: .rounded))
            }
            Text(status.lastSeenAt == .distantPast
                 ? "尚未收到状态"
                 : "最后同步 \(status.lastSeenAt.formatted(date: .omitted, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let detail: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            Text(value).font(.system(size: 30, weight: .bold, design: .rounded))
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .cardStyle()
    }
}

private struct EventRow: View {
    let event: ViolationEvent

    var body: some View {
        HStack(spacing: 14) {
            CategoryIcon(category: event.category)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(event.appName).font(.headline)
                    if let domain = event.normalizedDomain {
                        Text(domain).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(event.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(event.durationSeconds / 60) 分 \(event.durationSeconds % 60) 秒")
                Text("提醒 \(event.warningCount) 次\(event.wasEnforced ? " · 已结束" : "")")
                    .font(.caption)
                    .foregroundStyle(event.wasEnforced ? .orange : .secondary)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct CategoryIcon: View {
    let category: ActivityCategory
    var tint: Color? = nil

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(tint ?? color)
            .frame(width: 38, height: 38)
            .background((tint ?? color).opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
    }

    private var icon: String {
        switch category {
        case .game: "gamecontroller.fill"
        case .video: "play.rectangle.fill"
        case .other: "doc.text"
        case .idle: "moon.zzz"
        }
    }
    private var color: Color {
        switch category {
        case .game: .purple
        case .video: .blue
        case .other: .teal
        case .idle: .gray
        }
    }
}

private struct PageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 28, weight: .bold, design: .rounded))
            Text(subtitle).foregroundStyle(.secondary)
        }
    }
}

private struct EmptyState: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 30)).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct ConnectionBadge: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "circle.fill")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
    }
}

private struct ErrorToast: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(.callout)
            .padding(12)
            .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 8)
    }
}

private extension View {
    func cardStyle() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            }
    }
}
