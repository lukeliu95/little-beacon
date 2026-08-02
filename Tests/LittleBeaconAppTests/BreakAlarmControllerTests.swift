import Testing
@testable import LittleBeaconApp

@Test @MainActor func breakAlarmUsesAppBundledAudioResources() {
    #expect(BreakAlarmController.hasBundledResources)
}
