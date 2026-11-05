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

    var isEmpty: Bool { areas.isEmpty && goal == nil }
}

protocol IntentExtractor {
    func extract(_ text: String) async throws -> AskIntent
}
