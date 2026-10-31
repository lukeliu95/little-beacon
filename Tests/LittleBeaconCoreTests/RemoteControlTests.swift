import Foundation
import Testing
@testable import LittleBeaconCore

private let tokyo = TimeZone(identifier: "Asia/Tokyo")!
private let classifier = ActivityClassifier()

private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = tokyo
    return calendar
}

private func at(_ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
    var components = DateComponents()
    components.calendar = calendar
    components.timeZone = tokyo
    components.year = 2026
    components.month = 7
    components.day = 20
    components.hour = hour
    components.minute = minute
    components.second = second
    return components.date!
}

private func close(
    _ target: RemoteTarget,
    lock: RemoteLockOption = .noLock,
    at created: Date = at(20),
    id: UUID = UUID()
) -> RemoteCommand {
    RemoteCommand(
        id: id,
        kind: .close,
        target: target,
        lock: lock,
        createdAt: created,
        expiresAt: created.addingTimeInterval(300)
    )
}

private func unlock(_ target: RemoteTarget, at created: Date = at(20, 5)) -> RemoteCommand {
    RemoteCommand(kind: .unlock, target: target, createdAt: created, expiresAt: created.addingTimeInterval(86_400))
}

private func stage(_ state: RemoteControlState) -> [RemoteCommandReport.Stage] {
    state.reports.map(\.status)
}

// MARK: - Receiving

@Test func anOpenTargetGetsANoticeAndAMinute() {
    var state = RemoteControlState()
    let events = state.receive([close(.game, lock: .oneHour)], openState: { _ in .app }, at: at(20))

    #expect(events == [.closing(.game, lock: .oneHour)])
    #expect(state.active.first?.deadline == at(20, 1))
    #expect(state.startDueCloses(at: at(20, 0, 59)).isEmpty)
    #expect(state.startDueCloses(at: at(20, 1)).map(\.target) == [.game])
    #expect(stage(state) == [.received])
}

@Test func nothingOpenRunsAtOnceWithoutBotheringTheChild() {
    var state = RemoteControlState()
    let events = state.receive([close(.browser)], openState: { _ in .notOpen }, at: at(20))

    #expect(events.isEmpty)
    #expect(state.startDueCloses(at: at(20)).count == 1)
}

@Test func theSameCommandHandedOverTwiceRunsOnce() {
    var state = RemoteControlState()
    let command = close(.game)
    _ = state.receive([command], openState: { _ in .app }, at: at(20))
    let again = state.receive([command], openState: { _ in .app }, at: at(20, 0, 30))

    #expect(again.isEmpty)
    #expect(state.active.count == 1)
    #expect(stage(state) == [.received])
}

@Test func aCloseDueWhileClosingIsNotStartedTwice() {
    var state = RemoteControlState()
    _ = state.receive([close(.game)], openState: { _ in .app }, at: at(20))
    #expect(state.startDueCloses(at: at(20, 1)).count == 1)
    #expect(state.startDueCloses(at: at(20, 1, 1)).isEmpty)
}

@Test func aCloseCutOffByARestartRunsAgain() {
    var state = RemoteControlState()
    _ = state.receive([close(.game)], openState: { _ in .app }, at: at(20))
    _ = state.startDueCloses(at: at(20, 1))
    state.resumeAfterRestart()
    #expect(state.startDueCloses(at: at(20, 1, 5)).count == 1)
}

@Test func aCloseCutOffAfterItWorkedStillCountsAsClosed() {
    var state = RemoteControlState()
    let command = close(.game)
    _ = state.receive([command], openState: { _ in .app }, at: at(20))
    _ = state.startDueCloses(at: at(20, 1))
    state.resumeAfterRestart()
    _ = state.startDueCloses(at: at(20, 1, 20))

    let report = state.finish(command.id, closed: [], failed: [], at: at(20, 1, 21), calendar: calendar)

    #expect(report?.outcome == .closed)
}

@Test func aBrowserGameLeftBehindIsNotReportedAsClosed() {
    var state = RemoteControlState()
    let command = close(.game)
    _ = state.receive([command], openState: { _ in .browserTabOnly }, at: at(20))
    _ = state.startDueCloses(at: at(20, 1))

    let report = state.finish(command.id, closed: [], failed: [], at: at(20, 1), calendar: calendar)

    #expect(report?.outcome == .notConfirmed)
}

@Test func aBrowserGameClosedInFrontIsReportedAsClosed() {
    var state = RemoteControlState()
    let command = close(.game)
    _ = state.receive([command], openState: { _ in .browserTabOnly }, at: at(20))
    _ = state.startDueCloses(at: at(20, 1))

    let report = state.finish(command.id, closed: ["Safari 里的网页游戏"], failed: [], at: at(20, 1), calendar: calendar)

    #expect(report?.outcome == .closed)
}

@Test func aMacThatSleptPastTheDeadlineDoesNotCloseAnything() {
    var state = RemoteControlState()
    _ = state.receive([close(.game, lock: .today)], openState: { _ in .app }, at: at(20))

    #expect(state.startDueCloses(at: at(23)).isEmpty)
    #expect(state.active.isEmpty)
    #expect(state.reports.last?.outcome == .stale)
    #expect(state.lockEnd(for: .game, at: at(23)) == nil)
}

@Test func aDeadlineJustMissedStillRuns() {
    var state = RemoteControlState()
    _ = state.receive([close(.game)], openState: { _ in .app }, at: at(20))
    #expect(state.startDueCloses(at: at(20, 6)).count == 1)
}

// MARK: - Finishing

private func finished(
    open: Bool,
    closed: [String] = [],
    failed: [String] = [],
    lock: RemoteLockOption = .noLock
) -> (RemoteControlState, RemoteCommandReport?) {
    var state = RemoteControlState()
    let command = close(.game, lock: lock)
    _ = state.receive([command], openState: { _ in open ? .app : .notOpen }, at: at(20))
    _ = state.startDueCloses(at: at(20, 1))
    let report = state.finish(command.id, closed: closed, failed: failed, at: at(20, 1, 5), calendar: calendar)
    return (state, report)
}

@Test func theOutcomeSaysWhatReallyHappened() {
    #expect(finished(open: true, closed: ["Roblox"]).1?.outcome == .closed)
    #expect(finished(open: true, closed: ["Roblox"], failed: ["Steam"]).1?.outcome == .partial)
    #expect(finished(open: true, failed: ["Steam"]).1?.outcome == .partial)
    #expect(finished(open: true).1?.outcome == .closedByChild)
    #expect(finished(open: false).1?.outcome == .nothingOpen)
}

@Test func theLockStartsWhenTheCloseHappens() {
    let (state, report) = finished(open: true, closed: ["Roblox"], lock: .thirtyMinutes)
    #expect(report?.lockEndsAt == at(20, 31, 5))
    #expect(state.lockEnd(for: .game, at: at(20, 31)) == at(20, 31, 5))
    #expect(state.lockEnd(for: .game, at: at(20, 31, 5)) == nil)
    #expect(state.lockEnd(for: .browser, at: at(20, 2)) == nil)
}

@Test func aLockAppliesEvenWhenNothingWasOpen() {
    let (state, _) = finished(open: false, lock: .oneHour)
    #expect(state.lockEnd(for: .game, at: at(20, 30)) != nil)
}

@Test func aLockForTodayRunsToMidnightInTheFamilysTimeZone() {
    let end = RemoteLockOption.today.endsAt(from: at(20), calendar: calendar)
    #expect(end == calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: at(20))))
    #expect(remoteLockEndText(end!, timeZoneIdentifier: "Asia/Tokyo") == "到今天结束")
    #expect(remoteLockEndText(at(21, 30), timeZoneIdentifier: "Asia/Tokyo") == "到 21:30")
}

@Test func todayMeansTheDayTheParentAsked() {
    var state = RemoteControlState()
    let command = close(.game, lock: .today, at: at(23, 59, 30))
    _ = state.receive([command], openState: { _ in .app }, at: at(23, 59, 30))
    _ = state.startDueCloses(at: at(23, 59, 30).addingTimeInterval(60))

    let finishedAt = at(23, 59, 30).addingTimeInterval(61)
    let report = state.finish(command.id, closed: ["Roblox"], failed: [], at: finishedAt, calendar: calendar)

    #expect(report?.lockEndsAt == RemoteLockOption.today.endsAt(from: at(20), calendar: calendar))
    #expect(state.lockEnd(for: .game, at: finishedAt) == nil)
}

@Test func aShorterLockNeverCutsALongerOneShort() {
    var state = RemoteControlState()
    let long = close(.game, lock: .oneHour)
    let short = close(.game, lock: .thirtyMinutes, at: at(20, 10))
    _ = state.receive([long], openState: { _ in .app }, at: at(20))
    _ = state.startDueCloses(at: at(20, 1))
    state.finish(long.id, closed: ["Roblox"], failed: [], at: at(20, 1), calendar: calendar)
    _ = state.receive([short], openState: { _ in .notOpen }, at: at(20, 10))
    _ = state.startDueCloses(at: at(20, 10))
    state.finish(short.id, closed: [], failed: [], at: at(20, 10), calendar: calendar)

    #expect(state.lockEnd(for: .game, at: at(20, 50)) == at(21, 1))
}

@Test func anUnlockEndsTheLockAndTheLockStillOnItsWay() {
    var state = RemoteControlState()
    let locked = close(.game, lock: .today)
    let coming = close(.game, lock: .today, at: at(20, 2))
    _ = state.receive([locked], openState: { _ in .app }, at: at(20))
    _ = state.startDueCloses(at: at(20, 1))
    state.finish(locked.id, closed: ["Roblox"], failed: [], at: at(20, 1), calendar: calendar)
    _ = state.receive([coming], openState: { _ in .app }, at: at(20, 2))

    let events = state.receive([unlock(.game)], openState: { _ in .app }, at: at(20, 2, 30))

    #expect(events == [.unlocked(.game)])
    #expect(state.lockEnd(for: .game, at: at(20, 3)) == nil)
    _ = state.startDueCloses(at: at(20, 3))
    state.finish(coming.id, closed: ["Roblox"], failed: [], at: at(20, 3), calendar: calendar)
    #expect(state.lockEnd(for: .game, at: at(20, 4)) == nil)
    #expect(state.reports.contains { $0.outcome == .unlocked })
}

@Test func anUnlockWithNothingLockedSaysNothingToTheChild() {
    var state = RemoteControlState()
    #expect(state.receive([unlock(.browser)], openState: { _ in .notOpen }, at: at(20)).isEmpty)
}

@Test func commandsRunInTheOrderTheyWereGiven() {
    var state = RemoteControlState()
    let events = state.receive(
        [unlock(.game, at: at(20, 1)), close(.browser, at: at(20))],
        openState: { _ in .app },
        at: at(20, 2)
    )
    #expect(events == [.closing(.browser, lock: .noLock)])
    #expect(state.reports.map(\.status) == [.received, .finished])
}

@Test func anUploadedReportLeavesTheQueue() {
    var state = RemoteControlState()
    _ = state.receive([close(.game)], openState: { _ in .app }, at: at(20))
    state.clearReport(state.reports[0])
    #expect(state.reports.isEmpty)
}

@Test func oldLocksAndMemoriesArePruned() {
    let (lockedState, _) = finished(open: true, closed: ["Roblox"], lock: .thirtyMinutes)
    var state = lockedState
    state.prune(now: at(22))
    #expect(state.locks.isEmpty)
    #expect(state.reports.count == 2)
    state.prune(now: at(20).addingTimeInterval(31 * 86_400))
    #expect(state.reports.isEmpty)
}

@Test func theStateSurvivesBeingSaved() throws {
    var state = RemoteControlState()
    _ = state.receive([close(.game, lock: .oneHour)], openState: { _ in .app }, at: at(20))
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let restored = try decoder.decode(RemoteControlState.self, from: encoder.encode(state))
    #expect(restored == state)
}

// MARK: - Locks in use

private func activity(_ category: ActivityCategory, bundle: String? = nil, domain: String? = nil) -> ClassifiedActivity {
    ClassifiedActivity(
        observation: ActivityObservation(appName: "App", bundleIdentifier: bundle, normalizedDomain: domain),
        category: category
    )
}

@Test func onlyTheLockedKindIsBlocked() {
    let (state, _) = finished(open: true, closed: ["Roblox"], lock: .oneHour)
    let now = at(20, 10)

    #expect(state.blockedTarget(for: activity(.game), isBrowser: false, at: now) == .game)
    #expect(state.blockedTarget(for: activity(.video), isBrowser: false, at: now) == nil)
    #expect(state.blockedTarget(for: activity(.other), isBrowser: true, at: now) == nil)
    #expect(state.blockedTarget(for: activity(.game), isBrowser: false, at: at(21, 30)) == nil)
}

@Test func aBrowserGameCountsAsAGame() {
    let (state, _) = finished(open: true, closed: ["Roblox"], lock: .oneHour)
    #expect(state.blockedTarget(for: activity(.game, domain: "4399.com"), isBrowser: true, at: at(20, 10)) == .game)
}

@Test func aCloseUnderWayKeepsTheMinuteItPromisedOverTheLock() {
    let (locked, _) = finished(open: false, lock: .thirtyMinutes)
    var state = locked
    let again = close(.game, lock: .thirtyMinutes, at: at(20, 2))
    _ = state.receive([again], openState: { _ in .app }, at: at(20, 2))

    #expect(state.blockedTarget(for: activity(.game), isBrowser: false, at: at(20, 2, 30)) == nil)

    _ = state.startDueCloses(at: at(20, 3))
    state.finish(again.id, closed: ["Stardew"], failed: [], at: at(20, 3), calendar: calendar)
    #expect(state.blockedTarget(for: activity(.game), isBrowser: false, at: at(20, 3, 1)) == .game)
}

@Test func theGuardWarnsThenClosesEvenIfTheChildSwitchesAway() {
    var guardian = RemoteLockGuard()
    #expect(guardian.advance(blocked: .game, at: at(20)) == .warn(.game))
    #expect(guardian.advance(blocked: nil, at: at(20, 0, 3)) == nil)
    #expect(guardian.advance(blocked: .game, at: at(20, 0, 4)) == nil)
    #expect(guardian.advance(blocked: nil, at: at(20, 0, 5)) == .close(.game))
    #expect(guardian.advance(blocked: nil, at: at(20, 0, 6)) == nil)
    #expect(guardian.advance(blocked: .game, at: at(20, 0, 7)) == .warn(.game))
}

// MARK: - Which apps

@Test func gamesAreWhateverTheRulesCallAGame() {
    let override = ClassificationOverride(target: .bundleIdentifier, value: "com.example.mygame", category: .game)
    let matches = { (bundle: String) in
        classifier.matches(.game, appName: "App", bundleIdentifier: bundle, overrides: [override], own: "app.littlebeacon.mac")
    }
    #expect(matches("com.roblox.RobloxPlayer"))
    #expect(matches("com.example.mygame"))
    #expect(!matches("com.apple.TextEdit"))
    #expect(!matches("com.google.Chrome"))
    #expect(!matches("org.videolan.vlc"))
}

@Test func browsersComeFromAFixedList() {
    let matches = { (bundle: String?) in
        classifier.matches(.browser, appName: "App", bundleIdentifier: bundle, overrides: [], own: nil)
    }
    for bundle in ["com.apple.Safari", "com.google.Chrome", "com.microsoft.edgemac", "org.mozilla.firefox", "company.thebrowser.Browser"] {
        #expect(matches(bundle), "\(bundle)")
    }
    #expect(!matches("com.electron.slack"))
    #expect(!matches(nil))
}

@Test func nothingProtectedIsEverClosedWhateverTheOverrides() {
    let overrides = ["com.apple.finder", "app.littlebeacon.mac"].map {
        ClassificationOverride(target: .bundleIdentifier, value: $0, category: .game)
    }
    for bundle in ["com.apple.finder", "App.LittleBeacon.Mac"] {
        #expect(!classifier.matches(.game, appName: "App", bundleIdentifier: bundle, overrides: overrides, own: "app.littlebeacon.mac"))
    }
}

// MARK: - What the parent reads

private func command(
    status: RemoteCommandStatus,
    outcome: RemoteOutcome? = nil,
    closed: [String] = [],
    failed: [String] = [],
    front: (String, String)? = nil,
    received: Date? = nil,
    lockEnds: Date? = nil,
    created: Date = at(20)
) -> RemoteCommand {
    RemoteCommand(
        kind: .close,
        target: .game,
        status: status,
        createdAt: created,
        expiresAt: created.addingTimeInterval(300),
        receivedAt: received,
        outcome: outcome,
        closedApps: closed,
        failedApps: failed,
        frontAppName: front?.0,
        frontAppBundleID: front?.1,
        lockEndsAt: lockEnds
    )
}

@Test func theParentAlwaysKnowsWhereACloseStands() {
    let soon = at(20, 1)
    #expect(command(status: .pending).parentOutcome(at: soon) == "已发给孩子的 Mac，等它收到")
    #expect(command(status: .received, received: at(20)).parentOutcome(at: soon) == "孩子已收到，1 分钟内关闭")
    #expect(command(status: .expired).parentOutcome(at: soon).hasPrefix("孩子的 Mac 没有回应"))
    #expect(command(status: .finished, outcome: .closed, closed: ["Roblox", "Steam"]).parentOutcome(at: soon) == "已关闭 Roblox、Steam")
    #expect(command(status: .finished, outcome: .partial, closed: ["Roblox"], failed: ["Steam"]).parentOutcome(at: soon) == "已关闭 Roblox，有 1 个没关掉：Steam")
    #expect(command(status: .finished, outcome: .nothingOpen).parentOutcome(at: soon) == "没有打开的游戏")
    #expect(command(status: .finished, outcome: .closedByChild).parentOutcome(at: soon) == "孩子已经自己关了")
    #expect(command(status: .finished, outcome: .closed).parentOutcome(at: soon) == "已关闭游戏")
    #expect(command(status: .finished, outcome: .notConfirmed).parentOutcome(at: soon).contains("没能确认"))
    #expect(command(status: .finished, outcome: .stale).parentOutcome(at: soon).contains("休眠"))
}

@Test func aCloseThatNeverReportsBackStopsLookingBusy() {
    let received = command(status: .received, received: at(20))
    #expect(received.isInFlight(at: at(20, 2)))
    #expect(!received.isInFlight(at: at(20, 3)))
    #expect(received.parentOutcome(at: at(20, 3)).hasPrefix("孩子的 Mac 没有回应"))

    let pending = command(status: .pending)
    #expect(pending.isInFlight(at: at(20, 4)))
    #expect(!pending.isInFlight(at: at(20, 5)))
}

@Test func anUnrecognizedGameCanBeCalledOut() {
    let found = command(status: .finished, outcome: .nothingOpen, front: ("Stardew", "com.example.stardew"))
    #expect(found.parentOutcome(at: at(20, 1)) == "没有识别到游戏，孩子现在用的是 Stardew")
    #expect(found.unrecognizedApp?.bundleIdentifier == "com.example.stardew")
    #expect(command(status: .finished, outcome: .closed, closed: ["Roblox"]).unrecognizedApp == nil)
}

@Test func theParentSeesTheSameLockTheChildHolds() {
    let closed = command(status: .finished, outcome: .closed, lockEnds: at(21))
    #expect(remoteLockEnd(for: .game, in: [closed], at: at(20, 30)) == at(21))
    #expect(remoteLockEnd(for: .browser, in: [closed], at: at(20, 30)) == nil)
    #expect(remoteLockEnd(for: .game, in: [closed], at: at(21)) == nil)

    let released = unlock(.game, at: at(20, 10))
    #expect(remoteLockEnd(for: .game, in: [released, closed], at: at(20, 30)) == nil)

    let lockedAgain = command(status: .finished, outcome: .closed, lockEnds: at(22), created: at(20, 20))
    #expect(remoteLockEnd(for: .game, in: [lockedAgain, released, closed], at: at(20, 30)) == at(22))
}

@Test func anUnlockThatExpiredDidNotReleaseAnything() {
    let closed = command(status: .finished, outcome: .closed, lockEnds: at(21))
    var released = unlock(.game, at: at(20, 10))
    released.status = .expired
    #expect(remoteLockEnd(for: .game, in: [closed, released], at: at(20, 30)) == at(21))
}

// MARK: - What the child reads

@Test func theNoticeSaysWhoAskedAndWhatToDo() {
    let game = ReminderMessage.remoteClosing(.game, lock: .noLock)
    #expect(game.title == "家长让你现在结束游戏")
    #expect(game.body == "1 分钟后关闭，记得存档。")

    let browser = ReminderMessage.remoteClosing(.browser, lock: .thirtyMinutes)
    #expect(browser.body == "1 分钟后关闭，没保存的内容记得先保存。关闭后 30 分钟内不能再打开。")
    #expect(ReminderMessage.remoteClosing(.game, lock: .today).body.hasSuffix("关闭后今天不能再打开。"))
}

@Test func theClosedMessageExplainsTheLock() {
    #expect(ReminderMessage.remoteClosed(.game, lockEnd: "到 21:30").body == "家长锁定了游戏，到 21:30。")
    #expect(ReminderMessage.remoteLocked(.game, lockEnd: "到今天结束").body == "家长锁定到今天结束，马上会关闭。")
    #expect(ReminderMessage.remoteClosed(.browser, lockEnd: nil).title == "浏览器已关闭")
}
