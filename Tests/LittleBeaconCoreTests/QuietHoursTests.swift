import Foundation
import Testing
@testable import LittleBeaconCore

private let tokyo = TimeZone(identifier: "Asia/Tokyo")!

/// 2026-07-20 is a Monday; day 25 is the Saturday after it.
private func date(day: Int = 20, _ hour: Int, _ minute: Int = 0, in timeZone: TimeZone = tokyo) -> Date {
    var components = DateComponents()
    components.calendar = Calendar(identifier: .gregorian)
    components.timeZone = timeZone
    components.year = 2026
    components.month = 7
    components.day = day
    components.hour = hour
    components.minute = minute
    return components.date!
}

private func schoolRules(pomodoro: PomodoroMode = .gentle, enabled: Bool = true) -> RuleSet {
    var rules = RuleSet.starter
    rules.timeZoneIdentifier = "Asia/Tokyo"
    rules.pomodoroMode = pomodoro
    rules.schoolQuietHours.enabled = enabled
    return rules
}

@Test func schoolHoursAreWeekdaysEightToSixAndOffByDefault() {
    let hours = QuietHours.schoolDefault
    #expect(!hours.enabled)
    #expect(hours.weekdays == [2, 3, 4, 5, 6])
    #expect(hours.startMinute == 480)
    #expect(hours.endMinute == 1_080)
    #expect(!RuleSet.starter.isQuiet(at: date(10)))
}

@Test func schoolHoursCoverEightOClockButNotSixOClock() {
    let rules = schoolRules()
    #expect(!rules.isQuiet(at: date(7, 59)))
    #expect(rules.isQuiet(at: date(8, 0)))
    #expect(rules.isQuiet(at: date(17, 59)))
    #expect(!rules.isQuiet(at: date(18, 0)))
    #expect(!rules.isQuiet(at: date(day: 25, 10)))
}

@Test func schoolHoursFollowTheFamilyTimeZoneNotTheMac() {
    let rules = schoolRules()
    // 10:00 in Tokyo is 01:00 UTC; 10:00 UTC is 19:00 in Tokyo.
    #expect(rules.isQuiet(at: date(1, 0, in: TimeZone(identifier: "UTC")!)))
    #expect(!rules.isQuiet(at: date(10, 0, in: TimeZone(identifier: "UTC")!)))
}

@Test func insideSchoolHoursOnlyTheGentleEyeReminderRuns() {
    let plan = SupervisionPlan(rules: schoolRules(pomodoro: .enforced), at: date(10))
    #expect(plan.pomodoroMode == .gentle)
    #expect(!plan.followsSchedule)
    #expect(!plan.countsDailyUsage)
    #expect(!plan.checksViewingDistance)
}

@Test func outsideSchoolHoursEverythingWorksAsBefore() {
    let plan = SupervisionPlan(rules: schoolRules(pomodoro: .enforced), at: date(18))
    #expect(plan.pomodoroMode == .enforced)
    #expect(plan.followsSchedule)
    #expect(plan.countsDailyUsage)
    #expect(plan.checksViewingDistance)

    let switchedOff = SupervisionPlan(rules: schoolRules(pomodoro: .enforced, enabled: false), at: date(10))
    #expect(switchedOff.pomodoroMode == .enforced)
    #expect(switchedOff.followsSchedule)
}

@Test func aParentWhoTurnedTheEyeReminderOffKeepsItOff() {
    #expect(SupervisionPlan(rules: schoolRules(pomodoro: .off), at: date(10)).pomodoroMode == .off)
}

@Test func invalidSchoolHoursNeverSilenceAnything() {
    var rules = schoolRules()
    rules.schoolQuietHours.startMinute = 18 * 60
    rules.schoolQuietHours.endMinute = 8 * 60
    #expect(!rules.schoolQuietHours.isValid)
    #expect(!rules.isQuiet(at: date(10)))
    #expect(!rules.isQuiet(at: date(20)))
}

@Test func outlookTellsParentAndChildWhenSchoolHoursAreOn() {
    let rules = schoolRules()
    let during = DayOutlook(rules: rules, requests: [], at: date(10))
    #expect(during.quiet == DaySpan(startMinute: 480, endMinute: 1_080))
    #expect(during.isQuietNow)
    #expect(during.summary == "上学时段，到 18:00 只提醒休息眼睛")
    #expect(childHeadline(outlook: during, activity: .game) == during.summary)
    let playing = DeviceStatus(category: .game, lastSeenAt: date(10))
    #expect(deviceHeadline(status: playing, outlook: during) == "孩子的 Mac 在线，上学时段在玩游戏")

    let after = DayOutlook(rules: rules, requests: [], at: date(19))
    #expect(!after.isQuietNow)
    #expect(after.summary != during.summary)
    #expect(DayOutlook(rules: rules, requests: [], at: date(day: 25, 10)).quiet == nil)
}

@Test func oldRulesWithoutSchoolHoursDecodeAsOff() throws {
    let oldJSON = """
    {"revision":1,"timeZoneIdentifier":"Asia/Tokyo","activityRules":[],"overrides":[]}
    """.data(using: .utf8)!
    let rules = try JSONDecoder().decode(RuleSet.self, from: oldJSON)
    #expect(rules.schoolQuietHours == .schoolDefault)

    var changed = rules
    changed.schoolQuietHours.enabled = true
    changed.schoolQuietHours.weekdays = [2, 4]
    let roundTrip = try JSONDecoder().decode(RuleSet.self, from: JSONEncoder().encode(changed))
    #expect(roundTrip.schoolQuietHours == changed.schoolQuietHours)
}
