import Foundation
import Testing
@testable import LittleBeaconApp
@testable import LittleBeaconCore

@Test func pomodoroSessionStoreRestoresAnActiveBreakAcrossRelaunch() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("PomodoroSessionStoreTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let triggeredAt = Date(timeIntervalSince1970: 1_800_000_000)
    let machine = PomodoroBreakMachine(phase: .awaitingAcknowledgement(triggeredAt: triggeredAt))

    let writer = PomodoroSessionStore(directoryURL: directory)
    try writer.save(machine)

    let reader = PomodoroSessionStore(directoryURL: directory)
    #expect(try reader.load() == machine)
}

@Test func pomodoroSessionStoreFallsBackToTheLastKnownGoodFile() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("PomodoroSessionStoreTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = PomodoroSessionStore(directoryURL: directory)
    let lastKnownGood = PomodoroBreakMachine(
        phase: .awaitingAcknowledgement(triggeredAt: Date(timeIntervalSince1970: 1_800_000_000))
    )
    let newer = PomodoroBreakMachine(
        phase: .requiredBreak(
            triggeredAt: Date(timeIntervalSince1970: 1_800_000_000),
            acknowledgedAt: Date(timeIntervalSince1970: 1_800_000_100),
            closeAvailableAt: Date(timeIntervalSince1970: 1_800_000_400)
        )
    )
    try store.save(lastKnownGood)
    try store.save(newer)
    try Data("not-json".utf8).write(to: directory.appendingPathComponent("pomodoro-session.json"))

    #expect(try store.load() == lastKnownGood)
}

@Test func savingAfterFallbackNeverPromotesACorruptMainFileToLastKnownGood() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("PomodoroSessionStoreTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = PomodoroSessionStore(directoryURL: directory)
    let lastKnownGood = PomodoroBreakMachine(
        phase: .awaitingAcknowledgement(triggeredAt: Date(timeIntervalSince1970: 1_800_000_000))
    )
    try store.save(lastKnownGood)
    try store.save(PomodoroBreakMachine())
    try Data("not-json".utf8).write(to: directory.appendingPathComponent("pomodoro-session.json"))

    let recovered = try store.load()
    #expect(recovered == lastKnownGood)
    try store.save(recovered)
    try Data("broken-again".utf8).write(to: directory.appendingPathComponent("pomodoro-session.json"))

    #expect(try store.load() == lastKnownGood)
}
