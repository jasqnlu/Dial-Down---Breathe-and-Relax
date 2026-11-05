import Foundation

/// One phrase from the Ask keyword tables (safety screener and keyword extractor),
/// matched against text in `boundaryForm`.
/// - Latin-script phrases match whole words: "back" never matches "backpack".
/// - A trailing "*" in the source marks a stem that may continue into a longer word
///   ("tingl*" matches "tingly" and "tingling"). Never put "*" mid-phrase.
/// - CJK phrases match as substrings (Chinese has no spaces between words).
nonisolated struct PhraseMatcher {
    /// The phrase in boundary form, without the padding spaces.
    let text: String
    let isStem: Bool
    let isCJK: Bool

    init(_ source: String) {
        isStem = source.hasSuffix("*")
        let raw = isStem ? String(source.dropLast()) : source
        text = Self.boundaryForm(Self.normalize(raw)).trimmingCharacters(in: .whitespaces)
        isCJK = text.unicodeScalars.contains { $0.value >= 0x2E80 }
    }

    /// What is searched for in a boundary-form haystack.
    private var needle: String {
        isCJK ? text : " " + text + (isStem ? "" : " ")
    }

    /// `haystack` must be in `boundaryForm`.
    func matches(_ haystack: String) -> Bool { haystack.contains(needle) }

    /// Replaces the first match with spaces (keeping neighbouring boundary spaces).
    func blankFirstMatch(in haystack: inout String) -> Bool {
        guard let found = haystack.range(of: needle) else { return false }
        var inner = found
        if !isCJK {
            inner = haystack.index(after: found.lowerBound)..<(isStem ? found.upperBound
                                                               : haystack.index(before: found.upperBound))
        }
        haystack.replaceSubrange(inner, with: String(repeating: " ", count: haystack[inner].count))
        return true
    }

    // MARK: - Text forms

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

    /// Normalized text with every non-letter/digit turned into a space, single-spaced and
    /// padded with spaces, so Latin phrases can be matched on word boundaries.
    static func boundaryForm(_ normalized: String) -> String {
        let mapped = String(normalized.unicodeScalars.map {
            CharacterSet.alphanumerics.contains($0) ? Character($0) : " "
        })
        return " " + mapped.split(separator: " ").joined(separator: " ") + " "
    }
}
