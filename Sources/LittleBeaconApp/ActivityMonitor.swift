import AppKit
import Foundation
import LittleBeaconCore

@MainActor
protocol ClosableApplication: AnyObject {
    var closableName: String { get }
    var isTerminated: Bool { get }
    @discardableResult func terminate() -> Bool
    @discardableResult func forceTerminate() -> Bool
}

extension NSRunningApplication: ClosableApplication {
    var closableName: String { localizedName ?? bundleIdentifier ?? "未知应用" }
}

struct ApplicationCloseResult: Equatable {
    var closed: [String] = []
    var failed: [String] = []
}

/// Asks apps to quit, then checks they really did. `terminate()` only reports that the request
/// was sent; an app waiting on a save dialog can ignore it, so only `isTerminated` counts.
@MainActor
struct ApplicationCloser {
    var politeSeconds: TimeInterval = 10
    var forcedSeconds: TimeInterval = 3
    var pollSeconds: TimeInterval = 0.2

    /// Only a parent's own close forces: the rules ask politely, because forcing an app sitting on
    /// a save dialog loses work, and the rules also reach apps that are not games.
    func close(_ applications: [any ClosableApplication], forcing: Bool = true) async -> ApplicationCloseResult {
        applications.forEach { $0.terminate() }
        await waitUntilTerminated(applications, seconds: politeSeconds)

        if forcing {
            let stubborn = applications.filter { !$0.isTerminated }
            stubborn.forEach { $0.forceTerminate() }
            await waitUntilTerminated(stubborn, seconds: forcedSeconds)
        }

        var result = ApplicationCloseResult()
        for application in applications {
            if application.isTerminated {
                if !result.closed.contains(application.closableName) { result.closed.append(application.closableName) }
            } else if !result.failed.contains(application.closableName) {
                result.failed.append(application.closableName)
            }
        }
        return result
    }

    private func waitUntilTerminated(_ applications: [any ClosableApplication], seconds: TimeInterval) async {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline, !applications.allSatisfy(\.isTerminated) {
            try? await Task.sleep(for: .seconds(pollSeconds))
        }
    }
}

@MainActor
final class ActivityMonitor {
    private let safariBundleID = "com.apple.Safari"
    private let chromeBundleID = "com.google.Chrome"
    private let inactiveSessionBundleIDs: Set<String> = [
        "com.apple.loginwindow",
        "com.apple.ScreenSaver.Engine",
    ]
    private let closer = ApplicationCloser()

    func observeFrontmostActivity() -> ActivityObservation {
        guard let app = NSWorkspace.shared.frontmostApplication else { return .idle }
        let bundleID = app.bundleIdentifier
        if let bundleID, inactiveSessionBundleIDs.contains(bundleID) {
            return .idle
        }
        var domain: String?
        if bundleID == safariBundleID {
            domain = readDomain(script: "tell application \"Safari\" to get URL of current tab of front window")
        } else if bundleID == chromeBundleID {
            domain = readDomain(script: "tell application \"Google Chrome\" to get URL of active tab of front window")
        }
        return ActivityObservation(
            appName: app.localizedName ?? "未知应用",
            bundleIdentifier: bundleID,
            normalizedDomain: domain,
            processIdentifier: app.processIdentifier
        )
    }

    func enforce(_ activity: ClassifiedActivity) async -> Bool {
        let observation = activity.observation
        if observation.bundleIdentifier == safariBundleID {
            return execute(script: "tell application \"Safari\" to close current tab of front window")
        }
        if observation.bundleIdentifier == chromeBundleID {
            return execute(script: "tell application \"Google Chrome\" to close active tab of front window")
        }
        guard let pid = observation.processIdentifier,
              let app = NSRunningApplication(processIdentifier: pid) else { return false }
        return await closer.close([app], forcing: false).failed.isEmpty
    }

    func runningApplications(
        matching target: RemoteTarget,
        classifier: ActivityClassifier,
        overrides: [ClassificationOverride]
    ) -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { app in
            app.activationPolicy == .regular && !app.isTerminated && classifier.matches(
                target,
                appName: app.localizedName ?? "",
                bundleIdentifier: app.bundleIdentifier,
                overrides: overrides,
                own: Bundle.main.bundleIdentifier
            )
        }
    }

    /// A game played in a browser tab is not an app of its own: it shows up only as the front tab.
    func frontmostBrowserGame(
        classifier: ActivityClassifier,
        overrides: [ClassificationOverride]
    ) -> ClassifiedActivity? {
        let activity = classifier.classify(observeFrontmostActivity(), overrides: overrides)
        guard activity.category == .game,
              activity.observation.normalizedDomain != nil,
              classifier.isBrowser(bundleIdentifier: activity.observation.bundleIdentifier) else { return nil }
        return activity
    }

    func openState(
        of target: RemoteTarget,
        classifier: ActivityClassifier,
        overrides: [ClassificationOverride]
    ) -> RemoteOpenState {
        if !runningApplications(matching: target, classifier: classifier, overrides: overrides).isEmpty { return .app }
        if target == .game, frontmostBrowserGame(classifier: classifier, overrides: overrides) != nil {
            return .browserTabOnly
        }
        return .notOpen
    }

    /// Ends everything the target covers, whether or not it is in front.
    func close(
        _ target: RemoteTarget,
        classifier: ActivityClassifier,
        overrides: [ClassificationOverride]
    ) async -> ApplicationCloseResult {
        var result = ApplicationCloseResult()
        if target == .game, let tab = frontmostBrowserGame(classifier: classifier, overrides: overrides) {
            let name = "\(tab.observation.appName) 里的网页游戏"
            if await enforce(tab) {
                result.closed.append(name)
            } else {
                result.failed.append(name)
            }
        }
        let applications = await closer.close(
            runningApplications(matching: target, classifier: classifier, overrides: overrides)
        )
        result.closed += applications.closed
        result.failed += applications.failed
        return result
    }

    /// What to tell the parent when a close of games found none: the app the child is really in.
    func frontmostApp(classifier: ActivityClassifier) -> RemoteFrontApp? {
        let observation = observeFrontmostActivity()
        guard observation != .idle,
              let bundleIdentifier = observation.bundleIdentifier,
              !classifier.isBrowser(bundleIdentifier: bundleIdentifier),
              !classifier.isProtected(bundleIdentifier: bundleIdentifier, own: Bundle.main.bundleIdentifier) else {
            return nil
        }
        return RemoteFrontApp(name: observation.appName, bundleIdentifier: bundleIdentifier)
    }

    private func readDomain(script: String) -> String? {
        guard let raw = run(script: script), let url = URL(string: raw), let host = url.host else {
            return nil
        }
        let lowered = host.lowercased()
        return lowered.hasPrefix("www.") ? String(lowered.dropFirst(4)) : lowered
    }

    private func run(script: String) -> String? {
        var error: NSDictionary?
        let result = NSAppleScript(source: script)?.executeAndReturnError(&error)
        guard error == nil else { return nil }
        return result?.stringValue
    }

    /// For commands that return nothing, such as `close`: only an error means it did not happen.
    private func execute(script: String) -> Bool {
        var error: NSDictionary?
        _ = NSAppleScript(source: script)?.executeAndReturnError(&error)
        return error == nil
    }
}
