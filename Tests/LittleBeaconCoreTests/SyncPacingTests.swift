import Foundation
import Testing
@testable import LittleBeaconCore

private let start = Date(timeIntervalSince1970: 1_800_000_000)

private func tick(_ pacer: inout SyncPacer, busy: Bool, idleInterval: TimeInterval, at date: Date) -> Bool {
    pacer.shouldSync(busy: busy, idleInterval: idleInterval, at: date)
}

@Test func firstTickAlwaysSyncs() {
    var pacer = SyncPacer()
    #expect(tick(&pacer, busy: false, idleInterval: SyncPace.childAway, at: start))
}

@Test func busySideKeepsTheThirtySecondBeat() {
    var pacer = SyncPacer()
    _ = pacer.shouldSync(busy: true, idleInterval: SyncPace.childAway, at: start)
    pacer.recordSync(at: start)
    #expect(!tick(&pacer, busy: true, idleInterval: SyncPace.childAway, at: start.addingTimeInterval(10)))
    // A timer tick that lands a moment early still counts.
    #expect(tick(&pacer, busy: true, idleInterval: SyncPace.childAway, at: start.addingTimeInterval(29.5)))
}

@Test func awayChildSyncsEveryHalfHourOnly() {
    var pacer = SyncPacer()
    _ = pacer.shouldSync(busy: false, idleInterval: SyncPace.childAway, at: start)
    pacer.recordSync(at: start)
    for minute in stride(from: 1, to: 29, by: 1) {
        #expect(!tick(&pacer, busy: false, idleInterval: SyncPace.childAway, at: start.addingTimeInterval(Double(minute) * 60)))
    }
    #expect(tick(&pacer, busy: false, idleInterval: SyncPace.childAway, at: start.addingTimeInterval(30 * 60)))
}

@Test func parentInTheBackgroundSyncsEveryFifteenMinutes() {
    var pacer = SyncPacer()
    _ = pacer.shouldSync(busy: false, idleInterval: SyncPace.parentBackground, at: start)
    pacer.recordSync(at: start)
    #expect(!tick(&pacer, busy: false, idleInterval: SyncPace.parentBackground, at: start.addingTimeInterval(14 * 60)))
    #expect(tick(&pacer, busy: false, idleInterval: SyncPace.parentBackground, at: start.addingTimeInterval(15 * 60)))
    #expect(SyncPace.idleInterval(for: .parent) == 15 * 60)
    #expect(SyncPace.idleInterval(for: .child) == 30 * 60)
}

@Test func arrivingAndLeavingSyncAtOnce() {
    var pacer = SyncPacer()
    _ = pacer.shouldSync(busy: false, idleInterval: SyncPace.childAway, at: start)
    pacer.recordSync(at: start)
    // The child comes back two minutes later: no waiting for the half hour.
    #expect(tick(&pacer, busy: true, idleInterval: SyncPace.childAway, at: start.addingTimeInterval(120)))
    pacer.recordSync(at: start.addingTimeInterval(120))
    #expect(!tick(&pacer, busy: true, idleInterval: SyncPace.childAway, at: start.addingTimeInterval(130)))
    // Locking the Mac reports "idle" right away so the parent knows the next sync may be late.
    #expect(tick(&pacer, busy: false, idleInterval: SyncPace.childAway, at: start.addingTimeInterval(140)))
}

@Test func parentKeepsAnIdleChildOnlineThroughTheAwayInterval() {
    #expect(SyncPace.onlineGrace(for: .game) == 90)
    #expect(SyncPace.onlineGrace(for: .other) == 90)
    #expect(SyncPace.onlineGrace(for: .idle) > SyncPace.childAway)
}
