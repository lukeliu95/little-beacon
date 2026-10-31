import AppKit
import Foundation
import Testing
@testable import LittleBeaconApp
@testable import LittleBeaconCore

private let message = ReminderMessage(title: "还有 5 分钟", body: "游戏快结束了，记得存档。")

@Test @MainActor func cornerNoteNeverTakesTheKeyboard() {
    _ = NSApplication.shared
    let toast = ChildToastController()
    defer { toast.hide() }

    toast.show(message)

    #expect(toast.isShowingForTesting)
    #expect(toast.panelIsNonActivatingForTesting)
    toast.hide()
    #expect(!toast.isShowingForTesting)
}

@Test @MainActor func dimmingLeavesTheScreenUsable() {
    _ = NSApplication.shared
    let dimmer = ScreenDimController()
    defer { dimmer.hide() }

    dimmer.show()
    dimmer.show()

    let contracts = dimmer.panelContractsForTesting
    #expect(contracts.count == NSScreen.screens.count)
    for contract in contracts {
        #expect(contract.ignoresMouse)
        #expect(contract.isNonActivating)
        #expect(contract.joinsAllSpaces)
    }
    dimmer.hide()
    #expect(!dimmer.isDimming)
}

@Test @MainActor func fullScreenReminderCanBeClosed() {
    _ = NSApplication.shared
    let shield = ReminderShieldController()
    defer { shield.hide() }

    shield.show(message)
    #expect(shield.isShowing == !NSScreen.screens.isEmpty)
    shield.hide()
    #expect(!shield.isShowing)
}

@Test func stateSavedBeforeStrategiesStillLoads() throws {
    var original = LocalSnapshot()
    original.role = .child
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    var object = try #require(try JSONSerialization.jsonObject(with: encoder.encode(original)) as? [String: Any])
    object.removeValue(forKey: "endingMachine")
    object.removeValue(forKey: "extensionGrants")
    object.removeValue(forKey: "extensionLedger")

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let restored = try decoder.decode(LocalSnapshot.self, from: JSONSerialization.data(withJSONObject: object))

    #expect(restored.role == .child)
    #expect(restored.extensionGrants.isEmpty)
    #expect(restored.endingMachine == EndingMachine())
}

@Test func expiredExtensionsArePruned() {
    let now = Date()
    var snapshot = LocalSnapshot()
    snapshot.extensionGrants = [
        TemporaryGrant(category: .game, startsAt: now.addingTimeInterval(-600), endsAt: now.addingTimeInterval(-300)),
        TemporaryGrant(category: .game, startsAt: now, endsAt: now.addingTimeInterval(300)),
    ]

    snapshot.prune(now: now)

    #expect(snapshot.extensionGrants.count == 1)
}
