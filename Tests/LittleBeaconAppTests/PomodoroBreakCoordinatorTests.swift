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
    var isWaitingAlarmActive = false
    var completionPlayCount = 0

    func startWaitingAlarm() { isWaitingAlarmActive = true }
    func stopWaitingAlarm() { isWaitingAlarmActive = false }
    func playCompletion() { completionPlayCount += 1 }
}
