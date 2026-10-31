import Foundation

/// What a parent can ask the child Mac to close.
public enum RemoteTarget: String, Codable, CaseIterable, Identifiable, Sendable {
    case game
    case browser

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .game: "游戏"
        case .browser: "浏览器"
        }
    }
}

public enum RemoteCommandKind: String, Codable, Sendable {
    case close
    case unlock
}

/// How long the target stays closed once it has been closed.
public enum RemoteLockOption: String, Codable, CaseIterable, Identifiable, Sendable {
    case noLock = "none"
    case thirtyMinutes = "30m"
    case oneHour = "60m"
    case today

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .noLock: "不锁"
        case .thirtyMinutes: "30 分钟"
        case .oneHour: "1 小时"
        case .today: "今天"
        }
    }

    /// `nil` when nothing is locked. "Today" runs to the next midnight of the family's time zone.
    public func endsAt(from date: Date, calendar: Calendar) -> Date? {
        switch self {
        case .noLock: nil
        case .thirtyMinutes: date.addingTimeInterval(30 * 60)
        case .oneHour: date.addingTimeInterval(60 * 60)
        case .today: calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))
        }
    }
}

public enum RemoteCommandStatus: String, Codable, Sendable {
    case pending
    case received
    case finished
    /// Nobody picked it up in time. The server derives this; it is never stored.
    case expired
}

public enum RemoteOutcome: String, Codable, Sendable {
    case closed
    /// At least one app could not be closed.
    case partial
    case nothingOpen
    /// It was open when the notice went up, and gone by the deadline.
    case closedByChild
    /// A game in a browser tab, no longer in front at the deadline. Other tabs are never read, so
    /// nobody can say whether it was closed.
    case notConfirmed
    /// The Mac slept through the deadline, so nothing ran.
    case stale
    case unlocked
}

public struct RemoteCommand: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var kind: RemoteCommandKind
    public var target: RemoteTarget
    public var lock: RemoteLockOption
    public var status: RemoteCommandStatus
    public var createdAt: Date
    public var expiresAt: Date
    public var receivedAt: Date?
    public var finishedAt: Date?
    public var outcome: RemoteOutcome?
    public var closedApps: [String]
    public var failedApps: [String]
    public var frontAppName: String?
    public var frontAppBundleID: String?
    public var lockEndsAt: Date?

    public init(
        id: UUID = UUID(),
        kind: RemoteCommandKind,
        target: RemoteTarget,
        lock: RemoteLockOption = .noLock,
        status: RemoteCommandStatus = .pending,
        createdAt: Date,
        expiresAt: Date,
        receivedAt: Date? = nil,
        finishedAt: Date? = nil,
        outcome: RemoteOutcome? = nil,
        closedApps: [String] = [],
        failedApps: [String] = [],
        frontAppName: String? = nil,
        frontAppBundleID: String? = nil,
        lockEndsAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.target = target
        self.lock = lock
        self.status = status
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.receivedAt = receivedAt
        self.finishedAt = finishedAt
        self.outcome = outcome
        self.closedApps = closedApps
        self.failedApps = failedApps
        self.frontAppName = frontAppName
        self.frontAppBundleID = frontAppBundleID
        self.lockEndsAt = lockEndsAt
    }
}

/// What the child Mac tells the server about a command. Queued, so a lost connection only delays it.
public struct RemoteCommandReport: Codable, Equatable, Sendable {
    public enum Stage: String, Codable, Sendable {
        case received
        case finished
    }

    public var id: UUID
    public var status: Stage
    public var at: Date
    public var outcome: RemoteOutcome?
    public var closedApps: [String]
    public var failedApps: [String]
    public var frontAppName: String?
    public var frontAppBundleID: String?
    public var lockEndsAt: Date?

    public init(
        id: UUID,
        status: Stage,
        at: Date,
        outcome: RemoteOutcome? = nil,
        closedApps: [String] = [],
        failedApps: [String] = [],
        frontAppName: String? = nil,
        frontAppBundleID: String? = nil,
        lockEndsAt: Date? = nil
    ) {
        self.id = id
        self.status = status
        self.at = at
        self.outcome = outcome
        self.closedApps = closedApps
        self.failedApps = failedApps
        self.frontAppName = frontAppName
        self.frontAppBundleID = frontAppBundleID
        self.lockEndsAt = lockEndsAt
    }
}

/// What was found open when a close arrived.
public enum RemoteOpenState: Equatable, Sendable {
    case notOpen
    case app
    /// Only a game in the front browser tab, which can be seen only while it stays in front.
    case browserTabOnly
}

/// A close the child has been told about, waiting for its deadline.
public struct ActiveRemoteClose: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var target: RemoteTarget
    public var lock: RemoteLockOption
    public var receivedAt: Date
    public var deadline: Date
    public var openState: RemoteOpenStateRecord
    public var isClosing = false
    /// Cut off by a restart while closing: finding nothing afterwards means the close worked.
    public var wasInterrupted = false

    public var wasOpenWhenReceived: Bool { openState != .notOpen }
}

public enum RemoteOpenStateRecord: String, Codable, Sendable {
    case notOpen
    case app
    case browserTabOnly

    init(_ state: RemoteOpenState) {
        switch state {
        case .notOpen: self = .notOpen
        case .app: self = .app
        case .browserTabOnly: self = .browserTabOnly
        }
    }
}

public struct RemoteLock: Codable, Equatable, Sendable {
    public var target: RemoteTarget
    public var endsAt: Date
}

public enum RemoteControlEvent: Equatable, Sendable {
    /// The child gets the notice: the target closes at the deadline.
    case closing(RemoteTarget, lock: RemoteLockOption)
    case unlocked(RemoteTarget)
}

/// The app the child is in, reported only when a parent's close found no game to close.
public struct RemoteFrontApp: Equatable, Sendable {
    public var name: String
    public var bundleIdentifier: String

    public init(name: String, bundleIdentifier: String) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
    }
}

/// Everything the child Mac keeps about remote commands. Saved on every change, so a restart
/// carries on with the same deadline and the same locks, offline included.
public struct RemoteControlState: Codable, Equatable, Sendable {
    /// How long the child has to save before the close.
    public static let noticeSeconds: TimeInterval = 60
    /// A deadline missed by longer than this (the Mac slept) is dropped, never run late.
    public static let staleAfterSeconds: TimeInterval = 300
    private static let seenRetention: TimeInterval = 2 * 86_400
    private static let reportRetention: TimeInterval = 30 * 86_400

    private struct SeenCommand: Codable, Equatable, Sendable {
        var id: UUID
        var at: Date
    }

    public private(set) var active: [ActiveRemoteClose] = []
    public private(set) var locks: [RemoteLock] = []
    public private(set) var reports: [RemoteCommandReport] = []
    private var seen: [SeenCommand] = []

    public init() {}

    /// Takes in what the server handed over. Commands already seen are ignored, because a
    /// "received" report lost on the way makes the server hand the same command over again.
    public mutating func receive(
        _ commands: [RemoteCommand],
        openState: (RemoteTarget) -> RemoteOpenState,
        at now: Date
    ) -> [RemoteControlEvent] {
        var events: [RemoteControlEvent] = []
        for command in commands.sorted(by: { $0.createdAt < $1.createdAt })
        where !seen.contains(where: { $0.id == command.id }) {
            seen.append(SeenCommand(id: command.id, at: now))
            switch command.kind {
            case .close:
                reports.append(RemoteCommandReport(id: command.id, status: .received, at: now))
                let state = openState(command.target)
                let open = state != .notOpen
                // Nothing to warn about: it falls due at once, so the parent hears back quickly.
                active.append(ActiveRemoteClose(
                    id: command.id,
                    target: command.target,
                    lock: command.lock,
                    receivedAt: now,
                    deadline: open ? now.addingTimeInterval(Self.noticeSeconds) : now,
                    openState: RemoteOpenStateRecord(state)
                ))
                if open { events.append(.closing(command.target, lock: command.lock)) }
            case .unlock:
                let wasLocked = locks.contains { $0.target == command.target }
                locks.removeAll { $0.target == command.target }
                // The parent's newest word wins over a lock still on its way.
                for index in active.indices where active[index].target == command.target {
                    active[index].lock = .noLock
                }
                reports.append(RemoteCommandReport(id: command.id, status: .finished, at: now, outcome: .unlocked))
                if wasLocked { events.append(.unlocked(command.target)) }
            }
        }
        return events
    }

    /// Closes whose deadline has come, marked as being closed. Those missed by too long end here.
    public mutating func startDueCloses(at now: Date) -> [ActiveRemoteClose] {
        var due: [ActiveRemoteClose] = []
        for close in active where !close.isClosing && close.deadline <= now {
            if now.timeIntervalSince(close.deadline) > Self.staleAfterSeconds {
                active.removeAll { $0.id == close.id }
                reports.append(RemoteCommandReport(id: close.id, status: .finished, at: now, outcome: .stale))
            } else if let index = active.firstIndex(where: { $0.id == close.id }) {
                active[index].isClosing = true
                due.append(active[index])
            }
        }
        return due
    }

    /// A close cut off by a restart runs again: closing what is already gone does no harm.
    public mutating func resumeAfterRestart() {
        for index in active.indices where active[index].isClosing {
            active[index].isClosing = false
            active[index].wasInterrupted = true
        }
    }

    /// Records how a close went and starts its lock. A lock applies even when nothing was open:
    /// the parent asked for the time to be free of it.
    @discardableResult
    public mutating func finish(
        _ id: UUID,
        closed: [String],
        failed: [String],
        frontApp: RemoteFrontApp? = nil,
        at now: Date,
        calendar: Calendar
    ) -> RemoteCommandReport? {
        guard let close = active.first(where: { $0.id == id }) else { return nil }
        active.removeAll { $0.id == id }

        let outcome: RemoteOutcome
        if !failed.isEmpty {
            outcome = .partial
        } else if !closed.isEmpty || close.wasInterrupted {
            outcome = .closed
        } else if close.openState == .browserTabOnly {
            outcome = .notConfirmed
        } else {
            outcome = close.wasOpenWhenReceived ? .closedByChild : .nothingOpen
        }
        // "Today" means the day the parent asked, even if the close lands after midnight.
        let lockStart = close.lock == .today ? close.receivedAt : now
        let lockEndsAt = close.lock.endsAt(from: lockStart, calendar: calendar)
        if let lockEndsAt { extendLock(close.target, to: lockEndsAt) }

        let report = RemoteCommandReport(
            id: id,
            status: .finished,
            at: now,
            outcome: outcome,
            closedApps: closed,
            failedApps: failed,
            frontAppName: frontApp?.name,
            frontAppBundleID: frontApp?.bundleIdentifier,
            lockEndsAt: lockEndsAt
        )
        reports.append(report)
        return report
    }

    public func lockEnd(for target: RemoteTarget, at now: Date) -> Date? {
        locks.first { $0.target == target && $0.endsAt > now }?.endsAt
    }

    /// Which lock the current activity runs into, if any. A close under way keeps the minute it
    /// promised the child, so the lock waits for it.
    public func blockedTarget(for activity: ClassifiedActivity, isBrowser: Bool, at now: Date) -> RemoteTarget? {
        let isLocked = { (target: RemoteTarget) in
            lockEnd(for: target, at: now) != nil && !active.contains { $0.target == target }
        }
        if activity.category == .game, isLocked(.game) { return .game }
        if isBrowser, isLocked(.browser) { return .browser }
        return nil
    }

    public mutating func clearReport(_ report: RemoteCommandReport) {
        reports.removeAll { $0 == report }
    }

    public mutating func prune(now: Date) {
        locks.removeAll { $0.endsAt <= now }
        seen.removeAll { now.timeIntervalSince($0.at) > Self.seenRetention }
        reports.removeAll { now.timeIntervalSince($0.at) > Self.reportRetention }
    }

    private mutating func extendLock(_ target: RemoteTarget, to endsAt: Date) {
        if let index = locks.firstIndex(where: { $0.target == target }) {
            locks[index].endsAt = max(locks[index].endsAt, endsAt)
        } else {
            locks.append(RemoteLock(target: target, endsAt: endsAt))
        }
    }
}

public enum RemoteLockAction: Equatable, Sendable {
    case warn(RemoteTarget)
    case close(RemoteTarget)
}

/// Gives a locked app a few seconds on screen, so the child reads why it is going away. Once
/// warned the close happens whatever is in front: switching away must not reset the countdown.
public struct RemoteLockGuard: Equatable, Sendable {
    public static let graceSeconds: TimeInterval = 5

    private var pendingTarget: RemoteTarget?
    private var closeAt: Date?

    public init() {}

    public mutating func advance(blocked: RemoteTarget?, at now: Date) -> RemoteLockAction? {
        if let pendingTarget, let closeAt {
            guard now >= closeAt else { return nil }
            self.pendingTarget = nil
            self.closeAt = nil
            return .close(pendingTarget)
        }
        guard let blocked else { return nil }
        pendingTarget = blocked
        closeAt = now.addingTimeInterval(Self.graceSeconds)
        return .warn(blocked)
    }
}

public extension ActivityClassifier {
    static let knownBrowserBundleIDs: Set<String> = [
        "com.apple.safari",
        "com.apple.safaritechnologypreview",
        "com.google.chrome",
        "com.google.chrome.canary",
        "com.microsoft.edgemac",
        "org.mozilla.firefox",
        "company.thebrowser.browser",
        "com.brave.browser",
        "com.operasoftware.opera",
        "com.vivaldi.vivaldi",
    ]

    /// Never closed remotely, whatever a parent's override says about them.
    static let protectedBundleIDs: Set<String> = [
        "com.apple.finder",
        "com.apple.dock",
        "com.apple.loginwindow",
        "com.apple.systempreferences",
        "com.apple.systemuiserver",
        "com.apple.controlcenter",
    ]

    func isBrowser(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return Self.knownBrowserBundleIDs.contains(bundleIdentifier.lowercased())
    }

    func isProtected(bundleIdentifier: String?, own ownBundleIdentifier: String?) -> Bool {
        guard let bundle = bundleIdentifier?.lowercased() else { return false }
        return bundle == ownBundleIdentifier?.lowercased() || Self.protectedBundleIDs.contains(bundle)
    }

    /// Whether a running app is what a remote close of `target` should end.
    func matches(
        _ target: RemoteTarget,
        appName: String,
        bundleIdentifier: String?,
        overrides: [ClassificationOverride],
        own ownBundleIdentifier: String?
    ) -> Bool {
        guard !isProtected(bundleIdentifier: bundleIdentifier, own: ownBundleIdentifier) else { return false }
        switch target {
        case .game:
            let observation = ActivityObservation(appName: appName, bundleIdentifier: bundleIdentifier)
            return classify(observation, overrides: overrides).category == .game
        case .browser:
            return isBrowser(bundleIdentifier: bundleIdentifier)
        }
    }
}

// MARK: - What the parent sees

public extension RemoteCommand {
    /// A close the child took in but never finished stops counting after this: it ran into trouble.
    static let inFlightSeconds: TimeInterval = 180

    func isInFlight(at now: Date) -> Bool {
        guard kind == .close else { return false }
        switch status {
        case .pending: return expiresAt > now
        case .received: return now.timeIntervalSince(receivedAt ?? createdAt) < Self.inFlightSeconds
        case .finished, .expired: return false
        }
    }

    /// Finished, or given up on.
    func hasEnded(at now: Date) -> Bool {
        kind == .close && !isInFlight(at: now)
    }

    var parentTitle: String { "家长关闭\(target.displayName)" }

    func parentOutcome(at now: Date) -> String {
        let name = target.displayName
        switch status {
        case .pending where isInFlight(at: now):
            return "已发给孩子的 Mac，等它收到"
        case .received where isInFlight(at: now):
            return "孩子已收到，1 分钟内关闭"
        case .pending, .received, .expired:
            return "孩子的 Mac 没有回应，可能离线或还没升级"
        case .finished:
            break
        }
        switch outcome {
        case .closed:
            return closedApps.isEmpty ? "已关闭\(name)" : "已关闭 \(closedApps.joined(separator: "、"))"
        case .partial:
            let failures = "有 \(failedApps.count) 个没关掉：\(failedApps.joined(separator: "、"))"
            return closedApps.isEmpty ? failures : "已关闭 \(closedApps.joined(separator: "、"))，\(failures)"
        case .nothingOpen:
            if let frontAppName { return "没有识别到游戏，孩子现在用的是 \(frontAppName)" }
            return "没有打开的\(name)"
        case .closedByChild:
            return "孩子已经自己关了"
        case .notConfirmed:
            return "孩子切到了别的窗口，没能确认网页游戏关了没有"
        case .stale:
            return "孩子的 Mac 当时在休眠，没有执行"
        case .unlocked:
            return "已解除"
        case nil:
            return "结果没有传回来"
        }
    }

    /// The app to offer "设为游戏并关闭" for, when a close of games found none.
    var unrecognizedApp: RemoteFrontApp? {
        guard target == .game, outcome == .nothingOpen, let frontAppName, let frontAppBundleID else { return nil }
        return RemoteFrontApp(name: frontAppName, bundleIdentifier: frontAppBundleID)
    }
}

/// When the target's lock ends, as far as the parent knows: replays the commands in the order they
/// were given, the way the child applied them. An unlock counts from the moment it is sent.
public func remoteLockEnd(for target: RemoteTarget, in commands: [RemoteCommand], at now: Date) -> Date? {
    var end: Date?
    for command in commands.sorted(by: { $0.createdAt < $1.createdAt }) where command.target == target {
        switch command.kind {
        case .close:
            if let lockEndsAt = command.lockEndsAt { end = max(end ?? lockEndsAt, lockEndsAt) }
        case .unlock:
            if command.status != .expired { end = nil }
        }
    }
    guard let end, end > now else { return nil }
    return end
}

// MARK: - What the child sees

/// "到 21:30", or "到今天结束" for a lock that runs to midnight.
public func remoteLockEndText(_ endsAt: Date, timeZoneIdentifier: String) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
    let parts = calendar.dateComponents([.hour, .minute], from: endsAt)
    let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    return minute == 0 ? "到今天结束" : "到 \(clockText(minute))"
}

public extension ReminderMessage {
    static func remoteClosing(_ target: RemoteTarget, lock: RemoteLockOption) -> ReminderMessage {
        let save = target == .game ? "记得存档" : "没保存的内容记得先保存"
        let after: String
        switch lock {
        case .noLock: after = ""
        case .thirtyMinutes, .oneHour: after = "关闭后 \(lock.displayName)内不能再打开。"
        case .today: after = "关闭后今天不能再打开。"
        }
        return ReminderMessage(
            title: "家长让你现在结束\(target.displayName)",
            body: "1 分钟后关闭，\(save)。\(after)"
        )
    }

    static func remoteClosed(_ target: RemoteTarget, lockEnd: String?) -> ReminderMessage {
        ReminderMessage(
            title: "\(target.displayName)已关闭",
            body: lockEnd.map { "家长锁定了\(target.displayName)，\($0)。" } ?? "这是家长要求关闭的。"
        )
    }

    static func remoteLocked(_ target: RemoteTarget, lockEnd: String) -> ReminderMessage {
        ReminderMessage(
            title: "\(target.displayName)现在被锁定了",
            body: "家长锁定\(lockEnd)，马上会关闭。"
        )
    }

    static func remoteUnlocked(_ target: RemoteTarget) -> ReminderMessage {
        ReminderMessage(title: "\(target.displayName)已解除锁定", body: "家长解除了锁定。")
    }
}
