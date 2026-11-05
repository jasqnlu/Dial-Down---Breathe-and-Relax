import Foundation

/// What the Ask sheet should show for a request.
enum AskReply: Equatable {
    case routine(AskRoutine, intent: AskIntent)
    case safety(SafetyLevel, intent: AskIntent)
    case clarify
    case offTopic
    case noMatch(intent: AskIntent)
}

/// Safety screening, then intent extraction (AI with keyword fallback), then routine picking.
struct AskPipeline {
    let primary: IntentExtractor?
    let fallback: KeywordIntentExtractor
    let timeout: Duration

    init(primary: IntentExtractor?, fallback: KeywordIntentExtractor = .init(), timeout: Duration = .seconds(6)) {
        self.primary = primary
        self.fallback = fallback
        self.timeout = timeout
    }

    static func live() -> AskPipeline {
        AskPipeline(primary: ModelIntentExtractor.isAvailable ? ModelIntentExtractor() : nil)
    }

    func respond(to text: String, catalog: [Exercise]) async -> AskReply {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }) else {
            return .clarify
        }

        let screen = SafetyScreener.screen(trimmed)
        let intent = await extractIntent(from: trimmed)

        let level = max(screen, intent.seriousness)
        if level > .ok { return .safety(level, intent: intent) }
        if intent.isOffTopic { return .offTopic }
        if intent.isEmpty { return .clarify }

        if let routine = RoutinePicker.pick(intent: intent, from: catalog) {
            return .routine(routine, intent: intent)
        }
        return .noMatch(intent: intent)
    }

    func gentleRoutine(for intent: AskIntent, catalog: [Exercise]) -> AskReply {
        if let routine = RoutinePicker.pick(intent: intent, from: catalog, gentle: true) {
            return .routine(routine, intent: intent)
        }
        return .noMatch(intent: intent)
    }

    // MARK: - Private

    private func extractIntent(from text: String) async -> AskIntent {
        if let primary, let intent = await extractWithTimeout(primary, text) {
            return intent
        }
        return fallback.intent(for: text)
    }

    /// Races the extractor against a sleep; nil on throw or timeout.
    private func extractWithTimeout(_ extractor: IntentExtractor, _ text: String) async -> AskIntent? {
        let timeout = self.timeout
        return await withTaskGroup(of: AskIntent?.self) { group in
            group.addTask { try? await extractor.extract(text) }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
