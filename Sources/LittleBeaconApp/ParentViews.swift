import AppKit
import SwiftUI
import UniformTypeIdentifiers
import LittleBeaconCore

enum BeaconStyle {
    /// The lighthouse lamp from the app icon. It only ever means "this time is open".
    static let lamp = Color(red: 242 / 255, green: 169 / 255, blue: 59 / 255)
    static let lampHover = Color(red: 232 / 255, green: 154 / 255, blue: 36 / 255)
    static let groupFill = Color.primary.opacity(0.05)
    static let trackFill = Color.primary.opacity(0.06)
    static let selectedFill = Color.primary.opacity(0.09)
    static let hairline = Color.primary.opacity(0.08)
    static let contentBackground = Color(nsColor: .textBackgroundColor)
}

struct BeaconButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case quiet
        case destructive
    }

    var kind: Kind = .quiet

    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration, kind: kind)
    }

    private struct StyledLabel: View {
        let configuration: Configuration
        let kind: Kind
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 14, weight: kind == .primary ? .semibold : .regular))
                .foregroundStyle(foreground)
                .padding(.horizontal, 14)
                .frame(minHeight: 32)
                .background(background, in: RoundedRectangle(cornerRadius: 8))
                .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
                .contentShape(RoundedRectangle(cornerRadius: 8))
                .onHover { isHovering = $0 }
        }

        private var foreground: Color {
            switch kind {
            case .primary: BeaconStyle.contentBackground
            case .quiet: .primary
            case .destructive: Color(red: 155 / 255, green: 44 / 255, blue: 31 / 255)
            }
        }

        private var background: Color {
            switch kind {
            case .primary: .primary.opacity(isHovering ? 0.85 : 1)
            case .quiet, .destructive: .primary.opacity(isHovering ? 0.11 : 0.07)
            }
        }
    }
}

enum ParentSection: String, CaseIterable, Identifiable {
    case today = "今天"
    case rules = "规则"
    case records = "记录"
    case devices = "设备"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .today: "sun.max"
        case .rules: "calendar"
        case .records: "list.bullet"
        case .devices: "laptopcomputer"
        }
    }
}

struct ParentShellView: View {
    @ObservedObject var model: AppModel
    @State private var section: ParentSection = .today

    var body: some View {
        HStack(spacing: 0) {
            ParentSidebar(
                selection: $section,
                pendingCount: model.pendingRequests.count,
                connection: model.connectionMessage
            )
            Group {
                switch section {
                case .today: TodayView(model: model)
                case .rules: RulesView(model: model)
                case .records: RecordsView(model: model)
                case .devices: DevicesView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(BeaconStyle.contentBackground)
    }
}

private struct ParentSidebar: View {
    @Binding var selection: ParentSection
    let pendingCount: Int
    let connection: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("小灯塔")
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.top, 4)
                .padding(.bottom, 14)
            ForEach(ParentSection.allCases) { section in
                SidebarButton(
                    section: section,
                    isSelected: selection == section,
                    badge: section == .today && pendingCount > 0 ? pendingCount : nil
                ) {
                    selection = section
                }
            }
            Spacer()
            Text(connection)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.bottom, 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 20)
        .frame(width: 172)
        .frame(maxHeight: .infinity)
        .background(BeaconStyle.groupFill)
    }
}

private struct SidebarButton: View {
    let section: ParentSection
    let isSelected: Bool
    let badge: Int?
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: section.icon)
                    .font(.system(size: 14))
                    .frame(width: 18)
                Text(section.rawValue)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                Spacer()
                if let badge {
                    Text("\(badge)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("\(badge) 个待处理申请")
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(
                isSelected || isHovering ? BeaconStyle.selectedFill : .clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ParentPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                content
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct PageTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 24, weight: .semibold))
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text).font(.system(size: 15, weight: .semibold))
    }
}

// MARK: - 今天

private struct TodayView: View {
    @ObservedObject var model: AppModel
    @State private var resolution: String?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let outlook = DayOutlook(rules: model.rules, requests: model.requests, at: context.date)
            ParentPage {
                header(outlook: outlook)
                ForEach(model.pendingRequests) { request in
                    PendingRequestBand(request: request, now: context.date) { approved in
                        resolve(request, approved: approved)
                    }
                }
                if let resolution {
                    Text(resolution)
                        .font(.system(size: 14, weight: .semibold))
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(BeaconStyle.groupFill, in: RoundedRectangle(cornerRadius: 12))
                }
                VStack(alignment: .leading, spacing: 14) {
                    SectionTitle(text: "今天的时段")
                    DayRail(outlook: outlook)
                }
                recentEvents
            }
        }
    }

    private func header(outlook: DayOutlook) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                PageTitle(text: deviceHeadline(status: model.currentStatus, outlook: outlook))
                Text(outlook.summary).foregroundStyle(.secondary)
            }
            Spacer()
            Text("今日已用 \(formatUsageDuration(model.currentStatus.dailyUsageSeconds))")
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 14))
    }

    private var recentEvents: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(text: "最近发生的事")
            if model.events.isEmpty {
                Text("最近没有超出时段的活动")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 10)
            } else {
                EventList(events: Array(model.events.prefix(4)))
            }
        }
        .font(.system(size: 14))
    }

    private func resolve(_ request: TemporaryRequest, approved: Bool) {
        model.resolveRequest(request, approved: approved)
        resolution = approved ? approvalMessage(for: request) : "已拒绝，孩子端会看到结果"
        Task {
            try? await Task.sleep(for: .seconds(8))
            resolution = nil
        }
    }

    private func approvalMessage(for request: TemporaryRequest) -> String {
        temporaryApprovalText(for: request, timeZoneIdentifier: model.rules.timeZoneIdentifier)
    }
}

func temporaryApprovalText(for request: TemporaryRequest, timeZoneIdentifier: String) -> String {
    let what = "\(request.category.displayName) \(request.durationMinutes) 分钟"
    if let startsAt = request.startsAt {
        return "已批准\(what)，\(temporaryWindowText(startsAt: startsAt, durationMinutes: request.durationMinutes))"
    }
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    formatter.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
    let end = Date().addingTimeInterval(TimeInterval(request.durationMinutes * 60))
    return "已批准\(what)，到 \(formatter.string(from: end)) 结束"
}

/// "12 分钟前" — how long a request has been waiting.
func waitingText(since date: Date, now: Date) -> String {
    let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
    if minutes == 0 { return "刚刚" }
    if minutes < 60 { return "\(minutes) 分钟前" }
    if minutes < 1_440 { return "\(minutes / 60) 小时前" }
    return "\(minutes / 1_440) 天前"
}

func requestTimingText(_ request: TemporaryRequest, now: Date) -> String {
    let waited = waitingText(since: request.createdAt, now: now)
    guard let startsAt = request.startsAt else {
        return "\(waited)申请，批准后立即开始"
    }
    return "\(waited)申请，时间是 \(temporaryWindowText(startsAt: startsAt, durationMinutes: request.durationMinutes))"
}

private struct PendingRequestBand: View {
    let request: TemporaryRequest
    let now: Date
    let resolve: (Bool) -> Void

    var body: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 2) {
                Text(request.parentTitle).font(.system(size: 15, weight: .semibold))
                Text(requestTimingText(request, now: now))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("拒绝") { resolve(false) }
                .buttonStyle(BeaconButtonStyle())
            Button("批准") { resolve(true) }
                .buttonStyle(BeaconButtonStyle(kind: .primary))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(BeaconStyle.groupFill, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Maps minutes of a day onto a lane. The axis only reaches before 06:00 when a rule does,
/// so an evening window stays readable without ever hiding an early one.
struct DayAxis: Equatable {
    let startHour: Int

    init(spans: [DaySpan]) {
        let earliest = spans.map(\.startMinute).min() ?? 6 * 60
        startHour = min(6, earliest / 60)
    }

    private var startMinute: Int { startHour * 60 }
    private var length: Double { Double(1_440 - startMinute) }

    func fraction(_ minute: Int) -> Double {
        min(1, max(0, Double(minute - startMinute) / length))
    }
}

private struct DayRail: View {
    let outlook: DayOutlook

    private var axis: DayAxis {
        DayAxis(spans: outlook.game.spans + outlook.video.spans)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            lane(outlook.game)
            lane(outlook.video)
            HStack(spacing: 12) {
                Color.clear.frame(width: 44, height: 1)
                TimeTicks(axis: axis, hours: [axis.startHour, 12, 21, 24], nowMinute: outlook.nowMinute)
            }
        }
    }

    private func lane(_ category: CategoryOutlook) -> some View {
        HStack(spacing: 12) {
            Text(category.category.displayName)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 6).fill(BeaconStyle.trackFill)
                    ForEach(category.spans, id: \.startMinute) { span in
                        RoundedRectangle(cornerRadius: 6)
                            .fill(BeaconStyle.lamp)
                            .frame(width: proxy.size.width * (axis.fraction(span.endMinute) - axis.fraction(span.startMinute)))
                            .offset(x: proxy.size.width * axis.fraction(span.startMinute))
                    }
                }
                .overlay(alignment: .topLeading) {
                    Rectangle()
                        .fill(.primary)
                        .frame(width: 2, height: proxy.size.height + 10)
                        .offset(x: proxy.size.width * axis.fraction(outlook.nowMinute) - 1, y: -5)
                }
            }
            .frame(height: 26)
            .accessibilityElement()
            .accessibilityLabel(laneDescription(category))
        }
    }

    private func laneDescription(_ category: CategoryOutlook) -> String {
        let name = category.category.displayName
        guard !category.spans.isEmpty else { return "\(name)今天不开放" }
        let spans = category.spans
            .map { "\(clockText($0.startMinute)) 到 \(clockText($0.endMinute))" }
            .joined(separator: "，")
        return "\(name)今天开放 \(spans)"
    }
}

private struct TimeTicks: View {
    let axis: DayAxis
    let hours: [Int]
    var nowMinute: Int?

    private let labelHalfWidth: CGFloat = 18
    private let nowHalfWidth: CGFloat = 36

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let nowX = nowMinute.map { position(of: $0, in: width, halfWidth: nowHalfWidth) }
            ZStack(alignment: .topLeading) {
                ForEach(hours, id: \.self) { hour in
                    let x = position(of: hour * 60, in: width, halfWidth: labelHalfWidth)
                    if nowX.map({ abs($0 - x) > nowHalfWidth + labelHalfWidth + 6 }) ?? true {
                        Text(clockText(hour * 60))
                            .foregroundStyle(.secondary)
                            .position(x: x, y: 9)
                    }
                }
                if let nowX, let nowMinute {
                    Text("现在 \(clockText(nowMinute))")
                        .fontWeight(.semibold)
                        .position(x: nowX, y: 9)
                }
            }
            .font(.system(size: 12).monospacedDigit())
        }
        .frame(height: 18)
    }

    private func position(of minute: Int, in width: CGFloat, halfWidth: CGFloat) -> CGFloat {
        min(width - halfWidth, max(halfWidth, width * axis.fraction(minute)))
    }
}

private struct EventList: View {
    let events: [ViolationEvent]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                HStack(spacing: 16) {
                    Text(eventTimeText(event.startedAt))
                        .foregroundStyle(.secondary)
                        .frame(width: 112, alignment: .leading)
                    Text(event.parentTitle)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 16)
                    Text(event.parentOutcome)
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 14).monospacedDigit())
                .padding(.vertical, 10)
                if index < events.count - 1 {
                    Rectangle().fill(BeaconStyle.hairline).frame(height: 1)
                }
            }
        }
    }
}

func eventTimeText(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "HH:mm"
    let time = formatter.string(from: date)
    if calendar.isDate(date, inSameDayAs: now) { return "今天 \(time)" }
    if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
       calendar.isDate(date, inSameDayAs: yesterday) {
        return "昨天 \(time)"
    }
    formatter.dateFormat = "M月d日 HH:mm"
    return formatter.string(from: date)
}

// MARK: - 记录

private struct RecordsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ParentPage {
            VStack(alignment: .leading, spacing: 4) {
                PageTitle(text: "记录")
                Text("只记录超出时段的活动，保留 30 天后自动删除。")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            if model.events.isEmpty {
                Text("最近 30 天没有超出时段的活动")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            } else {
                EventList(events: model.events)
            }
        }
    }
}

// MARK: - 规则

private enum RuleTab: String, CaseIterable, Identifiable {
    case schedule = "时段"
    case care = "休息与护眼"
    case apps = "应用与网站"

    var id: String { rawValue }
}

private struct RulesView: View {
    @ObservedObject var model: AppModel
    @State private var tab: RuleTab = .schedule

    var body: some View {
        ParentPage {
            HStack {
                PageTitle(text: "规则")
                Spacer()
                Picker("规则分类", selection: $tab) {
                    ForEach(RuleTab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 300)
            }
            switch tab {
            case .schedule: WeekScheduleView(model: model)
            case .care: CareRulesView(model: model)
            case .apps: AppRulesView(model: model)
            }
        }
    }
}

private struct WeekScheduleView: View {
    @ObservedObject var model: AppModel
    @State private var category: ActivityCategory = .game
    @State private var weekday = Calendar.current.component(.weekday, from: Date())

    private static let days = [(2, "周一"), (3, "周二"), (4, "周三"), (5, "周四"), (6, "周五"), (7, "周六"), (1, "周日")]
    private static let defaultWindow = (startMinute: 18 * 60, endMinute: 20 * 60)

    private var windows: [ScheduleWindow] {
        model.rules.activityRules.first { $0.category == category }?.windows ?? []
    }

    private var axis: DayAxis {
        DayAxis(spans: windows.map { DaySpan(startMinute: $0.startMinute, endMinute: $0.endMinute) })
    }

    private var selectedWindows: [ScheduleWindow] {
        windows.filter { $0.weekday == weekday }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                ForEach([ActivityCategory.game, .video]) { item in
                    Button(item.displayName) { category = item }
                        .buttonStyle(BeaconButtonStyle(kind: item == category ? .primary : .quiet))
                }
                Spacer()
                Text("亮起来的时段可以\(category == .game ? "玩游戏" : "看视频")，其他时间不可以")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 6) {
                HStack(spacing: 12) {
                    Color.clear.frame(width: 40, height: 1)
                    TimeTicks(axis: axis, hours: [axis.startHour, 12, 18, 24])
                }
                ForEach(Self.days, id: \.0) { day, name in
                    HStack(spacing: 12) {
                        Text(name)
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .leading)
                        ScheduleLane(
                            name: name,
                            windows: windows.filter { $0.weekday == day },
                            axis: axis,
                            isSelected: day == weekday,
                            select: { weekday = day },
                            addDefault: {
                                weekday = day
                                model.setWindow(
                                    category: category,
                                    weekdays: [day],
                                    startMinute: Self.defaultWindow.startMinute,
                                    endMinute: Self.defaultWindow.endMinute
                                )
                            }
                        )
                    }
                }
            }
            ScheduleEditor(
                model: model,
                category: category,
                weekday: weekday,
                dayName: Self.days.first { $0.0 == weekday }?.1 ?? "",
                windows: selectedWindows
            )
            .id("\(category.rawValue)-\(weekday)-\(selectedWindows.first?.id.uuidString ?? "none")")
        }
    }
}

private struct ScheduleLane: View {
    let name: String
    let windows: [ScheduleWindow]
    let axis: DayAxis
    let isSelected: Bool
    let select: () -> Void
    let addDefault: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6).fill(BeaconStyle.trackFill)
                if windows.isEmpty {
                    Button(action: addDefault) {
                        Text("不开放，点击添加")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(name)不开放，点击添加时段")
                }
                ForEach(windows) { window in
                    let start = axis.fraction(window.startMinute)
                    let width = proxy.size.width * (axis.fraction(window.endMinute) - start)
                    Button(action: select) {
                        Text(width >= 48 ? spanText(window) : "")
                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.black)
                            .lineLimit(1)
                            .frame(width: width, height: proxy.size.height)
                            .background(BeaconStyle.lamp, in: RoundedRectangle(cornerRadius: 6))
                            .overlay {
                                if isSelected {
                                    RoundedRectangle(cornerRadius: 7)
                                        .stroke(.primary, lineWidth: 2)
                                        .padding(-1)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .offset(x: proxy.size.width * start)
                    .accessibilityLabel("\(name) \(clockText(window.startMinute)) 到 \(clockText(window.endMinute))，点击编辑")
                }
            }
        }
        .frame(height: 32)
    }

    private func spanText(_ window: ScheduleWindow) -> String {
        guard window.startMinute % 60 == 0, window.endMinute % 60 == 0 else {
            return "\(clockText(window.startMinute))–\(clockText(window.endMinute))"
        }
        return "\(window.startMinute / 60)–\(window.endMinute / 60) 点"
    }
}

private struct ScheduleEditor: View {
    @ObservedObject var model: AppModel
    let category: ActivityCategory
    let weekday: Int
    let dayName: String
    let windows: [ScheduleWindow]
    @State private var start = Date()
    @State private var end = Date()
    @State private var isInvalid = false

    private static let workdays = Array(2...6)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                Text(dayName).font(.system(size: 14, weight: .semibold))
                if windows.isEmpty {
                    Text("这天不开放，点上面的空行可以添加时段")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    timeField("开始", selection: $start)
                    timeField("结束", selection: $end)
                    Spacer()
                    Button("应用到工作日") {
                        apply(to: Self.workdays)
                    }
                    .buttonStyle(BeaconButtonStyle())
                    Button("这天不开放") {
                        model.clearWindows(category: category, weekday: weekday)
                    }
                    .buttonStyle(BeaconButtonStyle())
                }
            }
            if isInvalid {
                Text("结束时间要晚于开始时间，这次修改没有保存")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            if windows.count > 1 {
                Text("这天原来有 \(windows.count) 段时段，修改后会合并成一段")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BeaconStyle.groupFill, in: RoundedRectangle(cornerRadius: 12))
        .onAppear {
            guard let window = windows.first else { return }
            start = Self.date(from: window.startMinute)
            end = Self.date(from: window.endMinute)
        }
    }

    private func timeField(_ label: String, selection: Binding<Date>) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.system(size: 14)).foregroundStyle(.secondary)
            DatePicker(
                label,
                selection: Binding(
                    get: { selection.wrappedValue },
                    set: { value in
                        selection.wrappedValue = value
                        apply(to: [weekday])
                    }
                ),
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
        }
    }

    private func apply(to weekdays: [Int]) {
        let startMinute = Self.minutes(from: start)
        let endMinute = Self.minutes(from: end)
        isInvalid = endMinute <= startMinute
        guard !isInvalid else { return }
        model.setWindow(category: category, weekdays: weekdays, startMinute: startMinute, endMinute: endMinute)
    }

    private static func date(from minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
    }

    private static func minutes(from date: Date) -> Int {
        Calendar.current.component(.hour, from: date) * 60 + Calendar.current.component(.minute, from: date)
    }
}

private struct SettingRow<Trailing: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 2) {
                SectionTitle(text: title)
                Text(detail)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            trailing
        }
    }
}

private struct CareRulesView: View {
    @ObservedObject var model: AppModel

    private static let modes: [(mode: PomodoroMode, name: String, note: String)] = [
        (.off, "不提醒", "不计算连续使用时间"),
        (.gentle, "温和提醒", "弹一次提示，孩子可以马上关掉"),
        (.enforced, "强制休息", "遮住屏幕，确认后休息满 5 分钟"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: "连续用 25 分钟后")
                HStack(spacing: 8) {
                    ForEach(Self.modes, id: \.mode) { item in
                        PomodoroChoice(
                            name: item.name,
                            note: item.note,
                            isSelected: model.rules.pomodoroMode == item.mode
                        ) {
                            model.setPomodoroMode(item.mode)
                        }
                    }
                }
            }
            divider
            SettingRow(title: "每日用机提醒", detail: "只提醒，不结束任何应用，也不算违规") {
                HStack(spacing: 14) {
                    if let threshold = model.rules.dailyUsageThresholdSeconds {
                        Stepper(
                            "超过 \(durationText(minutes: threshold / 60))",
                            value: Binding(
                                get: { threshold / 60 },
                                set: { model.setDailyUsageThresholdSeconds($0 * 60) }
                            ),
                            in: 30...720,
                            step: 30
                        )
                        .font(.system(size: 14))
                        .fixedSize()
                    }
                    Toggle("每日用机提醒", isOn: Binding(
                        get: { model.rules.dailyUsageThresholdSeconds != nil },
                        set: { model.setDailyUsageThresholdSeconds($0 ? 7_200 : nil) }
                    ))
                    .labelsHidden()
                }
            }
            divider
            VStack(alignment: .leading, spacing: 12) {
                SettingRow(
                    title: "坐姿距离提醒",
                    detail: "开启后要在孩子 Mac 上授权摄像头并校准，画面不离开孩子 Mac"
                ) {
                    Toggle("坐姿距离提醒", isOn: Binding(
                        get: { model.rules.viewingDistancePolicy.enabled },
                        set: { model.setViewingDistanceEnabled($0) }
                    ))
                    .labelsHidden()
                }
                if model.rules.viewingDistancePolicy.enabled {
                    HStack(spacing: 24) {
                        Stepper(
                            "每 \(model.rules.viewingDistancePolicy.checkIntervalMinutes) 分钟检查一次",
                            value: Binding(
                                get: { model.rules.viewingDistancePolicy.checkIntervalMinutes },
                                set: { model.setViewingDistanceCheckIntervalMinutes($0) }
                            ),
                            in: 5...60,
                            step: 5
                        )
                        Stepper(
                            "最近距离 \(model.rules.viewingDistancePolicy.minimumDistanceCentimeters) 厘米",
                            value: Binding(
                                get: { model.rules.viewingDistancePolicy.minimumDistanceCentimeters },
                                set: { model.setViewingDistanceMinimumCentimeters($0) }
                            ),
                            in: 30...80,
                            step: 5
                        )
                    }
                    .font(.system(size: 14))
                    .fixedSize()
                }
            }
        }
        .toggleStyle(.switch)
        .tint(.primary)
    }

    private var divider: some View {
        Rectangle().fill(BeaconStyle.hairline).frame(height: 1)
    }
}

private struct PomodoroChoice: View {
    let name: String
    let note: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 14, weight: .semibold))
                Text(note)
                    .font(.system(size: 13))
                    .opacity(isSelected ? 0.8 : 0.65)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(isSelected ? BeaconStyle.contentBackground : Color.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
            .background(
                isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(BeaconStyle.groupFill),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct AppRulesView: View {
    @ObservedObject var model: AppModel
    @State private var target: OverrideTarget = .domain
    @State private var input = ""
    @State private var category: ActivityCategory = .game

    private var pendingValue: String? {
        switch target {
        case .domain:
            return normalizedDomain(fromParentInput: input)
        case .bundleIdentifier:
            let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.contains(".") && !value.contains(" ") ? value : nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("常见的游戏和视频已经内置。分错了，或者想放行某个学习网站，在这里改。")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Picker("类型", selection: $target) {
                    Text("网站").tag(OverrideTarget.domain)
                    Text("应用").tag(OverrideTarget.bundleIdentifier)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 110)
                TextField(
                    target == .domain ? "网站地址，例如 example.com" : "应用标识，例如 com.example.game",
                    text: $input
                )
                .textFieldStyle(.roundedBorder)
                .onSubmit(add)
                if target == .bundleIdentifier {
                    Button("选择应用…", action: chooseApp)
                        .buttonStyle(BeaconButtonStyle())
                }
                Picker("算作", selection: $category) {
                    Text("游戏").tag(ActivityCategory.game)
                    Text("视频").tag(ActivityCategory.video)
                    Text("不限制").tag(ActivityCategory.other)
                }
                .fixedSize()
                Button("添加", action: add)
                    .buttonStyle(BeaconButtonStyle(kind: .primary))
                    .disabled(pendingValue == nil)
            }
            if model.rules.overrides.isEmpty {
                Text("还没有自定义设置，都按内置分类判断。")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(model.rules.overrides.enumerated()), id: \.element.id) { index, item in
                        HStack(spacing: 16) {
                            Text(displayName(of: item))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text(categoryName(item.category))
                                .foregroundStyle(.secondary)
                                .frame(width: 80, alignment: .leading)
                            Button("移除") { model.removeOverride(id: item.id) }
                                .buttonStyle(BeaconButtonStyle())
                        }
                        .font(.system(size: 14))
                        .padding(.vertical, 8)
                        if index < model.rules.overrides.count - 1 {
                            Rectangle().fill(BeaconStyle.hairline).frame(height: 1)
                        }
                    }
                }
            }
        }
    }

    private func add() {
        guard let pendingValue else { return }
        model.addOverride(target: target, value: pendingValue, category: category)
        input = ""
    }

    /// Reads the identifier from a copy of the app on this Mac, so parents never have to know it.
    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "选择"
        guard panel.runModal() == .OK,
              let url = panel.url,
              let identifier = Bundle(url: url)?.bundleIdentifier else { return }
        model.addOverride(target: .bundleIdentifier, value: identifier, category: category)
    }

    private func displayName(of item: ClassificationOverride) -> String {
        guard item.target == .bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: item.value) else {
            return item.value
        }
        return url.deletingPathExtension().lastPathComponent
    }

    private func categoryName(_ category: ActivityCategory) -> String {
        category == .other ? "不限制" : category.displayName
    }
}

// MARK: - 设备

private struct DevicesView: View {
    @ObservedObject var model: AppModel
    @EnvironmentObject private var updates: UpdateController
    @State private var baseURL = ""
    @State private var setupKey = ""
    @State private var showsAdvanced = false
    @State private var confirmsReset = false

    var body: some View {
        ParentPage {
            PageTitle(text: "设备")
            if model.hasRemoteConfiguration {
                childDevice
            } else {
                firstConnection
            }
            hairline
            SettingRow(title: "软件更新", detail: "这台 Mac 的版本是 \(updates.currentVersion)") {
                Button("检查更新") { updates.checkForUpdates() }
                    .buttonStyle(BeaconButtonStyle())
                    .disabled(!updates.canCheckForUpdates)
            }
            hairline
            advanced
        }
        .onAppear { baseURL = model.snapshot.apiBaseURL }
        .confirmationDialog(
            "重新选择这台 Mac 的角色？",
            isPresented: $confirmsReset,
            titleVisibility: .visible
        ) {
            Button("清除连接并重新选择", role: .destructive) { model.resetConfiguration() }
        } message: {
            Text("这台 Mac 上的连接和本地记录会被清除。")
        }
    }

    private var hairline: some View {
        Rectangle().fill(BeaconStyle.hairline).frame(height: 1)
    }

    private var childDevice: some View {
        let status = model.currentStatus
        let isPaired = status.lastSeenAt != .distantPast
        return VStack(alignment: .leading, spacing: 12) {
            SettingRow(
                title: isPaired ? "孩子的 Mac" : "还没有配对孩子的 Mac",
                detail: childDetail(status)
            ) {
                Button(isPaired ? "重新配对" : "生成配对码") {
                    Task { await model.generatePairingCode() }
                }
                .buttonStyle(BeaconButtonStyle())
                .disabled(model.isBusy)
            }
            if let code = model.pairingCode {
                HStack(spacing: 24) {
                    Text(pairingCodeText(code))
                        .font(.system(size: 30, weight: .semibold).monospacedDigit())
                        .tracking(2)
                        .textSelection(.enabled)
                    Text(pairingCodeNote)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(BeaconStyle.groupFill, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func childDetail(_ status: DeviceStatus) -> String {
        guard status.lastSeenAt != .distantPast else { return "生成配对码，在孩子 Mac 上输入" }
        let time = status.lastSeenAt.formatted(date: .omitted, time: .shortened)
        return status.isOnline ? "在线 · \(time) 同步" : "离线 · 最后同步 \(time)"
    }

    private var pairingCodeNote: String {
        guard let expires = model.pairingCodeExpiresAt else { return "在孩子 Mac 上输入，只能用一次" }
        return "在孩子 Mac 上输入，\(expires.formatted(date: .omitted, time: .shortened)) 前有效，只能用一次"
    }

    private func pairingCodeText(_ code: String) -> String {
        guard code.count == 6 else { return code }
        return "\(code.prefix(3)) \(code.suffix(3))"
    }

    private var firstConnection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: "连接服务")
            TextField("https://little-beacon-api.vercel.app", text: $baseURL)
                .textFieldStyle(.roundedBorder)
            SecureField("首次设置密钥", text: $setupKey)
                .textFieldStyle(.roundedBorder)
            Button("建立家长端") {
                Task { await model.bootstrapParent(baseURL: baseURL, setupKey: setupKey) }
            }
            .buttonStyle(BeaconButtonStyle(kind: .primary))
            .disabled(baseURL.isEmpty || setupKey.isEmpty || model.isBusy)
        }
    }

    private var advanced: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                showsAdvanced.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .rotationEffect(.degrees(showsAdvanced ? 90 : 0))
                    SectionTitle(text: "高级")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(showsAdvanced ? "已展开" : "已收起")
            if showsAdvanced {
                LabeledContent("服务地址") {
                    Text(model.snapshot.apiBaseURL).textSelection(.enabled)
                }
                .font(.system(size: 14))
                Text(model.autoStartMessage)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                SettingRow(title: "角色", detail: "这台 Mac 现在是家长端。重新选择会清除这里的连接。") {
                    Button("重新选择角色") { confirmsReset = true }
                        .buttonStyle(BeaconButtonStyle(kind: .destructive))
                }
            }
        }
        .animation(.easeOut(duration: 0.18), value: showsAdvanced)
    }
}

// MARK: - 菜单栏

struct ParentMenuPanel: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @State private var resolution: String?

    private static let shownRequests = 2

    var body: some View {
        let now = Date()
        let outlook = DayOutlook(rules: model.rules, requests: model.requests, at: now)
        let pending = model.pendingRequests
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(deviceHeadline(status: model.currentStatus, outlook: outlook))
                    .font(.system(size: 15, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("今日已用 \(formatUsageDuration(model.currentStatus.dailyUsageSeconds))")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            ForEach(pending.prefix(Self.shownRequests)) { request in
                requestCard(request, now: now)
            }
            if pending.count > Self.shownRequests {
                Text("还有 \(pending.count - Self.shownRequests) 个申请，打开小灯塔查看")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            if let resolution {
                Text(resolution)
                    .font(.system(size: 14, weight: .semibold))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(BeaconStyle.groupFill, in: RoundedRectangle(cornerRadius: 10))
            }
            Text(outlook.summary)
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
                MenuPanelRow(title: "退出小灯塔") {
                    NSApp.terminate(nil)
                }
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    private func requestCard(_ request: TemporaryRequest, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text(request.parentTitle).font(.system(size: 14, weight: .semibold))
                Text(requestTimingText(request, now: now))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button { resolve(request, approved: false) } label: {
                    Text("拒绝").frame(maxWidth: .infinity)
                }
                .buttonStyle(BeaconButtonStyle())
                Button { resolve(request, approved: true) } label: {
                    Text("批准").frame(maxWidth: .infinity)
                }
                .buttonStyle(BeaconButtonStyle(kind: .primary))
            }
        }
        .padding(12)
        .background(BeaconStyle.groupFill, in: RoundedRectangle(cornerRadius: 10))
    }

    private func resolve(_ request: TemporaryRequest, approved: Bool) {
        model.resolveRequest(request, approved: approved)
        resolution = approved
            ? temporaryApprovalText(for: request, timeZoneIdentifier: model.rules.timeZoneIdentifier)
            : "已拒绝，孩子端会看到结果"
    }
}

private struct MenuPanelRow: View {
    let title: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14))
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                .background(isHovering ? BeaconStyle.selectedFill : .clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
