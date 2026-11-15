import AppKit
import Foundation

/// The LaunchAgent that keeps a child Mac's app running (`packaging/launch-agent.plist`, ADR-0016).
enum AutoRecovery {
    static let label = "app.littlebeacon.mac"
    static let installedPropertyList = URL(fileURLWithPath: "/Library/LaunchAgents/app.littlebeacon.mac.plist")
}

enum AutoRecoveryState: Equatable {
    /// Installed and restarts the app after every exit.
    case active
    /// Installed by a version before 0.10, which only restarts the app after a crash.
    case outdated
    case missing

    var childText: String {
        switch self {
        case .active: "自动恢复已开启"
        case .outdated: "自动恢复需要更新，请家长在这台 Mac 上重新运行安装脚本"
        case .missing: "自动恢复未开启，请家长在这台 Mac 上运行安装脚本"
        }
    }
}

func autoRecoveryState(fileExists: Bool, propertyList: [String: Any]?) -> AutoRecoveryState {
    guard fileExists else { return .missing }
    return (propertyList?["KeepAlive"] as? Bool) == true ? .active : .outdated
}

func readAutoRecoveryState(at url: URL = AutoRecovery.installedPropertyList) -> AutoRecoveryState {
    let propertyList = (try? Data(contentsOf: url)).flatMap {
        try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any]
    }
    return autoRecoveryState(fileExists: FileManager.default.fileExists(atPath: url.path), propertyList: propertyList)
}

/// launchd names a job's process after its label; an app opened by Launch Services gets
/// `application.<bundle id>.<numbers>` instead.
func isManagedByLaunchAgent(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
    environment["XPC_SERVICE_NAME"] == AutoRecovery.label
}

enum InstanceDecision: Equatable {
    case proceed
    /// Another copy is already running; this one leaves quietly.
    case yield
    /// This copy belongs to launchd and replaces the ones that do not, so a later kill is restarted.
    case replace([pid_t])
}

func instanceDecision(isManagedByLaunchAgent: Bool, otherInstances: [pid_t]) -> InstanceDecision {
    guard !otherInstances.isEmpty else { return .proceed }
    return isManagedByLaunchAgent ? .replace(otherInstances) : .yield
}

/// The login item and the LaunchAgent can both start the app at login, and a Sparkle relaunch can
/// race launchd's restart. Exactly one copy may enforce the rules, and it should be launchd's.
@MainActor
enum SingleInstanceGuard {
    static func enforce() {
        // `swift run` during development must not quit the family's real copy, or be quit by it.
        guard Bundle.main.bundlePath.hasSuffix(".app"), let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { $0.processIdentifier != ownPID && !$0.isTerminated }
        switch instanceDecision(
            isManagedByLaunchAgent: isManagedByLaunchAgent(),
            otherInstances: others.map(\.processIdentifier)
        ) {
        case .proceed:
            return
        case .yield:
            exit(0)
        case .replace:
            // A paired child refuses an ordinary quit, so only a forced end works. State is
            // persisted every second, and an unfinished break is restored by this copy.
            others.forEach { $0.forceTerminate() }
            let deadline = Date().addingTimeInterval(3)
            while others.contains(where: { !$0.isTerminated }), Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
        }
    }
}

/// Reads the build number from the bundle on disk, which Sparkle or a reinstall may have replaced
/// while this process keeps running the old code.
func installedBuildNumber(bundleURL: URL = Bundle.main.bundleURL) -> String? {
    let url = bundleURL.appendingPathComponent("Contents/Info.plist")
    guard let data = try? Data(contentsOf: url),
          let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
        return nil
    }
    return plist["CFBundleVersion"] as? String
}

/// launchd restarts the old binary right after an update quits it, so that copy has to notice the
/// new bundle and step aside for it.
func shouldRestartIntoInstalledBuild(running: String?, installed: String?) -> Bool {
    guard let running, let installed else { return false }
    return running != installed
}
