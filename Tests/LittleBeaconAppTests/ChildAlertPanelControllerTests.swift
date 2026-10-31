import AppKit
import Testing
@testable import LittleBeaconApp

@Test @MainActor func childAlertAppearsInItsOwnPanelAboveOtherApps() throws {
    _ = NSApplication.shared
    let controller = ChildAlertPanelController()
    defer { controller.hide() }

    controller.show(ChildAlert(title: "休息一下", message: "起来看看远处。", tone: .gentle)) {}

    let contract = try #require(controller.panelContractForTesting)
    #expect(contract.level == NSWindow.Level.floating.rawValue)
    #expect(contract.isBorderless)
    #expect(contract.isNonActivating)
    #expect(contract.joinsAllSpaces)
    #expect(contract.supportsFullScreenAuxiliary)
    #expect(!contract.hidesOnDeactivate)
}

@Test @MainActor func childAlertPanelGoesAwayWhenHidden() {
    _ = NSApplication.shared
    let controller = ChildAlertPanelController()

    controller.show(ChildAlert(title: "小灯塔提醒", message: "第一条", tone: .warning)) {}
    controller.show(ChildAlert(title: "小灯塔提醒", message: "第二条", tone: .warning)) {}
    #expect(controller.panelContractForTesting != nil)

    controller.hide()
    #expect(controller.panelContractForTesting == nil)
}
