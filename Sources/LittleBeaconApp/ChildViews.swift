import AppKit
import SwiftUI
import LittleBeaconCore

struct ChildDashboardView: View {
    @ObservedObject var model: AppModel
    @State private var selectedCategory: ActivityCategory = .game
    @State private var selectedDuration = 30
    @State private var scheduleLater = false
    @State private var scheduledStart = ChildDashboardView.nextRoundHalfHour()
    @State private var sentMessage: String?

    private static let durations = [15, 30, 60]

    private var scheduleTooFarAhead: Bool {
        scheduleLater && scheduledStart > Date().addingTimeInterval(14 * 86_400)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let outlook = DayOutlook(
                rules: model.rules,
                requests: model.requests,
                grants: model.activeGrants,
                at: context.date
            )
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header(outlook: outlook)
                    if let warning = model.warningMessage {
                        Text(warning)
                            .font(.system(size: 14, weight: .semibold))
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(BeaconStyle.groupFill, in: RoundedRectangle(cornerRadius: 12))
                    }
                    finishingBanner
                    ForEach(model.remoteNotices, id: \.self) { notice in
                        Text(notice)
                            .font(.system(size: 14, weight: .semibold))
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(BeaconStyle.groupFill, in: RoundedRectangle(cornerRadius: 12))
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        Text("今天什么时候可以玩").font(.system(size: 15, weight: .semibold))
                        DayRail(outlook: outlook)
                    }
                    if model.rules.viewingDistancePolicy.enabled {
                        ViewingDistanceSetupCard(model: model)
                    }
                    requestForm
                    if !model.requests.isEmpty {
                        myRequests
                    }
                    if !model.hasRemoteConfiguration {
                        ChildPairingForm(model: model)
                    }
                    footer
                }
                .padding(.horizontal, 36)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(BeaconStyle.contentBackground)
        }
    }

    private func header(outlook: DayOutlook) -> some View {
        let headline = childHeadline(outlook: outlook, activity: model.currentActivity.category)
        return HStack(alignment: .lastTextBaseline, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text(headline).font(.system(size: 28, weight: .semibold))
                if headline != outlook.summary {
                    Text(outlook.summary).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("今天用了 \(formatUsageDuration(model.currentStatus.dailyUsageSeconds))")
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 14))
    }

    @ViewBuilder
    private var finishingBanner: some View {
        if let countdown = model.endingCountdown, countdown.isFinishing {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("收尾时间还剩 \(model.menuBarCountdownClock ?? "")")
                        .font(.system(size: 15, weight: .semibold).monospacedDigit())
                    Text("找个地方停下来，记得存档")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let category = model.extensionCategory {
                    Button("再玩 \(ReminderStrategy.extensionMinutes) 分钟（今天还能用 \(model.extensionsLeft(for: category)) 次）") {
                        model.useExtension(category: category)
                    }
                    .buttonStyle(BeaconButtonStyle(kind: .primary))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(BeaconStyle.groupFill, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var requestForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("想多用一会儿").font(.system(size: 15, weight: .semibold))
            HStack(spacing: 8) {
                ForEach([ActivityCategory.game, .video]) { item in
                    Button(item.displayName) { selectedCategory = item }
                        .buttonStyle(BeaconButtonStyle(kind: item == selectedCategory ? .selected : .quiet))
                }
                Color.clear.frame(width: 8, height: 1)
                ForEach(Self.durations, id: \.self) { duration in
                    Button("\(duration) 分钟") { selectedDuration = duration }
                        .buttonStyle(BeaconButtonStyle(kind: duration == selectedDuration ? .selected : .quiet))
                }
                Spacer()
                Button("发给家长", action: sendRequest)
                    .buttonStyle(BeaconButtonStyle(kind: .primary))
                    .disabled(scheduleTooFarAhead)
            }
            HStack(spacing: 12) {
                Picker("开始方式", selection: $scheduleLater) {
                    Text("现在开始").tag(false)
                    Text("预约时间").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)
                if scheduleLater {
                    DatePicker(
                        "开始时间",
                        selection: $scheduledStart,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    Text(temporaryWindowText(startsAt: scheduledStart, durationMinutes: selectedDuration))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            if scheduleTooFarAhead {
                Text("最多只能预约 14 天以内的时间。")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            if let sentMessage {
                Text(sentMessage)
                    .font(.system(size: 14, weight: .semibold))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(BeaconStyle.groupFill, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var myRequests: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("我的申请").font(.system(size: 15, weight: .semibold))
            VStack(spacing: 0) {
                let shown = Array(model.requests.prefix(5))
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, request in
                    ChildRequestRow(request: request)
                        .padding(.vertical, 8)
                    if index < shown.count - 1 {
                        Rectangle().fill(BeaconStyle.hairline).frame(height: 1)
                    }
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("小灯塔只看你在用游戏、视频还是其他，不看屏幕内容，也不记按键。")
            Text(syncText)
        }
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
    }

    private var syncText: String {
        guard let lastSyncAt = model.snapshot.lastRulesSyncAt else {
            return "\(model.connectionMessage) · 规则版本 \(model.rules.revision)"
        }
        return "规则版本 \(model.rules.revision) · \(lastSyncAt.formatted(date: .omitted, time: .shortened)) 同步"
    }

    private func sendRequest() {
        model.requestTemporaryUse(
            category: selectedCategory,
            durationMinutes: selectedDuration,
            startsAt: scheduleLater ? scheduledStart : nil
        )
        sentMessage = "已发给家长：\(selectedCategory.displayName) \(selectedDuration) 分钟。批准后这里会告诉你。"
        Task {
            try? await Task.sleep(for: .seconds(8))
            sentMessage = nil
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
        HStack(spacing: 16) {
            Text("\(request.category.displayName) · \(windowText)")
            Spacer()
            Text(statusText).foregroundStyle(.secondary)
        }
        .font(.system(size: 14))
    }

    private var windowText: String {
        if let startsAt = request.startsAt {
            return temporaryWindowText(startsAt: startsAt, durationMinutes: request.durationMinutes)
        }
        return "\(request.durationMinutes) 分钟"
    }

    private var statusText: String {
        switch request.status {
        case .pending: "等家长批准"
        case .denied: "没有批准"
        case .approved:
            if let startsAt = request.startsAt, startsAt > Date() {
                "已批准 · \(temporaryStartText(startsAt)) 开始"
            } else {
                "已批准"
            }
        }
    }
}

private struct ChildPairingForm: View {
    @ObservedObject var model: AppModel
    @State private var baseURL = ""
    @State private var pairCode = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("连接家长端").font(.system(size: 15, weight: .semibold))
            TextField("https://little-beacon-api.vercel.app", text: $baseURL)
                .textFieldStyle(.roundedBorder)
            TextField("6 位配对码", text: $pairCode)
                .textFieldStyle(.roundedBorder)
            Button("连接家长端") {
                Task { await model.pairChild(baseURL: baseURL, code: pairCode) }
            }
            .buttonStyle(BeaconButtonStyle(kind: .primary))
            .disabled(baseURL.isEmpty || pairCode.count != 6 || model.isBusy)
            Text(model.connectionMessage)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BeaconStyle.groupFill, in: RoundedRectangle(cornerRadius: 12))
        .onAppear { baseURL = model.snapshot.apiBaseURL }
    }
}

private struct ViewingDistanceSetupCard: View {
    @ObservedObject var model: AppModel

    private var policy: ViewingDistancePolicy {
        model.rules.viewingDistancePolicy
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("坐姿距离提醒").font(.system(size: 15, weight: .semibold))
            Text(model.viewingDistanceStatusMessage)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Text("每 \(policy.checkIntervalMinutes) 分钟短暂检查一次，最近距离 \(policy.minimumDistanceCentimeters) 厘米。校准时坐到这个距离，正对屏幕几秒。画面只在这台 Mac 上处理，不拍照、不录像、也不上传。")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(model.hasViewingDistanceCalibration ? "重新校准安全距离" : "授权摄像头并校准") {
                Task { await model.calibrateViewingDistance() }
            }
            .buttonStyle(BeaconButtonStyle(kind: .primary))
            .disabled(model.isViewingDistanceBusy)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BeaconStyle.groupFill, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct ChildMenuPanel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updates: UpdateController
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @State private var sent = false

    private static let quickMinutes = 15

    var body: some View {
        let outlook = DayOutlook(
            rules: model.rules,
            requests: model.requests,
            grants: model.activeGrants,
            at: Date()
        )
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title(outlook: outlook))
                    .font(.system(size: 17, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(outlook.summary)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let warning = model.warningMessage {
                Text(warning)
                    .font(.system(size: 13, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(model.remoteNotices, id: \.self) { notice in
                Text(notice)
                    .font(.system(size: 13, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let category = model.extensionCategory {
                Button {
                    model.useExtension(category: category)
                } label: {
                    Text("再玩 \(ReminderStrategy.extensionMinutes) 分钟（还能用 \(model.extensionsLeft(for: category)) 次）")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BeaconButtonStyle(kind: .primary))
            }
            if sent {
                Text("已发给家长")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                    .background(BeaconStyle.groupFill, in: RoundedRectangle(cornerRadius: 8))
            } else {
                Button(action: askForMore) {
                    Text("申请多用 \(Self.quickMinutes) 分钟").frame(maxWidth: .infinity)
                }
                .buttonStyle(BeaconButtonStyle())
            }
            Text("今天用了 \(formatUsageDuration(model.currentStatus.dailyUsageSeconds))")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Rectangle().fill(BeaconStyle.hairline).frame(height: 1)
            VStack(alignment: .leading, spacing: 2) {
                MenuPanelRow(title: "打开小灯塔") {
                    dismiss()
                    showMainWindow(openWindow)
                }
                MenuPanelRow(title: "立即同步") {
                    Task { await model.syncNow() }
                }
                MenuPanelRow(title: "检查更新…") {
                    updates.checkForUpdates()
                }
                MenuPanelRow(title: "退出小灯塔…") {
                    NSApp.terminate(nil)
                }
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    private func title(outlook: DayOutlook) -> String {
        if let countdown = model.endingCountdown, countdown.isFinishing,
           let clock = model.menuBarCountdownClock {
            return "收尾时间还剩 \(clock)"
        }
        return childHeadline(outlook: outlook, activity: model.currentActivity.category)
    }

    private func askForMore() {
        let current = model.currentActivity.category
        model.requestTemporaryUse(
            category: current == .video ? .video : .game,
            durationMinutes: Self.quickMinutes
        )
        sent = true
    }
}
