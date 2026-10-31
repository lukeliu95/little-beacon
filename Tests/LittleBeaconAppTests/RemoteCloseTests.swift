import Foundation
import Testing
@testable import LittleBeaconApp
import LittleBeaconCore

/// An app that quits after a set number of asks, the way a real one might sit on a save dialog.
@MainActor
private final class FakeApplication: ClosableApplication {
    let closableName: String
    var isTerminated = false
    var terminateCalls = 0
    var forceCalls = 0
    private let quitsWhenAsked: Bool
    private let quitsWhenForced: Bool

    init(_ name: String, quitsWhenAsked: Bool = true, quitsWhenForced: Bool = true) {
        closableName = name
        self.quitsWhenAsked = quitsWhenAsked
        self.quitsWhenForced = quitsWhenForced
    }

    func terminate() -> Bool {
        terminateCalls += 1
        if quitsWhenAsked { isTerminated = true }
        return true
    }

    func forceTerminate() -> Bool {
        forceCalls += 1
        if quitsWhenForced { isTerminated = true }
        return true
    }
}

@MainActor
private let quickCloser = ApplicationCloser(politeSeconds: 0.05, forcedSeconds: 0.05, pollSeconds: 0.01)

@Test @MainActor func anAppThatQuitsIsNeverForced() async {
    let app = FakeApplication("Roblox")
    let result = await quickCloser.close([app])
    #expect(result == ApplicationCloseResult(closed: ["Roblox"]))
    #expect(app.forceCalls == 0)
}

@Test @MainActor func anAppThatIgnoresTheRequestIsForced() async {
    let app = FakeApplication("Steam", quitsWhenAsked: false)
    let result = await quickCloser.close([app])
    #expect(result == ApplicationCloseResult(closed: ["Steam"]))
    #expect(app.terminateCalls == 1)
    #expect(app.forceCalls == 1)
}

@Test @MainActor func theRulesNeverForceAnApp() async {
    let app = FakeApplication("Notes", quitsWhenAsked: false)
    let result = await quickCloser.close([app], forcing: false)
    #expect(result == ApplicationCloseResult(failed: ["Notes"]))
    #expect(app.forceCalls == 0)
}

@Test @MainActor func anAppThatSurvivesIsReportedNotHidden() async {
    let stuck = FakeApplication("Stuck", quitsWhenAsked: false, quitsWhenForced: false)
    let fine = FakeApplication("Fine")
    let result = await quickCloser.close([stuck, fine])
    #expect(result == ApplicationCloseResult(closed: ["Fine"], failed: ["Stuck"]))
}

@Test @MainActor func twoWindowsOfOneAppAreNamedOnce() async {
    let result = await quickCloser.close([FakeApplication("Chrome"), FakeApplication("Chrome")])
    #expect(result.closed == ["Chrome"])
}

@Test @MainActor func nothingToCloseEndsAtOnce() async {
    #expect(await quickCloser.close([]) == ApplicationCloseResult())
}

private let baseSync = """
"rules": {"revision": 1, "timeZoneIdentifier": "Asia/Tokyo", "activityRules": [], "overrides": []},
"requests": []
"""

private let serverCommand = """
{
  "id": "6f9619ff-8b86-4d11-b42d-00c04fc964ff",
  "kind": "close",
  "target": "game",
  "lock": "30m",
  "status": "pending",
  "createdAt": "2026-10-31T12:00:00Z",
  "expiresAt": "2026-10-31T12:05:00Z",
  "receivedAt": null,
  "finishedAt": null,
  "outcome": null,
  "closedApps": [],
  "failedApps": [],
  "frontAppName": null,
  "frontAppBundleID": null,
  "lockEndsAt": null
}
"""

@Test func aChildSyncCarriesCommands() throws {
    let json = "{\(baseSync), \"grants\": [], \"commands\": [\(serverCommand)]}"
    let response = try APIJSONCoding.makeDecoder().decode(ChildSyncResponse.self, from: Data(json.utf8))
    #expect(response.commands.first?.lock == .thirtyMinutes)
    #expect(response.commands.first?.target == .game)
}

@Test func aServerWithoutCommandsStillSyncs() throws {
    let child = try APIJSONCoding.makeDecoder().decode(
        ChildSyncResponse.self,
        from: Data("{\(baseSync), \"grants\": []}".utf8)
    )
    let parent = try APIJSONCoding.makeDecoder().decode(
        ParentSyncResponse.self,
        from: Data("{\(baseSync), \"events\": []}".utf8)
    )
    #expect(child.commands.isEmpty)
    #expect(parent.commands.isEmpty)
}

@Test func aCommandFromTheFutureDoesNotBreakTheSync() throws {
    let unknown = serverCommand.replacingOccurrences(of: "\"close\"", with: "\"reboot\"")
    let json = "{\(baseSync), \"grants\": [], \"commands\": [\(unknown), \(serverCommand)]}"
    let response = try APIJSONCoding.makeDecoder().decode(ChildSyncResponse.self, from: Data(json.utf8))
    #expect(response.commands.map(\.kind) == [.close])
    #expect(response.rules.revision == 1)
}

@Test func aReportEncodesWhatTheServerExpects() throws {
    let report = RemoteCommandReport(
        id: UUID(uuidString: "6F9619FF-8B86-4D11-B42D-00C04FC964FF")!,
        status: .finished,
        at: Date(timeIntervalSince1970: 1_800_000_000),
        outcome: .nothingOpen,
        frontAppName: "Stardew",
        frontAppBundleID: "com.example.stardew"
    )
    let json = try #require(
        JSONSerialization.jsonObject(with: APIJSONCoding.makeEncoder().encode(report)) as? [String: Any]
    )
    #expect(json["status"] as? String == "finished")
    #expect(json["outcome"] as? String == "nothingOpen")
    #expect(json["frontAppBundleID"] as? String == "com.example.stardew")
    #expect((json["at"] as? String)?.hasSuffix("Z") == true)
    #expect(json["lockEndsAt"] == nil)
}

@Test func stateSavedBeforeRemoteCloseStillLoads() throws {
    let saved = """
    {
      "role": "child",
      "deviceName": "Old Mac",
      "apiBaseURL": "https://example.com",
      "rules": {"revision": 3, "timeZoneIdentifier": "Asia/Tokyo", "activityRules": [], "overrides": []},
      "temporaryGrants": [],
      "requests": [],
      "events": [],
      "pendingEventIDs": [],
      "currentStatus": {"category": "idle", "lastSeenAt": "2026-07-19T00:00:00Z", "isOnline": false},
      "monitoringEnabled": true
    }
    """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let snapshot = try decoder.decode(LocalSnapshot.self, from: Data(saved.utf8))
    #expect(snapshot.remoteControl == RemoteControlState())
    #expect(snapshot.remoteCommands.isEmpty)
}

@Test func locksAndPendingClosesSurviveARestart() throws {
    var snapshot = LocalSnapshot()
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let command = RemoteCommand(
        kind: .close,
        target: .browser,
        lock: .oneHour,
        createdAt: now,
        expiresAt: now.addingTimeInterval(300)
    )
    _ = snapshot.remoteControl.receive([command], openState: { _ in .app }, at: now)

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let restored = try decoder.decode(LocalSnapshot.self, from: encoder.encode(snapshot))
    #expect(restored.remoteControl.active.map(\.target) == [.browser])
}
