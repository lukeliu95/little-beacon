import Foundation

public struct ActivityClassifier: Sendable {
    public static let knownGameBundleIDs: Set<String> = [
        "com.valvesoftware.steam",
        "com.blizzard.battle.net",
        "com.epicgames.launcher",
        "com.mojang.minecraftlauncher",
        "com.riotgames.leagueoflegends",
        "com.roblox.roblox",
        // The actual macOS Roblox client ships as com.roblox.RobloxPlayer (verified against
        // /Applications/Roblox.app); the plain com.roblox.roblox entry above never matched it.
        // Compared lowercased, so entries here must be lowercase.
        "com.roblox.robloxplayer",
    ]

    public static let knownVideoBundleIDs: Set<String> = [
        "com.apple.tv",
        "com.netflix.Netflix",
        "tv.plex.desktop",
        "com.colliderli.iina",
        "org.videolan.vlc",
    ].map { $0.lowercased() }.reduce(into: Set<String>()) { $0.insert($1) }

    public static let knownVideoDomains: Set<String> = [
        "youtube.com",
        "youtu.be",
        "bilibili.com",
        "netflix.com",
        "twitch.tv",
        "vimeo.com",
        "iqiyi.com",
        "youku.com",
        "mgtv.com",
        "disneyplus.com",
        "primevideo.com",
    ]

    public init() {}

    public func classify(
        _ observation: ActivityObservation,
        overrides: [ClassificationOverride]
    ) -> ClassifiedActivity {
        if observation == .idle {
            return ClassifiedActivity(observation: observation, category: .idle)
        }

        if let domain = observation.normalizedDomain?.lowercased(),
           let override = overrides.first(where: {
               $0.target == .domain && Self.domain(domain, matches: $0.value)
           }) {
            return ClassifiedActivity(observation: observation, category: override.category)
        }

        if let bundle = observation.bundleIdentifier?.lowercased(),
           let override = overrides.first(where: {
               $0.target == .bundleIdentifier && $0.value.lowercased() == bundle
           }) {
            return ClassifiedActivity(observation: observation, category: override.category)
        }

        if let domain = observation.normalizedDomain?.lowercased(),
           Self.knownVideoDomains.contains(where: { Self.domain(domain, matches: $0) }) {
            return ClassifiedActivity(observation: observation, category: .video)
        }

        if let bundle = observation.bundleIdentifier?.lowercased() {
            if Self.knownGameBundleIDs.contains(bundle) {
                return ClassifiedActivity(observation: observation, category: .game)
            }
            if Self.knownVideoBundleIDs.contains(bundle) {
                return ClassifiedActivity(observation: observation, category: .video)
            }
        }

        return ClassifiedActivity(observation: observation, category: .other)
    }

    private static func domain(_ candidate: String, matches rule: String) -> Bool {
        let normalizedRule = rule.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return candidate == normalizedRule || candidate.hasSuffix(".\(normalizedRule)")
    }
}

public struct RuleEvaluator: Sendable {
    public init() {}

    public func isAllowed(
        category: ActivityCategory,
        at date: Date,
        rules: RuleSet,
        temporaryGrants: [TemporaryGrant]
    ) -> Bool {
        guard category == .game || category == .video else { return true }

        if temporaryGrants.contains(where: { $0.category == category && $0.isActive(at: date) }) {
            return true
        }

        guard let rule = rules.activityRules.first(where: { $0.category == category }) else {
            return false
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: rules.timeZoneIdentifier) ?? .current
        let weekday = calendar.component(.weekday, from: date)
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let minuteOfDay = hour * 60 + minute

        return rule.windows.contains { window in
            guard window.weekday == weekday else { return false }
            if window.startMinute <= window.endMinute {
                return minuteOfDay >= window.startMinute && minuteOfDay < window.endMinute
            }
            return minuteOfDay >= window.startMinute || minuteOfDay < window.endMinute
        }
    }
}

public enum ViolationAction: Equatable, Sendable {
    case warning(level: Int, activity: ClassifiedActivity)
    case beginEvent(activity: ClassifiedActivity, startedAt: Date)
    case enforce(activity: ClassifiedActivity)
    case reset
}

public struct ViolationState: Equatable, Sendable {
    public var startedAt: Date
    public var activeSeconds: TimeInterval
    public var cleanSeconds: TimeInterval
    public var warningCount: Int
    public var latestActivity: ClassifiedActivity
    public var enforcedActivityKeys: Set<String>

    public init(startedAt: Date, latestActivity: ClassifiedActivity) {
        self.startedAt = startedAt
        self.activeSeconds = 0
        self.cleanSeconds = 0
        self.warningCount = 0
        self.latestActivity = latestActivity
        self.enforcedActivityKeys = []
    }
}

public struct ViolationMachine: Sendable {
    public private(set) var state: ViolationState?

    public init() {}

    public mutating func advance(
        activity: ClassifiedActivity,
        isAllowed: Bool,
        elapsedSeconds: TimeInterval,
        at date: Date,
        strategy: ReminderStrategy = .standard
    ) -> [ViolationAction] {
        let delta = max(0, elapsedSeconds)
        let plan = strategy.plan
        let isRestricted = activity.category == .game || activity.category == .video

        guard isRestricted && !isAllowed else {
            guard var current = state else { return [] }
            current.cleanSeconds += delta
            if current.cleanSeconds >= 300 {
                state = nil
                return [.reset]
            }
            state = current
            return []
        }

        var actions: [ViolationAction] = []
        var current = state ?? ViolationState(startedAt: date, latestActivity: activity)
        current.latestActivity = activity
        current.cleanSeconds = 0
        current.activeSeconds += delta

        if current.warningCount == 0 {
            current.warningCount = 1
            actions.append(.warning(level: 1, activity: activity))
        }
        if current.activeSeconds >= 60 && current.warningCount < 2 {
            current.warningCount = 2
            actions.append(.warning(level: 2, activity: activity))
            actions.append(.beginEvent(activity: activity, startedAt: current.startedAt))
        }
        if let lastWarning = plan.lastWarningSeconds,
           current.activeSeconds >= TimeInterval(lastWarning),
           current.warningCount < 3 {
            current.warningCount = 3
            actions.append(.warning(level: 3, activity: activity))
        }
        if let enforceAfter = plan.enforceAfterSeconds, current.activeSeconds >= TimeInterval(enforceAfter) {
            let key = activity.observation.stableKey
            if !current.enforcedActivityKeys.contains(key) {
                current.enforcedActivityKeys.insert(key)
                actions.append(.enforce(activity: activity))
            }
        }

        state = current
        return actions
    }
}
