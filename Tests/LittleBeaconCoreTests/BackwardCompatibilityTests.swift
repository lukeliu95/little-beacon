import Foundation
import Testing
@testable import LittleBeaconCore

// A real family's existing backend/on-disk documents predate pomodoroEnabled,
// dailyUsageThresholdSeconds, dailyUsageSeconds, and startsAt. Swift's synthesized Decodable
// throws keyNotFound for a missing key even when the property has a default value, so RuleSet,
// DeviceStatus, and TemporaryRequest decode these new fields manually. These tests guard that
// behavior.

@Test func oldRuleSetJSONDecodesWithDefaultsForNewFields() throws {
    let oldJSON = """
    {"revision":1,"timeZoneIdentifier":"Asia/Tokyo","activityRules":[{"category":"game","windows":[]}],"overrides":[]}
    """.data(using: .utf8)!
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let rules = try decoder.decode(RuleSet.self, from: oldJSON)
    #expect(rules.pomodoroEnabled == true)
    #expect(rules.dailyUsageThresholdSeconds == 7_200)
}

@Test func oldDeviceStatusJSONDecodesWithDefaultForNewField() throws {
    let oldJSON = """
    {"category":"idle","lastSeenAt":"2026-07-20T00:00:00Z","isOnline":false}
    """.data(using: .utf8)!
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let status = try decoder.decode(DeviceStatus.self, from: oldJSON)
    #expect(status.dailyUsageSeconds == 0)
}

@Test func oldTemporaryRequestJSONDecodesWithoutStartsAt() throws {
    let oldJSON = """
    {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","category":"game","durationMinutes":30,\
    "status":"pending","createdAt":"2026-07-20T00:00:00Z"}
    """.data(using: .utf8)!
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let request = try decoder.decode(TemporaryRequest.self, from: oldJSON)
    #expect(request.startsAt == nil)
    #expect(request.resolvedAt == nil)
    #expect(request.durationMinutes == 30)
    #expect(request.status == .pending)
}
