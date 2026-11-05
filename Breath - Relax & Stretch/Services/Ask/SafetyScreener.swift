import Foundation

/// Deterministic red-flag phrase checker. Runs before any routine is built.
/// Checks all four app languages regardless of the current app language.
enum SafetyScreener {
    static func screen(_ text: String) -> SafetyLevel {
        let normalized = normalize(text)
        let padded = boundaryForm(normalized)
        if urgentPhrases.contains(where: { $0.matches(normalized, padded) }) { return .urgent }
        if concerningPhrases.contains(where: { $0.matches(normalized, padded) }) { return .concerning }
        return .ok
    }

    /// Lowercased, diacritics folded, apostrophe variants straightened, whitespace collapsed.
    static func normalize(_ text: String) -> String {
        var s = text
        for variant in ["\u{2019}", "\u{2018}", "\u{02BC}", "\u{FF07}"] {
            s = s.replacingOccurrences(of: variant, with: "'")
        }
        let folded = s
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
        return folded.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Normalized text with every non-letter/digit turned into a space, padded with spaces,
    /// so Latin phrases can be matched on word boundaries.
    private static func boundaryForm(_ normalized: String) -> String {
        let mapped = String(normalized.unicodeScalars.map {
            CharacterSet.alphanumerics.contains($0) ? Character($0) : " "
        })
        return " " + mapped.split(separator: " ").joined(separator: " ") + " "
    }

    private struct Phrase {
        let text: String          // normalized
        let boundary: String      // word-boundary form
        let isStem: Bool          // trailing "*" in source: may continue into a longer word
        let isCJK: Bool

        init(_ source: String) {
            isStem = source.hasSuffix("*")
            text = SafetyScreener.normalize(isStem ? String(source.dropLast()) : source)
            boundary = SafetyScreener.boundaryForm(text).dropLast(isStem ? 1 : 0).description
            isCJK = text.unicodeScalars.contains { $0.value >= 0x2E80 }
        }

        func matches(_ normalized: String, _ padded: String) -> Bool {
            isCJK ? normalized.contains(text) : padded.contains(boundary)
        }
    }

    // Phrases ending in "*" are deliberate stems (match as a word prefix); all other
    // Latin-script phrases match whole words only. CJK phrases match as substrings.
    private static let urgentPhrases: [Phrase] = [
        // en
        "chest pain", "can't breathe", "cant breathe", "cannot breathe", "can not breathe",
        "trouble breathing", "difficulty breathing", "shortness of breath", "short of breath",
        "unbearable", "worst pain", "passed out", "fainted", "can't move my legs",
        "can't feel my legs", "lost control of my bladder", "heart attack", "stroke",
        "pain in my chest", "chest tightness", "chest pressure",
        // es
        "dolor en el pecho", "dolor de pecho", "no puedo respirar", "dificultad para respirar",
        "insoportable", "me desmaye", "me desmayo",
        // fr
        "douleur thoracique", "douleur a la poitrine", "mal a la poitrine",
        "je ne peux pas respirer", "difficulte a respirer", "insupportable", "evanoui*",
        // zh
        "胸痛", "胸口疼", "胸闷", "喘不过气", "无法呼吸", "呼吸困难", "晕倒", "疼得受不了",
    ].map { Phrase($0) }

    private static let concerningPhrases: [Phrase] = [
        // en
        "sharp", "shooting", "numb", "numbness", "tingling", "pins and needles", "after a fall",
        "fell", "accident", "swollen", "for weeks", "getting worse",
        // es
        "punzante", "entumecid*", "hormigueo", "despues de una caida", "hinchad*", "empeora",
        // fr
        "aigu", "aigue", "lancinant", "engourdi*", "fourmillement", "apres une chute", "enfle*",
        "ca empire", "de pire en pire",
        // zh
        "刺痛", "麻木", "发麻", "摔倒", "肿", "越来越疼",
    ].map { Phrase($0) }
}
