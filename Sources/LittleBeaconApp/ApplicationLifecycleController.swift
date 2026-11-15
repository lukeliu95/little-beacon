import AppKit
import CoreServices
import LittleBeaconCore

enum TerminationDecision: Equatable {
    case allow
    case reject
    case requireParent
}

/// Logout, restart and shutdown must never be held up by the app; `nil` means an ordinary quit.
func isSystemSessionEnding(quitReason: OSType?) -> Bool {
    guard let quitReason else { return false }
    return [
        OSType(kAELogOut),
        OSType(kAEReallyLogOut),
        OSType(kAEShowRestartDialog),
        OSType(kAERestart),
        OSType(kAEShowShutdownDialog),
        OSType(kAEShutDown),
    ].contains(quitReason)
}

/// An unpaired child Mac stays an ordinary app so the parent can finish pairing in its window.
func runsInBackground(role: DeviceRole, isPaired: Bool) -> Bool {
    role == .child && isPaired
}

/// What an ordinary quit (menu, Cmd-Q, Activity Monitor's "Quit") does on this Mac.
enum OrdinaryQuitPolicy: Equatable {
    case allow
    /// An unpaired child Mac is still being set up, so the parent may close it with their password.
    case requireParent
    /// A paired child Mac has no way out; anything that kills it is restarted by the LaunchAgent.
    case refuse
}

func ordinaryQuitPolicy(role: DeviceRole, isPaired: Bool) -> OrdinaryQuitPolicy {
    guard role == .child else { return .allow }
    return isPaired ? .refuse : .requireParent
}

@MainActor
final class ApplicationTerminationGate {
    static let shared = ApplicationTerminationGate()
    private(set) var blocksTermination = false
    private var quitPolicy: OrdinaryQuitPolicy = .allow
    private var updateIsRelaunching = false
    private var postponedUpdateInstallers: [() -> Void] = []

    init() {}

    func setBreakActive(_ isActive: Bool) {
        blocksTermination = isActive
        guard !isActive, !postponedUpdateInstallers.isEmpty else { return }
        let installers = postponedUpdateInstallers
        postponedUpdateInstallers.removeAll()
        installers.forEach { $0() }
    }

    func setQuitPolicy(_ policy: OrdinaryQuitPolicy) {
        quitPolicy = policy
    }

    /// Sparkle quits through the same path as everyone else; a signed update must not need a parent.
    func allowUpdateRelaunch() {
        updateIsRelaunching = true
    }

    func postponeUpdateUntilBreakCompletes(_ installer: @escaping () -> Void) -> Bool {
        guard blocksTermination else { return false }
        postponedUpdateInstallers.append(installer)
        return true
    }

    func decision(systemSessionIsEnding: Bool) -> TerminationDecision {
        if systemSessionIsEnding { return .allow }
        if blocksTermination { return .reject }
        if updateIsRelaunching { return .allow }
        switch quitPolicy {
        case .allow: return .allow
        case .requireParent: return .requireParent
        case .refuse: return .reject
        }
    }
}

/// Keeps the child Mac's agent running out of the Dock while the parent app stays an ordinary app.
@MainActor
final class ApplicationPresenceController {
    private var activityToken: NSObjectProtocol?

    func apply(role: DeviceRole, isPaired: Bool) {
        NSApplication.shared.setActivationPolicy(runsInBackground(role: role, isPaired: isPaired) ? .accessory : .regular)
        ApplicationTerminationGate.shared.setQuitPolicy(ordinaryQuitPolicy(role: role, isPaired: isPaired))

        guard role == .child else {
            if let activityToken { ProcessInfo.processInfo.endActivity(activityToken) }
            activityToken = nil
            return
        }
        // With no visible window macOS would nap the app and stretch the 1-second rule checks.
        activityToken = activityToken ?? ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "孩子端在后台执行家庭规则"
        )
    }
}

@MainActor
final class ApplicationLifecycleController: NSObject, NSApplicationDelegate {
    private let gate: ApplicationTerminationGate
    private let parentAuthorizer: ParentAuthorizing
    private let quitReason: () -> OSType?
    private let replyToTermination: (Bool) -> Void
    private var isAwaitingParent = false

    override convenience init() {
        self.init(
            gate: .shared,
            parentAuthorizer: AdministratorPasswordAuthorizer(),
            quitReason: { ApplicationLifecycleController.currentQuitReason() },
            replyToTermination: { NSApp.reply(toApplicationShouldTerminate: $0) }
        )
    }

    init(
        gate: ApplicationTerminationGate,
        parentAuthorizer: ParentAuthorizing,
        quitReason: @escaping () -> OSType?,
        replyToTermination: @escaping (Bool) -> Void
    ) {
        self.gate = gate
        self.parentAuthorizer = parentAuthorizer
        self.quitReason = quitReason
        self.replyToTermination = replyToTermination
        super.init()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        switch gate.decision(systemSessionIsEnding: isSystemSessionEnding(quitReason: quitReason())) {
        case .allow:
            return .terminateNow
        case .reject:
            return .terminateCancel
        case .requireParent:
            guard !isAwaitingParent else { return .terminateCancel }
            isAwaitingParent = true
            Task { @MainActor in
                let approved = await parentAuthorizer.authorizeQuit()
                isAwaitingParent = false
                // A break can start while the system dialog is open.
                replyToTermination(approved && !gate.blocksTermination)
            }
            return .terminateLater
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private static func currentQuitReason() -> OSType? {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return nil }
        let keyword = AEKeyword(kAEQuitReason)
        let reason = event.attributeDescriptor(forKeyword: keyword) ?? event.paramDescriptor(forKeyword: keyword)
        return reason?.enumCodeValue
    }
}
