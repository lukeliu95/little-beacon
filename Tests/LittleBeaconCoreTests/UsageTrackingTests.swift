import Foundation
import Testing
@testable import LittleBeaconCore

private func date(
    _ hour: Int,
    _ minute: Int = 0,
    year: Int = 2026,
    month: Int = 7,
    day: Int = 20
) -> Date {
    var components = DateComponents()
    components.calendar = Calendar(identifier: .gregorian)
    components.timeZone = TimeZone(identifier: "Asia/Tokyo")
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    return components.date!
}

private var tokyoCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    return calendar
}

@Test func dailyUsageTrackerAccumulatesActiveSecondsAndExcludesIdle() {
    var tracker = DailyUsageTracker(dayKey: DailyUsageTracker.dayKey(for: date(9), calendar: tokyoCalendar))
    tracker.advance(isIdle: false, elapsedSeconds: 30, at: date(9, 0), calendar: tokyoCalendar)
    tracker.advance(isIdle: true, elapsedSeconds: 30, at: date(9, 1), calendar: tokyoCalendar)
    tracker.advance(isIdle: false, elapsedSeconds: 45, at: date(9, 2), calendar: tokyoCalendar)

    #expect(tracker.activeSeconds == 75)
}

@Test func dailyUsageTrackerResetsWhenLocalCalendarDayRolls() {
    var tracker = DailyUsageTracker(dayKey: DailyUsageTracker.dayKey(for: date(23), calendar: tokyoCalendar), activeSeconds: 500)
    tracker.advance(isIdle: false, elapsedSeconds: 30, at: date(23, 59), calendar: tokyoCalendar)
    #expect(tracker.activeSeconds == 530)

    tracker.advance(isIdle: false, elapsedSeconds: 10, at: date(0, 1, day: 21), calendar: tokyoCalendar)
    #expect(tracker.activeSeconds == 10)
    #expect(tracker.dayKey == DailyUsageTracker.dayKey(for: date(0, 1, day: 21), calendar: tokyoCalendar))
}

@Test func pomodoroTimerSuggestsBreakAfterTwentyFiveMinutesOfContinuousUse() {
    var timer = PomodoroTimer()
    #expect(timer.advance(isIdle: false, elapsedSeconds: 1_000) == nil)
    #expect(timer.advance(isIdle: false, elapsedSeconds: 499) == nil)
    #expect(timer.advance(isIdle: false, elapsedSeconds: 1) == .breakSuggested)
    #expect(timer.activeSeconds == 0)
}

@Test func pomodoroTimerTreatsTwoContinuousIdleMinutesAsARealBreak() {
    var timer = PomodoroTimer()
    #expect(timer.advance(isIdle: false, elapsedSeconds: 1_200) == nil)
    #expect(timer.advance(isIdle: true, elapsedSeconds: 60) == nil)
    #expect(timer.advance(isIdle: true, elapsedSeconds: 60) == nil)
    #expect(timer.activeSeconds == 0)
    #expect(timer.idleSeconds == 0)

    // After the reset, resuming activity starts a fresh 25-minute window.
    #expect(timer.advance(isIdle: false, elapsedSeconds: 1_499) == nil)
    #expect(timer.advance(isIdle: false, elapsedSeconds: 1) == .breakSuggested)
}

@Test func pomodoroTimerBriefIdleGapDoesNotResetTheCounter() {
    var timer = PomodoroTimer()
    #expect(timer.advance(isIdle: false, elapsedSeconds: 1_200) == nil)
    #expect(timer.advance(isIdle: true, elapsedSeconds: 30) == nil)
    #expect(timer.advance(isIdle: false, elapsedSeconds: 299) == nil)
    #expect(timer.advance(isIdle: false, elapsedSeconds: 1) == .breakSuggested)
}
