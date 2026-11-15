import Foundation

/// School hours set by the parent (ADR-0017). Inside them only the 25-minute eye-care reminder
/// runs, as a gentle prompt; schedules, reminders, endings, events and the daily-usage nudge
/// all stand aside. Outside them everything works as before.
public struct QuietHours: Codable, Equatable, Sendable {
    public var enabled: Bool
    /// Calendar weekdays: 1 is Sunday and 7 is Saturday.
    public var weekdays: [Int]
    /// Minutes from local midnight. School hours never cross midnight, so start < end.
    public var startMinute: Int
    public var endMinute: Int

    public init(enabled: Bool, weekdays: [Int], startMinute: Int, endMinute: Int) {
        self.enabled = enabled
        self.weekdays = weekdays
        self.startMinute = startMinute
        self.endMinute = endMinute
    }

    /// Weekdays 8:00–18:00, off until the parent turns it on so an upgrade changes nothing.
    public static let schoolDefault = QuietHours(
        enabled: false,
        weekdays: [2, 3, 4, 5, 6],
        startMinute: 8 * 60,
        endMinute: 18 * 60
    )

    public var isValid: Bool {
        weekdays.allSatisfy { (1...7).contains($0) }
            && startMinute >= 0 && endMinute <= DaySchedule.dayMinutes && startMinute < endMinute
    }

    /// Today's quiet stretch, if any.
    public func span(onWeekday weekday: Int) -> DaySpan? {
        guard enabled, isValid, weekdays.contains(weekday) else { return nil }
        return DaySpan(startMinute: startMinute, endMinute: endMinute)
    }

    public func contains(_ date: Date, calendar: Calendar) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        guard let span = span(onWeekday: weekday) else { return false }
        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        return minute >= span.startMinute && minute < span.endMinute
    }
}

public extension RuleSet {
    private var familyCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        return calendar
    }

    func isQuiet(at date: Date) -> Bool {
        schoolQuietHours.contains(date, calendar: familyCalendar)
    }

    /// School hours keep the eye-care reminder but never cover the screen.
    func pomodoroMode(at date: Date) -> PomodoroMode {
        guard isQuiet(at: date), pomodoroMode == .enforced else { return pomodoroMode }
        return .gentle
    }
}

/// What the child Mac does on one monitor tick. School hours switch off everything but the
/// gentle eye-care reminder; a parent's own remote close is not part of this and keeps working.
public struct SupervisionPlan: Equatable, Sendable {
    public var pomodoroMode: PomodoroMode
    /// Schedules, outside-window reminders, endings, the "再玩 5 分钟" offer and violation events.
    public var followsSchedule: Bool
    public var countsDailyUsage: Bool
    public var checksViewingDistance: Bool

    public init(rules: RuleSet, at date: Date) {
        let isQuiet = rules.isQuiet(at: date)
        pomodoroMode = rules.pomodoroMode(at: date)
        followsSchedule = !isQuiet
        countsDailyUsage = !isQuiet
        checksViewingDistance = !isQuiet
    }
}
