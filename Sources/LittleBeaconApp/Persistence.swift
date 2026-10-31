import Foundation
import LittleBeaconCore
import Security

struct LocalSnapshot: Codable {
    var role: DeviceRole = .unconfigured
    var deviceName: String = Host.current().localizedName ?? "这台 Mac"
    var apiBaseURL: String = "https://little-beacon-api.vercel.app"
    var householdID: String?
    var deviceID: String?
    var rules: RuleSet = .starter
    var temporaryGrants: [TemporaryGrant] = []
    var requests: [TemporaryRequest] = []
    var events: [ViolationEvent] = []
    var pendingEventIDs: Set<UUID> = []
    var currentStatus = DeviceStatus(category: .idle, lastSeenAt: .distantPast, isOnline: false)
    var monitoringEnabled = true
    var lastRulesSyncAt: Date?
    var dailyUsage = DailyUsageTracker()
    var dailyUsageNudgeShown = false
    /// Device-local geometric calibration only; never included in family-rule sync.
    var viewingDistanceCalibration: ViewingDistanceCalibration?
    /// Survives a restart so an unfinished ending is neither repeated nor treated as a violation.
    var endingMachine = EndingMachine()
    /// "再玩 5 分钟" grants live apart from `temporaryGrants`, which every sync replaces.
    var extensionGrants: [TemporaryGrant] = []
    var extensionLedger = ExtensionLedger()
    /// On the child: closes on their way, locks, and reports still to upload.
    var remoteControl = RemoteControlState()
    /// On the parent: what was asked of the child Mac and how it went.
    var remoteCommands: [RemoteCommand] = []

    init() {}

    private enum CodingKeys: String, CodingKey {
        case role, deviceName, apiBaseURL, householdID, deviceID, rules, temporaryGrants
        case requests, events, pendingEventIDs, currentStatus, monitoringEnabled, lastRulesSyncAt
        case dailyUsage, dailyUsageNudgeShown, viewingDistanceCalibration
        case endingMachine, extensionGrants, extensionLedger
        case remoteControl, remoteCommands
    }

    // Custom decoding: a real family's existing state.json predates dailyUsage/dailyUsageNudgeShown.
    // Swift's synthesized Decodable throws keyNotFound for a missing key even when the property
    // has a default value, so every new field here is decoded with decodeIfPresent(...) ?? default.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decode(DeviceRole.self, forKey: .role)
        deviceName = try container.decode(String.self, forKey: .deviceName)
        apiBaseURL = try container.decode(String.self, forKey: .apiBaseURL)
        householdID = try container.decodeIfPresent(String.self, forKey: .householdID)
        deviceID = try container.decodeIfPresent(String.self, forKey: .deviceID)
        rules = try container.decode(RuleSet.self, forKey: .rules)
        temporaryGrants = try container.decode([TemporaryGrant].self, forKey: .temporaryGrants)
        requests = try container.decode([TemporaryRequest].self, forKey: .requests)
        events = try container.decode([ViolationEvent].self, forKey: .events)
        pendingEventIDs = try container.decode(Set<UUID>.self, forKey: .pendingEventIDs)
        currentStatus = try container.decode(DeviceStatus.self, forKey: .currentStatus)
        monitoringEnabled = try container.decode(Bool.self, forKey: .monitoringEnabled)
        lastRulesSyncAt = try container.decodeIfPresent(Date.self, forKey: .lastRulesSyncAt)
        dailyUsage = try container.decodeIfPresent(DailyUsageTracker.self, forKey: .dailyUsage) ?? DailyUsageTracker()
        dailyUsageNudgeShown = try container.decodeIfPresent(Bool.self, forKey: .dailyUsageNudgeShown) ?? false
        viewingDistanceCalibration = try container.decodeIfPresent(
            ViewingDistanceCalibration.self,
            forKey: .viewingDistanceCalibration
        )
        endingMachine = try container.decodeIfPresent(EndingMachine.self, forKey: .endingMachine) ?? EndingMachine()
        extensionGrants = try container.decodeIfPresent([TemporaryGrant].self, forKey: .extensionGrants) ?? []
        extensionLedger = try container.decodeIfPresent(ExtensionLedger.self, forKey: .extensionLedger) ?? ExtensionLedger()
        remoteControl = try container.decodeIfPresent(RemoteControlState.self, forKey: .remoteControl) ?? RemoteControlState()
        remoteCommands = try container.decodeIfPresent([RemoteCommand].self, forKey: .remoteCommands) ?? []
    }

    mutating func prune(now: Date = Date()) {
        events.removeAll { $0.expiresAt <= now }
        pendingEventIDs.formIntersection(events.map(\.id))
        temporaryGrants.removeAll { $0.endsAt <= now }
        extensionGrants.removeAll { $0.endsAt <= now }
        remoteControl.prune(now: now)
    }
}

final class LocalStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LittleBeacon", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("state.json")
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> LocalSnapshot {
        guard let data = try? Data(contentsOf: fileURL),
              var snapshot = try? decoder.decode(LocalSnapshot.self, from: data) else {
            return LocalSnapshot()
        }
        if snapshot.apiBaseURL.isEmpty {
            snapshot.apiBaseURL = LocalSnapshot().apiBaseURL
        }
        snapshot.prune()
        return snapshot
    }

    func save(_ snapshot: LocalSnapshot) {
        guard let data = try? encoder.encode(snapshot) else { return }
        let temporaryURL = fileURL.appendingPathExtension("tmp")
        do {
            try data.write(to: temporaryURL, options: .atomic)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: temporaryURL)
            } else {
                try FileManager.default.moveItem(at: temporaryURL, to: fileURL)
            }
        } catch {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

enum KeychainStore {
    private static let service = "app.littlebeacon.credentials"

    static func save(token: String, role: DeviceRole) throws {
        let account = role.rawValue
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var value = query
        value[kSecValueData as String] = data
        let status = SecItemAdd(value as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    static func read(role: DeviceRole) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: role.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(role: DeviceRole) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: role.rawValue,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

struct KeychainError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? { "无法写入钥匙串（\(status)）" }
}
