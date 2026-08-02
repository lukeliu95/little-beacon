import AppKit
import Testing
@testable import LittleBeaconApp

@Test @MainActor func activeBreakRejectsNormalApplicationTermination() {
    let controller = ApplicationLifecycleController()
    let gate = ApplicationTerminationGate.shared
    defer { gate.blocksTermination = false }

    gate.blocksTermination = false
    #expect(controller.applicationShouldTerminate(.shared) == .terminateNow)

    gate.blocksTermination = true
    #expect(controller.applicationShouldTerminate(.shared) == .terminateCancel)
}
