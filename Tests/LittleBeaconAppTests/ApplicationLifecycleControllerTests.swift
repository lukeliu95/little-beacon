import AppKit
import CoreServices
import Testing
@testable import LittleBeaconApp
@testable import LittleBeaconCore

private struct StubParentAuthorizer: ParentAuthorizing {
    let isApproved: Bool

    func authorizeQuit(with credential: QuitCredential) async -> Bool {
        isApproved
    }
}

@MainActor
private final class TerminationReplies {
    var values: [Bool] = []

    func next() async -> Bool {
        while values.isEmpty {
            await Task.yield()
        }
        return values.removeFirst()
    }
}

@MainActor
private func makeController(
    gate: ApplicationTerminationGate,
    isApproved: Bool = false,
    quitReason: OSType? = nil,
    replies: TerminationReplies? = nil,
    explainRefusal: @escaping () -> Void = {},
    stopAutoRecovery: @escaping () -> Void = {}
) -> ApplicationLifecycleController {
    ApplicationLifecycleController(
        gate: gate,
        parentAuthorizer: StubParentAuthorizer(isApproved: isApproved),
        quitReason: { quitReason },
        replyToTermination: { replies?.values.append($0) },
        explainRefusal: explainRefusal,
        stopAutoRecovery: stopAutoRecovery
    )
}

private let sampleExitPassword = ExitPassword.make(from: "1234", iterations: 1_000)!

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

@Test @MainActor func childQuitWaitsForParentAndContinuesWhenApproved() async {
    let gate = ApplicationTerminationGate()
    gate.setQuitPolicy(.requireParent(.administrator))
    let replies = TerminationReplies()
    let controller = makeController(gate: gate, isApproved: true, replies: replies)

    #expect(controller.applicationShouldTerminate(.shared) == .terminateLater)
    #expect(await replies.next())
}

@Test @MainActor func childQuitStaysRunningWhenParentDeclines() async {
    let gate = ApplicationTerminationGate()
    gate.setQuitPolicy(.requireParent(.administrator))
    let replies = TerminationReplies()
    let controller = makeController(gate: gate, isApproved: false, replies: replies)

    #expect(controller.applicationShouldTerminate(.shared) == .terminateLater)
    #expect(await replies.next() == false)
}

@Test @MainActor func secondChildQuitDoesNotOpenAnotherPasswordDialog() async {
    let gate = ApplicationTerminationGate()
    gate.setQuitPolicy(.requireParent(.administrator))
    let replies = TerminationReplies()
    let controller = makeController(gate: gate, isApproved: false, replies: replies)

    #expect(controller.applicationShouldTerminate(.shared) == .terminateLater)
    #expect(controller.applicationShouldTerminate(.shared) == .terminateCancel)
    _ = await replies.next()
    #expect(controller.applicationShouldTerminate(.shared) == .terminateLater)
    _ = await replies.next()
}

@Test @MainActor func approvedQuitIsRefusedIfABreakStartedDuringThePrompt() async {
    let gate = ApplicationTerminationGate()
    gate.setQuitPolicy(.requireParent(.administrator))
    let replies = TerminationReplies()
    let controller = makeController(gate: gate, isApproved: true, replies: replies)

    #expect(controller.applicationShouldTerminate(.shared) == .terminateLater)
    gate.setBreakActive(true)
    #expect(await replies.next() == false)
}

@Test @MainActor func activeBreakStillRefusesAQuitBeforeAskingForThePassword() {
    let gate = ApplicationTerminationGate()
    gate.setQuitPolicy(.requireParent(.administrator))
    gate.setBreakActive(true)

    #expect(makeController(gate: gate, isApproved: true).applicationShouldTerminate(.shared) == .terminateCancel)
}

@Test @MainActor func systemShutdownIsNeverHeldUp() {
    let gate = ApplicationTerminationGate()
    gate.setQuitPolicy(.requireParent(.administrator))
    let controller = makeController(gate: gate, quitReason: OSType(kAEShutDown))

    #expect(controller.applicationShouldTerminate(.shared) == .terminateNow)
    gate.setBreakActive(true)
    #expect(controller.applicationShouldTerminate(.shared) == .terminateNow)
}

@Test func quitReasonsCoverLogoutRestartAndShutdownOnly() {
    for reason in [kAELogOut, kAEReallyLogOut, kAEShowRestartDialog, kAERestart, kAEShowShutdownDialog, kAEShutDown] {
        #expect(isSystemSessionEnding(quitReason: OSType(reason)))
    }
    #expect(!isSystemSessionEnding(quitReason: nil))
    #expect(!isSystemSessionEnding(quitReason: OSType(kAEQuitApplication)))
}

@Test @MainActor func updateRelaunchDoesNotNeedTheParent() {
    let gate = ApplicationTerminationGate()
    gate.setQuitPolicy(.requireParent(.administrator))
    gate.allowUpdateRelaunch()

    #expect(makeController(gate: gate).applicationShouldTerminate(.shared) == .terminateNow)
}

@Test @MainActor func parentMacQuitsNormally() {
    let gate = ApplicationTerminationGate()

    #expect(makeController(gate: gate).applicationShouldTerminate(.shared) == .terminateNow)
}

@Test func onlyAPairedChildMacRunsInTheBackground() {
    #expect(runsInBackground(role: .child, isPaired: true))
    #expect(!runsInBackground(role: .child, isPaired: false))
    #expect(!runsInBackground(role: .parent, isPaired: true))
    #expect(!runsInBackground(role: .unconfigured, isPaired: false))
}

@Test @MainActor func pairedChildWithoutAnExitPasswordExplainsAndKeepsRunning() {
    let gate = ApplicationTerminationGate()
    gate.setQuitPolicy(.refuse)
    var explained = 0

    let controller = makeController(gate: gate, isApproved: true, explainRefusal: { explained += 1 })
    #expect(controller.applicationShouldTerminate(.shared) == .terminateCancel)
    #expect(explained == 1)
}

@Test @MainActor func correctExitPasswordQuitsAndStopsTheRestart() async {
    let gate = ApplicationTerminationGate()
    gate.setQuitPolicy(.requireParent(.exitPassword(sampleExitPassword)))
    var saved = 0
    var stopped = 0
    gate.persistBeforeApprovedQuit = { saved += 1 }
    let replies = TerminationReplies()
    let controller = makeController(gate: gate, isApproved: true, replies: replies, stopAutoRecovery: { stopped += 1 })

    #expect(controller.applicationShouldTerminate(.shared) == .terminateLater)
    #expect(await replies.next())
    #expect(saved == 1)
    #expect(stopped == 1)
}

@Test @MainActor func wrongExitPasswordKeepsTheAppAndTheRestart() async {
    let gate = ApplicationTerminationGate()
    gate.setQuitPolicy(.requireParent(.exitPassword(sampleExitPassword)))
    var stopped = 0
    let replies = TerminationReplies()
    let controller = makeController(gate: gate, isApproved: false, replies: replies, stopAutoRecovery: { stopped += 1 })

    #expect(controller.applicationShouldTerminate(.shared) == .terminateLater)
    #expect(await replies.next() == false)
    #expect(stopped == 0)
}

@Test @MainActor func aBreakStartedDuringThePasswordPromptKeepsTheRestart() async {
    let gate = ApplicationTerminationGate()
    gate.setQuitPolicy(.requireParent(.exitPassword(sampleExitPassword)))
    var stopped = 0
    let replies = TerminationReplies()
    let controller = makeController(gate: gate, isApproved: true, replies: replies, stopAutoRecovery: { stopped += 1 })

    #expect(controller.applicationShouldTerminate(.shared) == .terminateLater)
    gate.setBreakActive(true)
    #expect(await replies.next() == false)
    #expect(stopped == 0)
}

@Test @MainActor func pairedChildStillLetsShutdownAndUpdatesThrough() {
    let gate = ApplicationTerminationGate()
    gate.setQuitPolicy(.refuse)
    #expect(makeController(gate: gate, quitReason: OSType(kAELogOut)).applicationShouldTerminate(.shared) == .terminateNow)

    gate.allowUpdateRelaunch()
    #expect(makeController(gate: gate).applicationShouldTerminate(.shared) == .terminateNow)
}

@Test func quitPolicyFollowsPairingAndTheParentsExitPassword() {
    #expect(ordinaryQuitPolicy(role: .child, isPaired: true) == .refuse)
    #expect(ordinaryQuitPolicy(role: .child, isPaired: true, exitPassword: sampleExitPassword)
        == .requireParent(.exitPassword(sampleExitPassword)))
    #expect(ordinaryQuitPolicy(role: .child, isPaired: false) == .requireParent(.administrator))
    #expect(ordinaryQuitPolicy(role: .child, isPaired: false, exitPassword: sampleExitPassword)
        == .requireParent(.administrator))
    #expect(ordinaryQuitPolicy(role: .parent, isPaired: true, exitPassword: sampleExitPassword) == .allow)
    #expect(ordinaryQuitPolicy(role: .unconfigured, isPaired: false) == .allow)
}
