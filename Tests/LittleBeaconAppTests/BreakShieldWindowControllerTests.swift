import AppKit
import Foundation
import Testing
@testable import LittleBeaconApp
@testable import LittleBeaconCore

@Test @MainActor func shieldCreatesOneNonClosableTopLevelPanelPerScreen() {
    _ = NSApplication.shared
    let controller = BreakShieldWindowController()
    controller.present(
        phase: .awaitingAcknowledgement(triggeredAt: Date()),
        acknowledge: {},
        close: {}
    )
    defer { controller.dismiss() }

    let contracts = controller.panelContractsForTesting
    #expect(contracts.count == NSScreen.screens.count)
    // `swift test` may run without a WindowServer screen (including CI). On a desktop session,
    // the loop below verifies every real screen; the live QA record covers the visible panel.
    for contract in contracts {
        #expect(contract.level == NSWindow.Level.screenSaver.rawValue)
        #expect(contract.isBorderless)
        #expect(!contract.hasCloseButton)
        #expect(contract.joinsAllSpaces)
        #expect(contract.supportsFullScreenAuxiliary)
        #expect(!contract.hidesOnDeactivate)
    }
}
