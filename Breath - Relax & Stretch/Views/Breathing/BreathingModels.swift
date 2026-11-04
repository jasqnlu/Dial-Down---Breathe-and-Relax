import SwiftUI

// MARK: - Breathing Pattern

enum BreathingPattern: String, CaseIterable, Identifiable {
    case box            = "Box Breathing"
    case fourSevenEight = "4-7-8"
    case belly          = "Belly Breathing"
    case energising     = "Energising"
    case custom         = "Custom"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .box:            return "square.fill"
        case .fourSevenEight: return "lungs.fill"
        case .belly:          return "circle.fill"
        case .energising:     return "bolt.fill"
        case .custom:         return "slider.horizontal.3"
        }
    }

    var description: String {
        switch self {
        case .box:
            return "Equal inhale, hold, exhale, hold — great for stress relief and focus."
        case .fourSevenEight:
            return "Calming ratio that activates the parasympathetic nervous system."
        case .belly:
            return "Diaphragmatic breathing to deepen relaxation and release tension."
        case .energising:
            return "Short exhale ratio to boost alertness and mental clarity."
        case .custom:
            return "Your own rhythm — tap \"Edit Pattern\" below to set the timing."
        }
    }

    /// Durations: (inhale, hold, exhale, hold2) in seconds. 0 = skip phase.
    /// `.custom` reads from UserDefaults, written by CustomPatternEditorView.
    var phases: (inhale: Int, hold: Int, exhale: Int, hold2: Int) {
        switch self {
        case .box:            return (4, 4, 4, 4)
        case .fourSevenEight: return (4, 7, 8, 0)
        case .belly:          return (4, 1, 6, 0)
        case .energising:     return (6, 0, 2, 0)
        case .custom:
            let d = UserDefaults.standard
            let inhale = d.object(forKey: "customBreath.inhale") as? Int ?? 4
            let hold   = d.object(forKey: "customBreath.hold")   as? Int ?? 4
            let exhale = d.object(forKey: "customBreath.exhale") as? Int ?? 4
            let hold2  = d.object(forKey: "customBreath.hold2")  as? Int ?? 0
            return (inhale, hold, exhale, hold2)
        }
    }

    /// Icon-circle pastel for this pattern's tile.
    var pastel: Color {
        switch self {
        case .box:            return .pastelBlue
        case .fourSevenEight: return .pastelLavender
        case .belly:          return .pastelMint
        case .energising:     return .pastelYellow
        case .custom:         return .pastelPeach
        }
    }

    /// Total seconds for one full round.
    var roundDuration: Int {
        let p = phases
        return p.inhale + p.hold + p.exhale + p.hold2
    }
}

// MARK: - Breath Phase

enum BreathPhase: String {
    case inhale = "Inhale..."
    case hold   = "Hold..."
    case exhale = "Exhale..."
    case hold2  = "Hold2..."   // distinct raw value; displayLabel used for UI text

    /// Human-readable label — both hold phases show "Hold..."
    var displayLabel: String {
        switch self {
        case .inhale:       return "Inhale..."
        case .hold, .hold2: return "Hold..."
        case .exhale:       return "Exhale..."
        }
    }

    /// Pastel family (seperate-main restyle): soft blue in, lavender hold,
    /// mint out — calmer on the black page than saturated colors.
    var color: Color {
        switch self {
        case .inhale:       return .pastelBlue
        case .hold, .hold2: return .pastelLavender
        case .exhale:       return .pastelMint
        }
    }
}
