import AppKit
import Foundation
import LittleBeaconCore

final class ActivityMonitor {
    private let safariBundleID = "com.apple.Safari"
    private let chromeBundleID = "com.google.Chrome"

    func observeFrontmostActivity() -> ActivityObservation {
        guard let app = NSWorkspace.shared.frontmostApplication else { return .idle }
        let bundleID = app.bundleIdentifier
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

    func enforce(_ activity: ClassifiedActivity) -> Bool {
        let observation = activity.observation
        if observation.bundleIdentifier == safariBundleID {
            return run(script: "tell application \"Safari\" to close current tab of front window") != nil
        }
        if observation.bundleIdentifier == chromeBundleID {
            return run(script: "tell application \"Google Chrome\" to close active tab of front window") != nil
        }
        guard let pid = observation.processIdentifier,
              let app = NSRunningApplication(processIdentifier: pid) else { return false }
        return app.terminate()
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
}
