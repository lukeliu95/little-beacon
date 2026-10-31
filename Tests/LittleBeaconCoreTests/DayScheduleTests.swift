import Foundation
import Testing
@testable import LittleBeaconCore

private func hours(_ start: Double, _ end: Double) -> DaySlot {
    DaySlot(startMinute: Int(start * 60), endMinute: Int(end * 60))
}

private func times(_ slot: DaySlot?) -> [Int]? {
    slot.map { [$0.startMinute, $0.endMinute] }
}

@Test func moveKeepsTheLengthAndSnapsToQuarterHours() {
    let slot = hours(18, 20)
    let moved = DaySchedule(slots: [slot]).moved(slot, byMinutes: 37)

    #expect(moved.id == slot.id)
    #expect(moved.startMinute == 18 * 60 + 30)
    #expect(moved.length == slot.length)
}

@Test func moveStopsAtTheEdgesOfTheDay() {
    let slot = hours(18, 20)
    let schedule = DaySchedule(slots: [slot])

    #expect(times(schedule.moved(slot, byMinutes: -5_000)) == [0, 120])
    #expect(times(schedule.moved(slot, byMinutes: 5_000)) == [1_320, 1_440])
}

@Test func moveStopsAgainstItsNeighbours() {
    let morning = hours(9, 10)
    let evening = hours(18, 20)
    let late = hours(21, 22)
    let schedule = DaySchedule(slots: [morning, evening, late])

    #expect(times(schedule.moved(evening, byMinutes: 300)) == [19 * 60, 21 * 60])
    #expect(times(schedule.moved(evening, byMinutes: -900)) == [10 * 60, 12 * 60])
}

@Test func resizeKeepsTheMinimumLengthAndTheOtherEnd() {
    let slot = hours(18, 20)
    let schedule = DaySchedule(slots: [slot])

    #expect(times(schedule.resizedStart(slot, toMinute: 19 * 60 + 50)) == [19 * 60 + 30, 20 * 60])
    #expect(times(schedule.resizedEnd(slot, toMinute: 18 * 60 + 5)) == [18 * 60, 18 * 60 + 30])
    #expect(times(schedule.resizedStart(slot, toMinute: 16 * 60 + 52)) == [16 * 60 + 45, 20 * 60])
    #expect(times(schedule.resizedEnd(slot, toMinute: 21 * 60 + 8)) == [18 * 60, 21 * 60 + 15])
}

@Test func resizeStopsAgainstNeighboursAndTheEndOfTheDay() {
    let first = hours(9, 10)
    let second = hours(12, 13)
    let last = hours(23, 23.5)
    let schedule = DaySchedule(slots: [first, second, last])

    #expect(times(schedule.resizedEnd(first, toMinute: 14 * 60)) == [9 * 60, 12 * 60])
    #expect(times(schedule.resizedStart(second, toMinute: 8 * 60)) == [10 * 60, 13 * 60])
    #expect(times(schedule.resizedEnd(last, toMinute: 2_000)) == [23 * 60, 1_440])
}

@Test func typedTimesKeepTheirExactMinutes() {
    let slot = hours(18, 20)
    let schedule = DaySchedule(slots: [slot])

    #expect(times(schedule.resizedStart(slot, toMinute: 18 * 60 + 7, snapping: false)) == [18 * 60 + 7, 20 * 60])
    #expect(times(schedule.resizedEnd(slot, toMinute: 20 * 60 + 13, snapping: false)) == [18 * 60, 20 * 60 + 13])
}

@Test func drawingWorksInBothDirectionsAndSnaps() {
    let empty = DaySchedule(slots: [])

    #expect(times(empty.drawnSlot(from: 9 * 60 + 4, to: 11 * 60 + 8)) == [9 * 60, 11 * 60 + 15])
    #expect(times(empty.drawnSlot(from: 11 * 60, to: 9 * 60)) == [9 * 60, 11 * 60])
}

@Test func aShortDrawStillMakesAUsableSlot() {
    let empty = DaySchedule(slots: [])

    #expect(times(empty.drawnSlot(from: 600, to: 605)) == [600, 630])
    #expect(times(empty.drawnSlot(from: 1_435, to: 1_438)) == [1_410, 1_440])
}

@Test func drawingStopsAtTheNeighbouringSlot() {
    let schedule = DaySchedule(slots: [hours(12, 13)])

    #expect(times(schedule.drawnSlot(from: 10 * 60, to: 15 * 60)) == [10 * 60, 12 * 60])
    #expect(times(schedule.drawnSlot(from: 14 * 60, to: 9 * 60)) == [13 * 60, 14 * 60])
}

@Test func drawingNeedsAGapThatFitsTheMinimum() {
    let schedule = DaySchedule(slots: [hours(9, 10), DaySlot(startMinute: 615, endMinute: 660)])

    #expect(schedule.drawnSlot(from: 605, to: 610) == nil)
    #expect(schedule.drawnSlot(from: 9 * 60 + 30, to: 11 * 60) == nil)
}

@Test func addingPrefersTheEveningAndFallsBackToTheLargestGap() {
    #expect(times(DaySchedule(slots: []).suggestedSlot()) == [18 * 60, 20 * 60])
    #expect(times(DaySchedule(slots: [hours(17, 22)]).suggestedSlot()) == [0, 120])
    #expect(DaySchedule(slots: [hours(0, 24)]).suggestedSlot() == nil)
}

@Test func addingNearTheEndOfTheDayStaysInsideIt() {
    let schedule = DaySchedule(slots: [hours(0, 17), hours(19, 24)])
    #expect(times(schedule.suggestedSlot()) == [18 * 60, 19 * 60])
}

@Test func windowsBecomeSortedTidySlots() {
    let schedule = DaySchedule(windows: [
        ScheduleWindow(weekday: 2, startMinute: 18 * 60, endMinute: 20 * 60),
        ScheduleWindow(weekday: 2, startMinute: 9 * 60, endMinute: 10 * 60),
        ScheduleWindow(weekday: 2, startMinute: 19 * 60, endMinute: 21 * 60),
        ScheduleWindow(weekday: 2, startMinute: 700, endMinute: 700),
    ])

    #expect(schedule.slots.map { [$0.startMinute, $0.endMinute] } == [[540, 600], [1_080, 1_260]])
}

@Test func windowCrossingMidnightIsEditedAsItsTwoRealParts() {
    let window = ScheduleWindow(weekday: 2, startMinute: 22 * 60, endMinute: 60)
    let first = DaySchedule(windows: [window])
    let second = DaySchedule(windows: [window])

    #expect(first.slots.map { [$0.startMinute, $0.endMinute] } == [[0, 60], [1_320, 1_440]])
    #expect(first.slots.map(\.id) == second.slots.map(\.id))
    #expect(first.slot(id: window.id)?.startMinute == 1_320)
}

@Test func slotsTheEditorSavesBehaveTheSameAsTheMidnightWindowTheyCameFrom() {
    let window = ScheduleWindow(weekday: 2, startMinute: 22 * 60, endMinute: 60)
    var original = RuleSet(timeZoneIdentifier: "Asia/Tokyo", activityRules: [
        ActivityRule(category: .game, windows: [window]),
    ])
    let saved = { () -> RuleSet in
        var copy = original
        copy.setSchedule(copy.daySchedule(for: .game, weekday: 2), for: .game, weekday: 2)
        return copy
    }()
    original.revision = saved.revision

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    for hour in 0..<24 {
        let date = calendar.date(from: DateComponents(year: 2026, month: 7, day: 20, hour: hour, minute: 30))!
        let evaluator = RuleEvaluator()
        #expect(
            evaluator.isAllowed(category: .game, at: date, rules: saved, temporaryGrants: [])
                == evaluator.isAllowed(category: .game, at: date, rules: original, temporaryGrants: [])
        )
    }
}

@Test func slotsThatTouchBecomeOneContinuousSlot() {
    let afternoon = hours(14, 18)
    let schedule = DaySchedule(slots: [afternoon])
    let drawn = schedule.drawnSlot(from: 12 * 60, to: 16 * 60)

    #expect(times(drawn) == [12 * 60, 14 * 60])
    let merged = schedule.applying(drawn!)
    #expect(merged.slots.map { [$0.startMinute, $0.endMinute] } == [[12 * 60, 18 * 60]])
    #expect(merged.slots.first?.id == drawn?.id)
}

@Test func applyingAndRemovingKeepOtherSlots() {
    let morning = hours(9, 10)
    let evening = hours(18, 20)
    let schedule = DaySchedule(slots: [evening, morning])

    let moved = schedule.applying(schedule.moved(evening, byMinutes: 60))
    #expect(moved.slots.map(\.id) == [morning.id, evening.id])
    #expect(moved.slot(id: evening.id)?.startMinute == 19 * 60)
    #expect(schedule.removing(id: morning.id).slots.map(\.id) == [evening.id])
}

@Test func savingADayIsOneRuleChangeAndLeavesOtherDaysAlone() {
    var set = RuleSet.starter
    let revision = set.revision
    let tuesday = set.daySchedule(for: .game, weekday: 3)
    let schedule = DaySchedule(slots: [hours(7, 8), hours(19, 21)])

    set.setSchedule(schedule, for: .game, weekday: 2)

    #expect(set.revision == revision + 1)
    #expect(set.daySchedule(for: .game, weekday: 2).slots == schedule.slots)
    #expect(set.daySchedule(for: .game, weekday: 3) == tuesday)
}

@Test func clearingADayMeansNoSlotsForThatCategoryOnly() {
    var set = RuleSet.starter
    let video = set.daySchedule(for: .video, weekday: 2)

    set.setSchedule(DaySchedule(slots: []), for: .game, weekday: 2)

    #expect(set.daySchedule(for: .game, weekday: 2).slots.isEmpty)
    #expect(set.daySchedule(for: .video, weekday: 2) == video)
}

@Test func copyingADayKeepsAllItsSlotsAndIsOneRuleChange() {
    var set = RuleSet.starter
    set.setSchedule(DaySchedule(slots: [hours(7, 8), hours(19, 21)]), for: .game, weekday: 2)
    let revision = set.revision
    let saturday = set.daySchedule(for: .game, weekday: 7)

    set.copySchedule(for: .game, from: 2, to: Array(2...6))

    #expect(set.revision == revision + 1)
    for weekday in 2...6 {
        #expect(set.daySchedule(for: .game, weekday: weekday).slots.map(\.startMinute) == [7 * 60, 19 * 60])
    }
    #expect(set.daySchedule(for: .game, weekday: 7) == saturday)
    let ids = set.activityRules.first { $0.category == .game }!.windows.map(\.id)
    #expect(Set(ids).count == ids.count)
}
