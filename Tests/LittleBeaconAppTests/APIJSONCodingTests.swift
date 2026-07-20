import Foundation
import Testing
@testable import LittleBeaconApp

@Test func childSyncDecodesDatesWithAndWithoutFractionalSeconds() throws {
    let payload = #"{"rules":{"revision":42,"timeZoneIdentifier":"Asia/Tokyo","activityRules":[{"category":"game","windows":[{"id":"E5F33C1D-0CE8-449C-90E8-BCF062B328B3","weekday":2,"startMinute":1080,"endMinute":1200}]},{"category":"video","windows":[]}],"overrides":[]},"grants":[],"requests":[{"id":"DC85AF7A-FE1C-466C-9737-610A1B1AA27B","category":"game","durationMinutes":15,"status":"pending","createdAt":"2026-07-20T12:34:56.123Z","resolvedAt":"2026-07-20T12:35:00Z"}]}"#.data(using: .utf8)!

    let response = try APIJSONCoding.makeDecoder().decode(ChildSyncResponse.self, from: payload)

    #expect(response.rules.revision == 42)
    #expect(response.requests.count == 1)
}
