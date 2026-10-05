import Foundation
import SwiftData

/// Pure, testable seed-migration logic used by `BreathRelaxStretchApp`.
///
/// Backfills data added to the bundled seed after a user first installed:
///   v2 — pose keyframes for the stick-figure animation
///   v3 — video tutorial links (mediaURL) for select exercises
///   v4 — full muscle-group vocabulary (MuscleGroup) + full coverage seed
///   v5 — isBilateral flag (side-switch cue for unilateral stretches)
///   v6 — backfills `Exercise.seedID` onto rows seeded before that field
///        existed, so all subsequent matching can key off a stable id
///        instead of `name` (renaming a seed exercise used to silently
///        orphan the user's row and insert a duplicate under the new name)
enum SeedMigrator {

    /// v3 — the one place name-matching is still acceptable: it predates
    /// `Exercise.seedID` and only ever runs once, on installs old enough to
    /// lack the id entirely.
    @discardableResult
    static func migrateV3(context: ModelContext, rawExercises: [[String: Any]]) -> Bool {
        var posesByName: [String: Data] = [:]
        var mediaByName: [String: String] = [:]
        for raw in rawExercises {
            guard let name = raw["name"] as? String else { continue }
            if let posesRaw = raw["poses"],
               let poseData = try? JSONSerialization.data(withJSONObject: posesRaw) {
                posesByName[name] = poseData
            }
            if let media = raw["mediaURL"] as? String, !media.isEmpty {
                mediaByName[name] = media
            }
        }

        let existing = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        var changed = false
        for exercise in existing {
            if exercise.posesData.isEmpty, let poseData = posesByName[exercise.name] {
                exercise.posesData = poseData
                changed = true
            }
            // Only fill in a video when the exercise doesn't already have one,
            // so we never clobber a link the user added themselves.
            if (exercise.mediaURL ?? "").isEmpty, let media = mediaByName[exercise.name] {
                exercise.mediaURL = media
                changed = true
            }
        }
        return changed
    }

    /// v4 — migrates the exercise vocabulary from the old coarse body-map
    /// regions (e.g. "Left Leg", "Upper Back") to the full `MuscleGroup` set
    /// (e.g. "Left Quadriceps", "Left Trapezius"/"Right Trapezius"), and adds
    /// the new stretches needed for full muscle-group coverage.
    ///
    /// Matches rows to seed entries by the stable `seedID` first, falling
    /// back to `name` only for rows seeded before `Exercise.seedID` existed.
    /// Once matched, `seedID` is backfilled — so renaming an exercise in the
    /// bundle seed can never again orphan the user's row (which used to
    /// leave the old row un-migrated and insert an unwanted duplicate).
    @discardableResult
    static func migrateV4(context: ModelContext, rawExercises: [[String: Any]]) -> Bool {
        let existing = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []

        var existingBySeedID: [String: Exercise] = [:]
        var existingByName: [String: Exercise] = [:]
        for exercise in existing {
            if let seedID = exercise.seedID {
                existingBySeedID[seedID] = exercise
            } else {
                existingByName[exercise.name] = exercise
            }
        }

        var changed = false

        for raw in rawExercises {
            guard
                let name         = raw["name"] as? String,
                let typeStr      = raw["type"] as? String,
                let type         = ExerciseType(rawValue: typeStr.capitalized),
                let parts        = raw["targetBodyParts"] as? [String],
                let duration     = raw["durationSeconds"] as? Int,
                let difficulty   = raw["difficulty"] as? Int,
                let instructions = raw["instructions"] as? [String]
            else { continue }

            let seedID = raw["id"] as? String
            let match = seedID.flatMap { existingBySeedID[$0] } ?? existingByName[name]

            if let exercise = match {
                // Already-seeded exercise the user has — adopt the bundle's
                // re-authored targets verbatim so upgrading users get the
                // same anatomically-correct groups as fresh installs (a
                // plain MuscleGroup.migrate of e.g. "Left Leg" would land
                // hamstring stretches on Quadriceps).
                if exercise.targetBodyParts != parts {
                    exercise.targetBodyParts = parts
                    changed = true
                }
                if let seedID, exercise.seedID != seedID {
                    exercise.seedID = seedID
                    changed = true
                }
            } else {
                // Brand-new in v4 — insert it as-is.
                let exercise = Exercise(
                    uuid: Exercise.seedUUID(seedID: seedID, name: name),
                    name: name, type: type, targetBodyParts: parts,
                    durationSeconds: duration, difficulty: difficulty,
                    instructions: instructions,
                    mediaURL: raw["mediaURL"] as? String,
                    caution: raw["caution"] as? String,
                    isBilateral: raw["isBilateral"] as? Bool ?? true
                )
                exercise.seedID = seedID
                exercise.localVideoName = raw["localVideoName"] as? String
                exercise.animationName = raw["animationName"] as? String
                context.insert(exercise)
                if let seedID { existingBySeedID[seedID] = exercise }
                existingByName[name] = exercise
                changed = true
            }
        }

        // User-created exercises (anything not seeded from the bundle) keep
        // their own content but still need old region names mapped forward;
        // unrecognized/custom entries pass through unchanged.
        let seedIDs = Set(rawExercises.compactMap { $0["id"] as? String })
        let seedNames = Set(rawExercises.compactMap { $0["name"] as? String })
        for exercise in existing {
            let isSeeded = (exercise.seedID.map { seedIDs.contains($0) } ?? false) || seedNames.contains(exercise.name)
            guard !isSeeded else { continue }
            let migrated = MuscleGroup.migrate(exercise.targetBodyParts)
            if migrated != exercise.targetBodyParts {
                exercise.targetBodyParts = migrated
                changed = true
            }
        }

        // Body-map marks saved from the old region set need the same
        // one-time vocabulary migration.
        let defaults = UserDefaults.standard
        if let markedRegions = defaults.stringArray(forKey: "bodymap.markedRegions") {
            let migratedRegions = MuscleGroup.migrate(markedRegions)
            if migratedRegions != markedRegions {
                defaults.set(migratedRegions, forKey: "bodymap.markedRegions")
            }
        }

        return changed
    }

    /// v5 — backfills the `isBilateral` flag onto already-seeded exercises so
    /// upgrading users get the same "switch sides" cues as fresh installs. New
    /// installs already read `isBilateral` at seed time, so this only matters
    /// for users seeded before the flag existed (all such rows defaulted to
    /// true). We only ever flip a bundle-seeded exercise to `false`; we never
    /// touch user-created exercises (default stays true).
    @discardableResult
    static func migrateV5(context: ModelContext, rawExercises: [[String: Any]]) -> Bool {
        // Only the exercises the bundle explicitly marks unilateral.
        var unilateralNames: Set<String> = []
        for raw in rawExercises {
            guard let name = raw["name"] as? String else { continue }
            if (raw["isBilateral"] as? Bool) == false {
                unilateralNames.insert(name)
            }
        }

        let existing = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        var changed = false
        for exercise in existing where unilateralNames.contains(exercise.name) {
            if exercise.isBilateral {
                exercise.isBilateral = false
                changed = true
            }
        }
        return changed
    }

    /// v6 — backfills `Exercise.seedID` for rows that were seeded before that
    /// field existed (matched by name, the last time name-matching is ever
    /// used for these rows). From here on, renaming an exercise in the
    /// bundled seed can no longer orphan or duplicate an installed user's row.
    @discardableResult
    static func migrateV6(context: ModelContext, rawExercises: [[String: Any]]) -> Bool {
        var seedIDByName: [String: String] = [:]
        for raw in rawExercises {
            guard let name = raw["name"] as? String, let id = raw["id"] as? String else { continue }
            seedIDByName[name] = id
        }

        let existing = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        var changed = false
        for exercise in existing where exercise.seedID == nil {
            if let id = seedIDByName[exercise.name] {
                exercise.seedID = id
                changed = true
            }
        }
        return changed
    }

    /// v7 — backfills `Exercise.animationName` (the baked 3D muscle-animation
    /// demo loop) onto already-seeded rows, matched by the stable `seedID`.
    /// New installs already read `animationName` at insert time (`migrateV4`),
    /// so this only matters for users seeded before the field carried a value.
    /// Only fills an *empty* animationName from the bundle — never clobbers one
    /// already set, and never touches user-created rows (which have no seedID).
    @discardableResult
    static func migrateV7(context: ModelContext, rawExercises: [[String: Any]]) -> Bool {
        var animationBySeedID: [String: String] = [:]
        for raw in rawExercises {
            guard let id = raw["id"] as? String,
                  let anim = raw["animationName"] as? String, !anim.isEmpty else { continue }
            animationBySeedID[id] = anim
        }

        let existing = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        var changed = false
        for exercise in existing {
            guard let seedID = exercise.seedID,
                  let anim = animationBySeedID[seedID],
                  (exercise.animationName ?? "").isEmpty else { continue }
            exercise.animationName = anim
            changed = true
        }
        return changed
    }

    /// v8 — backfills `Exercise.cueStyle` onto already-seeded rows, matched by
    /// `seedID`. New installs already read `cueStyle` at insert time; this
    /// only matters for users seeded before the field existed. Parses the
    /// bundle's lowercase string via `ExerciseCueStyle(rawValue:)` on the
    /// capitalized string, same as the insert-time parsing.
    @discardableResult
    static func migrateV8(context: ModelContext, rawExercises: [[String: Any]]) -> Bool {
        var cueStyleBySeedID: [String: ExerciseCueStyle] = [:]
        for raw in rawExercises {
            guard let id = raw["id"] as? String,
                  let cueStyleStr = raw["cueStyle"] as? String,
                  let cueStyle = ExerciseCueStyle(rawValue: cueStyleStr.capitalized) else { continue }
            cueStyleBySeedID[id] = cueStyle
        }

        let existing = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        var changed = false
        for exercise in existing {
            guard let seedID = exercise.seedID,
                  let cueStyle = cueStyleBySeedID[seedID],
                  exercise.cueStyle != cueStyle else { continue }
            exercise.cueStyle = cueStyle
            changed = true
        }
        return changed
    }

    /// v9 — inserts brand-new seed exercises added to the bundle after a
    /// user's initial install, matched by `seedID` so it never duplicates a
    /// row the user already has. Unlike v3–v6 (one-time vocabulary/id
    /// migrations), this is NOT gated behind a version bump: exercises get
    /// added to `SeedData.json` on an ongoing basis, and gating this would
    /// mean only installs that happened to cross v9 at the right moment ever
    /// pick up later additions. Naturally idempotent — a no-op once every
    /// bundle entry has a matching on-device row — so it's cheap and safe to
    /// run on every launch, same rationale as `migrateV7`.
    @discardableResult
    static func migrateV9(context: ModelContext, rawExercises: [[String: Any]]) -> Bool {
        let existing = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        let existingSeedIDs = Set(existing.compactMap(\.seedID))

        var changed = false
        for raw in rawExercises {
            guard
                let seedID     = raw["id"] as? String,
                !existingSeedIDs.contains(seedID),
                let name         = raw["name"] as? String,
                let typeStr      = raw["type"] as? String,
                let type         = ExerciseType(rawValue: typeStr.capitalized),
                let parts        = raw["targetBodyParts"] as? [String],
                let duration     = raw["durationSeconds"] as? Int,
                let difficulty   = raw["difficulty"] as? Int,
                let instructions = raw["instructions"] as? [String]
            else { continue }

            let cueStyle = (raw["cueStyle"] as? String).flatMap { ExerciseCueStyle(rawValue: $0.capitalized) } ?? .hold
            let exercise = Exercise(
                uuid: Exercise.seedUUID(seedID: seedID, name: name),
                name: name, type: type, targetBodyParts: parts,
                durationSeconds: duration, difficulty: difficulty,
                instructions: instructions,
                mediaURL: raw["mediaURL"] as? String,
                caution: raw["caution"] as? String,
                isBilateral: raw["isBilateral"] as? Bool ?? true,
                cueStyle: cueStyle
            )
            exercise.seedID = seedID
            exercise.localVideoName = raw["localVideoName"] as? String
            exercise.animationName = raw["animationName"] as? String
            exercise.animationIsApproximate = raw["animationIsApproximate"] as? Bool ?? false
            exercise.animationCallout = AnimationCallout.parse(fromRawExercise: raw)
            if let posesRaw = raw["poses"],
               let posesData = try? JSONSerialization.data(withJSONObject: posesRaw) {
                exercise.posesData = posesData
            }
            context.insert(exercise)
            changed = true
        }
        return changed
    }

    /// v10 — backfills `Exercise.animationIsApproximate` onto already-seeded
    /// rows, matched by `seedID`. Like `migrateV7`/`migrateV9`, NOT gated
    /// behind a one-time version bump: which exercises are flagged as
    /// approximate can grow over time as more rig limitations/animation bugs
    /// are found, and a gated migration would only ever pick up whatever was
    /// flagged as of the version-bump launch. Syncs in both directions
    /// (matches the bundle exactly) since this is authored content, not user
    /// data — same rationale as `migrateV8`'s cueStyle sync.
    @discardableResult
    static func migrateV10(context: ModelContext, rawExercises: [[String: Any]]) -> Bool {
        var approximateBySeedID: [String: Bool] = [:]
        for raw in rawExercises {
            guard let id = raw["id"] as? String else { continue }
            approximateBySeedID[id] = raw["animationIsApproximate"] as? Bool ?? false
        }

        let existing = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        var changed = false
        for exercise in existing {
            guard let seedID = exercise.seedID,
                  let approximate = approximateBySeedID[seedID],
                  exercise.animationIsApproximate != approximate else { continue }
            exercise.animationIsApproximate = approximate
            changed = true
        }
        return changed
    }

    /// v11 — backfills `Exercise.breathPattern` onto already-seeded rows,
    /// matched by `seedID`. New installs already read `breathPattern` off the
    /// bundle at seed-insert time; this matters for (a) users seeded before
    /// the field existed, and (b) a newer exercise inserted later by
    /// `migrateV9`'s own insert path, which predates `breathPattern` and
    /// never sets it. Like `migrateV7`/`migrateV9`/`migrateV10`, this is NOT
    /// gated behind a one-time `seedDataVersion` bump — patterns keep getting
    /// authored for new exercises across releases, the same way `migrateV9`
    /// itself keeps inserting new exercises; a one-time gate here would mean
    /// any pattern-bearing exercise added after a device passed this version
    /// never gets backfilled. Naturally idempotent (only fills when the
    /// bundle's pattern actually differs from what's stored), so it's cheap
    /// and safe to run on every launch.
    @discardableResult
    static func migrateV11(context: ModelContext, rawExercises: [[String: Any]]) -> Bool {
        var patternBySeedID: [String: [BreathPhaseStep]] = [:]
        for raw in rawExercises {
            guard let id = raw["id"] as? String,
                  let rawPattern = raw["breathPattern"] as? [[String: Any]], !rawPattern.isEmpty
            else { continue }
            let phases = rawPattern.compactMap { entry -> BreathPhaseStep? in
                guard let label = entry["label"] as? String, let seconds = entry["seconds"] as? Int else { return nil }
                return BreathPhaseStep(label: label, seconds: seconds)
            }
            guard !phases.isEmpty else { continue }
            patternBySeedID[id] = phases
        }

        let existing = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        var changed = false
        for exercise in existing {
            guard let seedID = exercise.seedID,
                  let pattern = patternBySeedID[seedID],
                  exercise.breathPattern != pattern else { continue }
            exercise.breathPattern = pattern
            changed = true
        }
        return changed
    }

    /// v12 — backfills `Exercise.animationCallout` onto already-seeded rows,
    /// matched by `seedID`. Like `migrateV7`/`migrateV9`/`migrateV10`, NOT
    /// gated behind a one-time version bump: callouts are authored
    /// incrementally, batch by batch (see the animation-callout instruction
    /// spec), so a gated migration would only ever pick up whatever was
    /// authored as of the version-bump launch. Syncs in both directions
    /// (matches the bundle exactly, including clearing a callout the bundle
    /// removed) since this is authored content, not user data — same
    /// rationale as `migrateV8`/`migrateV10`.
    @discardableResult
    static func migrateV12(context: ModelContext, rawExercises: [[String: Any]]) -> Bool {
        var calloutBySeedID: [String: AnimationCallout?] = [:]
        for raw in rawExercises {
            guard let id = raw["id"] as? String else { continue }
            calloutBySeedID[id] = AnimationCallout.parse(fromRawExercise: raw)
        }

        let existing = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        var changed = false
        for exercise in existing {
            guard let seedID = exercise.seedID,
                  let callout = calloutBySeedID[seedID],
                  exercise.animationCallout != callout else { continue }
            exercise.animationCallout = callout
            changed = true
        }
        return changed
    }

    /// Drops the storage behind the retired body-map marking flow (sensation
    /// colours + marked regions with dots), removed in the "Tap to Stretch"
    /// rework. Not a versioned seed migration — it touches no SwiftData and
    /// carries no `seedDataVersion` gate; `removeObject` on an absent key is
    /// a no-op, so running it on every launch costs nothing.
    ///
    /// Deliberately does NOT touch `bodymap.markedRegions`, which is a
    /// different, still-live key migrated by `migrateV4`.
    static func removeRetiredBodyMapMarkStorage(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: "bodymap.markedSensations")
    }

    /// Backfills `Routine.ownerID` for routines created before that field
    /// existed (empty string). Claims them for `claimant` — there's no way
    /// to know who really made them retroactively, and leaving them
    /// ownerless would make them vanish from every account's routine list
    /// once query sites filter on `ownerID`, which reads worse than a
    /// guess. Not a versioned seed migration — idempotent by construction:
    /// once claimed, a routine's `ownerID` is never empty again, so later
    /// runs find nothing left to do.
    @discardableResult
    static func claimOwnerlessRoutines(context: ModelContext, claimant: String) -> Bool {
        let descriptor = FetchDescriptor<Routine>(predicate: #Predicate { $0.ownerID == "" })
        guard let ownerless = try? context.fetch(descriptor), !ownerless.isEmpty else { return false }
        for routine in ownerless {
            routine.ownerID = claimant
            routine.markUpdated(in: context)
        }
        return true
    }
}
