import Foundation
import FoundationModels

/// Side-neutral body areas a request can name. Each maps to the catalog tags
/// (`MuscleGroup` / joint-region names) fed to `RegionExerciseResolver`.
@Generable
enum AskArea: String, CaseIterable, Codable {
    case neck, head, jaw, eyes, upperBack, shoulders, chest, core, obliques, lats
    case lowerBack, biceps, triceps, forearms, hands, glutes, hipFlexors, hips
    case adductors, quads, hamstrings, calves, shins, feet

    var regions: [String] {
        switch self {
        case .lowerBack:  return ["Lower Back", "Spinal Erectors", "Lower Spine"]
        case .neck:       return ["Front Neck", "Back Neck", "Neck"]
        case .upperBack:  return ["Left Trapezius", "Right Trapezius"]
        case .shoulders:  return ["Left Shoulder", "Right Shoulder",
                                  "Left Shoulder Joint", "Right Shoulder Joint"]
        case .hips:       return ["Left Hip", "Right Hip"]
        case .head:       return ["Head", "Forehead", "Left Temple", "Right Temple"]
        case .jaw:        return ["Left Jaw", "Right Jaw"]
        case .eyes:       return ["Left Eye", "Right Eye"]
        case .chest:      return Self.pair("Chest")
        case .core:       return Self.pair("Abs")
        case .obliques:   return Self.pair("Obliques")
        case .lats:       return Self.pair("Lats")
        case .biceps:     return Self.pair("Biceps")
        case .triceps:    return Self.pair("Triceps")
        case .forearms:   return Self.pair("Forearm")
        case .hands:      return Self.pair("Hand")
        case .glutes:     return Self.pair("Glutes")
        case .hipFlexors: return Self.pair("Hip Flexors")
        case .adductors:  return Self.pair("Adductors")
        case .quads:      return Self.pair("Quadriceps")
        case .hamstrings: return Self.pair("Hamstrings")
        case .calves:     return Self.pair("Calves")
        case .shins:      return Self.pair("Tibialis")
        case .feet:       return Self.pair("Foot")
        }
    }

    private static func pair(_ name: String) -> [String] { ["Left \(name)", "Right \(name)"] }
}

/// Goals a request can name. Raw values equal `GoalMeta` ids.
@Generable
enum AskGoal: String, CaseIterable, Codable {
    case flexibility
    case stress_relief
    case pain_relief
    case better_breathing
    case wake_up
    case unwind
}

/// Ways a request can change the routine already built.
@Generable
enum AskEdit: String, CaseIterable, Codable {
    case remove, swap, shorter, longer
}

/// One answer to "Did you mean…?": a body area, or a catalog exercise by its shared
/// name (a Left/Right pair by the name without its side).
enum AskChoice: Hashable {
    case area(AskArea)
    case exercise(String)
}

enum SafetyLevel: Int, Comparable, Codable {
    case ok = 0, concerning, urgent

    static func < (lhs: SafetyLevel, rhs: SafetyLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// What the extractor understood from a request. The AI only ever fills this;
/// it never names exercises.
struct AskIntent: Equatable {
    var areas: [AskArea]
    var goal: AskGoal?
    var minutes: Int?
    var seriousness: SafetyLevel
    var isOffTopic: Bool
    /// Exercises asked for ("3 stretches"), 1...10. A Left/Right pair counts as one.
    var count: Int? = nil
    /// The user explicitly asked for a new routine ("start over", "create a new routine").
    /// Otherwise a request adds to the routine they're building.
    var wantsNewRoutine = false
    /// A change to the routine already built ("remove the last one", "make it shorter").
    var edit: AskEdit? = nil

    /// Only makes sense against the routine being built: an edit, or "start over",
    /// "2 more", "make it 5 minutes" with no area or goal of their own.
    var isDraftEdit: Bool {
        edit != nil || (isEmpty && (wantsNewRoutine || count != nil || minutes != nil))
    }

    /// Largest `count` any extractor reports.
    static let maxCount = 10

    var isEmpty: Bool { areas.isEmpty && goal == nil }
}

protocol IntentExtractor {
    func extract(_ text: String) async throws -> AskIntent
}
