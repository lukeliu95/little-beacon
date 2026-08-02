import Foundation
import LittleBeaconCore

@MainActor
protocol BreakShieldPresenting: AnyObject {
    func present(
        phase: PomodoroBreakPhase,
        acknowledge: @escaping @MainActor () -> Void,
        close: @escaping @MainActor () -> Void
    )
    func update(phase: PomodoroBreakPhase)
    func dismiss()
}

@MainActor
protocol BreakAlarmPlaying: AnyObject {
    func startWaitingAlarm()
    func stopWaitingAlarm()
    func playCompletion()
}

@MainActor
final class PomodoroBreakCoordinator {
    private let store: PomodoroSessionPersisting
    private let shield: BreakShieldPresenting
    private let alarm: BreakAlarmPlaying
    private var machine: PomodoroBreakMachine
    private var lastCountingSaveAt = Date.distantPast

    var onPhaseChange: ((PomodoroBreakPhase) -> Void)?
    var onError: ((Error) -> Void)?

    init(
        store: PomodoroSessionPersisting,
        shield: BreakShieldPresenting,
        alarm: BreakAlarmPlaying,
        initialMachine: PomodoroBreakMachine? = nil,
        now: Date = Date()
    ) throws {
        self.store = store
        self.shield = shield
        self.alarm = alarm
        var restored = try initialMachine ?? store.load()
        let becameReadyWhileAway = restored.refresh(at: now) != nil
        if becameReadyWhileAway {
            try store.save(restored)
        }
        machine = restored
        restorePresentation()
        if becameReadyWhileAway {
            alarm.playCompletion()
        }
    }

    var phase: PomodoroBreakPhase { machine.phase }
    var isActiveBreak: Bool { machine.phase.isActiveBreak }

    func advance(isIdle: Bool, elapsedSeconds: TimeInterval, at date: Date) throws {
        guard !machine.phase.isActiveBreak else {
            try refresh(at: date)
            return
        }
        var proposed = machine
        let transition = proposed.advance(isIdle: isIdle, elapsedSeconds: elapsedSeconds, at: date)
        if transition == .triggered {
            try store.save(proposed)
            machine = proposed
            publishPhase()
            presentShield()
            alarm.startWaitingAlarm()
            return
        }

        machine = proposed
        if date.timeIntervalSince(lastCountingSaveAt) >= 10 {
            try store.save(machine)
            lastCountingSaveAt = date
        }
        publishPhase()
    }

    func acknowledge(at date: Date = Date()) throws {
        var proposed = machine
        guard proposed.acknowledge(at: date) == .acknowledged else { return }
        try store.save(proposed)
        machine = proposed
        alarm.stopWaitingAlarm()
        shield.update(phase: machine.phase)
        publishPhase()
    }

    func refresh(at date: Date = Date()) throws {
        var proposed = machine
        guard proposed.refresh(at: date) == .closeBecameAvailable else { return }
        try store.save(proposed)
        machine = proposed
        shield.update(phase: machine.phase)
        alarm.playCompletion()
        publishPhase()
    }

    func close() throws {
        var proposed = machine
        guard proposed.close() else { return }
        try store.save(proposed)
        machine = proposed
        alarm.stopWaitingAlarm()
        shield.dismiss()
        publishPhase()
    }

    func resetCounting() throws {
        guard !machine.phase.isActiveBreak else { return }
        let reset = PomodoroBreakMachine()
        try store.save(reset)
        machine = reset
        lastCountingSaveAt = .distantPast
        publishPhase()
    }

    private func restorePresentation() {
        guard machine.phase.isActiveBreak else { return }
        presentShield()
        if case .awaitingAcknowledgement = machine.phase {
            alarm.startWaitingAlarm()
        }
    }

    private func presentShield() {
        shield.present(
            phase: machine.phase,
            acknowledge: { [weak self] in self?.perform { try self?.acknowledge() } },
            close: { [weak self] in self?.perform { try self?.close() } }
        )
    }

    private func publishPhase() {
        onPhaseChange?(machine.phase)
    }

    private func perform(_ operation: () throws -> Void) {
        do {
            try operation()
        } catch {
            onError?(error)
        }
    }
}
