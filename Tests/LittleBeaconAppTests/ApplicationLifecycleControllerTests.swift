import AppKit
import Testing
@testable import LittleBeaconApp

@Test @MainActor func activeBreakRejectsNormalApplicationTermination() {
    let controller = ApplicationLifecycleController()
    let gate = ApplicationTerminationGate.shared
    defer { gate.setBreakActive(false) }

    gate.setBreakActive(false)
    #expect(controller.applicationShouldTerminate(.shared) == .terminateNow)

    gate.setBreakActive(true)
    #expect(controller.applicationShouldTerminate(.shared) == .terminateCancel)
}

@Test @MainActor func postponedUpdateResumesWhenTheBreakCompletes() {
    let gate = ApplicationTerminationGate.shared
    defer { gate.setBreakActive(false) }
    var installerWasInvoked = false
    gate.setBreakActive(true)

    #expect(gate.postponeUpdateUntilBreakCompletes { installerWasInvoked = true })
    #expect(!installerWasInvoked)

    gate.setBreakActive(false)
    #expect(installerWasInvoked)
}
