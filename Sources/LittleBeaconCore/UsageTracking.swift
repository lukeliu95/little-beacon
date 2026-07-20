import Foundation

/// Accumulates total non-idle screen time for "today" in the device's local calendar.
///
/// Category does not matter here — this is total screen-on time (game + video + other),
/// independent of the game/video rule engine. The accumulator resets to 0 whenever the
/// local calendar day rolls over.
public struct DailyUsageTracker: Codable, Equatable, Sendable {
    public private(set) var dayKey: String
    public private(set) var activeSeconds: Int

    public init(dayKey: String = DailyUsageTracker.dayKey(for: Date(), calendar: .current), activeSeconds: Int = 0) {
        self.dayKey = dayKey
        self.activeSeconds = activeSeconds
    }

    public static func dayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    /// Advances the accumulator by `elapsedSeconds`. Idle time is excluded. Rolls the
    /// accumulator over to 0 when `date` falls on a different local calendar day than the
    /// day this tracker currently represents.
    public mutating func advance(isIdle: Bool, elapsedSeconds: TimeInterval, at date: Date, calendar: Calendar = .current) {
        let todayKey = Self.dayKey(for: date, calendar: calendar)
        if todayKey != dayKey {
            dayKey = todayKey
            activeSeconds = 0
        }
        guard !isIdle else { return }
        activeSeconds += Int(max(0, elapsedSeconds).rounded())
    }
}

/// Signal emitted by `PomodoroTimer` when it is time to suggest a break.
public enum PomodoroSignal: Equatable, Sendable {
    case breakSuggested
}

/// 25-minute Pomodoro-style eye-care break reminder, independent of category and of the
/// game/video rule engine. Counts continuous active (non-idle) seconds; a continuous 2
/// minutes of idle time counts as a real break and resets the counter early.
///
/// This is a gentle nudge only — it never blocks, locks, or pauses anything.
public struct PomodoroTimer: Equatable, Sendable {
    public static let breakThreshold: TimeInterval = 25 * 60
    public static let idleResetThreshold: TimeInterval = 2 * 60

    public private(set) var activeSeconds: TimeInterval
    public private(set) var idleSeconds: TimeInterval

    public init() {
        activeSeconds = 0
        idleSeconds = 0
    }

    @discardableResult
    public mutating func advance(isIdle: Bool, elapsedSeconds: TimeInterval) -> PomodoroSignal? {
        let delta = max(0, elapsedSeconds)
        if isIdle {
            idleSeconds += delta
            if idleSeconds >= Self.idleResetThreshold {
                activeSeconds = 0
                idleSeconds = 0
            }
            return nil
        }

        idleSeconds = 0
        activeSeconds += delta
        if activeSeconds >= Self.breakThreshold {
            activeSeconds = 0
            return .breakSuggested
        }
        return nil
    }
}
