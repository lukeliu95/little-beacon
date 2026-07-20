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

@Test func classifierUsesDomainAndParentOverride() {
    let classifier = ActivityClassifier()
    let youtube = ActivityObservation(
        appName: "Safari",
        bundleIdentifier: "com.apple.Safari",
        normalizedDomain: "www.youtube.com"
    )
    #expect(classifier.classify(youtube, overrides: []).category == .video)

    let override = ClassificationOverride(target: .domain, value: "youtube.com", category: .other)
    #expect(classifier.classify(youtube, overrides: [override]).category == .other)
}

@Test func evaluatorHonorsWeeklyWindowAndTemporaryGrant() {
    let rules = RuleSet(
        timeZoneIdentifier: "Asia/Tokyo",
        activityRules: [
            ActivityRule(category: .game, windows: [
                ScheduleWindow(weekday: 2, startMinute: 18 * 60, endMinute: 20 * 60),
            ]),
        ]
    )
    let evaluator = RuleEvaluator()
    #expect(evaluator.isAllowed(category: .game, at: date(19), rules: rules, temporaryGrants: []))
    #expect(!evaluator.isAllowed(category: .game, at: date(21), rules: rules, temporaryGrants: []))

    let grant = TemporaryGrant(
        category: .game,
        startsAt: date(20),
        endsAt: date(22)
    )
    #expect(evaluator.isAllowed(category: .game, at: date(21), rules: rules, temporaryGrants: [grant]))
}

@Test func violationEscalatesAtExpectedThresholds() {
    var machine = ViolationMachine()
    let activity = ClassifiedActivity(
        observation: ActivityObservation(appName: "Minecraft", bundleIdentifier: "com.mojang.minecraftlauncher"),
        category: .game
    )
    let start = Date(timeIntervalSince1970: 1_000)

    #expect(machine.advance(activity: activity, isAllowed: false, elapsedSeconds: 0, at: start) == [
        .warning(level: 1, activity: activity),
    ])
    #expect(machine.advance(activity: activity, isAllowed: false, elapsedSeconds: 60, at: start.addingTimeInterval(60)) == [
        .warning(level: 2, activity: activity),
        .beginEvent(activity: activity, startedAt: start),
    ])
    #expect(machine.advance(activity: activity, isAllowed: false, elapsedSeconds: 60, at: start.addingTimeInterval(120)) == [
        .warning(level: 3, activity: activity),
    ])
    #expect(machine.advance(activity: activity, isAllowed: false, elapsedSeconds: 60, at: start.addingTimeInterval(180)) == [
        .enforce(activity: activity),
    ])
}

@Test func shortCleanGapPausesAndFiveMinutesResets() {
    var machine = ViolationMachine()
    let game = ClassifiedActivity(
        observation: ActivityObservation(appName: "Game", bundleIdentifier: "game.id"),
        category: .game
    )
    let other = ClassifiedActivity(observation: ActivityObservation(appName: "Pages"), category: .other)
    let start = Date(timeIntervalSince1970: 2_000)

    _ = machine.advance(activity: game, isAllowed: false, elapsedSeconds: 0, at: start)
    _ = machine.advance(activity: game, isAllowed: false, elapsedSeconds: 59, at: start.addingTimeInterval(59))
    #expect(machine.advance(activity: other, isAllowed: true, elapsedSeconds: 2, at: start.addingTimeInterval(61)).isEmpty)
    #expect(machine.advance(activity: game, isAllowed: false, elapsedSeconds: 1, at: start.addingTimeInterval(62)).contains {
        if case .warning(level: 2, _) = $0 { true } else { false }
    })

    #expect(machine.advance(activity: other, isAllowed: true, elapsedSeconds: 300, at: start.addingTimeInterval(362)) == [.reset])
    #expect(machine.state == nil)
}

@Test func switchingRestrictedCategoriesKeepsWarningDebt() {
    var machine = ViolationMachine()
    let game = ClassifiedActivity(
        observation: ActivityObservation(appName: "Game", bundleIdentifier: "game.id"),
        category: .game
    )
    let video = ClassifiedActivity(
        observation: ActivityObservation(appName: "Safari", normalizedDomain: "youtube.com"),
        category: .video
    )
    let start = Date(timeIntervalSince1970: 3_000)

    _ = machine.advance(activity: game, isAllowed: false, elapsedSeconds: 0, at: start)
    _ = machine.advance(activity: game, isAllowed: false, elapsedSeconds: 119, at: start.addingTimeInterval(119))
    let actions = machine.advance(activity: video, isAllowed: false, elapsedSeconds: 1, at: start.addingTimeInterval(120))
    #expect(actions == [.warning(level: 3, activity: video)])
}
