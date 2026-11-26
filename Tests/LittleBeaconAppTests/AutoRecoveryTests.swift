import Foundation
import Testing
@testable import LittleBeaconApp

private let packagedLaunchAgent = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("../../packaging/launch-agent.plist")
    .standardizedFileURL

@Test func packagedLaunchAgentRestartsAfterEveryExit() throws {
    let data = try Data(contentsOf: packagedLaunchAgent)
    let plist = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])

    #expect(plist["Label"] as? String == AutoRecovery.label)
    #expect(autoRecoveryState(fileExists: true, propertyList: plist) == .active)
    #expect(readAutoRecoveryState(at: packagedLaunchAgent) == .active)
}

@Test func agentFromBeforeThisReleaseOnlyRestartsAfterACrash() {
    let old: [String: Any] = ["Label": AutoRecovery.label, "KeepAlive": ["SuccessfulExit": false]]
    let tenSeconds: [String: Any] = ["Label": AutoRecovery.label, "KeepAlive": true]
    let slow: [String: Any] = ["Label": AutoRecovery.label, "KeepAlive": true, "ThrottleInterval": 10]

    #expect(autoRecoveryState(fileExists: true, propertyList: old) == .outdated)
    #expect(autoRecoveryState(fileExists: true, propertyList: tenSeconds) == .outdated)
    #expect(autoRecoveryState(fileExists: true, propertyList: slow) == .outdated)
    #expect(autoRecoveryState(fileExists: true, propertyList: nil) == .outdated)
    #expect(autoRecoveryState(fileExists: false, propertyList: nil) == .missing)
    #expect(readAutoRecoveryState(at: URL(fileURLWithPath: "/nonexistent/agent.plist")) == .missing)
}

@Test func launchdJobIsToldApartFromALaunchServicesCopy() {
    #expect(isManagedByLaunchAgent(environment: ["XPC_SERVICE_NAME": "app.littlebeacon.mac"]))
    #expect(!isManagedByLaunchAgent(environment: ["XPC_SERVICE_NAME": "application.app.littlebeacon.mac.4594.4595"]))
    #expect(!isManagedByLaunchAgent(environment: ["XPC_SERVICE_NAME": "0"]))
    #expect(!isManagedByLaunchAgent(environment: [:]))
}

@Test func launchdCopyWinsOverEveryOtherCopy() {
    #expect(instanceDecision(isManagedByLaunchAgent: true, otherInstances: []) == .proceed)
    #expect(instanceDecision(isManagedByLaunchAgent: false, otherInstances: []) == .proceed)
    #expect(instanceDecision(isManagedByLaunchAgent: true, otherInstances: [42]) == .replace([42]))
    #expect(instanceDecision(isManagedByLaunchAgent: false, otherInstances: [42]) == .yield)
}

@Test func oldBinaryStepsAsideOnlyWhenTheBundleOnDiskChanged() throws {
    #expect(shouldRestartIntoInstalledBuild(running: "9000", installed: "10000"))
    #expect(!shouldRestartIntoInstalledBuild(running: "9000", installed: "9000"))
    #expect(!shouldRestartIntoInstalledBuild(running: "9000", installed: nil))
    #expect(!shouldRestartIntoInstalledBuild(running: nil, installed: "9000"))

    let bundle = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".app")
    defer { try? FileManager.default.removeItem(at: bundle) }
    try FileManager.default.createDirectory(at: bundle.appendingPathComponent("Contents"), withIntermediateDirectories: true)
    let info = try PropertyListSerialization.data(fromPropertyList: ["CFBundleVersion": "10000"], format: .xml, options: 0)
    try info.write(to: bundle.appendingPathComponent("Contents/Info.plist"))
    #expect(installedBuildNumber(bundleURL: bundle) == "10000")
}

@Test func packagedLaunchAgentRestartsWithinFiveSeconds() throws {
    let data = try Data(contentsOf: packagedLaunchAgent)
    let plist = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    #expect(plist["ThrottleInterval"] as? Int == 5)
}

/// The install script carries its own copy so it can run from a pasted `curl` line.
@Test func installScriptWritesTheSameAgentAsThePackage() throws {
    let script = try String(
        contentsOf: packagedLaunchAgent.deletingLastPathComponent()
            .appendingPathComponent("../scripts/install-auto-recovery.sh").standardizedFileURL,
        encoding: .utf8
    )
    let start = try #require(script.range(of: "<<'PLIST_END'\n"))
    let end = try #require(script.range(of: "\nPLIST_END\n", range: start.upperBound..<script.endIndex))
    let embedded = String(script[start.upperBound..<end.lowerBound]) + "\n"
    #expect(embedded == (try String(contentsOf: packagedLaunchAgent, encoding: .utf8)))
}

@Test func aCopyOutsideLaunchdHandsItselfBack() {
    #expect(handOverStep(state: .active, isManagedByLaunchAgent: false, isLoaded: false) == .bootstrap)
    #expect(handOverStep(state: .active, isManagedByLaunchAgent: false, isLoaded: true) == .kickstart)
    #expect(handOverStep(state: .active, isManagedByLaunchAgent: true, isLoaded: true) == .none)
    #expect(handOverStep(state: .outdated, isManagedByLaunchAgent: false, isLoaded: false) == .none)
    #expect(handOverStep(state: .missing, isManagedByLaunchAgent: false, isLoaded: false) == .none)
}
