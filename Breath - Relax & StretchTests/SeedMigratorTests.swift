import Testing
import SwiftData
import Foundation
@testable import BreathRelaxStretch

// Covers the rename-safety fix for the seed migration pipeline: matching
// installed Exercise rows to bundled SeedData.json entries by a stable
// `seedID` instead of `name`, so renaming an exercise in the seed catalog
// no longer orphans the user's row / inserts a silent duplicate.
@MainActor
struct SeedMigratorTests {

    private func makeContext() -> ModelContext {
        let container = try! ModelContainer(
            for: Exercise.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func rawExercise(
        id: String, name: String, targetBodyParts: [String] = ["Left Quadriceps"]
    ) -> [String: Any] {
        [
            "id": id,
            "name": name,
            "type": "Stretch",
            "targetBodyParts": targetBodyParts,
            "durationSeconds": 60,
            "difficulty": 1,
            "instructions": ["Step one.", "Step two.", "Step three."],
        ]
    }

    // MARK: - v4: normal migration still works

    @Test func v4UpdatesExistingRowMatchedBySeedID() throws {
        let context = makeContext()
        let exercise = Exercise(
            name: "Quad Stretch", type: .stretch,
            targetBodyParts: ["Left Leg"], durationSeconds: 60,
            difficulty: 1, instructions: ["a", "b", "c"]
        )
        exercise.seedID = "quad-stretch-id"
        context.insert(exercise)
        try context.save()

        let raw = [rawExercise(id: "quad-stretch-id", name: "Quad Stretch")]
        let changed = SeedMigrator.migrateV4(context: context, rawExercises: raw)
        #expect(changed)

        let all = try context.fetch(FetchDescriptor<Exercise>())
        #expect(all.count == 1)
        #expect(all[0].targetBodyParts == ["Left Quadriceps"])
        #expect(all[0].seedID == "quad-stretch-id")
    }

    @Test func v4InsertsBrandNewSeedExercise() throws {
        let context = makeContext()
        let raw = [rawExercise(id: "new-id", name: "New Stretch")]
        let changed = SeedMigrator.migrateV4(context: context, rawExercises: raw)
        #expect(changed)

        let all = try context.fetch(FetchDescriptor<Exercise>())
        #expect(all.count == 1)
        #expect(all[0].name == "New Stretch")
        #expect(all[0].seedID == "new-id")
    }

    @Test func v4LeavesUserCreatedExerciseAlone() throws {
        let context = makeContext()
        let custom = Exercise(
            name: "My Custom Move", type: .stretch,
            targetBodyParts: ["Left Quadriceps"], durationSeconds: 30,
            difficulty: 1, instructions: ["x", "y", "z"]
        )
        context.insert(custom)
        try context.save()

        let raw = [rawExercise(id: "seed-1", name: "Something Else")]
        _ = SeedMigrator.migrateV4(context: context, rawExercises: raw)

        let all = try context.fetch(FetchDescriptor<Exercise>())
        #expect(all.count == 2)
        let mine = all.first { $0.name == "My Custom Move" }
        #expect(mine?.targetBodyParts == ["Left Quadriceps"])
    }

    // MARK: - v4: rename doesn't break migration

    @Test func v4RenameInSeedDoesNotOrphanOrDuplicate() throws {
        let context = makeContext()
        // User's installed row already carries the stable seedID from a
        // previous migration/seed — the exercise's *display name* is stale
        // relative to a since-renamed bundle entry.
        let exercise = Exercise(
            name: "Old Name", type: .stretch,
            targetBodyParts: ["Left Leg"], durationSeconds: 60,
            difficulty: 1, instructions: ["a", "b", "c"]
        )
        exercise.seedID = "stable-id-1"
        context.insert(exercise)
        try context.save()

        // The bundle seed renamed this exercise but kept the same id.
        let raw = [rawExercise(id: "stable-id-1", name: "New Name")]
        let changed = SeedMigrator.migrateV4(context: context, rawExercises: raw)
        #expect(changed)

        let all = try context.fetch(FetchDescriptor<Exercise>())
        // Must still be exactly one row — a name-keyed match would have
        // missed the existing row (still called "Old Name" on-device) and
        // inserted a duplicate under "New Name" instead of updating in place.
        #expect(all.count == 1)
        #expect(all[0].seedID == "stable-id-1")
        #expect(all[0].targetBodyParts == ["Left Quadriceps"])
    }

    // MARK: - v6: seedID backfill bootstrap

    @Test func v6BackfillsSeedIDForLegacyRowsByName() throws {
        let context = makeContext()
        let legacy = Exercise(
            name: "Legacy Stretch", type: .stretch,
            targetBodyParts: ["Left Quadriceps"], durationSeconds: 60,
            difficulty: 1, instructions: ["a", "b", "c"]
        )
        // Simulates a row seeded before Exercise.seedID existed.
        #expect(legacy.seedID == nil)
        context.insert(legacy)
        try context.save()

        let raw = [rawExercise(id: "legacy-id", name: "Legacy Stretch")]
        let changed = SeedMigrator.migrateV6(context: context, rawExercises: raw)
        #expect(changed)

        let all = try context.fetch(FetchDescriptor<Exercise>())
        #expect(all.count == 1)
        #expect(all[0].seedID == "legacy-id")
    }

    @Test func v6IsNoOpOnceSeedIDIsSet() throws {
        let context = makeContext()
        let exercise = Exercise(
            name: "Already Linked", type: .stretch,
            targetBodyParts: ["Left Quadriceps"], durationSeconds: 60,
            difficulty: 1, instructions: ["a", "b", "c"]
        )
        exercise.seedID = "already-set"
        context.insert(exercise)
        try context.save()

        let raw = [rawExercise(id: "already-set", name: "Renamed In Bundle")]
        let changed = SeedMigrator.migrateV6(context: context, rawExercises: raw)
        #expect(!changed)

        let all = try context.fetch(FetchDescriptor<Exercise>())
        #expect(all[0].seedID == "already-set")
        // v6 never touches name/content — that's v4's job.
        #expect(all[0].name == "Already Linked")
    }

    // MARK: - v5: isBilateral backfill

    @Test func v5FlipsIsBilateralFalseForNamedUnilateralExercises() throws {
        let context = makeContext()
        let exercise = Exercise(
            name: "Left Single-Leg Reach", type: .stretch,
            targetBodyParts: ["Left Quadriceps"], durationSeconds: 60,
            difficulty: 1, instructions: ["a", "b", "c"]
        )
        #expect(exercise.isBilateral)
        context.insert(exercise)
        try context.save()

        var raw = rawExercise(id: "unilateral-1", name: "Left Single-Leg Reach")
        raw["isBilateral"] = false
        let changed = SeedMigrator.migrateV5(context: context, rawExercises: [raw])
        #expect(changed)

        let all = try context.fetch(FetchDescriptor<Exercise>())
        #expect(all[0].isBilateral == false)
    }

    @Test func v5NeverTouchesUserCreatedExercises() throws {
        let context = makeContext()
        let custom = Exercise(
            name: "My Custom Move", type: .stretch,
            targetBodyParts: ["Left Quadriceps"], durationSeconds: 30,
            difficulty: 1, instructions: ["x", "y", "z"]
        )
        context.insert(custom)
        try context.save()

        let changed = SeedMigrator.migrateV5(context: context, rawExercises: [])
        #expect(!changed)

        let all = try context.fetch(FetchDescriptor<Exercise>())
        #expect(all[0].isBilateral)
    }

    // MARK: - v4: animationName on fresh insert

    @Test func v4InsertsAnimationName() throws {
        let context = makeContext()
        var raw = rawExercise(id: "new-id", name: "New Stretch")
        raw["animationName"] = "anim.mp4"
        _ = SeedMigrator.migrateV4(context: context, rawExercises: [raw])

        let all = try context.fetch(FetchDescriptor<Exercise>())
        #expect(all[0].animationName == "anim.mp4")
    }

    // MARK: - v7: animationName backfill onto existing installs

    @Test func v7BackfillsAnimationNameBySeedID() throws {
        let context = makeContext()
        let exercise = Exercise(
            name: "Clasp", type: .stretch,
            targetBodyParts: ["Left Shoulder"], durationSeconds: 45,
            difficulty: 2, instructions: ["a", "b", "c"]
        )
        exercise.seedID = "clasp-id"
        #expect(exercise.animationName == nil)
        context.insert(exercise)
        try context.save()

        var raw = rawExercise(id: "clasp-id", name: "Clasp")
        raw["animationName"] = "clasped_hands_behind_back.mp4"
        let changed = SeedMigrator.migrateV7(context: context, rawExercises: [raw])
        #expect(changed)

        let all = try context.fetch(FetchDescriptor<Exercise>())
        #expect(all[0].animationName == "clasped_hands_behind_back.mp4")
    }

    @Test func v7DoesNotClobberExistingAnimation() throws {
        let context = makeContext()
        let exercise = Exercise(
            name: "Clasp", type: .stretch,
            targetBodyParts: ["Left Shoulder"], durationSeconds: 45,
            difficulty: 2, instructions: ["a", "b", "c"]
        )
        exercise.seedID = "clasp-id"
        exercise.animationName = "already.mp4"
        context.insert(exercise)
        try context.save()

        var raw = rawExercise(id: "clasp-id", name: "Clasp")
        raw["animationName"] = "clasped_hands_behind_back.mp4"
        let changed = SeedMigrator.migrateV7(context: context, rawExercises: [raw])
        #expect(!changed)

        let all = try context.fetch(FetchDescriptor<Exercise>())
        #expect(all[0].animationName == "already.mp4")
    }

    @Test func v7NeverTouchesUserCreatedExercises() throws {
        let context = makeContext()
        let custom = Exercise(
            name: "My Custom Move", type: .stretch,
            targetBodyParts: ["Left Quadriceps"], durationSeconds: 30,
            difficulty: 1, instructions: ["x", "y", "z"]
        )
        context.insert(custom)   // no seedID
        try context.save()

        var raw = rawExercise(id: "seed-1", name: "Some Seed")
        raw["animationName"] = "x.mp4"
        let changed = SeedMigrator.migrateV7(context: context, rawExercises: [raw])
        #expect(!changed)

        let all = try context.fetch(FetchDescriptor<Exercise>())
        #expect(all[0].animationName == nil)
    }

    // MARK: - v8: cueStyle backfill

    @Test func v8BackfillsCueStyleBySeedID() throws {
        let context = makeContext()
        let exercise = Exercise(
            name: "Shoulder Roll", type: .stretch,
            targetBodyParts: ["Left Shoulder"], durationSeconds: 30,
            difficulty: 1, instructions: ["a", "b", "c"]
        )
        exercise.seedID = "shoulder-roll-id"
        #expect(exercise.cueStyle == .hold)
        context.insert(exercise)
        try context.save()

        var raw = rawExercise(id: "shoulder-roll-id", name: "Shoulder Roll")
        raw["cueStyle"] = "repeat"
        let changed = SeedMigrator.migrateV8(context: context, rawExercises: [raw])
        #expect(changed)

        let all = try context.fetch(FetchDescriptor<Exercise>())
        #expect(all[0].cueStyle == .repeatMotion)
    }

    @Test func v8IsNoOpWhenBundleCueStyleMatchesAlready() throws {
        let context = makeContext()
        let exercise = Exercise(
            name: "Child's Pose", type: .stretch,
            targetBodyParts: ["Back"], durationSeconds: 45,
            difficulty: 1, instructions: ["a", "b", "c"], cueStyle: .hold
        )
        exercise.seedID = "childs-pose-id"
        context.insert(exercise)
        try context.save()

        var raw = rawExercise(id: "childs-pose-id", name: "Child's Pose")
        raw["cueStyle"] = "hold"
        let changed = SeedMigrator.migrateV8(context: context, rawExercises: [raw])
        #expect(!changed)

        let all = try context.fetch(FetchDescriptor<Exercise>())
        #expect(all[0].cueStyle == .hold)
    }

    @Test func v8NeverTouchesUserCreatedExercises() throws {
        let context = makeContext()
        let custom = Exercise(
            name: "My Custom Move", type: .stretch,
            targetBodyParts: ["Left Quadriceps"], durationSeconds: 30,
            difficulty: 1, instructions: ["x", "y", "z"]
        )
        context.insert(custom)   // no seedID
        try context.save()

        var raw = rawExercise(id: "seed-1", name: "Some Seed")
        raw["cueStyle"] = "repeat"
        let changed = SeedMigrator.migrateV8(context: context, rawExercises: [raw])
        #expect(!changed)

        let all = try context.fetch(FetchDescriptor<Exercise>())
        #expect(all[0].cueStyle == .hold)
    }

    // MARK: - v9: brand-new exercises inserted for already-seeded installs

    @Test func v9InsertsNewSeedExerciseNotYetOnDevice() throws {
        let context = makeContext()
        let existing = Exercise(
            name: "Old Favorite", type: .stretch,
            targetBodyParts: ["Left Quadriceps"], durationSeconds: 60,
            difficulty: 1, instructions: ["a", "b", "c"]
        )
        existing.seedID = "old-favorite-id"
        context.insert(existing)
        try context.save()

        let raw = [
            rawExercise(id: "old-favorite-id", name: "Old Favorite"),
            rawExercise(id: "new-tibialis-id", name: "Standing Tibialis Raise (Toe Lifts)"),
        ]
        let changed = SeedMigrator.migrateV9(context: context, rawExercises: raw)
        #expect(changed)

        let all = try context.fetch(FetchDescriptor<Exercise>())
        #expect(all.count == 2)
        let inserted = all.first { $0.seedID == "new-tibialis-id" }
        #expect(inserted?.name == "Standing Tibialis Raise (Toe Lifts)")
    }

    @Test func v9IsNoOpWhenEverySeedExerciseAlreadyExists() throws {
        let context = makeContext()
        let existing = Exercise(
            name: "Already Here", type: .stretch,
            targetBodyParts: ["Left Quadriceps"], durationSeconds: 60,
            difficulty: 1, instructions: ["a", "b", "c"]
        )
        existing.seedID = "already-here-id"
        context.insert(existing)
        try context.save()

        let raw = [rawExercise(id: "already-here-id", name: "Already Here")]
        let changed = SeedMigrator.migrateV9(context: context, rawExercises: raw)
        #expect(!changed)

        let all = try context.fetch(FetchDescriptor<Exercise>())
        #expect(all.count == 1)
    }

    @Test func v9NeverTouchesUserCreatedExercises() throws {
        let context = makeContext()
        let custom = Exercise(
            name: "My Custom Move", type: .stretch,
            targetBodyParts: ["Left Quadriceps"], durationSeconds: 30,
            difficulty: 1, instructions: ["x", "y", "z"]
        )
        context.insert(custom)   // no seedID
        try context.save()

        let raw = [rawExercise(id: "seed-1", name: "Some Seed")]
        let changed = SeedMigrator.migrateV9(context: context, rawExercises: raw)
        #expect(changed)   // inserts the missing seed row...

        let all = try context.fetch(FetchDescriptor<Exercise>())
        #expect(all.count == 2)
        let mine = all.first { $0.name == "My Custom Move" }
        #expect(mine?.seedID == nil)   // ...without touching the user's row
    }

    // MARK: - v10: animationIsApproximate backfill

    @Test func v10FlipsApproximateTrueForFlaggedExercise() throws {
        let context = makeContext()
        let exercise = Exercise(
            name: "Reverse Prayer Stretch", type: .stretch,
            targetBodyParts: ["Left Forearm"], durationSeconds: 45,
            difficulty: 2, instructions: ["a", "b", "c"]
        )
        exercise.seedID = "reverse-prayer-id"
        #expect(!exercise.animationIsApproximate)
        context.insert(exercise)
        try context.save()

        var raw = rawExercise(id: "reverse-prayer-id", name: "Reverse Prayer Stretch")
        raw["animationIsApproximate"] = true
        let changed = SeedMigrator.migrateV10(context: context, rawExercises: [raw])
        #expect(changed)

        let all = try context.fetch(FetchDescriptor<Exercise>())
        #expect(all[0].animationIsApproximate)
    }

    @Test func v10IsNoOpWhenBundleFlagMatchesAlready() throws {
        let context = makeContext()
        let exercise = Exercise(
            name: "Accurate Move", type: .stretch,
            targetBodyParts: ["Left Quadriceps"], durationSeconds: 60,
            difficulty: 1, instructions: ["a", "b", "c"]
        )
        exercise.seedID = "accurate-id"
        context.insert(exercise)
        try context.save()

        let raw = rawExercise(id: "accurate-id", name: "Accurate Move")
        let changed = SeedMigrator.migrateV10(context: context, rawExercises: [raw])
        #expect(!changed)

        let all = try context.fetch(FetchDescriptor<Exercise>())
        #expect(!all[0].animationIsApproximate)
    }

    @Test func v10NeverTouchesUserCreatedExercises() throws {
        let context = makeContext()
        let custom = Exercise(
            name: "My Custom Move", type: .stretch,
            targetBodyParts: ["Left Quadriceps"], durationSeconds: 30,
            difficulty: 1, instructions: ["x", "y", "z"]
        )
        context.insert(custom)   // no seedID
        try context.save()

        var raw = rawExercise(id: "seed-1", name: "Some Seed")
        raw["animationIsApproximate"] = true
        let changed = SeedMigrator.migrateV10(context: context, rawExercises: [raw])
        #expect(!changed)

        let all = try context.fetch(FetchDescriptor<Exercise>())
        #expect(!all[0].animationIsApproximate)
    }

    // MARK: - v11: breathPattern backfill

    @Test func v11BackfillsBreathPatternBySeedID() throws {
        let context = makeContext()
        let exercise = Exercise(
            name: "Box Breathing", type: .breath,
            targetBodyParts: [], durationSeconds: 180,
            difficulty: 1, instructions: ["a", "b", "c"]
        )
        exercise.seedID = "box-breathing-id"
        #expect(exercise.breathPattern.isEmpty)
        context.insert(exercise)
        try context.save()

        var raw = rawExercise(id: "box-breathing-id", name: "Box Breathing")
        raw["breathPattern"] = [
            ["label": "Inhale", "seconds": 4],
            ["label": "Hold", "seconds": 4],
            ["label": "Exhale", "seconds": 4],
            ["label": "Hold", "seconds": 4],
        ]
        let changed = SeedMigrator.migrateV11(context: context, rawExercises: [raw])
        #expect(changed)

        let all = try context.fetch(FetchDescriptor<Exercise>())
        #expect(all[0].breathPattern == [
            BreathPhaseStep(label: "Inhale", seconds: 4),
            BreathPhaseStep(label: "Hold", seconds: 4),
            BreathPhaseStep(label: "Exhale", seconds: 4),
            BreathPhaseStep(label: "Hold", seconds: 4),
        ])
    }

    @Test func v11IsNoOpWhenBundleHasNoPattern() throws {
        let context = makeContext()
        let exercise = Exercise(
            name: "Alternate Nostril Breathing", type: .breath,
            targetBodyParts: [], durationSeconds: 180,
            difficulty: 1, instructions: ["a", "b", "c"]
        )
        exercise.seedID = "alt-nostril-id"
        context.insert(exercise)
        try context.save()

        let raw = rawExercise(id: "alt-nostril-id", name: "Alternate Nostril Breathing")
        // No "breathPattern" key — this exercise hasn't been authored yet.
        let changed = SeedMigrator.migrateV11(context: context, rawExercises: [raw])
        #expect(!changed)

        let all = try context.fetch(FetchDescriptor<Exercise>())
        #expect(all[0].breathPattern.isEmpty)
    }

    @Test func v11IsNoOpWhenBundlePatternMatchesAlready() throws {
        let context = makeContext()
        let exercise = Exercise(
            name: "Box Breathing", type: .breath,
            targetBodyParts: [], durationSeconds: 180,
            difficulty: 1, instructions: ["a", "b", "c"]
        )
        exercise.seedID = "box-breathing-id"
        exercise.breathPattern = [BreathPhaseStep(label: "Inhale", seconds: 4)]
        context.insert(exercise)
        try context.save()

        var raw = rawExercise(id: "box-breathing-id", name: "Box Breathing")
        raw["breathPattern"] = [["label": "Inhale", "seconds": 4]]
        let changed = SeedMigrator.migrateV11(context: context, rawExercises: [raw])
        #expect(!changed)
    }

    @Test func v11NeverTouchesUserCreatedExercises() throws {
        let context = makeContext()
        let custom = Exercise(
            name: "My Custom Breath", type: .breath,
            targetBodyParts: [], durationSeconds: 60,
            difficulty: 1, instructions: ["x", "y", "z"]
        )
        context.insert(custom)   // no seedID
        try context.save()

        var raw = rawExercise(id: "seed-1", name: "Some Seed")
        raw["breathPattern"] = [["label": "Inhale", "seconds": 4]]
        let changed = SeedMigrator.migrateV11(context: context, rawExercises: [raw])
        #expect(!changed)

        let all = try context.fetch(FetchDescriptor<Exercise>())
        #expect(all[0].breathPattern.isEmpty)
    }

    // MARK: - v12: animationCallout backfill

    private func rawCallout(startTime: Double = 1.0) -> [String: Any] {
        [
            "text": "Rotate your wrists in a circle",
            "shape": "rotate",
            "anchor": [0.15, 0.32],
            "angle": 0,
            "startTime": startTime,
            "duration": 2.0,
        ]
    }

    @Test func v12BackfillsAnimationCalloutBySeedID() throws {
        let context = makeContext()
        let exercise = Exercise(
            name: "Wrist Circles", type: .stretch,
            targetBodyParts: ["Left Forearm"], durationSeconds: 30,
            difficulty: 1, instructions: ["a", "b", "c"]
        )
        exercise.seedID = "wrist-circles-id"
        #expect(exercise.animationCallout == nil)
        context.insert(exercise)
        try context.save()

        var raw = rawExercise(id: "wrist-circles-id", name: "Wrist Circles")
        raw["animationCallout"] = rawCallout()
        let changed = SeedMigrator.migrateV12(context: context, rawExercises: [raw])
        #expect(changed)

        let all = try context.fetch(FetchDescriptor<Exercise>())
        #expect(all[0].animationCallout?.text == "Rotate your wrists in a circle")
        #expect(all[0].animationCallout?.shape == .rotate)
    }

    @Test func v12IsNoOpWhenBundleCalloutMatchesAlready() throws {
        let context = makeContext()
        let exercise = Exercise(
            name: "Wrist Circles", type: .stretch,
            targetBodyParts: ["Left Forearm"], durationSeconds: 30,
            difficulty: 1, instructions: ["a", "b", "c"]
        )
        exercise.seedID = "wrist-circles-id"
        exercise.animationCallout = AnimationCallout.parse(fromRawExercise: ["animationCallout": rawCallout()])
        context.insert(exercise)
        try context.save()

        var raw = rawExercise(id: "wrist-circles-id", name: "Wrist Circles")
        raw["animationCallout"] = rawCallout()
        let changed = SeedMigrator.migrateV12(context: context, rawExercises: [raw])
        #expect(!changed)
    }

    @Test func v12NeverTouchesUserCreatedExercises() throws {
        let context = makeContext()
        let custom = Exercise(
            name: "My Custom Move", type: .stretch,
            targetBodyParts: ["Left Quadriceps"], durationSeconds: 30,
            difficulty: 1, instructions: ["x", "y", "z"]
        )
        context.insert(custom)   // no seedID
        try context.save()

        var raw = rawExercise(id: "seed-1", name: "Some Seed")
        raw["animationCallout"] = rawCallout()
        let changed = SeedMigrator.migrateV12(context: context, rawExercises: [raw])
        #expect(!changed)

        let all = try context.fetch(FetchDescriptor<Exercise>())
        #expect(all[0].animationCallout == nil)
    }

    /// An animation that gets fixed drops both its callout and its
    /// approximate flag from the bundle; already-seeded installs must lose
    /// them too, not keep showing the old "inaccurate" messaging.
    @Test func v10AndV12ClearFixedAnimationsMessaging() throws {
        let context = makeContext()
        let exercise = Exercise(
            name: "Ankle Alphabet", type: .stretch,
            targetBodyParts: ["Right Foot"], durationSeconds: 60,
            difficulty: 1, instructions: ["a", "b", "c"]
        )
        exercise.seedID = "ankle-alphabet-id"
        exercise.animationIsApproximate = true
        exercise.animationCallout = AnimationCallout.parse(fromRawExercise: ["animationCallout": rawCallout()])
        context.insert(exercise)
        try context.save()

        let raw = rawExercise(id: "ankle-alphabet-id", name: "Ankle Alphabet")   // no flag, no callout
        #expect(SeedMigrator.migrateV10(context: context, rawExercises: [raw]))
        #expect(SeedMigrator.migrateV12(context: context, rawExercises: [raw]))

        let all = try context.fetch(FetchDescriptor<Exercise>())
        #expect(!all[0].animationIsApproximate)
        #expect(all[0].animationCallout == nil)
        #expect(!all[0].showsApproximateAnimationNote)
    }

    // MARK: - claimOwnerlessRoutines

    private func makeRoutineContext() -> ModelContext {
        let container = try! ModelContainer(
            for: Routine.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @Test func claimOwnerlessRoutinesAssignsTheClaimantToEmptyOwnerIDRows() throws {
        let context = makeRoutineContext()
        let routine = Routine(name: "Morning Wake-Up", exerciseIDs: [])
        context.insert(routine)
        try context.save()
        #expect(routine.ownerID == "")

        let changed = SeedMigrator.claimOwnerlessRoutines(context: context, claimant: "user-123")
        #expect(changed)
        #expect(routine.ownerID == "user-123")
    }

    @Test func claimOwnerlessRoutinesNeverTouchesAnAlreadyOwnedRoutine() throws {
        let context = makeRoutineContext()
        let routine = Routine(name: "Evening Unwind", exerciseIDs: [], ownerID: "someone-else")
        context.insert(routine)
        try context.save()

        let changed = SeedMigrator.claimOwnerlessRoutines(context: context, claimant: "user-123")
        #expect(!changed)
        #expect(routine.ownerID == "someone-else")
    }

    @Test func claimOwnerlessRoutinesIsANoOpWhenNothingIsOwnerless() throws {
        let context = makeRoutineContext()
        let changed = SeedMigrator.claimOwnerlessRoutines(context: context, claimant: "user-123")
        #expect(!changed)
    }

    // MARK: - Migration-inserted exercises get the seed's permanent uuid

    // Exercise.init defaults `uuid` to a fresh random UUID, so an insert that
    // doesn't pass one gives the same exercise a different identity on an
    // upgraded install than on a fresh one (which seeds from the "id" field).
    // Session/Routine exerciseIDs and Supabase compare these across devices.

    private let permanentID = "6f1c2a52-8d0e-5b7a-9c3d-2e4f5a6b7c8d"

    @Test func v4InsertedExerciseUsesTheSeedIDAsItsUUID() throws {
        let context = makeContext()
        let raw = [rawExercise(id: permanentID, name: "New Stretch")]
        _ = SeedMigrator.migrateV4(context: context, rawExercises: raw)

        let all = try context.fetch(FetchDescriptor<Exercise>())
        #expect(all.count == 1)
        #expect(all[0].uuid == UUID(uuidString: permanentID))
    }

    @Test func v9InsertedExerciseUsesTheSeedIDAsItsUUID() throws {
        let context = makeContext()
        let raw = [rawExercise(id: permanentID, name: "Standing Tibialis Raise (Toe Lifts)")]
        _ = SeedMigrator.migrateV9(context: context, rawExercises: raw)

        let all = try context.fetch(FetchDescriptor<Exercise>())
        #expect(all.count == 1)
        #expect(all[0].uuid == UUID(uuidString: permanentID))
    }

    @Test func migrationInsertFallsBackToTheNameHashForAMalformedSeedID() throws {
        let context = makeContext()
        let raw = [rawExercise(id: "not-a-uuid", name: "New Stretch")]
        _ = SeedMigrator.migrateV4(context: context, rawExercises: raw)

        let all = try context.fetch(FetchDescriptor<Exercise>())
        #expect(all.count == 1)
        #expect(all[0].uuid == Exercise.stableSeedUUID(forName: "New Stretch"))
    }

    @Test func v4NeverRewritesTheUUIDOfAnExistingRow() throws {
        let context = makeContext()
        let original = UUID()
        let exercise = Exercise(
            uuid: original, name: "Quad Stretch", type: .stretch,
            targetBodyParts: ["Left Leg"], durationSeconds: 60,
            difficulty: 1, instructions: ["a", "b", "c"]
        )
        exercise.seedID = permanentID
        context.insert(exercise)
        try context.save()

        _ = SeedMigrator.migrateV4(context: context, rawExercises: [rawExercise(id: permanentID, name: "Quad Stretch")])

        let all = try context.fetch(FetchDescriptor<Exercise>())
        #expect(all.count == 1)
        #expect(all[0].uuid == original)
    }
}
