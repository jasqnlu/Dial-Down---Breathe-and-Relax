import Foundation
import SwiftData
import CryptoKit

enum ExerciseType: String, Codable, CaseIterable {
    case stretch = "Stretch"
    case breath = "Breath"
    case both = "Both"
}

enum ExerciseCueStyle: String, Codable, CaseIterable {
    case hold = "Hold"
    case repeatMotion = "Repeat"
}

@Model
final class Exercise {
    // Inline defaults required for CloudKit (iCloud) sync compatibility.
    var uuid: UUID = UUID()
    var name: String = ""
    var type: ExerciseType = ExerciseType.stretch
    var targetBodyParts: [String] = []
    var durationSeconds: Int = 60
    var difficulty: Int = 1
    var instructions: [String] = []
    var mediaURL: String? = nil
    var caution: String? = nil
    /// Whether the exercise is performed on both sides at once / inherently
    /// bilateral (true) vs. one side at a time (false). Unilateral exercises
    /// get a mid-duration "switch sides" cue in the session player.
    /// Defaults to true — most stretches are bilateral — so the seed JSON only
    /// needs to specify `false` for the one-side-at-a-time exercises.
    var isBilateral: Bool = true
    /// Raw persisted storage for `cueStyle` — a plain `String`, not the
    /// `ExerciseCueStyle` enum directly. SwiftData's lightweight migration
    /// cannot safely decode a custom enum-typed property added after real
    /// data already exists: reading it on a pre-existing on-disk row throws
    /// a forced-cast failure (`swift_dynamicCastFailure`), crashing the app
    /// on launch. Every other field added after initial release (`seedID`,
    /// `animationName`, `localVideoName`, `isBilateral`) is a primitive type
    /// for exactly this reason. Mirrors the `posesData`/`poses` pattern below.
    var cueStyleRaw: String = ExerciseCueStyle.hold.rawValue
    var posesData: Data = Data()

    /// Whether this exercise is a static position held for the whole
    /// duration (.hold) or a rhythmic motion repeated throughout (.repeatMotion).
    /// Drives the session player's cue badge. Defaults to `.hold` for any
    /// unparseable/unexpected raw value (including a pre-migration row).
    var cueStyle: ExerciseCueStyle {
        get { ExerciseCueStyle(rawValue: cueStyleRaw) ?? .hold }
        set { cueStyleRaw = newValue.rawValue }
    }

    /// Stable identifier tying this row back to its entry in the bundled
    /// `SeedData.json` (the `"id"` field there), independent of `name`.
    /// Seed migrations key off this instead of `name` so renaming an
    /// exercise in the seed catalog doesn't orphan/duplicate installed
    /// users' rows. `nil` for user-created exercises and for rows seeded
    /// before this field existed (backfilled by `migrateSeedToV5IfNeeded`).
    var seedID: String? = nil

    /// Decoded pose keyframes for the stick-figure animation.
    var poses: [ExercisePose] {
        get { (try? JSONDecoder().decode([ExercisePose].self, from: posesData)) ?? [] }
        set { posesData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    /// Raw JSON-encoded storage for `breathPattern` — a primitive `Data`
    /// property, not `[BreathPhaseStep]` directly, for the same reason `posesData`
    /// and `cueStyleRaw` are: SwiftData's lightweight migration cannot safely
    /// decode a newly-added non-primitive property on pre-existing on-disk
    /// rows. Empty `Data()` (the default) means "no pattern authored" — the
    /// session player falls back to the existing flat instruction-cycling.
    var breathPatternData: Data = Data()

    /// An authored inhale/hold/exhale sequence for Breath-type exercises,
    /// e.g. Box Breathing's [Inhale 4, Hold 4, Exhale 4, Hold 4]. Empty for
    /// every exercise until authored (see SeedData.json's "breathPattern" key)
    /// and for any exercise this doesn't apply to. Falls back to `[]` for any
    /// unparseable raw storage, same defensive treatment `poses`/`cueStyle` get.
    var breathPattern: [BreathPhaseStep] {
        get { (try? JSONDecoder().decode([BreathPhaseStep].self, from: breathPatternData)) ?? [] }
        set { breathPatternData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    /// Bundle-relative file name of Jason's self-filmed demo clip.
    var localVideoName: String? = nil

    /// Bundle-relative file name of the generated 3D muscle-animation loop
    /// (a baked, muted video). The scalable library tier; a filmed
    /// `localVideoName` wins over it when both are present (see `demoVideoName`).
    var animationName: String? = nil

    /// Whether the generated 3D animation is a known approximation of the
    /// real movement — e.g. because the rig has no bone for the joint that
    /// actually does the rotating (no wrist/hand/ankle/foot bone exists;
    /// see `Tools/blender/exercises/ANIMATION_HANDOFF.md`). Drives a small
    /// disclaimer under the media card so the animation isn't mistaken for
    /// an exact demonstration. Defaults to false — most animations are
    /// accurate; the seed JSON only needs to mark the known exceptions.
    var animationIsApproximate: Bool = false

    /// Raw JSON-encoded storage for `animationCallout` — a primitive `Data`
    /// property, not `AnimationCallout?` directly, for the same reason
    /// `posesData`/`breathPatternData` are: SwiftData's lightweight migration
    /// cannot safely decode a newly-added non-primitive property (here, a
    /// struct containing an enum and a `CGPoint`) on pre-existing on-disk
    /// rows. Empty `Data()` (the default) means "no callout authored" and
    /// decodes to `nil`.
    var animationCalloutData: Data = Data()

    /// An authored flash-an-arrow-and-instruction overlay for this exercise's
    /// animation, shown by `AnimationCalloutOverlay` when set. Takes priority
    /// over the generic `animationIsApproximate` disclaimer — see
    /// `showsApproximateAnimationNote`. `nil` for every exercise until
    /// authored (see SeedData.json's "animationCallout" key) and for any
    /// unparseable raw storage, same defensive treatment `poses`/`breathPattern` get.
    var animationCallout: AnimationCallout? {
        get { try? JSONDecoder().decode(AnimationCallout.self, from: animationCalloutData) }
        set {
            guard let newValue else { animationCalloutData = Data(); return }
            animationCalloutData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    /// Whether the media card should show the static "may not be 100%
    /// accurate" disclaimer (`AnimationAccuracyNote`). Implements the
    /// resolution order from the animation-callout spec: an authored
    /// `animationCallout` replaces this note entirely (no double messaging);
    /// otherwise it shows exactly when the legacy bool flag is set.
    var showsApproximateAnimationNote: Bool {
        animationCallout == nil && animationIsApproximate
    }

    /// Resolves a bundle-relative clip name to its URL — nil when the name is
    /// unset/empty OR the file isn't bundled, so the UI can always fall back to
    /// the placeholder card instead of a broken player.
    private static func bundledClipURL(_ name: String?) -> URL? {
        guard let name, !name.isEmpty else { return nil }
        let ns = name as NSString
        return Bundle.main.url(forResource: ns.deletingPathExtension,
                               withExtension: ns.pathExtension.isEmpty ? "mp4" : ns.pathExtension)
    }

    /// Resolved bundle URL for the filmed clip — nil when unset or not bundled.
    var localVideoURL: URL? { Self.bundledClipURL(localVideoName) }

    /// Resolved bundle URL for the generated animation loop.
    var animationVideoURL: URL? { Self.bundledClipURL(animationName) }

    /// The clip name to demo this exercise: a filmed clip (hero content) wins
    /// over the generated animation. Pure name-level precedence — bundle
    /// resolution happens in `demoVideoURL`.
    var demoVideoName: String? {
        if let name = localVideoName, !name.isEmpty { return name }
        if let name = animationName, !name.isEmpty { return name }
        return nil
    }

    /// Resolved bundle URL of the clip to play as this exercise's demo — the
    /// filmed clip if bundled, otherwise the generated animation loop.
    var demoVideoURL: URL? { localVideoURL ?? animationVideoURL }

    /// Whether the demo clip is the generated 3D animation (a standing portrait)
    /// rather than a filmed landscape clip. Drives the media card's aspect ratio.
    var demoIsAnimation: Bool {
        (localVideoName ?? "").isEmpty && !(animationName ?? "").isEmpty
    }

    /// Human-readable duration: "30s", "2m", "1m 30s"
    var durationFormatted: String {
        let m = durationSeconds / 60
        let s = durationSeconds % 60
        if m == 0 { return "\(s)s" }
        if s == 0 { return "\(m)m" }
        return "\(m)m \(s)s"
    }

    init(
        uuid: UUID = UUID(),
        name: String,
        type: ExerciseType,
        targetBodyParts: [String],
        durationSeconds: Int,
        difficulty: Int,
        instructions: [String],
        mediaURL: String? = nil,
        caution: String? = nil,
        isBilateral: Bool = true,
        cueStyle: ExerciseCueStyle = .hold
    ) {
        self.uuid = uuid
        self.name = name
        self.type = type
        self.targetBodyParts = targetBodyParts
        self.durationSeconds = durationSeconds
        self.difficulty = difficulty
        self.instructions = instructions
        self.mediaURL = mediaURL
        self.caution = caution
        self.isBilateral = isBilateral
        self.cueStyle = cueStyle
    }

    /// The uuid a bundled seed exercise should carry: the catalog entry's own
    /// permanent `"id"` when it parses as a UUID, else the name-derived
    /// fallback. Every path that inserts a seed exercise (first-launch
    /// seeding and the migrations that add exercises to upgraded installs)
    /// uses this, so a fresh install and an upgraded one agree on identity.
    static func seedUUID(seedID: String?, name: String) -> UUID {
        seedID.flatMap(UUID.init(uuidString:)) ?? stableSeedUUID(forName: name)
    }

    /// Deterministic UUID derived from an exercise's name, so seeding the same
    /// bundled catalog on two different installs produces the same id instead
    /// of `Exercise.init`'s default `uuid: UUID = UUID()` generating a fresh
    /// random one each time. Session.exerciseIDs, Routine.exerciseIDs, and
    /// Supabase's RemoteExercise.id all compare exercise UUIDs, so without
    /// this they'd mean nothing across devices for bundled seed exercises.
    static func stableSeedUUID(forName name: String) -> UUID {
        let digest = SHA256.hash(data: Data("breathapp.seed-exercise:\(name)".utf8))
        let bytes = Array(digest.prefix(16))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
