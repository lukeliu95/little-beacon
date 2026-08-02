import Foundation
import LittleBeaconCore

enum PomodoroSessionStoreError: LocalizedError {
    case unreadable
    case unsupportedSchema(Int)

    var errorDescription: String? {
        switch self {
        case .unreadable:
            "番茄钟恢复数据无法读取"
        case let .unsupportedSchema(version):
            "番茄钟恢复数据版本不受支持（\(version)）"
        }
    }
}

private struct PomodoroSessionEnvelope: Codable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var machine: PomodoroBreakMachine

    init(machine: PomodoroBreakMachine) {
        schemaVersion = Self.currentSchemaVersion
        self.machine = machine
    }
}

protocol PomodoroSessionPersisting: AnyObject {
    func load() throws -> PomodoroBreakMachine
    func save(_ machine: PomodoroBreakMachine) throws
}

final class PomodoroSessionStore: PomodoroSessionPersisting {
    private let directoryURL: URL
    private let fileURL: URL
    private let backupURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(directoryURL: URL? = nil) {
        let base = directoryURL
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("LittleBeacon", isDirectory: true)
        self.directoryURL = base
        fileURL = base.appendingPathComponent("pomodoro-session.json")
        backupURL = base.appendingPathComponent("pomodoro-session.last-good.json")
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() throws -> PomodoroBreakMachine {
        let mainExists = FileManager.default.fileExists(atPath: fileURL.path)
        let backupExists = FileManager.default.fileExists(atPath: backupURL.path)
        if !mainExists && !backupExists {
            return PomodoroBreakMachine()
        }

        if mainExists, let machine = try? decode(at: fileURL) {
            return machine
        }
        if backupExists, let machine = try? decode(at: backupURL) {
            return machine
        }
        throw PomodoroSessionStoreError.unreadable
    }

    func save(_ machine: PomodoroBreakMachine) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try encoder.encode(PomodoroSessionEnvelope(machine: machine))
        // A save is not successful until both independently atomic files contain the same
        // newest state. Keeping the previous generation as "last good" can silently erase a
        // just-triggered shield when the main file is later damaged.
        try data.write(to: fileURL, options: .atomic)
        try data.write(to: backupURL, options: .atomic)
    }

    private func decode(at url: URL) throws -> PomodoroBreakMachine {
        let envelope = try decoder.decode(PomodoroSessionEnvelope.self, from: Data(contentsOf: url))
        guard envelope.schemaVersion == PomodoroSessionEnvelope.currentSchemaVersion else {
            throw PomodoroSessionStoreError.unsupportedSchema(envelope.schemaVersion)
        }
        return envelope.machine
    }
}
