import Foundation
import Testing
@testable import LittleBeaconCore

private let tokyo = TimeZone(identifier: "Asia/Tokyo")!

/// 2026-07-20 is a Monday.
private func date(day: Int = 20, _ hour: Int, _ minute: Int = 0) -> Date {
    var components = DateComponents()
    components.calendar = Calendar(identifier: .gregorian)
    components.timeZone = tokyo
    components.year = 2026
    components.month = 7
    components.day = day
    components.hour = hour
    components.minute = minute
    return components.date!
}

private func rules(studying from: Int, to: Int, school: Bool = false) -> RuleSet {
    var rules = RuleSet.starter
    rules.timeZoneIdentifier = "Asia/Tokyo"
    rules.pomodoroMode = .enforced
    rules.schoolQuietHours.enabled = school
    rules.studySessions = [StudySession(startsAt: date(from), endsAt: date(to))]
    return rules
}

// MARK: - Exit password

@Test func exitPasswordMatchesOnlyTheSameText() throws {
    let password = try #require(ExitPassword.make(from: "灯塔2026", iterations: 1_000))
    #expect(password.matches("灯塔2026"))
    #expect(!password.matches("灯塔2025"))
    #expect(!password.matches(""))
    #expect(!password.digest.contains("灯塔"))
}

@Test func exitPasswordIsSaltedAndNeedsFourCharacters() throws {
    #expect(ExitPassword.make(from: "123") == nil)
    let first = try #require(ExitPassword.make(from: "1234", iterations: 1_000))
    let second = try #require(ExitPassword.make(from: "1234", iterations: 1_000))
    #expect(first.salt != second.salt)
    #expect(first.digest != second.digest)
    #expect(ExitPassword.defaultIterations >= 100_000)
}

@Test func aDamagedExitPasswordNeverMatches() {
    #expect(!ExitPassword(salt: "!!", digest: "AAAA", iterations: 1_000).matches("1234"))
    #expect(!ExitPassword(salt: "AAAA", digest: "AAAA", iterations: 0).matches("1234"))
}

@Test func fiveWrongAnswersLockTheBoxForAMinute() {
    var attempts = ExitPasswordAttempts()
    let start = date(10)
    for _ in 1..<ExitPasswordAttempts.allowedFailures {
        attempts.record(success: false, at: start)
    }
    #expect(!attempts.isLocked(at: start))
    attempts.record(success: false, at: start)
    #expect(attempts.isLocked(at: start.addingTimeInterval(59)))
    #expect(attempts.secondsLeft(at: start.addingTimeInterval(30)) == 30)
    #expect(!attempts.isLocked(at: start.addingTimeInterval(60)))

    attempts.record(success: false, at: start.addingTimeInterval(61))
    #expect(!attempts.isLocked(at: start.addingTimeInterval(61)))
    attempts.record(success: true, at: start.addingTimeInterval(62))
    #expect(attempts == ExitPasswordAttempts())
}

@Test func clearedExitPasswordIsSentAsNullSoTheServerClearsIt() throws {
    var rules = RuleSet.starter
    rules.childExitPassword = nil
    let json = try #require(String(data: JSONEncoder().encode(rules), encoding: .utf8))
    #expect(json.contains("\"childExitPassword\":null"))

    rules.childExitPassword = ExitPassword.make(from: "123456", iterations: 1_000)
    let roundTrip = try JSONDecoder().decode(RuleSet.self, from: JSONEncoder().encode(rules))
    #expect(roundTrip.childExitPassword == rules.childExitPassword)
}

// MARK: - Study sessions

@Test func studySessionSilencesEverythingIncludingTheEyeReminder() {
    let studying = SupervisionPlan(rules: rules(studying: 19, to: 21), at: date(20))
    #expect(studying.pomodoroMode == .off)
    #expect(!studying.followsSchedule)
    #expect(!studying.countsDailyUsage)
    #expect(!studying.checksViewingDistance)

    let after = SupervisionPlan(rules: rules(studying: 19, to: 21), at: date(21))
    #expect(after.pomodoroMode == .enforced)
    #expect(after.followsSchedule)
    #expect(!rules(studying: 19, to: 21).isStudying(at: date(18, 59)))
}

@Test func studySessionIsQuieterThanSchoolHours() {
    let plan = SupervisionPlan(rules: rules(studying: 9, to: 11, school: true), at: date(10))
    #expect(plan.pomodoroMode == .off)
    let schoolOnly = SupervisionPlan(rules: rules(studying: 9, to: 11, school: true), at: date(12))
    #expect(schoolOnly.pomodoroMode == .gentle)
}

@Test func anInvalidStudySessionSilencesNothing() {
    var long = RuleSet.starter
    long.studySessions = [StudySession(startsAt: date(8), endsAt: date(21))]
    #expect(!long.isStudying(at: date(10)))
    var backwards = RuleSet.starter
    backwards.studySessions = [StudySession(startsAt: date(21), endsAt: date(19))]
    #expect(!backwards.isStudying(at: date(20)))
}

@Test func addingAStudySessionDropsFinishedOnesAndRefusesBadOnes() throws {
    let now = date(20)
    let finished = StudySession(startsAt: date(8), endsAt: date(10))
    let later = StudySession(startsAt: date(21), endsAt: date(22))
    let added = try #require(studySessions([later, finished], adding: StudySession(startsAt: now, endsAt: date(21)), at: now))
    #expect(added.count == 2)
    #expect(added.first?.startsAt == now)

    #expect(studySessions([], adding: StudySession(startsAt: date(8), endsAt: date(9)), at: now) == nil)
    #expect(studySessions([], adding: StudySession(startsAt: date(8), endsAt: date(21)), at: now) == nil)
    let full = (0..<StudySession.maximumCount).map { _ in later }
    #expect(studySessions(full, adding: later, at: now) == nil)
}

@Test func outlookShowsTheStudySessionToParentAndChild() {
    let rules = rules(studying: 19, to: 21)
    let during = DayOutlook(rules: rules, requests: [], at: date(20))
    #expect(during.study == [DaySpan(startMinute: 19 * 60, endMinute: 21 * 60)])
    #expect(during.isStudyingNow)
    #expect(during.isQuietNow)
    #expect(during.summary == "学习时段，到 21:00 小灯塔保持安静")
    #expect(childHeadline(outlook: during, activity: .game) == during.summary)
    #expect(deviceHeadline(status: DeviceStatus(category: .video, lastSeenAt: date(20)), outlook: during)
        == "孩子的 Mac 在线，学习时段在看视频")

    let before = DayOutlook(rules: rules, requests: [], at: date(18))
    #expect(!before.isStudyingNow)
    #expect(before.study.count == 1)
    #expect(DayOutlook(rules: rules, requests: [], at: date(day: 21, 20)).study.isEmpty)
}

@Test func oldRulesWithoutTheNewFieldsDecode() throws {
    let oldJSON = """
    {"revision":1,"timeZoneIdentifier":"Asia/Tokyo","activityRules":[],"overrides":[]}
    """.data(using: .utf8)!
    let rules = try JSONDecoder().decode(RuleSet.self, from: oldJSON)
    #expect(rules.studySessions.isEmpty)
    #expect(rules.childExitPassword == nil)
}
