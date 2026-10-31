import Foundation

public enum ReminderStrategy: String, Codable, CaseIterable, Identifiable, Sendable {
    case gentle
    case standard
    case strict

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .gentle: "温和"
        case .standard: "标准"
        case .strict: "严格"
        }
    }
}

public enum ReminderSurface: Equatable, Sendable {
    case corner
    case center
    case fullScreen
}

public struct ReminderSignal: Equatable, Sendable {
    public var surface: ReminderSurface
    public var playsSound: Bool
    public var speaks: Bool

    public init(_ surface: ReminderSurface, playsSound: Bool = false, speaks: Bool = false) {
        self.surface = surface
        self.playsSound = playsSound
        self.speaks = speaks
    }
}

/// What happens when the finishing time runs out and the child is still there.
public enum FinishOutcome: Equatable, Sendable {
    case notifyOnly
    case dimThenEnd(seconds: Int)
    case end
}

/// Every timing and surface of one strategy, in one place, so the three presets can be read
/// side by side and match the table in the spec.
public struct ReminderPlan: Equatable, Sendable {
    public var showsCountdown: Bool
    public var fifteenMinuteSignal: ReminderSignal?
    public var fiveMinuteSignal: ReminderSignal?
    public var endSignal: ReminderSignal
    public var finishSeconds: Int
    public var finishOutcome: FinishOutcome
    public var dailyExtensions: Int
    /// Seconds of continued activity outside any window before each outside-window warning.
    public var lastWarningSeconds: Int?
    public var enforceAfterSeconds: Int?
    public var outsideFirstSignal: ReminderSignal
    public var outsideSecondSignal: ReminderSignal
}

public extension ReminderStrategy {
    static let countdownSeconds = 15 * 60
    static let extensionMinutes = 5

    var plan: ReminderPlan {
        switch self {
        case .gentle:
            ReminderPlan(
                showsCountdown: false,
                fifteenMinuteSignal: nil,
                fiveMinuteSignal: ReminderSignal(.corner),
                endSignal: ReminderSignal(.corner),
                finishSeconds: 5 * 60,
                finishOutcome: .notifyOnly,
                dailyExtensions: 2,
                lastWarningSeconds: 120,
                enforceAfterSeconds: nil,
                outsideFirstSignal: ReminderSignal(.center, playsSound: true),
                outsideSecondSignal: ReminderSignal(.center, playsSound: true)
            )
        case .standard:
            ReminderPlan(
                showsCountdown: true,
                fifteenMinuteSignal: nil,
                fiveMinuteSignal: ReminderSignal(.corner, playsSound: true),
                endSignal: ReminderSignal(.center, playsSound: true),
                finishSeconds: 3 * 60,
                finishOutcome: .dimThenEnd(seconds: 30),
                dailyExtensions: 1,
                lastWarningSeconds: 120,
                enforceAfterSeconds: 180,
                outsideFirstSignal: ReminderSignal(.center, playsSound: true),
                outsideSecondSignal: ReminderSignal(.center, playsSound: true)
            )
        case .strict:
            ReminderPlan(
                showsCountdown: true,
                fifteenMinuteSignal: ReminderSignal(.corner),
                fiveMinuteSignal: ReminderSignal(.center, playsSound: true),
                endSignal: ReminderSignal(.center, playsSound: true, speaks: true),
                finishSeconds: 60,
                finishOutcome: .end,
                dailyExtensions: 0,
                lastWarningSeconds: nil,
                enforceAfterSeconds: 120,
                outsideFirstSignal: ReminderSignal(.center, playsSound: true, speaks: true),
                outsideSecondSignal: ReminderSignal(.fullScreen, playsSound: true)
            )
        }
    }
}

/// An unbroken open stretch of one category, and the strategy that governs how it ends.
public struct OpeningStretch: Equatable, Sendable {
    public var category: ActivityCategory
    public var endsAt: Date
    public var strategy: ReminderStrategy

    public init(category: ActivityCategory, endsAt: Date, strategy: ReminderStrategy) {
        self.category = category
        self.endsAt = endsAt
        self.strategy = strategy
    }
}

public extension RuleSet {
    /// When the category currently open closes, joining weekly slots and grants that touch, and
    /// carrying on past midnight when the next day continues. `nil` means it is closed right now.
    func openStretch(
        for category: ActivityCategory,
        at date: Date,
        grants: [TemporaryGrant]
    ) -> OpeningStretch? {
        guard category == .game || category == .video else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        let today = calendar.startOfDay(for: date)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return nil }

        struct Interval {
            var start: Date
            var end: Date
            var strategy: ReminderStrategy?
        }

        func intervals(on day: Date) -> [Interval] {
            let weekday = calendar.component(.weekday, from: day)
            return daySchedule(for: category, weekday: weekday).slots.map {
                Interval(
                    start: day.addingTimeInterval(TimeInterval($0.startMinute * 60)),
                    end: day.addingTimeInterval(TimeInterval($0.endMinute * 60)),
                    strategy: $0.reminderStrategy
                )
            }
        }

        let intervals = (intervals(on: today) + intervals(on: tomorrow) + grants
            .filter { $0.category == category }
            .map { Interval(start: $0.startsAt, end: $0.endsAt, strategy: nil) })
            .sorted { $0.start < $1.start }

        guard var current = intervals.first(where: { $0.start <= date && date < $0.end }) else {
            return nil
        }
        for interval in intervals where interval.start <= current.end && interval.end > current.end {
            current.end = interval.end
            current.strategy = interval.strategy
        }
        return OpeningStretch(
            category: category,
            endsAt: current.end,
            strategy: current.strategy ?? defaultReminderStrategy
        )
    }
}

public enum EndingMoment: Equatable, Sendable {
    case fifteenMinutes
    case fiveMinutes
    case timeUp(finishSeconds: Int)
}

public enum EndingAction: Equatable, Sendable {
    case remind(EndingMoment, category: ActivityCategory, strategy: ReminderStrategy)
    /// Finishing time is over and this strategy only tells the parent.
    case reportOnly(category: ActivityCategory)
    case endActivity(category: ActivityCategory, strategy: ReminderStrategy)
}

public struct EndingCountdown: Equatable, Sendable {
    public var category: ActivityCategory
    public var remainingSeconds: Int
    public var isFinishing: Bool

    public init(category: ActivityCategory, remainingSeconds: Int, isFinishing: Bool) {
        self.category = category
        self.remainingSeconds = remainingSeconds
        self.isFinishing = isFinishing
    }
}

public struct EndingStep: Equatable, Sendable {
    public var actions: [EndingAction] = []
    /// True while an ending is being handled, so the outside-window warnings stay out of it.
    public var keepsActivityAllowed = false
    public var countdown: EndingCountdown?
    public var isDimming = false

    public init() {}
}

/// Follows one activity to the end of its open stretch: reminders ahead of the end, then the
/// finishing time, then that strategy's outcome. A child who is not using the activity when it
/// closes never enters this path; opening it later is the ordinary outside-window case.
public struct EndingMachine: Codable, Equatable, Sendable {
    private struct Tracked: Codable, Equatable {
        var endsAt: Date
        var strategy: ReminderStrategy
        var lastInUseAt: Date
        var sentFifteen = false
        var sentFive = false
        var isClosing = false
        var sentTimeUp = false
        var sentOutcome = false
    }

    /// Being on the activity this close to the end counts as "still using it when it closed".
    public func strategy(for category: ActivityCategory) -> ReminderStrategy? {
        tracked[category]?.strategy
    }

    private static let closingTolerance: TimeInterval = 60
    private static let abandonedAfter: TimeInterval = 300

    private var tracked: [ActivityCategory: Tracked] = [:]

    public init() {}

    public mutating func advance(
        category: ActivityCategory,
        stretch: OpeningStretch?,
        at date: Date
    ) -> EndingStep {
        tracked = tracked.filter { date.timeIntervalSince($0.value.lastInUseAt) < Self.abandonedAfter }
        guard category == .game || category == .video else { return EndingStep() }
        if let stretch {
            return followOpen(stretch, at: date)
        }
        return followClosed(category, at: date)
    }

    private mutating func followOpen(_ stretch: OpeningStretch, at date: Date) -> EndingStep {
        let remaining = stretch.endsAt.timeIntervalSince(date)
        var entry: Tracked
        if let existing = tracked[stretch.category], existing.endsAt == stretch.endsAt {
            entry = existing
        } else {
            entry = Tracked(endsAt: stretch.endsAt, strategy: stretch.strategy, lastInUseAt: date)
            // More time granted during the finishing time should not restart the warnings.
            if tracked[stretch.category]?.isClosing == true {
                entry.sentFifteen = remaining <= TimeInterval(ReminderStrategy.countdownSeconds)
                entry.sentFive = remaining <= 300
            }
        }
        entry.strategy = stretch.strategy
        entry.lastInUseAt = date

        var step = EndingStep()
        step.keepsActivityAllowed = true
        let plan = stretch.strategy.plan
        if remaining <= 300, !entry.sentFive {
            entry.sentFive = true
            entry.sentFifteen = true
            if plan.fiveMinuteSignal != nil {
                step.actions.append(.remind(.fiveMinutes, category: stretch.category, strategy: stretch.strategy))
            }
        } else if remaining <= TimeInterval(ReminderStrategy.countdownSeconds), !entry.sentFifteen {
            entry.sentFifteen = true
            if plan.fifteenMinuteSignal != nil {
                step.actions.append(.remind(.fifteenMinutes, category: stretch.category, strategy: stretch.strategy))
            }
        }
        if plan.showsCountdown, remaining <= TimeInterval(ReminderStrategy.countdownSeconds) {
            step.countdown = EndingCountdown(
                category: stretch.category,
                remainingSeconds: Int(remaining.rounded(.up)),
                isFinishing: false
            )
        }
        tracked[stretch.category] = entry
        return step
    }

    private mutating func followClosed(_ category: ActivityCategory, at date: Date) -> EndingStep {
        guard var entry = tracked[category] else { return EndingStep() }
        if !entry.isClosing {
            guard date >= entry.endsAt,
                  entry.lastInUseAt.timeIntervalSince(entry.endsAt) >= -Self.closingTolerance else {
                tracked[category] = nil
                return EndingStep()
            }
            entry.isClosing = true
        }

        let plan = entry.strategy.plan
        let finishEnds = entry.endsAt.addingTimeInterval(TimeInterval(plan.finishSeconds))
        // Coming back after the finishing time ran out is an ordinary outside-window start.
        if date >= finishEnds, date.timeIntervalSince(entry.lastInUseAt) > 30 {
            tracked[category] = nil
            return EndingStep()
        }
        entry.lastInUseAt = date

        var step = EndingStep()
        step.keepsActivityAllowed = true
        if date < finishEnds {
            if !entry.sentTimeUp {
                entry.sentTimeUp = true
                step.actions.append(.remind(
                    .timeUp(finishSeconds: plan.finishSeconds),
                    category: category,
                    strategy: entry.strategy
                ))
            }
            step.countdown = EndingCountdown(
                category: category,
                remainingSeconds: Int(finishEnds.timeIntervalSince(date).rounded(.up)),
                isFinishing: true
            )
            tracked[category] = entry
            return step
        }

        switch plan.finishOutcome {
        case .notifyOnly:
            if !entry.sentOutcome {
                entry.sentOutcome = true
                step.actions.append(.reportOnly(category: category))
            }
            tracked[category] = entry
        case let .dimThenEnd(seconds):
            let endsAt = finishEnds.addingTimeInterval(TimeInterval(seconds))
            if date >= endsAt {
                step.actions.append(.endActivity(category: category, strategy: entry.strategy))
                tracked[category] = nil
            } else {
                step.isDimming = true
                step.countdown = EndingCountdown(
                    category: category,
                    remainingSeconds: Int(endsAt.timeIntervalSince(date).rounded(.up)),
                    isFinishing: true
                )
                tracked[category] = entry
            }
        case .end:
            step.actions.append(.endActivity(category: category, strategy: entry.strategy))
            tracked[category] = nil
        }
        return step
    }
}

/// How many times today the child has used "再玩 5 分钟". It resets with the local day.
public struct ExtensionLedger: Codable, Equatable, Sendable {
    public private(set) var dayKey = ""
    public private(set) var used = 0

    public init() {}

    public func remaining(limit: Int, dayKey: String) -> Int {
        max(0, limit - (dayKey == self.dayKey ? used : 0))
    }

    public mutating func record(dayKey: String) {
        if dayKey != self.dayKey {
            self.dayKey = dayKey
            used = 0
        }
        used += 1
    }
}

public extension ReminderMessage {
    static func of(_ moment: EndingMoment, category: ActivityCategory) -> ReminderMessage {
        let verb = category == .game ? "玩" : "看"
        let name = category.displayName
        switch moment {
        case .fifteenMinutes:
            return ReminderMessage(title: "\(name)还能\(verb) 15 分钟", body: "到时间前记得存档。")
        case .fiveMinutes:
            return ReminderMessage(title: "还有 5 分钟", body: "\(name)快结束了，记得存档。")
        case let .timeUp(finishSeconds):
            return ReminderMessage(
                title: "\(name)时间到了",
                body: "还有 \(finishSeconds / 60) 分钟收尾，找个地方停下来吧。"
            )
        }
    }

    static func finishOver(category: ActivityCategory) -> ReminderMessage {
        ReminderMessage(title: "\(category.displayName)时间结束了", body: "家长会收到提醒。")
    }

    static func activityEnded(category: ActivityCategory) -> ReminderMessage {
        ReminderMessage(title: "这段\(category.displayName)时间用完了", body: "已经帮你结束了。")
    }
}

/// What the child reads when an activity is opened outside any window. The standard wording
/// is the original three-step text.
public func outsideWarningText(level: Int, category: ActivityCategory, strategy: ReminderStrategy) -> String {
    let name = category.displayName
    switch (strategy, level) {
    case (_, 1) where strategy != .strict:
        return "现在不是\(name)时间，请在 60 秒内离开。"
    case (.strict, 1):
        return "现在不是\(name)时间，2 分钟后结束。"
    case (.strict, _):
        return "1 分钟后结束\(name)。"
    case (.gentle, 2):
        return "请先离开\(name)，家长端将收到通知。"
    case (.gentle, _):
        return "家长已经收到提醒。"
    case (_, 2):
        return "第二次提醒：请停止\(name)，家长端将收到通知。"
    default:
        return "最后提醒：60 秒后将结束当前\(name)活动。"
    }
}

public struct ReminderMessage: Equatable, Sendable {
    public var title: String
    public var body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }

    public var spokenText: String { "\(title)。\(body)" }
}

public extension ViolationEvent {
    /// A "再玩 5 分钟" is stored as an event with no warnings, so it needs no new table, syncs
    /// to the parent like any event, and expires after 30 days with the rest.
    static func extensionRecord(category: ActivityCategory, at date: Date) -> ViolationEvent {
        ViolationEvent(
            category: category,
            appName: "再玩一会儿",
            startedAt: date,
            durationSeconds: ReminderStrategy.extensionMinutes * 60,
            warningCount: 0,
            wasEnforced: false
        )
    }

    var isExtensionRecord: Bool { warningCount == 0 }
}

/// The child's first line: how long is left when something is open, otherwise when it opens.
public func childHeadline(outlook: DayOutlook, activity: ActivityCategory) -> String {
    let preferred: CategoryOutlook? = {
        if activity == .video, outlook.video.isOpenNow { return outlook.video }
        if outlook.game.isOpenNow { return outlook.game }
        return outlook.video.isOpenNow ? outlook.video : nil
    }()
    guard let preferred, let closesAt = preferred.closesAtMinute else { return outlook.summary }
    let verb = preferred.category == .game ? "玩" : "看"
    return "\(preferred.category.displayName)还能\(verb) \(durationText(minutes: closesAt - outlook.nowMinute))"
}
