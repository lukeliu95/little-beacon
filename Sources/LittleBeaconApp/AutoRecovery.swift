import AppKit
import Foundation

/// The LaunchAgent that keeps a child Mac's app running (`packaging/launch-agent.plist`, ADR-0016).
enum AutoRecovery {
    static let label = "app.littlebeacon.mac"
    static let installedPropertyList = URL(fileURLWithPath: "/Library/LaunchAgents/app.littlebeacon.mac.plist")
    /// launchd's wait before a restart. Its default is 10 seconds; families expect about five.
    static let restartDelaySeconds = 5
}

enum AutoRecoveryState: Equatable {
    /// Installed and restarts the app within five seconds of every exit.
    case active
    /// Installed by an older script: before 0.10 it only restarted after a crash, and 0.10's
    /// waited launchd's default 10 seconds.
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
    guard (propertyList?["KeepAlive"] as? Bool) == true,
          let delay = propertyList?["ThrottleInterval"] as? Int,
          delay <= AutoRecovery.restartDelaySeconds else { return .outdated }
    return .active
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
            let pids = others.map(\.processIdentifier)
            pids.forEach { kill($0, SIGKILL) }
            // Wait without spinning the run loop: this runs inside App.init, before AppKit has
            // finished launching, and running the loop here left CoreAudio stuck when AppModel
            // then prepared the break sounds (the copy froze with no menu bar icon).
            let deadline = Date().addingTimeInterval(3)
            while pids.contains(where: { kill($0, 0) == 0 }), Date() < deadline {
                usleep(50_000)
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

/// What a copy that launchd does not manage should do so the LaunchAgent takes over again.
enum HandOverStep: Equatable {
    case none
    /// The agent file is there but launchd has not loaded it (a failed install, or a manual bootout).
    case bootstrap
    /// Loaded but not running, for example after Sparkle relaunched the app through Launch Services.
    case kickstart
}

func handOverStep(state: AutoRecoveryState, isManagedByLaunchAgent: Bool, isLoaded: Bool) -> HandOverStep {
    guard state == .active, !isManagedByLaunchAgent else { return .none }
    return isLoaded ? .kickstart : .bootstrap
}

/// Talks to launchd about this Mac's own LaunchAgent. Everything here acts on the logged-in user's
/// own session, so none of it needs an administrator.
enum LaunchAgentControl {
    private static var service: String { "gui/\(getuid())/\(AutoRecovery.label)" }

    /// Only the real app owns the agent; `swift run` and test copies must never touch it.
    private static var ownsTheAgent: Bool {
        Bundle.main.bundlePath.hasSuffix(".app") && Bundle.main.bundleIdentifier == AutoRecovery.label
    }

    /// After a correct exit password: unload the job so launchd does not start the app again. The
    /// file stays, so the next login starts the app as usual. launchd ends this process on the way.
    static func stopForThisLogin() {
        guard ownsTheAgent, isManagedByLaunchAgent() else { return }
        run(["bootout", service])
    }

    /// Lets launchd's copy replace this one, which it does on launch (`SingleInstanceGuard`).
    static func handOverIfNeeded(state: AutoRecoveryState) {
        guard ownsTheAgent else { return }
        let isLoaded = state == .active && run(["print", service]) == 0
        switch handOverStep(state: state, isManagedByLaunchAgent: isManagedByLaunchAgent(), isLoaded: isLoaded) {
        case .none:
            return
        case .bootstrap:
            run(["bootstrap", "gui/\(getuid())", AutoRecovery.installedPropertyList.path])
        case .kickstart:
            run(["kickstart", service])
        }
    }

    @discardableResult
    private static func run(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }
}
