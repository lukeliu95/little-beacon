import SwiftUI
import LittleBeaconCore

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
        .background(BackgroundLaunchWindowCloser(shouldClose: model.consumeBackgroundLaunch))
    }
}

/// macOS 14 has no scene option to skip the launch window, so a paired child Mac closes it
/// before it is ever seen.
private struct BackgroundLaunchWindowCloser: NSViewRepresentable {
    let shouldClose: () -> Bool

    func makeNSView(context: Context) -> NSView {
        CloserView(shouldClose: shouldClose)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class CloserView: NSView {
        private let shouldClose: () -> Bool

        init(shouldClose: @escaping () -> Bool) {
            self.shouldClose = shouldClose
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not used from a nib") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, shouldClose() else { return }
            window.alphaValue = 0
            DispatchQueue.main.async {
                window.close()
                window.alphaValue = 1
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
                Text("孩子端始终显示在菜单栏；小灯塔不记录屏幕、按键或聊天内容。")
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

private struct ChildDashboardView: View {
    @ObservedObject var model: AppModel
    @State private var selectedCategory: ActivityCategory = .game
    @State private var selectedDuration = 30
    @State private var scheduleLater = false
    @State private var scheduledStart = ChildDashboardView.nextRoundHalfHour()

    private var scheduleTooFarAhead: Bool {
        scheduleLater && scheduledStart > Date().addingTimeInterval(14 * 86_400)
    }

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
                        Text("今日已用 \(formatUsageDuration(model.currentStatus.dailyUsageSeconds))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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

                if model.rules.viewingDistancePolicy.enabled {
                    ViewingDistanceSetupCard(model: model)
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
                            model.requestTemporaryUse(
                                category: selectedCategory,
                                durationMinutes: selectedDuration,
                                startsAt: scheduleLater ? scheduledStart : nil
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(scheduleTooFarAhead)
                    }
                    HStack {
                        Picker("开始方式", selection: $scheduleLater) {
                            Text("立即开始").tag(false)
                            Text("预约时间").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                        .labelsHidden()
                        if scheduleLater {
                            DatePicker(
                                "开始时间",
                                selection: $scheduledStart,
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            .labelsHidden()
                            Text(temporaryWindowText(startsAt: scheduledStart, durationMinutes: selectedDuration))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if scheduleTooFarAhead {
                        Text("最多只能预约 14 天以内的时间。")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    } else {
                        Text(scheduleLater
                             ? "家长批准后，会在预约时间自动生效，到期自动恢复原来的每周时段。"
                             : "家长批准后立即生效，到期自动恢复原来的每周时段。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if !model.requests.isEmpty {
                        Divider()
                        Text("我的申请").font(.headline)
                        ForEach(model.requests.prefix(5)) { request in
                            ChildRequestRow(request: request)
                        }
                    }
                }
                .cardStyle()

                ChildRuleSummary(rules: model.rules, lastSyncAt: model.snapshot.lastRulesSyncAt)

                if !model.hasRemoteConfiguration {
                    ChildPairingForm(model: model)
                }
            }
            .padding(28)
        }
    }

    /// Default for the schedule picker: the next round half hour (e.g. 15:12 → 15:30).
    private static func nextRoundHalfHour(now: Date = Date()) -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        components.minute = (components.minute ?? 0) - ((components.minute ?? 0) % 30)
        components.second = 0
        let floor = calendar.date(from: components) ?? now
        return floor.addingTimeInterval(30 * 60)
    }
}

private struct ChildRequestRow: View {
    let request: TemporaryRequest

    var body: some View {
        HStack(spacing: 10) {
            CategoryIcon(category: request.category)
            Text(request.category.displayName)
            Text(windowText)
                .foregroundStyle(.secondary)
            Spacer()
            Text(statusText)
                .font(.callout)
                .foregroundStyle(statusColor)
        }
    }

    private var windowText: String {
        if let startsAt = request.startsAt {
            return temporaryWindowText(startsAt: startsAt, durationMinutes: request.durationMinutes)
        }
        return "立即 · \(request.durationMinutes) 分钟"
    }

    private var statusText: String {
        switch request.status {
        case .pending: "待批准"
        case .denied: "已拒绝"
        case .approved:
            if let startsAt = request.startsAt, startsAt > Date() {
                "已批准 · \(temporaryStartText(startsAt)) 生效"
            } else {
                "已批准"
            }
        }
    }

    private var statusColor: Color {
        switch request.status {
        case .pending: .orange
        case .approved: .green
        case .denied: .secondary
        }
    }
}

private struct ChildPairingForm: View {
    @ObservedObject var model: AppModel
    @State private var baseURL = ""
    @State private var pairCode = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("连接家长端").font(.title2.bold())
            TextField("https://little-beacon-api.vercel.app", text: $baseURL)
                .textFieldStyle(.roundedBorder)
            TextField("6 位配对码", text: $pairCode)
                .textFieldStyle(.roundedBorder)
            Button("连接家长端") {
                Task { await model.pairChild(baseURL: baseURL, code: pairCode) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(baseURL.isEmpty || pairCode.count != 6 || model.isBusy)
            Text(model.connectionMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
        .onAppear { baseURL = model.snapshot.apiBaseURL }
    }
}

private struct ViewingDistanceSetupCard: View {
    @ObservedObject var model: AppModel

    private var policy: ViewingDistancePolicy {
        model.rules.viewingDistancePolicy
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("坐姿距离提醒", systemImage: "camera.metering.center.weighted")
                    .font(.title2.bold())
                Spacer()
                if model.isViewingDistanceBusy {
                    ProgressView().controlSize(.small)
                }
            }
            Text(model.viewingDistanceStatusMessage)
                .foregroundStyle(.secondary)
            Text(
                "家长设置为每 \(policy.checkIntervalMinutes) 分钟短暂检查一次，"
                + "最低距离 \(policy.minimumDistanceCentimeters) 厘米。"
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            Text("校准前，请坐到设定距离、正对屏幕并保持几秒。画面只在这台 Mac 的内存里处理，不拍照、不录像、也不上传。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button(model.hasViewingDistanceCalibration ? "重新校准安全距离" : "授权摄像头并校准") {
                Task { await model.calibrateViewingDistance() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isViewingDistanceBusy)
        }
        .cardStyle()
    }
}

func formatUsageDuration(_ seconds: Int) -> String {
    let hours = seconds / 3_600
    let minutes = (seconds % 3_600) / 60
    return hours > 0 ? "\(hours) 小时 \(minutes) 分" : "\(minutes) 分"
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
            HStack {
                Image(systemName: "timer")
                    .foregroundStyle(.indigo)
                Text("25 分钟番茄钟")
                Spacer()
                Text(pomodoroSummary).foregroundStyle(.secondary)
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

    private var pomodoroSummary: String {
        switch rules.pomodoroMode {
        case .off: "关闭"
        case .gentle: "温和提醒"
        case .enforced: "强制休息 5 分钟"
        }
    }

    private func time(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
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
