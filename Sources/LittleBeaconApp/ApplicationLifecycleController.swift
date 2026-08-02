import AppKit

@MainActor
final class ApplicationTerminationGate {
    static let shared = ApplicationTerminationGate()
    private(set) var blocksTermination = false
    private var postponedUpdateInstallers: [() -> Void] = []

    private init() {}

    func setBreakActive(_ isActive: Bool) {
        blocksTermination = isActive
        guard !isActive, !postponedUpdateInstallers.isEmpty else { return }
        let installers = postponedUpdateInstallers
        postponedUpdateInstallers.removeAll()
        installers.forEach { $0() }
    }

    func postponeUpdateUntilBreakCompletes(_ installer: @escaping () -> Void) -> Bool {
        guard blocksTermination else { return false }
        postponedUpdateInstallers.append(installer)
        return true
    }
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
