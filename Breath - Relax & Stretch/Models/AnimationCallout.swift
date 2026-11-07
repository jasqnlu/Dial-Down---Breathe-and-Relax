import Foundation
import CoreGraphics

/// An authored "flash an arrow + instruction" overlay for an exercise whose
/// generated 3D animation is a known approximation of the real movement (the
/// rig has no bone for the joint that actually moves — see
/// `Tools/blender/exercises/ANIMATION_HANDOFF.md`). Drawn on top of the
/// existing baked mp4 loop by `AnimationCalloutOverlay`, timed to the moment
/// in the loop where the rig's motion diverges from the real exercise.
///
/// See docs/superpowers/specs/2026-09-06-exercise-animation-instruction-callouts-design.md
/// for the full design.
nonisolated struct AnimationCallout: Codable, Equatable {
    /// Which arrow primitive `AnimationCalloutOverlay` draws. `angle`'s
    /// meaning is documented per case below.
    enum Shape: String, Codable {
        /// Full circular arrow, for joint rotations (ankle circles, wrist
        /// circles, neck rotation, shoulder rolls). `angle` is the arrow's
        /// starting position on the circle, in degrees, measured
        /// counterclockwise from the positive x-axis (screen-right).
        case rotate
        /// A partial arc with an arrowhead, for a limb swinging through a
        /// partial range (flexion/extension). `angle` is the arc's start
        /// angle in degrees, same convention as `.rotate`.
        case swingArc
        /// A straight arrow, for a linear direction (push forward, reach
        /// up). `angle` is the arrow's direction in degrees: 0 points
        /// screen-right, 90 points screen-up, increasing counterclockwise.
        case pushPull
        /// An expanding ring with no direction, for "focus here" emphasis
        /// when no directional cue is needed. `angle` is unused but kept for
        /// a uniform authoring shape across all four cases.
        case pulse
    }

    /// The instruction shown in the text pill, e.g. "Rotate your ankle in a
    /// circle". Always exposed via `accessibilityLabel`, independent of the
    /// fade timing.
    var text: String
    var shape: Shape
    /// Normalized (0-1) position within the video frame, authored by
    /// eyeballing the already-rendered clip — (0, 0) is the top-left corner.
    var anchor: CGPoint
    /// Orientation / arc-start angle in degrees. Meaning depends on `shape`
    /// — see the cases above.
    var angle: Double
    /// Seconds into the loop when the callout should start appearing.
    var startTime: Double
    /// How long the callout stays visible (including its fade in/out).
    /// Defaults to 2 seconds when the seed JSON omits the key.
    var duration: Double = 2.0

    private enum CodingKeys: String, CodingKey {
        case text, shape, anchor, angle, startTime, duration
    }

    init(text: String, shape: Shape, anchor: CGPoint, angle: Double, startTime: Double, duration: Double = 2.0) {
        self.text = text
        self.shape = shape
        self.anchor = anchor
        self.angle = angle
        self.startTime = startTime
        self.duration = duration
    }

    /// Custom decode so `duration` can fall back to its 2-second default when
    /// the seed JSON omits the key — the compiler-synthesized `Decodable`
    /// would otherwise require every key to be present regardless of the
    /// property's default value.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        shape = try container.decode(Shape.self, forKey: .shape)
        anchor = try container.decode(CGPoint.self, forKey: .anchor)
        angle = try container.decode(Double.self, forKey: .angle)
        startTime = try container.decode(Double.self, forKey: .startTime)
        duration = try container.decodeIfPresent(Double.self, forKey: .duration) ?? 2.0
    }

    /// How long the opacity ramps at the start and end of the callout's
    /// visible window.
    static let fadeDuration: Double = 0.3

    /// Pure "time in loop -> opacity" envelope, independent of any view or
    /// `AVPlayer` — unit-testable on its own. Opacity is 0 before
    /// `startTime`, ramps 0->1 over `fadeDuration`, holds at 1, ramps 1->0
    /// over `fadeDuration` ending at `startTime + duration`, then 0 again.
    /// A `duration` shorter than 2x `fadeDuration` clamps each fade to half
    /// the duration so the ramps never overlap past 1.0.
    func opacity(atLoopTime t: Double) -> Double {
        let end = startTime + duration
        guard t >= startTime, t <= end else { return 0 }

        let fadeIn = min(Self.fadeDuration, duration / 2)
        let fadeOut = min(Self.fadeDuration, duration / 2)

        if fadeIn > 0, t < startTime + fadeIn {
            return (t - startTime) / fadeIn
        }
        if fadeOut > 0, t > end - fadeOut {
            return (end - t) / fadeOut
        }
        return 1
    }

    /// Parses the optional `animationCallout` object out of a raw
    /// `SeedData.json` exercise dictionary (as produced by
    /// `JSONSerialization`), the same shape `seedIfNeeded`/`SeedMigrator`
    /// parse every other field from. Returns `nil` when the key is absent or
    /// malformed — callers fall back to the legacy `animationIsApproximate`
    /// bool disclaimer.
    static func parse(fromRawExercise raw: [String: Any]) -> AnimationCallout? {
        guard let calloutRaw = raw["animationCallout"] as? [String: Any],
              let data = try? JSONSerialization.data(withJSONObject: calloutRaw)
        else { return nil }
        return try? JSONDecoder().decode(AnimationCallout.self, from: data)
    }
}
