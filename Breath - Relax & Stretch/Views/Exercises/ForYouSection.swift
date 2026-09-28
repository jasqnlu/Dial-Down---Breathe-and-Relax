import SwiftUI
import Combine

// MARK: - Exercise card

struct ForYouCard: View {
    let exercise: Exercise

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let category = ExerciseCategory.primary(for: exercise.targetBodyParts)
            PoseGlyphIcon(exercise: exercise, category: category, size: 96)
                .frame(maxWidth: .infinity)
                .frame(height: 110)

            Text(exercise.name)
                .font(.luminaLabel)
                .foregroundStyle(Color.luminaOnSurface)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Text("\(exercise.durationFormatted) · \(exercise.type.rawValue)")
                .font(.luminaCaption)
                .foregroundStyle(Color.luminaOnSurfaceVariant)
        }
        .frame(width: 128)
        .padding(8)
        .luminaCard(padding: 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: exercise))
    }

    private func accessibilityLabel(for exercise: Exercise) -> String {
        let motion = MotionAccent.resolve(for: exercise) == .circular ? ", circular motion" : ""
        return "\(exercise.name), \(exercise.durationFormatted), \(exercise.type.rawValue)\(motion)"
    }
}

// MARK: - Premade routine card

struct PremadeRoutineCard: View {
    let routine: PremadeRoutine
    let meta: (count: Int, minutes: Int)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: routine.icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.luminaPrimary)
                .frame(width: 40, height: 40)
                .background(Color.luminaMintTint, in: Circle())

            Text(routine.title)
                .font(.luminaCardTitle)
                .foregroundStyle(Color.luminaOnSurface)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            if let meta {
                Text("\(meta.count) exercise\(meta.count == 1 ? "" : "s") · \(meta.minutes) min")
                    .font(.luminaCaption)
                    .foregroundStyle(Color.luminaOnSurfaceVariant)
            } else {
                Text("Unavailable")
                    .font(.luminaCaption)
                    .foregroundStyle(Color.luminaOnSurfaceVariant)
            }
        }
        .padding(12)
        .frame(width: 132, alignment: .leading)
        .luminaCard(padding: 0)
    }
}

// MARK: - Recommended carousel
//
// A rotating carousel of specific exercises drawn from the user's chosen
// focus areas (picked at signup), each card tagged with its category. Auto-
// advances unless Reduce Motion is on, and can be swiped by hand.

struct RecommendedCarousel: View {
    let items: [RecommendedExercise]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    private let advance = Timer.publish(every: 4, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 10) {
            TabView(selection: $index) {
                ForEach(Array(items.enumerated()), id: \.element.id) { offset, item in
                    NavigationLink(destination: ExerciseDetailView(exercise: item.exercise)) {
                        RecommendedCard(item: item)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 2)
                    .tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 132)

            if items.count > 1 {
                HStack(spacing: 6) {
                    ForEach(items.indices, id: \.self) { i in
                        Capsule()
                            .fill(i == index ? Color.luminaPrimary : Color.luminaOutline)
                            .frame(width: i == index ? 18 : 6, height: 6)
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: index)
            }
        }
        .onReceive(advance) { _ in
            guard !reduceMotion, items.count > 1 else { return }
            withAnimation(.easeInOut(duration: 0.5)) {
                index = (index + 1) % items.count
            }
        }
        .onChange(of: items.count) { _, newCount in
            if index >= newCount { index = 0 }
        }
    }
}

private struct RecommendedCard: View {
    let item: RecommendedExercise

    var body: some View {
        HStack(spacing: 14) {
            PoseGlyphIcon(exercise: item.exercise, category: item.category, size: 60)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.category.rawValue.uppercased())
                    .font(.luminaCaption)
                    .foregroundStyle(item.category.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(item.category.accentColor.opacity(0.14), in: Capsule())

                Text(item.exercise.name)
                    .font(.luminaCardTitle)
                    .foregroundStyle(Color.luminaOnSurface)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Text("\(item.exercise.durationFormatted) · \(item.exercise.type.rawValue)")
                    .font(.luminaCaption)
                    .foregroundStyle(Color.luminaOnSurfaceVariant)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .luminaCard(padding: 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let motion = MotionAccent.resolve(for: item.exercise) == .circular ? ", circular motion" : ""
        return "\(item.category.rawValue): \(item.exercise.name), \(item.exercise.durationFormatted), \(item.exercise.type.rawValue)\(motion)"
    }
}

// MARK: - Goal metadata

struct GoalMeta {
    let id: String
    let displayName: String
    let exerciseNames: [String]

    /// Interleaves exercises from each active goal so all goals contribute
    /// equally, deduped, up to `limit`. Shared by ForYouSection and the
    /// widget's quick-session deep link.
    static func recommend(
        from allExercises: [Exercise], activeGoalIDs: Set<String>, limit: Int, goals: [GoalMeta] = GoalMeta.all
    ) -> [Exercise] {
        Array(candidatePool(from: allExercises, activeGoalIDs: activeGoalIDs, goals: goals).prefix(limit))
    }

    /// Same candidate pool as `recommend`, but re-ranked with a neglect
    /// boost: exercises touching a currently-neglected muscle group
    /// (`ActivityInsightsEngine.neglectedGroups`) move up in the ranking, so
    /// under-trained areas surface in "Recommended for You" without
    /// overriding the user's chosen goals outright. `finalScore =
    /// positionScore + neglectWeight * neglectIndicator` — a plain linear
    /// weighted sum, not a fitted model. `neglectWeight` defaults low
    /// (0.4) so goal-tag order still dominates; it only nudges ranking.
    static func recommend(
        from allExercises: [Exercise],
        activeGoalIDs: Set<String>,
        limit: Int,
        neglectedGroups: [String],
        neglectWeight: Double = 0.4,
        goals: [GoalMeta] = GoalMeta.all
    ) -> [Exercise] {
        let pool = candidatePool(from: allExercises, activeGoalIDs: activeGoalIDs, goals: goals)
        guard !pool.isEmpty else { return [] }
        guard !neglectedGroups.isEmpty, neglectWeight != 0 else { return Array(pool.prefix(limit)) }

        let count = pool.count
        let scored = pool.enumerated().map { index, exercise -> (exercise: Exercise, score: Double, index: Int) in
            // Earlier position in goal order scores higher; last place scores 0.
            let positionScore = count > 1 ? 1.0 - (Double(index) / Double(count - 1)) : 1.0
            let isNeglected = exercise.targetBodyParts.contains { part in
                neglectedGroups.contains { part.localizedCaseInsensitiveContains($0) }
            }
            let neglectIndicator = isNeglected ? 1.0 : 0.0
            return (exercise, positionScore + neglectWeight * neglectIndicator, index)
        }
        let ranked = scored.sorted { lhs, rhs in
            lhs.score != rhs.score ? lhs.score > rhs.score : lhs.index < rhs.index
        }
        return Array(ranked.prefix(limit).map(\.exercise))
    }

    private static func candidatePool(from allExercises: [Exercise], activeGoalIDs: Set<String>, goals: [GoalMeta]) -> [Exercise] {
        let activeGoals = goals.filter { activeGoalIDs.contains($0.id) }
        guard !activeGoals.isEmpty else { return [] }
        let byName = Dictionary(grouping: allExercises, by: \.name).compactMapValues(\.first)

        var seen = Set<UUID>()
        var result: [Exercise] = []
        let goalLists = activeGoals.map { goal in
            goal.exerciseNames.compactMap { byName[$0] }
        }

        var index = 0
        while true {
            var addedAny = false
            for list in goalLists where index < list.count {
                let ex = list[index]
                if seen.insert(ex.uuid).inserted {
                    result.append(ex)
                    addedAny = true
                }
            }
            if !addedAny { break }
            index += 1
        }
        return result
    }

    static let all: [GoalMeta] = [
        // Exercise names below are matched against SeedData.json at render
        // time (see the file header comment). Several got lateralized into
        // Left/Right pairs after these goals were first written — see
        // CuratedContentIntegrityTests.
        GoalMeta(
            id: "flexibility",
            displayName: "Flexibility",
            exerciseNames: [
                "Standing Hamstring Stretch",
                "Left Standing Hip-Flexor Stretch (Foot Elevated)",
                "Right Standing Hip-Flexor Stretch (Foot Elevated)",
                "Left Standing Quad Stretch",
                "Right Standing Quad Stretch",
                "Left Seated Figure-Four Stretch",
                "Right Seated Figure-Four Stretch",
                "Left Standing Crescent Moon Side Stretch",
                "Right Standing Crescent Moon Side Stretch",
                "Cat-Cow Flow",
                "Left Seated Hamstring Stretch",
                "Right Seated Hamstring Stretch",
                "Left Standing Figure-4 Stretch",
                "Right Standing Figure-4 Stretch",
            ]
        ),
        GoalMeta(
            id: "stress_relief",
            displayName: "Stress Relief",
            exerciseNames: [
                "Shoulder Roll",
                "Left Scalene Neck Stretch",
                "Right Scalene Neck Stretch",
                "Seated Neck Rolls",
                "Eye Palming",
                "Child's Pose",
                "4-7-8 Breathing",
                "Alternate Nostril Breathing",
            ]
        ),
        GoalMeta(
            id: "pain_relief",
            displayName: "Pain Relief",
            exerciseNames: [
                "Cat-Cow Flow",
                "Child's Pose",
                "Double Knee-to-Chest Release",
                "Pelvic Tilt",
                "Bridge Pose",
                "Left Seated Spinal Twist",
                "Right Seated Spinal Twist",
                "Upper-Back Cat-Cow (Seated)",
                "Left Single-Leg Supine Knee-to-Chest",
                "Right Single-Leg Supine Knee-to-Chest",
            ]
        ),
        GoalMeta(
            id: "better_breathing",
            displayName: "Better Breathing",
            exerciseNames: [
                "Deep Belly Breath",
                "Box Breathing",
                "4-7-8 Breathing",
                "Diaphragmatic Breath with Counting",
                "Alternate Nostril Breathing",
                "Pursed-Lip Breathing",
            ]
        ),
        GoalMeta(
            id: "wake_up",
            displayName: "Wake Up",
            exerciseNames: [
                "Box Breathing",
                "Cat-Cow Flow",
                "Shoulder Roll",
                "Standing Back Extension",
                "Doorway Shoulder & Chest Opener",
                "Seated Neck Rotation",
            ]
        ),
        GoalMeta(
            id: "unwind",
            displayName: "Unwind",
            exerciseNames: [
                "4-7-8 Breathing",
                "Deep Belly Breath",
                "Diaphragmatic Breath with Counting",
                "Child's Pose",
                "Happy Baby Pose",
                "Eye Palming",
            ]
        ),
    ]
}
