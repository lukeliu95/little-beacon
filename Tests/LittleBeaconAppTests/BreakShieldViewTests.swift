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

@Test func accessibilityCountdownOnlyChangesAtWholeMinuteBoundaries() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let phase = PomodoroBreakPhase.requiredBreak(
        triggeredAt: now.addingTimeInterval(-1_500),
        acknowledgedAt: now,
        closeAvailableAt: now.addingTimeInterval(299)
    )

    #expect(pomodoroBreakAccessibilityMessage(for: phase, at: now) == "还需要休息 5 分钟。")
    #expect(pomodoroBreakAccessibilityMessage(for: phase, at: now.addingTimeInterval(58)) == "还需要休息 5 分钟。")
    #expect(pomodoroBreakAccessibilityMessage(for: phase, at: now.addingTimeInterval(59)) == "还需要休息 4 分钟。")
    #expect(pomodoroBreakAccessibilityMessage(
        for: .readyToClose(
            triggeredAt: now.addingTimeInterval(-1_500),
            acknowledgedAt: now,
            closeAvailableAt: now.addingTimeInterval(299)
        ),
        at: now.addingTimeInterval(299)
    ) == "休息完成，可以关闭提示并开始下一轮。")
}

@Test func activeBreakAlwaysRequiresAnIndependentRefreshHeartbeat() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    #expect(shouldRunPomodoroRefreshHeartbeat(
        for: .requiredBreak(
            triggeredAt: now.addingTimeInterval(-1_500),
            acknowledgedAt: now,
            closeAvailableAt: now.addingTimeInterval(300)
        )
    ))
    #expect(!shouldRunPomodoroRefreshHeartbeat(for: .counting(activeSeconds: 10, idleSeconds: 0)))
}
