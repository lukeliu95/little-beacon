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

    mutating func prune(now: Date = Date()) {
        events.removeAll { $0.expiresAt <= now }
        pendingEventIDs.formIntersection(events.map(\.id))
        temporaryGrants.removeAll { $0.endsAt <= now }
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
