import Foundation

/// What an edit did to the routine being built, for the chat to report.
enum AskDraftChange: Equatable {
    case cleared
    /// Names of what was removed, in routine order (a Left/Right pair by its shared name).
    case removed([String])
    case swapped(from: String, to: String)
    case retimed(totalSeconds: Int)
    /// The routine is empty, or nothing in it matched.
    case nothingToChange
}

/// The mini routine an Ask chat builds up request by request. Requests add to it; only an
/// explicit "new routine" replaces it. Held in memory by `AskChatModel`, never saved.
/// A Left/Right pair is always one slot: it is added, removed, swapped and timed together.
struct AskDraft {
    private(set) var exercises: [Exercise] = []
    private(set) var durationOverrides: [UUID: Int] = [:]
    /// True once a gentle ("show gentle stretches anyway") batch is in, so the routine
    /// keeps its "stop immediately" warning and swaps stay gentle.
    private(set) var isGentle = false
    /// The last request that added exercises: "another one" and "2 more" take their area here.
    private(set) var lastIntent: AskIntent?

    var isEmpty: Bool { exercises.isEmpty }
    var ids: Set<UUID> { Set(exercises.map(\.uuid)) }

    func seconds(for exercise: Exercise) -> Int {
        durationOverrides[exercise.uuid] ?? exercise.durationSeconds
    }

    var totalSeconds: Int { exercises.reduce(0) { $0 + seconds(for: $1) } }

    /// The whole draft as one playable routine.
    var routine: AskRoutine {
        AskRoutine(exercises: exercises, isGentle: isGentle, durationOverrides: durationOverrides)
    }

    // MARK: - Adding

    mutating func add(_ routine: AskRoutine, intent: AskIntent) {
        exercises += routine.exercises
        durationOverrides.merge(routine.durationOverrides) { _, new in new }
        isGentle = isGentle || routine.isGentle
        lastIntent = intent
    }

    mutating func replace(with routine: AskRoutine, intent: AskIntent) {
        self = AskDraft()
        add(routine, intent: intent)
    }

    // MARK: - Edits

    /// Applies a request that `AskIntent.isDraftEdit` marks as a change to this routine.
    /// What the user sees as one exercise: a Left/Right pair counts once.
    var slotCount: Int { RoutinePicker.slots(of: exercises).count }

    /// Takes the order, removals and times from the Customize screen. Keeps
    /// `lastIntent` so "2 more" still knows what was asked for.
    mutating func customize(exercises: [Exercise], durationOverrides: [UUID: Int]) {
        let kept = Set(exercises.map(\.uuid))
        self.exercises = exercises
        self.durationOverrides = durationOverrides.filter { kept.contains($0.key) }
    }

    mutating func apply(_ intent: AskIntent, catalog: [Exercise]) -> AskDraftChange {
        switch intent.edit {
        case .remove: return remove(intent)
        case .swap: return swap(intent, catalog: catalog)
        case .shorter: return retime(scaledBy: 0.75)
        case .longer: return retime(scaledBy: 1.25)
        case nil: break
        }
        if intent.wantsNewRoutine {
            self = AskDraft()
            return .cleared
        }
        if let minutes = intent.minutes {
            return retime(to: min(max(minutes, 1), 20) * 60)
        }
        return .nothingToChange
    }

    /// With areas: every matching exercise ("remove the neck ones"), or the last `count`
    /// of them. Without: the last `count` (default 1).
    private mutating func remove(_ intent: AskIntent) -> AskDraftChange {
        let slots = RoutinePicker.slots(of: exercises)
        let matching = intent.areas.isEmpty
            ? Array(slots.indices)
            : slots.indices.filter { Self.slot(slots[$0], touches: intent.areas) }
        let chosen = intent.areas.isEmpty || intent.count != nil
            ? Array(matching.suffix(intent.count ?? 1))
            : matching
        guard !chosen.isEmpty else { return .nothingToChange }

        let removed = chosen.map { slots[$0] }
        let gone = Set(removed.flatMap { $0.map(\.uuid) })
        exercises.removeAll { gone.contains($0.uuid) }
        for id in gone { durationOverrides[id] = nil }
        return .removed(removed.map(Self.name(of:)))
    }

    /// Replaces the last exercise (or the last one in the named area) with another from the
    /// same area that isn't already in the routine. The new one keeps the old one's time.
    private mutating func swap(_ intent: AskIntent, catalog: [Exercise]) -> AskDraftChange {
        let slots = RoutinePicker.slots(of: exercises)
        let index = intent.areas.isEmpty
            ? slots.indices.last
            : slots.indices.last { Self.slot(slots[$0], touches: intent.areas) }
        guard let index else { return .nothingToChange }
        let old = slots[index]

        let areas = intent.areas.isEmpty ? Self.areas(of: old) : intent.areas
        let wanted = AskIntent(areas: areas, goal: areas.isEmpty ? lastIntent?.goal : nil, minutes: nil,
                               seriousness: .ok, isOffTopic: false, count: 1)
        guard !wanted.isEmpty,
              let replacement = RoutinePicker.pick(intent: wanted, from: catalog, gentle: isGentle,
                                                   excluding: ids)?.exercises,
              let start = exercises.firstIndex(where: { $0.uuid == old[0].uuid })
        else { return .nothingToChange }

        let oldSeconds = old.reduce(0) { $0 + seconds(for: $1) }
        exercises.replaceSubrange(start..<(start + old.count), with: replacement)
        for exercise in old { durationOverrides[exercise.uuid] = nil }
        durationOverrides.merge(RoutinePicker.overrides(for: [replacement], slotSeconds: [oldSeconds])) { _, new in new }
        return .swapped(from: Self.name(of: old), to: Self.name(of: replacement))
    }

    private mutating func retime(scaledBy factor: Double) -> AskDraftChange {
        let target = Int((Double(totalSeconds) * factor / 10).rounded()) * 10
        return retime(to: min(max(target, 10), 20 * 60))
    }

    private mutating func retime(to target: Int) -> AskDraftChange {
        guard !isEmpty else { return .nothingToChange }
        let slots = RoutinePicker.slots(of: exercises)
        let current = slots.map { $0.reduce(0) { $0 + seconds(for: $1) } }
        let times = RoutinePicker.fit(times: current, slots: slots, to: target)
        durationOverrides = RoutinePicker.overrides(for: slots, slotSeconds: times)
        return .retimed(totalSeconds: totalSeconds)
    }

    // MARK: - Helpers

    private static func name(of slot: [Exercise]) -> String {
        slot.count == 2 ? RoutinePicker.pairKey(slot[0].name) : slot[0].name
    }

    private static func slot(_ slot: [Exercise], touches areas: [AskArea]) -> Bool {
        slot.contains { exercise in
            areas.contains { !Set($0.regions).isDisjoint(with: exercise.targetBodyParts) }
        }
    }

    /// The body areas a slot works, read back from its catalog tags.
    private static func areas(of slot: [Exercise]) -> [AskArea] {
        AskArea.allCases.filter { Self.slot(slot, touches: [$0]) }
    }
}
