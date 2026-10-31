import Foundation

/// One editable stretch of a weekday, always inside a single calendar day.
public struct DaySlot: Equatable, Identifiable, Sendable {
    public var id: UUID
    public var startMinute: Int
    public var endMinute: Int
    public var reminderStrategy: ReminderStrategy?

    public init(
        id: UUID = UUID(),
        startMinute: Int,
        endMinute: Int,
        reminderStrategy: ReminderStrategy? = nil
    ) {
        self.id = id
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.reminderStrategy = reminderStrategy
    }

    public var length: Int { endMinute - startMinute }
}

/// The slots of one weekday: sorted, inside the day and never overlapping. Every edit returns a
/// proposal that respects those rules, so a drag can be previewed and only saved when it ends.
public struct DaySchedule: Equatable, Sendable {
    public static let dayMinutes = 1_440
    public static let snapMinutes = 15
    public static let minimumMinutes = 30

    public private(set) var slots: [DaySlot]

    public init(slots: [DaySlot]) {
        self.slots = Self.tidied(slots)
    }

    public init(windows: [ScheduleWindow]) {
        self.init(slots: windows.flatMap(Self.slots(of:)))
    }

    public func slot(id: UUID) -> DaySlot? {
        slots.first { $0.id == id }
    }

    public func moved(_ slot: DaySlot, byMinutes delta: Int) -> DaySlot {
        let room = room(around: slot)
        let start = Self.snapped(slot.startMinute + delta)
        let clamped = min(room.upperBound - slot.length, max(room.lowerBound, start))
        var moved = slot
        moved.startMinute = clamped
        moved.endMinute = clamped + slot.length
        return moved
    }

    /// Dragging snaps; a time typed into a field is kept to the minute.
    public func resizedStart(_ slot: DaySlot, toMinute minute: Int, snapping: Bool = true) -> DaySlot {
        let room = room(around: slot)
        let latest = slot.endMinute - Self.minimumMinutes
        var resized = slot
        resized.startMinute = min(latest, max(room.lowerBound, snapping ? Self.snapped(minute) : minute))
        return resized
    }

    public func resizedEnd(_ slot: DaySlot, toMinute minute: Int, snapping: Bool = true) -> DaySlot {
        let room = room(around: slot)
        let earliest = slot.startMinute + Self.minimumMinutes
        var resized = slot
        resized.endMinute = max(earliest, min(room.upperBound, snapping ? Self.snapped(minute) : minute))
        return resized
    }

    /// A slot drawn from where the pointer went down to where it is now. Drawing stops at the
    /// neighbouring slots; `nil` means that gap is too small to hold one.
    public func drawnSlot(id: UUID = UUID(), from anchor: Int, to current: Int) -> DaySlot? {
        let gap = gap(containing: anchor)
        guard let gap, gap.upperBound - gap.lowerBound >= Self.minimumMinutes else { return nil }
        let low = min(gap.upperBound, max(gap.lowerBound, Self.snapped(min(anchor, current))))
        let high = min(gap.upperBound, max(gap.lowerBound, Self.snapped(max(anchor, current))))
        let end = max(high, min(gap.upperBound, low + Self.minimumMinutes))
        return DaySlot(id: id, startMinute: min(low, end - Self.minimumMinutes), endMinute: end)
    }

    /// Where "add a slot" should land: the preferred stretch, or the first gap with room.
    public func suggestedSlot(preferredStart: Int = 18 * 60, length: Int = 120) -> DaySlot? {
        let free = gaps.filter { $0.upperBound - $0.lowerBound >= Self.minimumMinutes }
        guard let gap = free.first(where: { $0.contains(preferredStart) && $0.upperBound > preferredStart + Self.minimumMinutes })
            ?? free.max(by: { $0.upperBound - $0.lowerBound < $1.upperBound - $1.lowerBound }) else {
            return nil
        }
        let start = gap.contains(preferredStart) ? preferredStart : gap.lowerBound
        return DaySlot(startMinute: start, endMinute: min(gap.upperBound, start + length))
    }

    public func applying(_ slot: DaySlot) -> DaySchedule {
        DaySchedule(slots: slots.filter { $0.id != slot.id } + [slot])
    }

    public func removing(id: UUID) -> DaySchedule {
        DaySchedule(slots: slots.filter { $0.id != id })
    }

    private func room(around slot: DaySlot) -> Range<Int> {
        let others = slots.filter { $0.id != slot.id }
        let lower = others.filter { $0.startMinute < slot.startMinute }.map(\.endMinute).max() ?? 0
        let upper = others.filter { $0.startMinute > slot.startMinute }.map(\.startMinute).min() ?? Self.dayMinutes
        return lower..<upper
    }

    private var gaps: [Range<Int>] {
        var result: [Range<Int>] = []
        var cursor = 0
        for slot in slots {
            if slot.startMinute > cursor { result.append(cursor..<slot.startMinute) }
            cursor = max(cursor, slot.endMinute)
        }
        if cursor < Self.dayMinutes { result.append(cursor..<Self.dayMinutes) }
        return result
    }

    private func gap(containing minute: Int) -> Range<Int>? {
        gaps.first { $0.contains(minute) }
    }

    private static func snapped(_ minute: Int) -> Int {
        Int((Double(minute) / Double(snapMinutes)).rounded()) * snapMinutes
    }

    /// A window that crosses midnight means both ends of the same weekday to the rule evaluator,
    /// so it is edited as the two stretches it really is.
    private static func slots(of window: ScheduleWindow) -> [DaySlot] {
        guard window.startMinute > window.endMinute else {
            return [DaySlot(
                id: window.id,
                startMinute: window.startMinute,
                endMinute: window.endMinute,
                reminderStrategy: window.reminderStrategy
            )]
        }
        return [
            DaySlot(
                id: siblingID(of: window.id),
                startMinute: 0,
                endMinute: window.endMinute,
                reminderStrategy: window.reminderStrategy
            ),
            DaySlot(
                id: window.id,
                startMinute: window.startMinute,
                endMinute: dayMinutes,
                reminderStrategy: window.reminderStrategy
            ),
        ]
    }

    /// Stable across renders, so a selected half of a midnight window stays selected.
    private static func siblingID(of id: UUID) -> UUID {
        var bytes = id.uuid
        bytes.0 ^= 0xFF
        return UUID(uuid: bytes)
    }

    private static func tidied(_ slots: [DaySlot]) -> [DaySlot] {
        var result: [DaySlot] = []
        let valid = slots
            .map {
                DaySlot(
                    id: $0.id,
                    startMinute: max(0, $0.startMinute),
                    endMinute: min(dayMinutes, $0.endMinute),
                    reminderStrategy: $0.reminderStrategy
                )
            }
            .filter { $0.endMinute > $0.startMinute }
            .sorted { $0.startMinute < $1.startMinute }
        for slot in valid {
            if let last = result.last, slot.startMinute <= last.endMinute {
                result[result.count - 1].endMinute = max(last.endMinute, slot.endMinute)
            } else {
                result.append(slot)
            }
        }
        return result
    }
}

public extension RuleSet {
    func daySchedule(for category: ActivityCategory, weekday: Int) -> DaySchedule {
        let windows = activityRules.first { $0.category == category }?.windows ?? []
        return DaySchedule(windows: windows.filter { $0.weekday == weekday })
    }

    /// Replaces one weekday and counts as one rule change.
    mutating func setSchedule(_ schedule: DaySchedule, for category: ActivityCategory, weekday: Int) {
        guard let index = activityRules.firstIndex(where: { $0.category == category }) else { return }
        activityRules[index].windows.removeAll { $0.weekday == weekday }
        activityRules[index].windows += schedule.slots.map {
            ScheduleWindow(
                id: $0.id,
                weekday: weekday,
                startMinute: $0.startMinute,
                endMinute: $0.endMinute,
                reminderStrategy: $0.reminderStrategy
            )
        }
        revision += 1
    }

    /// Copies one weekday onto others and counts as one rule change, so applying it to a whole
    /// week uploads once.
    mutating func copySchedule(for category: ActivityCategory, from source: Int, to weekdays: [Int]) {
        guard let index = activityRules.firstIndex(where: { $0.category == category }) else { return }
        let schedule = daySchedule(for: category, weekday: source)
        let targets = weekdays.filter { $0 != source }
        activityRules[index].windows.removeAll { targets.contains($0.weekday) }
        activityRules[index].windows += targets.flatMap { weekday in
            schedule.slots.map {
                ScheduleWindow(
                    weekday: weekday,
                    startMinute: $0.startMinute,
                    endMinute: $0.endMinute,
                    reminderStrategy: $0.reminderStrategy
                )
            }
        }
        revision += 1
    }
}
