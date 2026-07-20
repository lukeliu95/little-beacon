import Foundation
import Testing
@testable import LittleBeaconApp

// Simulates a real family's on-disk state.json from before dailyUsage/dailyUsageNudgeShown
// existed on LocalSnapshot. LocalStore.load() falls back to a blank LocalSnapshot() if
// decoding throws, so a missing key here must not throw keyNotFound.
@Test func oldStateJSONWithoutUsageFieldsDecodesInsteadOfResetting() throws {
    let oldJSON = """
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
    """.data(using: .utf8)!

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let snapshot = try decoder.decode(LocalSnapshot.self, from: oldJSON)

    #expect(snapshot.role == .child)
    #expect(snapshot.deviceName == "Old Mac")
    #expect(snapshot.dailyUsage.activeSeconds == 0)
    #expect(snapshot.dailyUsageNudgeShown == false)
    #expect(snapshot.rules.pomodoroEnabled == true)
    #expect(snapshot.currentStatus.dailyUsageSeconds == 0)
}
