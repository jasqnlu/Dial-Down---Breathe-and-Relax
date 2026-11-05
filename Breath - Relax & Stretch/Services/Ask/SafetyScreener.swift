import Foundation

/// Deterministic red-flag phrase checker. Runs before any routine is built.
/// Checks all four app languages regardless of the current app language.
enum SafetyScreener {
    static func screen(_ text: String) -> SafetyLevel {
        let normalized = normalize(text)
        if urgentPhrases.contains(where: normalized.contains) { return .urgent }
        if concerningPhrases.contains(where: normalized.contains) { return .concerning }
        return .ok
    }

    /// Lowercased, diacritics folded, curly apostrophes straightened, whitespace collapsed.
    static func normalize(_ text: String) -> String {
        let folded = text
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
        return folded.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static let urgentPhrases: [String] = [
        // en
        "chest pain", "can't breathe", "cant breathe", "trouble breathing", "unbearable",
        "worst pain", "passed out", "fainted", "can't move my legs", "lost control of my bladder",
        // es
        "dolor en el pecho", "no puedo respirar", "insoportable", "me desmaye",
        // fr
        "douleur thoracique", "douleur a la poitrine", "je ne peux pas respirer",
        "insupportable", "evanoui",
        // zh
        "胸痛", "胸口疼", "喘不过气", "无法呼吸", "晕倒", "疼得受不了",
    ].map(normalize)

    private static let concerningPhrases: [String] = [
        // en
        "sharp", "shooting", "numb", "tingling", "pins and needles", "after a fall", "fell",
        "accident", "swollen", "for weeks", "getting worse",
        // es
        "punzante", "entumecid", "hormigueo", "despues de una caida", "hinchad", "empeora",
        // fr
        "aigu", "lancinant", "engourdi", "fourmillement", "apres une chute", "enfle", "empire",
        // zh
        "刺痛", "麻木", "发麻", "摔倒", "肿", "越来越疼",
    ].map(normalize)
}
