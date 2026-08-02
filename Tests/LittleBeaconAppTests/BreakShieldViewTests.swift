import Foundation
import Testing
@testable import LittleBeaconApp
@testable import LittleBeaconCore

@Test func requiredBreakMessageFormatsTheVisibleCountdown() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let phase = PomodoroBreakPhase.requiredBreak(
        triggeredAt: now.addingTimeInterval(-1_500),
        acknowledgedAt: now,
        closeAvailableAt: now.addingTimeInterval(287)
    )

    #expect(pomodoroBreakMessage(for: phase, at: now) == "再休息 4:47。看看远处，喝口水，手先别急着找鼠标。")
}
