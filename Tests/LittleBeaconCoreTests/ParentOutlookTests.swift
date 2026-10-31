import Foundation
import Testing
@testable import LittleBeaconCore

private let tokyo = TimeZone(identifier: "Asia/Tokyo")!

/// 2026-07-20 is a Monday, weekday 2.
private func monday(_ hour: Int, _ minute: Int = 0) -> Date {
    var components = DateComponents()
    components.calendar = Calendar(identifier: .gregorian)
    components.timeZone = tokyo
    components.year = 2026
    components.month = 7
    components.day = 20
    components.hour = hour
    components.minute = minute
    return components.date!
}

private func rules(
    game: [(Int, Int)] = [(18 * 60, 20 * 60)],
    video: [(Int, Int)] = [(18 * 60, 21 * 60)]
) -> RuleSet {
    func windows(_ spans: [(Int, Int)]) -> [ScheduleWindow] {
        spans.map { ScheduleWindow(weekday: 2, startMinute: $0.0, endMinute: $0.1) }
    }
    return RuleSet(
        timeZoneIdentifier: "Asia/Tokyo",
        activityRules: [
            ActivityRule(category: .game, windows: windows(game)),
            ActivityRule(category: .video, windows: windows(video)),
        ]
    )
}

private func approvedGame(minutes: Int, resolvedAt: Date) -> TemporaryRequest {
    var request = TemporaryRequest(category: .game, durationMinutes: minutes)
    request.status = .approved
    request.resolvedAt = resolvedAt
    return request
}

private func status(_ category: ActivityCategory, online: Bool = true) -> DeviceStatus {
    DeviceStatus(category: category, lastSeenAt: monday(12), isOnline: online)
}

@Test func summaryCountsDownToASharedOpening() {
    let outlook = DayOutlook(rules: rules(), requests: [], at: monday(17, 42))
    #expect(outlook.summary == "游戏和视频 18:00 开放，还有 18 分钟")
    #expect(!outlook.game.isOpenNow)
}

@Test func summaryUsesHoursWhenTheOpeningIsFarAway() {
    #expect(DayOutlook(rules: rules(), requests: [], at: monday(14)).summary == "游戏和视频 18:00 开放，还有 4 小时")
    #expect(DayOutlook(rules: rules(), requests: [], at: monday(14, 30)).summary == "游戏和视频 18:00 开放，还有 3 小时 30 分")
}

@Test func summaryNamesEachCategoryWhenTheyDiffer() {
    #expect(DayOutlook(rules: rules(), requests: [], at: monday(18, 30)).summary == "游戏开放到 20:00，视频开放到 21:00")
    #expect(DayOutlook(rules: rules(), requests: [], at: monday(20, 30)).summary == "游戏今天不再开放，视频开放到 21:00")
    #expect(DayOutlook(rules: rules(), requests: [], at: monday(22)).summary == "今天游戏和视频都不再开放")
}

@Test func summaryCombinesCategoriesThatCloseTogether() {
    let sameEnd = rules(game: [(18 * 60, 21 * 60)])
    #expect(DayOutlook(rules: sameEnd, requests: [], at: monday(19)).summary == "游戏和视频开放到 21:00")
}

@Test func approvedRequestOpensTheCategoryAndMergesWithTheNextWindow() {
    let request = approvedGame(minutes: 30, resolvedAt: monday(17, 42))
    let outlook = DayOutlook(rules: rules(), requests: [request], at: monday(17, 42))

    #expect(outlook.game.isOpenNow)
    #expect(outlook.game.spans == [DaySpan(startMinute: 17 * 60 + 42, endMinute: 20 * 60)])
    #expect(outlook.summary == "游戏开放到 20:00，视频 18:00 开放")
}

@Test func pendingAndDeniedRequestsOpenNothing() {
    var denied = approvedGame(minutes: 30, resolvedAt: monday(17))
    denied.status = .denied
    let pending = TemporaryRequest(category: .game, durationMinutes: 30)

    #expect(!DayOutlook(rules: rules(), requests: [denied, pending], at: monday(17, 10)).game.isOpenNow)
}

@Test func scheduledApprovalStartsAtItsRequestedTime() {
    var request = TemporaryRequest(category: .video, durationMinutes: 60, startsAt: monday(10))
    request.status = .approved
    request.resolvedAt = monday(8)

    let outlook = DayOutlook(rules: rules(), requests: [request], at: monday(9))
    #expect(!outlook.video.isOpenNow)
    #expect(outlook.video.opensAtMinute == 10 * 60)
}

@Test func approvalThatEndedYesterdayLeavesTodayAlone() {
    let yesterday = monday(10).addingTimeInterval(-86_400)
    let outlook = DayOutlook(rules: rules(), requests: [approvedGame(minutes: 30, resolvedAt: yesterday)], at: monday(10))
    #expect(outlook.game.spans == [DaySpan(startMinute: 18 * 60, endMinute: 20 * 60)])
}

@Test func windowCrossingMidnightLightsBothEndsOfTheDay() {
    let late = rules(game: [(22 * 60, 60)])
    let outlook = DayOutlook(rules: late, requests: [], at: monday(0, 30))

    #expect(outlook.game.spans == [
        DaySpan(startMinute: 0, endMinute: 60),
        DaySpan(startMinute: 22 * 60, endMinute: 1_440),
    ])
    #expect(outlook.game.isOpenNow)
    #expect(RuleEvaluator().isAllowed(category: .game, at: monday(0, 30), rules: late, temporaryGrants: []))
}

@Test func outlookAgreesWithTheRuleEvaluatorAcrossTheDay() {
    let set = rules(game: [(9 * 60, 10 * 60), (18 * 60, 20 * 60)])
    for hour in 0..<24 {
        let date = monday(hour, 30)
        let outlook = DayOutlook(rules: set, requests: [], at: date)
        #expect(outlook.game.isOpenNow == RuleEvaluator().isAllowed(category: .game, at: date, rules: set, temporaryGrants: []))
    }
}

@Test func headlineSaysWhatTheChildIsDoingAndWhetherItIsAllowed() {
    let closed = DayOutlook(rules: rules(), requests: [], at: monday(12))
    let open = DayOutlook(rules: rules(), requests: [], at: monday(19))

    #expect(deviceHeadline(status: status(.other), outlook: closed) == "孩子的 Mac 在线，正在用其他应用")
    #expect(deviceHeadline(status: status(.idle), outlook: closed) == "孩子的 Mac 在线，暂时没有在用")
    #expect(deviceHeadline(status: status(.game), outlook: open) == "孩子的 Mac 在线，正在玩游戏")
    #expect(deviceHeadline(status: status(.video), outlook: closed) == "孩子正在看视频，现在不在允许时段")
}

@Test func headlineHandlesOfflineAndNeverSeenDevices() {
    let outlook = DayOutlook(rules: rules(), requests: [], at: monday(12))
    let neverSeen = DeviceStatus(category: .idle, lastSeenAt: .distantPast, isOnline: false)

    #expect(deviceHeadline(status: status(.game, online: false), outlook: outlook) == "孩子的 Mac 离线")
    #expect(deviceHeadline(status: neverSeen, outlook: outlook) == "还没有收到孩子 Mac 的状态")
}

@Test func eventTextOnlyClaimsWhatTheEventRecorded() {
    let tab = ViolationEvent(
        category: .video,
        appName: "Safari",
        normalizedDomain: "youtube.com",
        startedAt: monday(15),
        durationSeconds: 184,
        warningCount: 3,
        wasEnforced: true
    )
    let game = ViolationEvent(
        category: .game,
        appName: "Roblox",
        startedAt: monday(15),
        durationSeconds: 75,
        warningCount: 2,
        wasEnforced: false
    )

    #expect(tab.parentTitle == "不在时段内看视频 · youtube.com")
    #expect(tab.parentOutcome == "提醒 3 次后已关闭标签页")
    #expect(game.parentTitle == "不在时段内玩游戏 · Roblox")
    #expect(game.parentOutcome == "提醒 2 次，持续 1 分 15 秒")
}

@Test(arguments: [
    ("youtube.com", "youtube.com"),
    ("  WWW.YouTube.com ", "youtube.com"),
    ("https://www.bilibili.com/video/BV1?t=3", "bilibili.com"),
    ("http://m.iqiyi.com/", "m.iqiyi.com"),
])
func parentDomainInputIsReducedToItsHost(input: String, expected: String) {
    #expect(normalizedDomain(fromParentInput: input) == expected)
}

@Test(arguments: ["", "   ", "youtube", "not a site"])
func unusableDomainInputIsRejected(input: String) {
    #expect(normalizedDomain(fromParentInput: input) == nil)
}
