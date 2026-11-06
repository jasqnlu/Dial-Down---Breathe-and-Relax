import Foundation

/// A short, ready-to-start routine built from the catalog for an `AskIntent`.
struct AskRoutine: Equatable {
    let exercises: [Exercise]
    let isGentle: Bool
    /// Seconds per exercise where the request changed the catalog length (an even split
    /// for "3 in 3 minutes", or a trim to land on the minutes asked for). Same shape as
    /// CustomizeRoutineView's and SessionPlayerView's overrides.
    var durationOverrides: [UUID: Int] = [:]

    func seconds(for exercise: Exercise) -> Int {
        durationOverrides[exercise.uuid] ?? exercise.durationSeconds
    }

    var totalSeconds: Int { exercises.reduce(0) { $0 + seconds(for: $1) } }

    static func == (lhs: AskRoutine, rhs: AskRoutine) -> Bool {
        lhs.isGentle == rhs.isGentle && lhs.exercises.map(\.uuid) == rhs.exercises.map(\.uuid)
            && lhs.durationOverrides == rhs.durationOverrides
    }
}

/// Turns an `AskIntent` into a routine using the same region resolver and goal
/// lists the rest of the app uses. Never names exercises itself.
enum RoutinePicker {
    private static let defaultMinutes = 5
    private static let minSlots = 4
    private static let maxSlotsWithoutMinutes = 6

    /// Groups an ordered list into slots: an adjacent Left/Right pair of the same exercise
    /// is one slot, everything else stands alone. One "exercise" to the user is one slot.
    static func slots(of exercises: [Exercise]) -> [[Exercise]] {
        var result: [[Exercise]] = []
        var i = 0
        while i < exercises.count {
            if i + 1 < exercises.count, isPair(exercises[i], exercises[i + 1]) {
                result.append([exercises[i], exercises[i + 1]])
                i += 2
            } else {
                result.append([exercises[i]])
                i += 1
            }
        }
        return result
    }

    private static func isPair(_ a: Exercise, _ b: Exercise) -> Bool {
        pairKey(a.name) != a.name && pairKey(b.name) != b.name
            && a.name.hasPrefix("Left ") != b.name.hasPrefix("Left ")
            && pairKey(a.name) == pairKey(b.name)
    }

    /// `excluding` (exercises already in the routine being built) are never picked; a pair
    /// whose other side is excluded is dropped rather than split.
    static func pick(intent: AskIntent, from catalog: [Exercise], gentle: Bool = false,
                     excluding: Set<UUID> = []) -> AskRoutine? {
        let catalog = excluding.isEmpty ? catalog : catalog.filter { !excluding.contains($0.uuid) }
        var candidates = orderedCandidates(for: intent, in: catalog)
        if gentle { candidates = candidates.filter { $0.difficulty == 1 } }
        let slots = makeSlots(from: candidates, catalog: catalog,
                              allowBreath: intent.areas.isEmpty, gentle: gentle)

        let requested = intent.minutes.flatMap { $0 > 0 ? $0 : nil }
        let target = min(max(requested ?? defaultMinutes, 1), 20) * 60
        let count = intent.count.flatMap { $0 > 0 ? min($0, AskIntent.maxCount) : nil }

        var chosen: [[Exercise]]
        var times: [Int]?
        if let count {
            // Exactly the number asked for (a Left/Right pair is one slot).
            chosen = Array(slots.prefix(count))
            if requested != nil { times = evenSplit(target, into: chosen.count) }
        } else {
            chosen = []
            var total = 0
            for slot in slots {
                if total >= target && (requested != nil || chosen.count >= minSlots) { break }
                if requested == nil && chosen.count >= maxSlotsWithoutMinutes { break }
                chosen.append(slot)
                total += seconds(of: slot)
            }
            // Land exactly on the minutes asked for, but only when the pool reached them:
            // a short pool keeps its real lengths rather than being stretched.
            if requested != nil && total >= target {
                if chosen.count > 1, let last = chosen.last,
                   target - (total - seconds(of: last)) < total - target {
                    chosen.removeLast()
                }
                times = fit(chosen, to: target)
            }
        }
        guard !chosen.isEmpty else { return nil }
        let timing = times.map { overrides(for: chosen, slotSeconds: $0) } ?? [:]
        return AskRoutine(exercises: chosen.flatMap { $0 }, isGentle: gentle, durationOverrides: timing)
    }

    /// Strips a leading "Left "/"Right " so both sides share a key.
    static func pairKey(_ name: String) -> String {
        for prefix in ["Left ", "Right "] where name.hasPrefix(prefix) {
            return String(name.dropFirst(prefix.count))
        }
        return name
    }

    // MARK: - Timing
    // Slot times move in 10 s steps so a Left/Right pair's change splits evenly (5 s a side).

    private static let step = 10
    private static let minSlotSeconds = 10
    private static let minTrimmedSlotSeconds = 20

    private static func seconds(of slot: [Exercise]) -> Int {
        slot.reduce(0) { $0 + $1.durationSeconds }
    }

    /// `total` over `n` slots in 10 s steps; the remainder goes to the first slots.
    /// Never below 10 s a slot, even when that overshoots ("10 exercises in 1 minute").
    private static func evenSplit(_ total: Int, into n: Int) -> [Int] {
        guard n > 0 else { return [] }
        let base = max(minSlotSeconds, total / n / step * step)
        var times = Array(repeating: base, count: n)
        var remainder = total - base * n
        var i = 0
        while remainder >= step {
            times[i % n] += step
            remainder -= step
            i += 1
        }
        return times
    }

    private static func fit(_ slots: [[Exercise]], to target: Int) -> [Int] {
        fit(times: slots.map(seconds(of:)), slots: slots, to: target)
    }

    /// Nudges slot `times`, last slot first, until they add up to `target`. Trims stop at
    /// 20 s a slot. A leftover 5 s (catalog lengths like 45 s) can only go to a one-sided slot.
    static func fit(times: [Int], slots: [[Exercise]], to target: Int) -> [Int] {
        var times = times
        var diff = target - times.reduce(0, +)
        var i = times.count - 1
        var idle = 0
        while abs(diff) >= step && idle < times.count {
            let delta = diff > 0 ? step : -step
            if times[i] + delta >= minTrimmedSlotSeconds {
                times[i] += delta
                diff -= delta
                idle = 0
            } else {
                idle += 1
            }
            i = i == 0 ? times.count - 1 : i - 1
        }
        if diff != 0, let single = slots.lastIndex(where: { $0.count == 1 }),
           times[single] + diff >= minTrimmedSlotSeconds {
            times[single] += diff
        }
        return times
    }

    /// Overrides for the slots whose time changed. A pair splits its time between the sides
    /// (Left gets the half rounded down to 5 s, so the slot total stays exact).
    static func overrides(for slots: [[Exercise]], slotSeconds: [Int]) -> [UUID: Int] {
        var result: [UUID: Int] = [:]
        for (slot, seconds) in zip(slots, slotSeconds) where seconds != Self.seconds(of: slot) {
            if slot.count == 2 {
                let left = seconds / 2 / 5 * 5
                result[slot[0].uuid] = left
                result[slot[1].uuid] = seconds - left
            } else {
                for exercise in slot { result[exercise.uuid] = seconds }
            }
        }
        return result
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
    /// A one-sided slot is completed with its partner from the full catalog;
    /// if the partner is missing or breaks a rule (gentle, breath), the slot is dropped.
    private static func makeSlots(from exercises: [Exercise], catalog: [Exercise],
                                  allowBreath: Bool, gentle: Bool) -> [[Exercise]] {
        var order: [String] = []
        var groups: [String: [Exercise]] = [:]
        for exercise in exercises {
            let key = pairKey(exercise.name)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(exercise)
        }
        return order.compactMap { key in
            var slot = groups[key] ?? []
            if slot.count == 1, let only = slot.first, only.name != key {
                let partnerName = (only.name.hasPrefix("Left ") ? "Right " : "Left ") + key
                guard let partner = catalog.first(where: { $0.name == partnerName }),
                      allowBreath || partner.type != .breath,
                      !gentle || partner.difficulty == 1 else { return nil }
                slot.append(partner)
            }
            return slot.sorted { $0.name.hasPrefix("Left ") && !$1.name.hasPrefix("Left ") }
        }
    }
}
