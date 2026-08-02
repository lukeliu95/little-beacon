import AppKit

@MainActor
final class ApplicationTerminationGate {
    static let shared = ApplicationTerminationGate()
    var blocksTermination = false

    private init() {}
}

@MainActor
final class ApplicationLifecycleController: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        ApplicationTerminationGate.shared.blocksTermination ? .terminateCancel : .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
