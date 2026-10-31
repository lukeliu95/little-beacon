import Foundation
import Testing
@testable import LittleBeaconCore

private let tokyo = TimeZone(identifier: "Asia/Tokyo")!

/// 2026-07-20 is a Monday, weekday 2.
private func monday(_ hour: Int, _ minute: Int = 0, _ second: Int = 0, day: Int = 20) -> Date {
    var components = DateComponents()
    components.calendar = Calendar(identifier: .gregorian)
    components.timeZone = tokyo
    components.year = 2026
    components.month = 7
    components.day = day
    components.hour = hour
    components.minute = minute
    components.second = second
    return components.date!
}

private func rules(
    game: [ScheduleWindow] = [ScheduleWindow(weekday: 2, startMinute: 18 * 60, endMinute: 20 * 60)],
    fallback: ReminderStrategy = .standard
) -> RuleSet {
    RuleSet(
        timeZoneIdentifier: "Asia/Tokyo",
        activityRules: [
            ActivityRule(category: .game, windows: game),
            ActivityRule(category: .video, windows: []),
        ],
        defaultReminderStrategy: fallback
    )
}

private func playing(_ name: String = "Roblox") -> ClassifiedActivity {
    ClassifiedActivity(observation: ActivityObservation(appName: name), category: .game)
}

/// Runs the machine a second at a time, the way the monitor does, and collects what it did.
private struct Run {
    var machine = EndingMachine()
    var set: RuleSet
    var actions: [(Date, EndingAction)] = []
    var lastStep = EndingStep()

    init(_ set: RuleSet) {
        self.set = set
    }

    mutating func advance(from start: Date, to end: Date, category: ActivityCategory = .game, grants: [TemporaryGrant] = []) {
        var date = start
        while date <= end {
            let stretch = set.openStretch(for: category, at: date, grants: grants)
            lastStep = machine.advance(category: category, stretch: stretch, at: date)
            actions += lastStep.actions.map { (date, $0) }
            date.addTimeInterval(1)
        }
    }
}

// MARK: - 规则数据

@Test func documentsSavedBeforeStrategiesLoadAsStandard() throws {
    let old = #"{"revision":1,"timeZoneIdentifier":"Asia/Tokyo","overrides":[],"activityRules":[{"category":"game","windows":[{"id":"8CA96461-DFAB-409A-961E-218F0F6B429E","weekday":2,"startMinute":1080,"endMinute":1200}]}]}"#
    let decoded = try JSONDecoder().decode(RuleSet.self, from: Data(old.utf8))

    #expect(decoded.defaultReminderStrategy == .standard)
    #expect(decoded.activityRules[0].windows[0].reminderStrategy == nil)
}

@Test func strategiesSurviveARoundTrip() throws {
    var set = rules(fallback: .strict)
    set.activityRules[0].windows[0].reminderStrategy = .gentle

    let decoded = try JSONDecoder().decode(RuleSet.self, from: JSONEncoder().encode(set))

    #expect(decoded.defaultReminderStrategy == .strict)
    #expect(decoded.activityRules[0].windows[0].reminderStrategy == .gentle)
}

@Test func editingASlotKeepsItsStrategy() {
    let slot = DaySlot(startMinute: 18 * 60, endMinute: 20 * 60, reminderStrategy: .strict)
    let schedule = DaySchedule(slots: [slot])

    #expect(schedule.moved(slot, byMinutes: 60).reminderStrategy == .strict)
    #expect(schedule.resizedStart(slot, toMinute: 17 * 60).reminderStrategy == .strict)
    #expect(schedule.resizedEnd(slot, toMinute: 21 * 60).reminderStrategy == .strict)
}

@Test func strategiesAreSavedAndCopiedWithTheDay() {
    var set = RuleSet.starter
    let slot = DaySlot(startMinute: 18 * 60, endMinute: 20 * 60, reminderStrategy: .strict)
    set.setSchedule(DaySchedule(slots: [slot]), for: .game, weekday: 2)
    set.copySchedule(for: .game, from: 2, to: [3])

    #expect(set.daySchedule(for: .game, weekday: 2).slots.first?.reminderStrategy == .strict)
    #expect(set.daySchedule(for: .game, weekday: 3).slots.first?.reminderStrategy == .strict)
}

// MARK: - 当前时段

@Test func stretchEndsAtTheSlotEndAndUsesItsStrategy() {
    var set = rules()
    set.activityRules[0].windows[0].reminderStrategy = .strict

    let stretch = set.openStretch(for: .game, at: monday(19), grants: [])
    #expect(stretch == OpeningStretch(category: .game, endsAt: monday(20), strategy: .strict))
}

@Test func stretchFallsBackToTheDefaultStrategy() {
    #expect(rules(fallback: .gentle).openStretch(for: .game, at: monday(19), grants: [])?.strategy == .gentle)
}

@Test func nothingIsOpenOutsideAWindow() {
    #expect(rules().openStretch(for: .game, at: monday(15), grants: []) == nil)
    #expect(rules().openStretch(for: .other, at: monday(19), grants: []) == nil)
}

@Test func grantJoinsTheWindowItTouches() {
    let grant = TemporaryGrant(category: .game, startsAt: monday(19, 50), endsAt: monday(20, 20))

    #expect(rules().openStretch(for: .game, at: monday(19), grants: [grant])?.endsAt == monday(20, 20))
    #expect(rules().openStretch(for: .game, at: monday(20, 10), grants: [grant])?.endsAt == monday(20, 20))
}

@Test func grantEndingOutsideAnyWindowUsesTheDefault() {
    let grant = TemporaryGrant(category: .game, startsAt: monday(15), endsAt: monday(15, 30))
    let stretch = rules(fallback: .strict).openStretch(for: .game, at: monday(15, 10), grants: [grant])

    #expect(stretch?.endsAt == monday(15, 30))
    #expect(stretch?.strategy == .strict)
}

@Test func stretchCarriesOnPastMidnightWhenTheNextDayContinues() {
    let set = rules(game: [
        ScheduleWindow(weekday: 2, startMinute: 22 * 60, endMinute: 1_440),
        ScheduleWindow(weekday: 3, startMinute: 0, endMinute: 60),
    ])

    #expect(set.openStretch(for: .game, at: monday(23), grants: [])?.endsAt == monday(1, day: 21))
}

@Test func stretchAgreesWithTheRuleEvaluator() {
    let grant = TemporaryGrant(category: .game, startsAt: monday(12), endsAt: monday(12, 30))
    let set = rules(game: [
        ScheduleWindow(weekday: 2, startMinute: 9 * 60, endMinute: 10 * 60),
        ScheduleWindow(weekday: 2, startMinute: 22 * 60, endMinute: 60),
    ])
    for hour in 0..<24 {
        for minute in [0, 29, 45] {
            let date = monday(hour, minute)
            #expect(
                (set.openStretch(for: .game, at: date, grants: [grant]) != nil)
                    == RuleEvaluator().isAllowed(category: .game, at: date, rules: set, temporaryGrants: [grant])
            )
        }
    }
}

// MARK: - 结束前

@Test func standardRemindsOnceAtFiveMinutesAndCountsDownFromFifteen() {
    var run = Run(rules())
    run.advance(from: monday(19, 40), to: monday(19, 56))

    #expect(run.actions.map(\.1) == [.remind(.fiveMinutes, category: .game, strategy: .standard)])
    #expect(run.actions.first?.0 == monday(19, 55))
    #expect(run.lastStep.countdown?.remainingSeconds == 240)
}

@Test func noCountdownBeforeFifteenMinutes() {
    var run = Run(rules())
    run.advance(from: monday(19, 30), to: monday(19, 44))
    #expect(run.lastStep.countdown == nil)
}

@Test func gentleNeverShowsACountdown() {
    var run = Run(rules(fallback: .gentle))
    run.advance(from: monday(19, 50), to: monday(19, 58))
    #expect(run.lastStep.countdown == nil)
}

@Test func strictAlsoRemindsAtFifteenMinutes() {
    var run = Run(rules(fallback: .strict))
    run.advance(from: monday(19, 40), to: monday(19, 56))

    #expect(run.actions.map(\.1) == [
        .remind(.fifteenMinutes, category: .game, strategy: .strict),
        .remind(.fiveMinutes, category: .game, strategy: .strict),
    ])
}

@Test func openingTheActivityLateOnlySendsTheNextReminder() {
    var run = Run(rules(fallback: .strict))
    run.advance(from: monday(19, 57), to: monday(19, 58))
    #expect(run.actions.map(\.1) == [.remind(.fiveMinutes, category: .game, strategy: .strict)])
}

@Test func noRemindersWhileUsingSomethingElse() {
    var run = Run(rules())
    run.advance(from: monday(19, 40), to: monday(20, 5), category: .other)
    #expect(run.actions.isEmpty)
    #expect(run.lastStep == EndingStep())
}

// MARK: - 到点和收尾

@Test func timeUpStartsTheFinishingTimeAndStaysAllowed() {
    var run = Run(rules())
    run.advance(from: monday(19, 59), to: monday(20, 1))

    #expect(run.actions.map(\.1).contains(.remind(.timeUp(finishSeconds: 180), category: .game, strategy: .standard)))
    #expect(run.lastStep.keepsActivityAllowed)
    #expect(run.lastStep.countdown == EndingCountdown(category: .game, remainingSeconds: 120, isFinishing: true))
}

@Test func standardDimsAfterFinishingThenEndsTheActivity() {
    var run = Run(rules())
    run.advance(from: monday(19, 59), to: monday(20, 3, 10))
    #expect(run.lastStep.isDimming)
    #expect(run.lastStep.keepsActivityAllowed)
    #expect(!run.actions.map(\.1).contains(.endActivity(category: .game, strategy: .standard)))

    run.advance(from: monday(20, 3, 11), to: monday(20, 3, 31))
    let ended = run.actions.filter { $0.1 == .endActivity(category: .game, strategy: .standard) }
    #expect(ended.count == 1)
    #expect(ended.first?.0 == monday(20, 3, 30))
}

@Test func strictEndsTheActivityWhenItsShortFinishingTimeRunsOut() {
    var run = Run(rules(fallback: .strict))
    run.advance(from: monday(19, 59, 30), to: monday(20, 1, 5))

    let ended = run.actions.filter { $0.1 == .endActivity(category: .game, strategy: .strict) }
    #expect(ended.first?.0 == monday(20, 1))
}

@Test func gentleOnlyReportsAndNeverEndsTheActivity() {
    var run = Run(rules(fallback: .gentle))
    run.advance(from: monday(19, 59), to: monday(20, 10))

    let outcomes = run.actions.map(\.1).filter {
        if case .remind = $0 { return false }
        return true
    }
    #expect(outcomes == [.reportOnly(category: .game)])
    #expect(run.actions.first { $0.1 == .reportOnly(category: .game) }?.0 == monday(20, 5))
    #expect(run.lastStep.keepsActivityAllowed)
}

@Test func notBeingOnTheActivityWhenItClosesMeansNoFinishingTime() {
    var run = Run(rules())
    run.advance(from: monday(19, 30), to: monday(19, 40))
    run.advance(from: monday(19, 41), to: monday(20, 1), category: .other)
    run.advance(from: monday(20, 1, 1), to: monday(20, 1, 2))

    #expect(!run.lastStep.keepsActivityAllowed)
    #expect(!run.actions.map(\.1).contains(.remind(.timeUp(finishSeconds: 180), category: .game, strategy: .standard)))
}

@Test func openingOutsideAWindowIsNotAnEnding() {
    var run = Run(rules())
    run.advance(from: monday(15), to: monday(15, 2))

    #expect(run.actions.isEmpty)
    #expect(!run.lastStep.keepsActivityAllowed)
}

@Test func steppingAwayDuringFinishingStopsTheDimAndComingBackLateIsAnOutsideStart() {
    var run = Run(rules())
    run.advance(from: monday(19, 59), to: monday(20, 3, 5))
    #expect(run.lastStep.isDimming)

    run.advance(from: monday(20, 3, 6), to: monday(20, 3, 10), category: .other)
    #expect(!run.lastStep.isDimming)

    run.advance(from: monday(20, 4), to: monday(20, 4, 1))
    #expect(!run.lastStep.keepsActivityAllowed)
    #expect(!run.actions.map(\.1).contains(.endActivity(category: .game, strategy: .standard)))
}

@Test func moreTimeDuringFinishingCancelsTheEndingWithoutRepeatingWarnings() {
    var run = Run(rules())
    run.advance(from: monday(19, 59), to: monday(20, 1))
    let grant = TemporaryGrant(category: .game, startsAt: monday(20, 1), endsAt: monday(20, 6))
    run.actions = []

    run.advance(from: monday(20, 1, 1), to: monday(20, 5), grants: [grant])

    #expect(run.actions.isEmpty)
    #expect(run.lastStep.countdown?.isFinishing == false)
}

@Test func theMachineSurvivesARestartMidFinishing() throws {
    var run = Run(rules())
    run.advance(from: monday(19, 59), to: monday(20, 1))
    let restored = try JSONDecoder().decode(EndingMachine.self, from: JSONEncoder().encode(run.machine))

    var machine = restored
    let step = machine.advance(category: .game, stretch: nil, at: monday(20, 1, 5))
    #expect(step.keepsActivityAllowed)
    #expect(step.actions.isEmpty)
}

// MARK: - 时段外

@Test func standardOutsideFlowIsExactlyTheExistingOne() {
    var machine = ViolationMachine()
    let activity = playing()
    var fired: [String] = []
    for second in 0...185 {
        for action in machine.advance(activity: activity, isAllowed: false, elapsedSeconds: 1, at: monday(15, 0, 0).addingTimeInterval(TimeInterval(second))) {
            switch action {
            case let .warning(level, _): fired.append("warning\(level)@\(second)")
            case .beginEvent: fired.append("event@\(second)")
            case .enforce: fired.append("enforce@\(second)")
            case .reset: break
            }
        }
    }
    #expect(fired == ["warning1@0", "warning2@59", "event@59", "warning3@119", "enforce@179"])
}

@Test func gentleOutsideFlowNeverEnforces() {
    var machine = ViolationMachine()
    var enforced = false
    for second in 0...600 {
        let actions = machine.advance(activity: playing(), isAllowed: false, elapsedSeconds: 1, at: monday(15).addingTimeInterval(TimeInterval(second)), strategy: .gentle)
        if actions.contains(where: { if case .enforce = $0 { return true } else { return false } }) { enforced = true }
    }
    #expect(!enforced)
    #expect(machine.state?.warningCount == 3)
}

@Test func strictOutsideFlowEndsTheActivityAtTwoMinutes() {
    var machine = ViolationMachine()
    var enforcedAt: Int?
    for second in 0...180 {
        let actions = machine.advance(activity: playing(), isAllowed: false, elapsedSeconds: 1, at: monday(15).addingTimeInterval(TimeInterval(second)), strategy: .strict)
        if actions.contains(where: { if case .enforce = $0 { return true } else { return false } }), enforcedAt == nil {
            enforcedAt = second
        }
    }
    #expect(enforcedAt == 119)
    #expect(machine.state?.warningCount == 2)
}

// MARK: - 再玩一会儿

@Test func presetsAllowDifferentExtensionCounts() {
    #expect(ReminderStrategy.gentle.plan.dailyExtensions == 2)
    #expect(ReminderStrategy.standard.plan.dailyExtensions == 1)
    #expect(ReminderStrategy.strict.plan.dailyExtensions == 0)
}

@Test func extensionsAreCountedPerDay() {
    var ledger = ExtensionLedger()
    #expect(ledger.remaining(limit: 2, dayKey: "a") == 2)

    ledger.record(dayKey: "a")
    ledger.record(dayKey: "a")
    #expect(ledger.remaining(limit: 2, dayKey: "a") == 0)
    #expect(ledger.remaining(limit: 2, dayKey: "b") == 2)

    ledger.record(dayKey: "b")
    #expect(ledger.remaining(limit: 2, dayKey: "b") == 1)
}

@Test func extensionRecordsReadPlainlyForParents() {
    let record = ViolationEvent.extensionRecord(category: .game, at: monday(20))

    #expect(record.isExtensionRecord)
    #expect(record.parentTitle == "孩子用了一次“再玩 5 分钟” · 游戏")
    #expect(record.parentOutcome == "孩子自己加的时间")
    #expect(!ViolationEvent(category: .game, appName: "Roblox", startedAt: monday(20)).isExtensionRecord)
}

// MARK: - 孩子看到的文字

@Test func childHeadlineSaysHowLongIsLeft() {
    var set = rules()
    set.activityRules[1].windows = [ScheduleWindow(weekday: 2, startMinute: 18 * 60, endMinute: 21 * 60)]
    let outlook = DayOutlook(rules: set, requests: [], at: monday(18, 45))

    #expect(childHeadline(outlook: outlook, activity: .other) == "游戏还能玩 1 小时 15 分")
    #expect(childHeadline(outlook: outlook, activity: .game) == "游戏还能玩 1 小时 15 分")
    #expect(childHeadline(outlook: outlook, activity: .video) == "视频还能看 2 小时 15 分")
}

@Test func childHeadlineFallsBackToWhenItOpens() {
    var set = rules()
    set.activityRules[1].windows = [ScheduleWindow(weekday: 2, startMinute: 18 * 60, endMinute: 21 * 60)]
    let outlook = DayOutlook(rules: set, requests: [], at: monday(17, 42))

    #expect(childHeadline(outlook: outlook, activity: .other) == "游戏和视频 18:00 开放，还有 18 分钟")
}

@Test func directGrantsShowOnTheDayOutlook() {
    let grant = TemporaryGrant(category: .game, startsAt: monday(20), endsAt: monday(20, 5))
    let outlook = DayOutlook(rules: rules(), requests: [], grants: [grant], at: monday(20, 1))

    #expect(outlook.game.isOpenNow)
    #expect(outlook.game.closesAtMinute == 20 * 60 + 5)
}

@Test func messagesAreWrittenForChildren() {
    #expect(ReminderMessage.of(.fiveMinutes, category: .game).title == "还有 5 分钟")
    #expect(ReminderMessage.of(.timeUp(finishSeconds: 180), category: .game).body == "还有 3 分钟收尾，找个地方停下来吧。")
    #expect(ReminderMessage.of(.fifteenMinutes, category: .video).title == "视频还能看 15 分钟")
}

@Test func standardOutsideWordingIsUnchanged() {
    #expect(outsideWarningText(level: 1, category: .game, strategy: .standard) == "现在不是游戏时间，请在 60 秒内离开。")
    #expect(outsideWarningText(level: 2, category: .game, strategy: .standard) == "第二次提醒：请停止游戏，家长端将收到通知。")
    #expect(outsideWarningText(level: 3, category: .game, strategy: .standard) == "最后提醒：60 秒后将结束当前游戏活动。")
}

@Test func gentleNeverThreatensToEndTheActivity() {
    for level in 1...3 {
        #expect(!outsideWarningText(level: level, category: .game, strategy: .gentle).contains("结束"))
    }
}

@Test func strictTellsTheChildItsShorterTimeline() {
    #expect(outsideWarningText(level: 1, category: .video, strategy: .strict) == "现在不是视频时间，2 分钟后结束。")
    #expect(outsideWarningText(level: 2, category: .video, strategy: .strict) == "1 分钟后结束视频。")
}

