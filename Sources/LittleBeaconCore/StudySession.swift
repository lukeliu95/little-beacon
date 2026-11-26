import Foundation

/// A stretch the parent sets aside for serious study (issue #19). Inside it the child Mac stays
/// completely quiet: no eye-care reminder, no schedule, no events, no usage counting.
public struct StudySession: Codable, Equatable, Identifiable, Sendable {
    public static let maximumDuration: TimeInterval = 12 * 3_600
    public static let maximumCount = 20

    public var id: UUID
    public var startsAt: Date
    public var endsAt: Date

    public init(id: UUID = UUID(), startsAt: Date, endsAt: Date) {
        self.id = id
        self.startsAt = startsAt
        self.endsAt = endsAt
    }

    public var isValid: Bool {
        endsAt > startsAt && endsAt.timeIntervalSince(startsAt) <= Self.maximumDuration
    }

    public func contains(_ date: Date) -> Bool {
        isValid && date >= startsAt && date < endsAt
    }
}

public extension RuleSet {
    func activeStudySession(at date: Date) -> StudySession? {
        studySessions
            .filter { $0.contains(date) }
            .max { $0.endsAt < $1.endsAt }
    }

    func isStudying(at date: Date) -> Bool {
        activeStudySession(at: date) != nil
    }

    /// Sessions that have not ended yet, earliest first: what the parent still needs to see.
    func upcomingStudySessions(at date: Date) -> [StudySession] {
        studySessions
            .filter { $0.isValid && $0.endsAt > date }
            .sorted { $0.startsAt < $1.startsAt }
    }
}

/// Adds a session, drops the ones that are over, and keeps the list short enough to sync.
public func studySessions(
    _ sessions: [StudySession],
    adding session: StudySession,
    at date: Date
) -> [StudySession]? {
    guard session.isValid, session.endsAt > date else { return nil }
    var kept = sessions.filter { $0.isValid && $0.endsAt > date }
    guard kept.count < StudySession.maximumCount else { return nil }
    kept.append(session)
    return kept.sorted { $0.startsAt < $1.startsAt }
}
