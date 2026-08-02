import Foundation
import Testing
@testable import LittleBeaconApp
@testable import LittleBeaconCore

@MainActor
@Test func coordinatorPersistsThenPresentsAndSoundsAnEnforcedBreak() throws {
    let store = RecordingPomodoroStore()
    let shield = RecordingBreakShield()
    let alarm = RecordingBreakAlarm()
    let coordinator = try PomodoroBreakCoordinator(store: store, shield: shield, alarm: alarm)
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    try coordinator.advance(isIdle: false, elapsedSeconds: 1_500, at: now)

    #expect(store.savedMachines.last?.phase == .awaitingAcknowledgement(triggeredAt: now))
    #expect(shield.presentedPhase == .awaitingAcknowledgement(triggeredAt: now))
    #expect(alarm.isWaitingAlarmActive)
}

@MainActor
@Test func restoredExpiredBreakPresentsReadyStateAndPlaysCompletionOnce() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_500)
    let store = RecordingPomodoroStore(machineToLoad: PomodoroBreakMachine(
        phase: .requiredBreak(
            triggeredAt: now.addingTimeInterval(-500),
            acknowledgedAt: now.addingTimeInterval(-400),
            closeAvailableAt: now.addingTimeInterval(-100)
        )
    ))
    let shield = RecordingBreakShield()
    let alarm = RecordingBreakAlarm()

    let coordinator = try PomodoroBreakCoordinator(
        store: store,
        shield: shield,
        alarm: alarm,
        now: now
    )

    #expect(coordinator.phase == .readyToClose(
        triggeredAt: now.addingTimeInterval(-500),
        acknowledgedAt: now.addingTimeInterval(-400),
        closeAvailableAt: now.addingTimeInterval(-100)
    ))
    #expect(shield.presentedPhase == coordinator.phase)
    #expect(alarm.completionPlayCount == 1)
}

@MainActor
@Test func restoredWaitingBreakImmediatelyRebuildsShieldAndAlarm() throws {
    let triggeredAt = Date(timeIntervalSince1970: 1_800_000_000)
    let store = RecordingPomodoroStore(machineToLoad: PomodoroBreakMachine(
        phase: .awaitingAcknowledgement(triggeredAt: triggeredAt)
    ))
    let shield = RecordingBreakShield()
    let alarm = RecordingBreakAlarm()

    let coordinator = try PomodoroBreakCoordinator(
        store: store,
        shield: shield,
        alarm: alarm,
        now: triggeredAt.addingTimeInterval(600)
    )

    #expect(coordinator.phase == .awaitingAcknowledgement(triggeredAt: triggeredAt))
    #expect(shield.presentedPhase == coordinator.phase)
    #expect(alarm.isWaitingAlarmActive)
}

@MainActor
@Test func alarmPlaybackFailureIsReportedWithoutDismissingTheShield() throws {
    let store = RecordingPomodoroStore()
    let shield = RecordingBreakShield()
    let alarm = RecordingBreakAlarm()
    alarm.errorOnStart = TestAlarmError.failed
    let coordinator = try PomodoroBreakCoordinator(store: store, shield: shield, alarm: alarm)
    var reportedError: Error?
    coordinator.onError = { reportedError = $0 }

    try coordinator.advance(
        isIdle: false,
        elapsedSeconds: PomodoroBreakMachine.workThreshold,
        at: Date(timeIntervalSince1970: 1_800_000_000)
    )

    #expect(reportedError != nil)
    #expect(shield.presentedPhase?.isActiveBreak == true)
}

private enum TestAlarmError: Error {
    case failed
}

private final class RecordingPomodoroStore: PomodoroSessionPersisting {
    var savedMachines: [PomodoroBreakMachine] = []
    var machineToLoad = PomodoroBreakMachine()

    init(machineToLoad: PomodoroBreakMachine = PomodoroBreakMachine()) {
        self.machineToLoad = machineToLoad
    }

    func load() throws -> PomodoroBreakMachine { machineToLoad }
    func save(_ machine: PomodoroBreakMachine) throws { savedMachines.append(machine) }
}

@MainActor
private final class RecordingBreakShield: BreakShieldPresenting {
    var presentedPhase: PomodoroBreakPhase?

    func present(
        phase: PomodoroBreakPhase,
        acknowledge: @escaping @MainActor () -> Void,
        close: @escaping @MainActor () -> Void
    ) {
        presentedPhase = phase
    }

    func update(phase: PomodoroBreakPhase) { presentedPhase = phase }
    func dismiss() { presentedPhase = nil }
}

@MainActor
private final class RecordingBreakAlarm: BreakAlarmPlaying {
    var onPlaybackError: ((Error) -> Void)?
    var isWaitingAlarmActive = false
    var completionPlayCount = 0
    var errorOnStart: Error?

    func startWaitingAlarm() {
        isWaitingAlarmActive = true
        if let errorOnStart { onPlaybackError?(errorOnStart) }
    }
    func stopWaitingAlarm() { isWaitingAlarmActive = false }
    func playCompletion() { completionPlayCount += 1 }
}
