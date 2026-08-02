import Foundation
import Testing
@testable import LittleBeaconCore

@Test func enforcedPomodoroTriggersExactlyAfterTwentyFiveActiveMinutes() {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    var machine = PomodoroBreakMachine()

    #expect(machine.advance(isIdle: false, elapsedSeconds: 1_499, at: start) == nil)
    #expect(machine.phase == .counting(activeSeconds: 1_499, idleSeconds: 0))

    let triggeredAt = start.addingTimeInterval(1)
    #expect(machine.advance(isIdle: false, elapsedSeconds: 1, at: triggeredAt) == .triggered)
    #expect(machine.phase == .awaitingAcknowledgement(triggeredAt: triggeredAt))
    #expect(machine.advance(isIdle: false, elapsedSeconds: 60, at: triggeredAt.addingTimeInterval(60)) == nil)
}

@Test func enforcedPomodoroRequiresAcknowledgementThenFiveFullMinutesBeforeClose() {
    let triggeredAt = Date(timeIntervalSince1970: 1_800_000_000)
    let acknowledgedAt = triggeredAt.addingTimeInterval(600)
    let closeAvailableAt = acknowledgedAt.addingTimeInterval(300)
    var machine = PomodoroBreakMachine(phase: .awaitingAcknowledgement(triggeredAt: triggeredAt))

    #expect(machine.refresh(at: acknowledgedAt) == nil)
    #expect(machine.phase == .awaitingAcknowledgement(triggeredAt: triggeredAt))
    #expect(machine.acknowledge(at: acknowledgedAt) == .acknowledged)
    #expect(machine.phase == .requiredBreak(
        triggeredAt: triggeredAt,
        acknowledgedAt: acknowledgedAt,
        closeAvailableAt: closeAvailableAt
    ))

    #expect(machine.refresh(at: closeAvailableAt.addingTimeInterval(-0.001)) == nil)
    #expect(machine.close() == false)
    #expect(machine.refresh(at: closeAvailableAt) == .closeBecameAvailable)
    #expect(machine.phase == .readyToClose(
        triggeredAt: triggeredAt,
        acknowledgedAt: acknowledgedAt,
        closeAvailableAt: closeAvailableAt
    ))
    #expect(machine.close() == true)
    #expect(machine.phase == .counting(activeSeconds: 0, idleSeconds: 0))
}

@Test func enforcedPomodoroTreatsTwoIdleMinutesAsANaturalBreakBeforeTrigger() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var machine = PomodoroBreakMachine()

    _ = machine.advance(isIdle: false, elapsedSeconds: 1_200, at: now)
    _ = machine.advance(isIdle: true, elapsedSeconds: 119, at: now.addingTimeInterval(119))
    #expect(machine.phase == .counting(activeSeconds: 1_200, idleSeconds: 119))
    _ = machine.advance(isIdle: true, elapsedSeconds: 1, at: now.addingTimeInterval(120))
    #expect(machine.phase == .counting(activeSeconds: 0, idleSeconds: 0))
}

@Test func activePomodoroPhaseRoundTripsThroughJSON() throws {
    let original = PomodoroBreakMachine(
        phase: .requiredBreak(
            triggeredAt: Date(timeIntervalSince1970: 1_800_000_000),
            acknowledgedAt: Date(timeIntervalSince1970: 1_800_000_100),
            closeAvailableAt: Date(timeIntervalSince1970: 1_800_000_400)
        )
    )

    let restored = try JSONDecoder().decode(
        PomodoroBreakMachine.self,
        from: JSONEncoder().encode(original)
    )
    #expect(restored == original)
}
