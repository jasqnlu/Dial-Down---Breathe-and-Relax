import Foundation

/// What the Ask sheet should show for a request.
enum AskReply: Equatable {
    case routine(AskRoutine, intent: AskIntent)
    case safety(SafetyLevel, intent: AskIntent)
    case clarify
    case offTopic
    case noMatch(intent: AskIntent)
    /// "Show gentle stretches anyway" found nothing gentle; offers browsing instead.
    case gentleNoMatch(intent: AskIntent)
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
        return .gentleNoMatch(intent: intent)
    }

    // MARK: - Private

    private func extractIntent(from text: String) async -> AskIntent {
        let keyword = fallback.intent(for: text)
        guard let primary, var model = await extractWithTimeout(primary, text) else { return keyword }
        // An explicit number or "start over" is read precisely by the keyword parser;
        // prefer it so a model slip can't turn "3 exercises" into 5.
        model.count = keyword.count ?? model.count
        model.wantsNewRoutine = model.wantsNewRoutine || keyword.wantsNewRoutine
        guard model.isEmpty && !model.isOffTopic else { return model }
        var merged = keyword
        merged.seriousness = max(model.seriousness, keyword.seriousness)
        return merged
    }

    /// Races the extractor against a sleep and resumes with whichever finishes first
    /// (nil on throw or timeout). Returns on time even if the extractor ignores cancellation.
    private func extractWithTimeout(_ extractor: IntentExtractor, _ text: String) async -> AskIntent? {
        let timeout = self.timeout
        let race = Race()
        return await withCheckedContinuation { continuation in
            race.continuation = continuation
            race.work = Task { race.finish(try? await extractor.extract(text)) }
            race.timer = Task {
                try? await Task.sleep(for: timeout)
                race.finish(nil)
            }
        }
    }

    /// Resumes its continuation exactly once, then cancels both racers.
    @MainActor
    private final class Race {
        var continuation: CheckedContinuation<AskIntent?, Never>?
        var work: Task<Void, Never>?
        var timer: Task<Void, Never>?

        func finish(_ value: AskIntent?) {
            guard let continuation else { return }
            self.continuation = nil
            continuation.resume(returning: value)
            work?.cancel()
            timer?.cancel()
        }
    }
}
