import Foundation

public enum DeviceRole: String, Codable, CaseIterable, Sendable {
    case unconfigured
    case parent
    case child
}

public enum ActivityCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case game
    case video
    case other
    case idle

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .game: "游戏"
        case .video: "视频"
        case .other: "其他"
        case .idle: "空闲"
        }
    }
}

public enum OverrideTarget: String, Codable, CaseIterable, Sendable {
    case bundleIdentifier
    case domain
}

public struct ClassificationOverride: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var target: OverrideTarget
    public var value: String
    public var category: ActivityCategory

    public init(
        id: UUID = UUID(),
        target: OverrideTarget,
        value: String,
        category: ActivityCategory
    ) {
        self.id = id
        self.target = target
        self.value = value.lowercased()
        self.category = category
    }
}

public struct ScheduleWindow: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    /// Calendar weekday: 1 is Sunday and 7 is Saturday.
    public var weekday: Int
    public var startMinute: Int
    public var endMinute: Int
    /// `nil` follows the rule set's default strategy.
    public var reminderStrategy: ReminderStrategy?

    public init(
        id: UUID = UUID(),
        weekday: Int,
        startMinute: Int,
        endMinute: Int,
        reminderStrategy: ReminderStrategy? = nil
    ) {
        self.id = id
        self.weekday = weekday
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.reminderStrategy = reminderStrategy
    }
}

public struct ActivityRule: Codable, Equatable, Sendable {
    public var category: ActivityCategory
    public var windows: [ScheduleWindow]

    public init(category: ActivityCategory, windows: [ScheduleWindow]) {
        self.category = category
        self.windows = windows
    }
}

public enum PomodoroMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case off
    case gentle
    case enforced

    public var id: String { rawValue }
}

public struct RuleSet: Codable, Equatable, Sendable {
    public var revision: Int
    public var timeZoneIdentifier: String
    public var activityRules: [ActivityRule]
    public var overrides: [ClassificationOverride]
    /// 25-minute eye-care break behavior, independent of the game/video rule engine.
    public var pomodoroMode: PomodoroMode
    /// Legacy compatibility surface for clients and documents that predate `pomodoroMode`.
    public var pomodoroEnabled: Bool {
        get { pomodoroMode != .off }
        set { pomodoroMode = newValue ? .gentle : .off }
    }
    /// Soft daily-usage nudge threshold in seconds. `nil` disables the nudge; this never enforces or ends activity.
    public var dailyUsageThresholdSeconds: Int?
    /// Periodic, camera-based "too close to the screen" reminder. Disabled until the
    /// family explicitly enables it and the child Mac completes local calibration.
    public var viewingDistancePolicy: ViewingDistancePolicy
    /// Used outside any window and by slots that do not pick their own strategy.
    public var defaultReminderStrategy: ReminderStrategy

    public init(
        revision: Int = 1,
        timeZoneIdentifier: String = TimeZone.current.identifier,
        activityRules: [ActivityRule],
        overrides: [ClassificationOverride] = [],
        pomodoroMode: PomodoroMode = .gentle,
        dailyUsageThresholdSeconds: Int? = 7200,
        viewingDistancePolicy: ViewingDistancePolicy = .disabled,
        defaultReminderStrategy: ReminderStrategy = .standard
    ) {
        self.revision = revision
        self.timeZoneIdentifier = timeZoneIdentifier
        self.activityRules = activityRules
        self.overrides = overrides
        self.pomodoroMode = pomodoroMode
        self.dailyUsageThresholdSeconds = dailyUsageThresholdSeconds
        self.viewingDistancePolicy = viewingDistancePolicy
        self.defaultReminderStrategy = defaultReminderStrategy
    }

    private enum CodingKeys: String, CodingKey {
        case revision, timeZoneIdentifier, activityRules, overrides
        case pomodoroMode, pomodoroEnabled, dailyUsageThresholdSeconds, viewingDistancePolicy
        case defaultReminderStrategy
    }

    // Custom decoding keeps old saved/remote documents (missing the two newest keys) loadable
    // instead of throwing keyNotFound, since Swift's synthesized Decodable ignores default values.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        revision = try container.decode(Int.self, forKey: .revision)
        timeZoneIdentifier = try container.decode(String.self, forKey: .timeZoneIdentifier)
        activityRules = try container.decode([ActivityRule].self, forKey: .activityRules)
        overrides = try container.decode([ClassificationOverride].self, forKey: .overrides)
        let legacyPomodoroEnabled = try container.decodeIfPresent(Bool.self, forKey: .pomodoroEnabled) ?? true
        pomodoroMode = try container.decodeIfPresent(PomodoroMode.self, forKey: .pomodoroMode)
            ?? (legacyPomodoroEnabled ? .gentle : .off)
        dailyUsageThresholdSeconds = try container.decodeIfPresent(Int.self, forKey: .dailyUsageThresholdSeconds) ?? 7200
        viewingDistancePolicy = try container.decodeIfPresent(
            ViewingDistancePolicy.self,
            forKey: .viewingDistancePolicy
        ) ?? .disabled
        defaultReminderStrategy = try container.decodeIfPresent(
            ReminderStrategy.self,
            forKey: .defaultReminderStrategy
        ) ?? .standard
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(revision, forKey: .revision)
        try container.encode(timeZoneIdentifier, forKey: .timeZoneIdentifier)
        try container.encode(activityRules, forKey: .activityRules)
        try container.encode(overrides, forKey: .overrides)
        try container.encode(pomodoroMode, forKey: .pomodoroMode)
        try container.encode(pomodoroEnabled, forKey: .pomodoroEnabled)
        try container.encodeIfPresent(dailyUsageThresholdSeconds, forKey: .dailyUsageThresholdSeconds)
        try container.encode(viewingDistancePolicy, forKey: .viewingDistancePolicy)
        try container.encode(defaultReminderStrategy, forKey: .defaultReminderStrategy)
    }

    public static var starter: RuleSet {
        let weekdays = 2...6
        let weekends = [1, 7]
        let game = weekdays.map {
            ScheduleWindow(weekday: $0, startMinute: 18 * 60, endMinute: 20 * 60)
        } + weekends.map {
            ScheduleWindow(weekday: $0, startMinute: 14 * 60, endMinute: 18 * 60)
        }
        let video = weekdays.map {
            ScheduleWindow(weekday: $0, startMinute: 18 * 60, endMinute: 21 * 60)
        } + weekends.map {
            ScheduleWindow(weekday: $0, startMinute: 10 * 60, endMinute: 21 * 60)
        }
        return RuleSet(activityRules: [
            ActivityRule(category: .game, windows: game),
            ActivityRule(category: .video, windows: video),
        ])
    }
}

public struct TemporaryGrant: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var category: ActivityCategory
    public var startsAt: Date
    public var endsAt: Date

    public init(
        id: UUID = UUID(),
        category: ActivityCategory,
        startsAt: Date,
        endsAt: Date
    ) {
        self.id = id
        self.category = category
        self.startsAt = startsAt
        self.endsAt = endsAt
    }

    public func isActive(at date: Date) -> Bool {
        date >= startsAt && date < endsAt
    }
}

public struct ActivityObservation: Codable, Equatable, Sendable {
    public var appName: String
    public var bundleIdentifier: String?
    public var normalizedDomain: String?
    public var processIdentifier: Int32?

    public init(
        appName: String,
        bundleIdentifier: String? = nil,
        normalizedDomain: String? = nil,
        processIdentifier: Int32? = nil
    ) {
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.normalizedDomain = normalizedDomain
        self.processIdentifier = processIdentifier
    }

    public static let idle = ActivityObservation(appName: "")

    public var stableKey: String {
        if let normalizedDomain { return "domain:\(normalizedDomain)" }
        if let bundleIdentifier { return "bundle:\(bundleIdentifier.lowercased())" }
        return "app:\(appName.lowercased())"
    }
}

public struct ClassifiedActivity: Codable, Equatable, Sendable {
    public var observation: ActivityObservation
    public var category: ActivityCategory

    public init(observation: ActivityObservation, category: ActivityCategory) {
        self.observation = observation
        self.category = category
    }
}

public struct DeviceStatus: Codable, Equatable, Sendable {
    public var category: ActivityCategory
    public var lastSeenAt: Date
    public var isOnline: Bool
    /// Total non-idle screen time accumulated for the current local calendar day, all categories combined.
    public var dailyUsageSeconds: Int

    public init(
        category: ActivityCategory,
        lastSeenAt: Date,
        isOnline: Bool = true,
        dailyUsageSeconds: Int = 0
    ) {
        self.category = category
        self.lastSeenAt = lastSeenAt
        self.isOnline = isOnline
        self.dailyUsageSeconds = dailyUsageSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case category, lastSeenAt, isOnline, dailyUsageSeconds
    }

    // Custom decoding: old saved state / old sync payloads won't have dailyUsageSeconds.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        category = try container.decode(ActivityCategory.self, forKey: .category)
        lastSeenAt = try container.decode(Date.self, forKey: .lastSeenAt)
        isOnline = try container.decode(Bool.self, forKey: .isOnline)
        dailyUsageSeconds = try container.decodeIfPresent(Int.self, forKey: .dailyUsageSeconds) ?? 0
    }
}

public enum TemporaryRequestStatus: String, Codable, Sendable {
    case pending
    case approved
    case denied
}

public struct TemporaryRequest: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var category: ActivityCategory
    public var durationMinutes: Int
    /// When the child wants the temporary window to begin. `nil` keeps the legacy
    /// meaning: start immediately once the parent approves.
    public var startsAt: Date?
    public var status: TemporaryRequestStatus
    public var createdAt: Date
    public var resolvedAt: Date?

    public init(
        id: UUID = UUID(),
        category: ActivityCategory,
        durationMinutes: Int,
        startsAt: Date? = nil,
        status: TemporaryRequestStatus = .pending,
        createdAt: Date = Date(),
        resolvedAt: Date? = nil
    ) {
        self.id = id
        self.category = category
        self.durationMinutes = durationMinutes
        self.startsAt = startsAt
        self.status = status
        self.createdAt = createdAt
        self.resolvedAt = resolvedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, category, durationMinutes, startsAt, status, createdAt, resolvedAt
    }

    // Custom decoding: old saved state / old server payloads won't have startsAt.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        category = try container.decode(ActivityCategory.self, forKey: .category)
        durationMinutes = try container.decode(Int.self, forKey: .durationMinutes)
        startsAt = try container.decodeIfPresent(Date.self, forKey: .startsAt)
        status = try container.decode(TemporaryRequestStatus.self, forKey: .status)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        resolvedAt = try container.decodeIfPresent(Date.self, forKey: .resolvedAt)
    }
}

public struct ViolationEvent: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var category: ActivityCategory
    public var appName: String
    public var normalizedDomain: String?
    public var startedAt: Date
    public var durationSeconds: Int
    public var warningCount: Int
    public var wasEnforced: Bool
    public var expiresAt: Date

    public init(
        id: UUID = UUID(),
        category: ActivityCategory,
        appName: String,
        normalizedDomain: String? = nil,
        startedAt: Date,
        durationSeconds: Int = 60,
        warningCount: Int = 2,
        wasEnforced: Bool = false,
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.category = category
        self.appName = appName
        self.normalizedDomain = normalizedDomain
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.warningCount = warningCount
        self.wasEnforced = wasEnforced
        self.expiresAt = expiresAt
            ?? Calendar.current.date(byAdding: .day, value: 30, to: startedAt)
            ?? startedAt.addingTimeInterval(30 * 86_400)
    }
}
