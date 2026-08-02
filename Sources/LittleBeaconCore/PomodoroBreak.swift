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

public struct PomodoroClockEvidence: Codable, Equatable, Sendable {
    public var bootIdentifier: String
    public var acknowledgedContinuousSeconds: TimeInterval

    public init(bootIdentifier: String, acknowledgedContinuousSeconds: TimeInterval) {
        self.bootIdentifier = bootIdentifier
        self.acknowledgedContinuousSeconds = acknowledgedContinuousSeconds
    }
}

public struct PomodoroClockReading: Equatable, Sendable {
    public var wallDate: Date
    public var bootIdentifier: String?
    public var continuousSeconds: TimeInterval?

    public init(
        wallDate: Date,
        bootIdentifier: String? = nil,
        continuousSeconds: TimeInterval? = nil
    ) {
        self.wallDate = wallDate
        self.bootIdentifier = bootIdentifier
        self.continuousSeconds = continuousSeconds
    }

    var evidence: PomodoroClockEvidence? {
        guard let bootIdentifier, let continuousSeconds else { return nil }
        return PomodoroClockEvidence(
            bootIdentifier: bootIdentifier,
            acknowledgedContinuousSeconds: continuousSeconds
        )
    }
}

public struct PomodoroBreakMachine: Codable, Equatable, Sendable {
    public static let workThreshold: TimeInterval = 25 * 60
    public static let idleResetThreshold: TimeInterval = 2 * 60
    public static let requiredBreakDuration: TimeInterval = 5 * 60

    public private(set) var phase: PomodoroBreakPhase
    public private(set) var clockEvidence: PomodoroClockEvidence?

    public init(
        phase: PomodoroBreakPhase = .counting(activeSeconds: 0, idleSeconds: 0),
        clockEvidence: PomodoroClockEvidence? = nil
    ) {
        self.phase = phase
        self.clockEvidence = clockEvidence
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
            clockEvidence = nil
            return .triggered
        }
        phase = .counting(activeSeconds: newActiveSeconds, idleSeconds: 0)
        return nil
    }

    @discardableResult
    public mutating func acknowledge(
        at date: Date,
        clockReading: PomodoroClockReading? = nil
    ) -> PomodoroBreakTransition? {
        guard case let .awaitingAcknowledgement(triggeredAt) = phase else { return nil }
        phase = .requiredBreak(
            triggeredAt: triggeredAt,
            acknowledgedAt: date,
            closeAvailableAt: date.addingTimeInterval(Self.requiredBreakDuration)
        )
        clockEvidence = clockReading?.evidence
        return .acknowledged
    }

    @discardableResult
    public mutating func refresh(
        at date: Date,
        clockReading: PomodoroClockReading? = nil
    ) -> PomodoroBreakTransition? {
        guard case let .requiredBreak(triggeredAt, acknowledgedAt, closeAvailableAt) = phase else {
            return nil
        }
        if let clockEvidence,
           let clockReading,
           clockReading.bootIdentifier == clockEvidence.bootIdentifier,
           let continuousSeconds = clockReading.continuousSeconds {
            guard continuousSeconds - clockEvidence.acknowledgedContinuousSeconds >= Self.requiredBreakDuration else {
                return nil
            }
        } else {
            // A different boot cannot reuse a prior boot's monotonic counter. Falling back to
            // the persisted wall deadline preserves sleep/reboot recovery; administrator clock
            // changes across a reboot remain an explicit system boundary.
            guard date >= closeAvailableAt else { return nil }
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
        clockEvidence = nil
        return true
    }

    private enum CodingKeys: String, CodingKey {
        case phase, clockEvidence
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        phase = try container.decode(PomodoroBreakPhase.self, forKey: .phase)
        clockEvidence = try container.decodeIfPresent(PomodoroClockEvidence.self, forKey: .clockEvidence)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(phase, forKey: .phase)
        try container.encodeIfPresent(clockEvidence, forKey: .clockEvidence)
    }
}
