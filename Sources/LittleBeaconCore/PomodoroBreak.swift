import Foundation

public enum PomodoroBreakPhase: Codable, Equatable, Sendable {
    case counting(activeSeconds: TimeInterval, idleSeconds: TimeInterval)
    case awaitingAcknowledgement(triggeredAt: Date)
    case requiredBreak(triggeredAt: Date, acknowledgedAt: Date, closeAvailableAt: Date)
    case readyToClose(triggeredAt: Date, acknowledgedAt: Date, closeAvailableAt: Date)

    public var isActiveBreak: Bool {
        if case .counting = self { return false }
        return true
    }
}

public enum PomodoroBreakTransition: Equatable, Sendable {
    case triggered
    case acknowledged
    case closeBecameAvailable
}

public struct PomodoroBreakMachine: Codable, Equatable, Sendable {
    public static let workThreshold: TimeInterval = 25 * 60
    public static let idleResetThreshold: TimeInterval = 2 * 60
    public static let requiredBreakDuration: TimeInterval = 5 * 60

    public private(set) var phase: PomodoroBreakPhase

    public init(phase: PomodoroBreakPhase = .counting(activeSeconds: 0, idleSeconds: 0)) {
        self.phase = phase
    }

    @discardableResult
    public mutating func advance(
        isIdle: Bool,
        elapsedSeconds: TimeInterval,
        at date: Date
    ) -> PomodoroBreakTransition? {
        guard case let .counting(activeSeconds, idleSeconds) = phase else { return nil }
        let delta = max(0, elapsedSeconds)

        if isIdle {
            let newIdleSeconds = idleSeconds + delta
            if newIdleSeconds >= Self.idleResetThreshold {
                phase = .counting(activeSeconds: 0, idleSeconds: 0)
            } else {
                phase = .counting(activeSeconds: activeSeconds, idleSeconds: newIdleSeconds)
            }
            return nil
        }

        let newActiveSeconds = activeSeconds + delta
        if newActiveSeconds >= Self.workThreshold {
            phase = .awaitingAcknowledgement(triggeredAt: date)
            return .triggered
        }
        phase = .counting(activeSeconds: newActiveSeconds, idleSeconds: 0)
        return nil
    }

    @discardableResult
    public mutating func acknowledge(at date: Date) -> PomodoroBreakTransition? {
        guard case let .awaitingAcknowledgement(triggeredAt) = phase else { return nil }
        phase = .requiredBreak(
            triggeredAt: triggeredAt,
            acknowledgedAt: date,
            closeAvailableAt: date.addingTimeInterval(Self.requiredBreakDuration)
        )
        return .acknowledged
    }

    @discardableResult
    public mutating func refresh(at date: Date) -> PomodoroBreakTransition? {
        guard case let .requiredBreak(triggeredAt, acknowledgedAt, closeAvailableAt) = phase,
              date >= closeAvailableAt else {
            return nil
        }
        phase = .readyToClose(
            triggeredAt: triggeredAt,
            acknowledgedAt: acknowledgedAt,
            closeAvailableAt: closeAvailableAt
        )
        return .closeBecameAvailable
    }

    @discardableResult
    public mutating func close() -> Bool {
        guard case .readyToClose = phase else { return false }
        phase = .counting(activeSeconds: 0, idleSeconds: 0)
        return true
    }
}
