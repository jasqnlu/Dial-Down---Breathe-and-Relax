import Foundation

/// A short, ready-to-start routine built from the catalog for an `AskIntent`.
struct AskRoutine: Equatable {
    let exercises: [Exercise]
    let isGentle: Bool

    var totalSeconds: Int { exercises.reduce(0) { $0 + $1.durationSeconds } }

    static func == (lhs: AskRoutine, rhs: AskRoutine) -> Bool {
        lhs.isGentle == rhs.isGentle && lhs.exercises.map(\.uuid) == rhs.exercises.map(\.uuid)
    }
}

/// Turns an `AskIntent` into a routine using the same region resolver and goal
/// lists the rest of the app uses. Never names exercises itself.
enum RoutinePicker {
    private static let defaultMinutes = 5
    private static let minSlots = 4
    private static let maxSlotsWithoutMinutes = 6

    static func pick(intent: AskIntent, from catalog: [Exercise], gentle: Bool = false) -> AskRoutine? {
        var candidates = orderedCandidates(for: intent, in: catalog)
        if gentle { candidates = candidates.filter { $0.difficulty == 1 } }
        let slots = makeSlots(from: candidates)

        let requested = (intent.minutes ?? 0) > 0 ? intent.minutes : nil
        let target = min(max(requested ?? defaultMinutes, 1), 20) * 60

        var chosen: [Exercise] = []
        var slotCount = 0
        var total = 0
        for slot in slots {
            if total >= target && slotCount >= minSlots { break }
            if requested == nil && slotCount >= maxSlotsWithoutMinutes { break }
            chosen.append(contentsOf: slot)
            slotCount += 1
            total += slot.reduce(0) { $0 + $1.durationSeconds }
        }
        return chosen.isEmpty ? nil : AskRoutine(exercises: chosen, isGentle: gentle)
    }

    /// Strips a leading "Left "/"Right " so both sides share a key.
    static func pairKey(_ name: String) -> String {
        for prefix in ["Left ", "Right "] where name.hasPrefix(prefix) {
            return String(name.dropFirst(prefix.count))
        }
        return name
    }

    // MARK: - Private

    private static func orderedCandidates(for intent: AskIntent, in catalog: [Exercise]) -> [Exercise] {
        let goalNames = intent.goal.flatMap { goal in GoalMeta.all.first { $0.id == goal.rawValue } }?.exerciseNames ?? []

        if !intent.areas.isEmpty {
            let resolver = RegionExerciseResolver(regions: intent.areas.flatMap(\.regions), exercises: catalog)
            let pool = resolver.direct + resolver.related
            var seen = Set<UUID>()
            var result: [Exercise] = []
            func add(_ e: Exercise) { if seen.insert(e.uuid).inserted { result.append(e) } }
            for name in goalNames { pool.filter { $0.name == name }.forEach(add) }
            resolver.direct.forEach(add)
            resolver.related.forEach(add)
            return result
        }

        guard intent.goal != nil else { return [] }
        var seen = Set<UUID>()
        return goalNames.flatMap { name in catalog.filter { $0.name == name } }
            .filter { seen.insert($0.uuid).inserted }
    }

    /// Groups Left/Right pairs into one slot (Left first); others stand alone.
    private static func makeSlots(from exercises: [Exercise]) -> [[Exercise]] {
        var order: [String] = []
        var groups: [String: [Exercise]] = [:]
        for exercise in exercises {
            let key = pairKey(exercise.name)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(exercise)
        }
        return order.map { key in
            (groups[key] ?? []).sorted { $0.name.hasPrefix("Left ") && !$1.name.hasPrefix("Left ") }
        }
    }
}
