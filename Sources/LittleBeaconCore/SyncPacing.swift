import Foundation

/// How often each side talks to the server. The database sleeps only after five quiet minutes,
/// so a steady 30-second beat kept it awake around the clock. Each side now syncs often only while
/// somebody is there: a child using the Mac, or a parent looking at the window.
public enum SyncPace {
    public static let busy: TimeInterval = 30
    /// The child Mac is locked, on the screen saver, or its display is asleep.
    public static let childAway: TimeInterval = 30 * 60
    /// The parent window is closed or covered.
    public static let parentBackground: TimeInterval = 15 * 60

    public static func idleInterval(for role: DeviceRole) -> TimeInterval {
        role == .parent ? parentBackground : childAway
    }

    /// How long the parent keeps calling the child Mac online without hearing from it. A child that
    /// said it was idle may stay quiet for a whole away interval.
    public static func onlineGrace(for category: ActivityCategory) -> TimeInterval {
        category == .idle ? childAway + 5 * 60 : 90
    }
}

/// Decides, on every tick, whether this tick should sync.
public struct SyncPacer: Equatable, Sendable {
    /// A tick that lands a moment early still counts, so a 30-second timer keeps a 30-second beat.
    static let tolerance: TimeInterval = 2

    public private(set) var lastSyncAt: Date?
    public private(set) var wasBusy = true

    public init() {}

    /// Switching between busy and quiet syncs at once: arriving should feel instant, and leaving
    /// tells the other side that the next sync may be a while.
    public mutating func shouldSync(busy: Bool, idleInterval: TimeInterval, at now: Date) -> Bool {
        defer { wasBusy = busy }
        guard let lastSyncAt else { return true }
        if busy != wasBusy { return true }
        let interval = busy ? SyncPace.busy : idleInterval
        return now.timeIntervalSince(lastSyncAt) >= interval - Self.tolerance
    }

    public mutating func recordSync(at date: Date) {
        lastSyncAt = date
    }
}
