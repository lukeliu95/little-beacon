import Foundation

/// One lit stretch of a day, in minutes from local midnight.
public struct DaySpan: Equatable, Sendable {
    public var startMinute: Int
    public var endMinute: Int

    public init(startMinute: Int, endMinute: Int) {
        self.startMinute = startMinute
        self.endMinute = endMinute
    }
}

public struct CategoryOutlook: Equatable, Sendable {
    public var category: ActivityCategory
    public var spans: [DaySpan]
    public var isOpenNow: Bool
    public var closesAtMinute: Int?
    public var opensAtMinute: Int?

    init(category: ActivityCategory, spans: [DaySpan], nowMinute: Int) {
        self.category = category
        self.spans = spans
        let current = spans.first { nowMinute >= $0.startMinute && nowMinute < $0.endMinute }
        isOpenNow = current != nil
        closesAtMinute = current?.endMinute
        opensAtMinute = current == nil ? spans.first { $0.startMinute > nowMinute }?.startMinute : nil
    }

    fileprivate var phrase: String {
        if let closesAtMinute {
            return "\(category.displayName)开放到 \(clockText(closesAtMinute))"
        }
        if let opensAtMinute {
            return "\(category.displayName) \(clockText(opensAtMinute)) 开放"
        }
        return "\(category.displayName)今天不再开放"
    }
}

/// What the parent's day looks like: which stretches are open, and what happens next.
public struct DayOutlook: Equatable, Sendable {
    public var nowMinute: Int
    public var game: CategoryOutlook
    public var video: CategoryOutlook

    public init(rules: RuleSet, requests: [TemporaryRequest], at date: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: rules.timeZoneIdentifier) ?? .current
        let weekday = calendar.component(.weekday, from: date)
        let dayStart = calendar.startOfDay(for: date)
        let nowMinute = Int(date.timeIntervalSince(dayStart) / 60)
        self.nowMinute = nowMinute

        func outlook(for category: ActivityCategory) -> CategoryOutlook {
            let weekly = (rules.activityRules.first { $0.category == category }?.windows ?? [])
                .filter { $0.weekday == weekday }
                .flatMap(Self.spans(of:))
            let granted = requests
                .filter { $0.category == category && $0.status == .approved }
                .compactMap { Self.span(of: $0, dayStart: dayStart) }
            return CategoryOutlook(
                category: category,
                spans: Self.merged(weekly + granted),
                nowMinute: nowMinute
            )
        }

        game = outlook(for: .game)
        video = outlook(for: .video)
    }

    public func isOpen(_ category: ActivityCategory) -> Bool {
        switch category {
        case .game: game.isOpenNow
        case .video: video.isOpenNow
        case .other, .idle: true
        }
    }

    public var summary: String {
        if let closesAt = game.closesAtMinute, closesAt == video.closesAtMinute {
            return "游戏和视频开放到 \(clockText(closesAt))"
        }
        if !game.isOpenNow && !video.isOpenNow {
            if let opensAt = game.opensAtMinute, opensAt == video.opensAtMinute {
                return "游戏和视频 \(clockText(opensAt)) 开放，还有 \(durationText(minutes: opensAt - nowMinute))"
            }
            if game.opensAtMinute == nil && video.opensAtMinute == nil {
                return "今天游戏和视频都不再开放"
            }
        }
        return "\(game.phrase)，\(video.phrase)"
    }

    /// The evaluator treats a window that crosses midnight as both ends of the same weekday.
    private static func spans(of window: ScheduleWindow) -> [DaySpan] {
        guard window.startMinute > window.endMinute else {
            return [DaySpan(startMinute: window.startMinute, endMinute: window.endMinute)]
        }
        return [
            DaySpan(startMinute: 0, endMinute: window.endMinute),
            DaySpan(startMinute: window.startMinute, endMinute: 1_440),
        ]
    }

    private static func span(of request: TemporaryRequest, dayStart: Date) -> DaySpan? {
        guard let start = request.startsAt ?? request.resolvedAt else { return nil }
        let startMinute = Int(start.timeIntervalSince(dayStart) / 60)
        let endMinute = startMinute + request.durationMinutes
        guard endMinute > 0, startMinute < 1_440 else { return nil }
        return DaySpan(startMinute: max(0, startMinute), endMinute: min(1_440, endMinute))
    }

    private static func merged(_ spans: [DaySpan]) -> [DaySpan] {
        var result: [DaySpan] = []
        for span in spans.sorted(by: { $0.startMinute < $1.startMinute }) where span.endMinute > span.startMinute {
            if let last = result.last, span.startMinute <= last.endMinute {
                result[result.count - 1].endMinute = max(last.endMinute, span.endMinute)
            } else {
                result.append(span)
            }
        }
        return result
    }
}

public func clockText(_ minute: Int) -> String {
    String(format: "%02d:%02d", minute / 60, minute % 60)
}

public func durationText(minutes: Int) -> String {
    guard minutes >= 60 else { return "\(minutes) 分钟" }
    let remainder = minutes % 60
    return remainder == 0 ? "\(minutes / 60) 小时" : "\(minutes / 60) 小时 \(remainder) 分"
}

public func deviceHeadline(status: DeviceStatus, outlook: DayOutlook) -> String {
    guard status.lastSeenAt != .distantPast else { return "还没有收到孩子 Mac 的状态" }
    guard status.isOnline else { return "孩子的 Mac 离线" }
    switch status.category {
    case .game:
        return outlook.game.isOpenNow ? "孩子的 Mac 在线，正在玩游戏" : "孩子正在玩游戏，现在不在允许时段"
    case .video:
        return outlook.video.isOpenNow ? "孩子的 Mac 在线，正在看视频" : "孩子正在看视频，现在不在允许时段"
    case .other:
        return "孩子的 Mac 在线，正在用其他应用"
    case .idle:
        return "孩子的 Mac 在线，暂时没有在用"
    }
}

public extension ViolationEvent {
    var parentTitle: String {
        let action = category == .game ? "玩游戏" : "看视频"
        return "不在时段内\(action) · \(normalizedDomain ?? appName)"
    }

    var parentOutcome: String {
        guard wasEnforced else {
            return "提醒 \(warningCount) 次，持续 \(durationSeconds / 60) 分 \(durationSeconds % 60) 秒"
        }
        return "提醒 \(warningCount) 次后\(normalizedDomain == nil ? "已结束应用" : "已关闭标签页")"
    }
}

public extension TemporaryRequest {
    var parentTitle: String {
        let action = category == .game ? "玩" : "看"
        return "想\(action) \(durationMinutes) 分钟\(category.displayName)"
    }
}

/// Reduces whatever a parent pastes to the host the classifier compares against.
public func normalizedDomain(fromParentInput input: String) -> String? {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }
    let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
    guard let host = URL(string: candidate)?.host, host.contains(".") else { return nil }
    return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
}
