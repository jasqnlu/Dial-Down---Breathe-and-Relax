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
    /// A request that only makes sense against the routine being built. `AskChatModel`
    /// resolves it against its draft; it is never shown as is.
    case edit(AskIntent)
    /// What a resolved `.edit` did to the routine.
    case draftChanged(AskDraftChange)
    /// `word` matched no body area but sounds like one or names an exercise ("cat" for
    /// "calf"): ask instead of guessing. `intent` keeps the rest of the request (count…).
    case choose(word: String, intent: AskIntent, choices: [AskChoice])
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

    func respond(to text: String, catalog: [Exercise], excluding: Set<UUID> = []) async -> AskReply {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }) else {
            return .clarify
        }

        let screen = SafetyScreener.screen(trimmed)
        var intent = await extractIntent(from: trimmed)
        // Urgent (the emergency card) needs a red-flag phrase from the screener. The model
        // over-reads ("another calf exercise" came back urgent on device), so on its own it
        // may only suggest a doctor (concerning), and only when a symptom is described.
        intent.seriousness = SafetyScreener.describesSymptom(trimmed)
            ? min(intent.seriousness, .concerning) : .ok

        let level = max(screen, intent.seriousness)
        if level > .ok { return .safety(level, intent: intent) }
        // Nothing literal to go on but a word that sounds like an area or names an
        // exercise: ask before trusting the model's guess (before off-topic, too, since a
        // misheard word is likelier than an off-topic request in this app).
        let literal = fallback.intent(for: trimmed)
        if literal.isEmpty && literal.edit == nil && !literal.wantsNewRoutine,
           let found = AskChoices.find(in: trimmed, catalog: catalog, excluding: excluding) {
            return .choose(word: found.word, intent: intent, choices: found.choices)
        }
        if intent.isOffTopic { return .offTopic }
        if intent.isDraftEdit { return .edit(intent) }
        if intent.isEmpty { return .clarify }
        return routine(for: intent, catalog: catalog, excluding: excluding)
    }

    /// A routine for `intent` that skips `excluding` (the draft), unless the user asked
    /// for a new routine, which may reuse anything.
    func routine(for intent: AskIntent, catalog: [Exercise], excluding: Set<UUID> = []) -> AskReply {
        let skip = intent.wantsNewRoutine ? [] : excluding
        if let routine = RoutinePicker.pick(intent: intent, from: catalog, excluding: skip) {
            return .routine(routine, intent: intent)
        }
        return .noMatch(intent: intent)
    }

    func gentleRoutine(for intent: AskIntent, catalog: [Exercise], excluding: Set<UUID> = []) -> AskReply {
        if let routine = RoutinePicker.pick(intent: intent, from: catalog, gentle: true, excluding: excluding) {
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
        // Replacing throws the routine away, so only explicit wording does it (the model
        // turned "add a cat exercise to this" into a new routine on device).
        model.wantsNewRoutine = keyword.wantsNewRoutine
        // Areas the user literally named beat the model's reading of them.
        if !keyword.areas.isEmpty { model.areas = keyword.areas }
        // An edit can delete exercises, so a model guess never beats clear "add" wording
        // ("Can I get one calf exercise, add this" was read as an edit on device).
        let asksToAdd = keyword.count != nil || KeywordIntentExtractor.asksToAdd(text)
        model.edit = keyword.edit ?? (asksToAdd ? nil : model.edit)
        // "remove the last one" names no stretch, so the model may call it off-topic. Only
        // explicit routine wording overrides that; a bare number ("a poem in 5 minutes") doesn't.
        if keyword.edit != nil || keyword.wantsNewRoutine { model.isOffTopic = false }
        guard model.isEmpty && !model.isOffTopic else { return model }
        var merged = keyword
        merged.seriousness = max(model.seriousness, keyword.seriousness)
        merged.edit = merged.edit ?? model.edit   // "I don't like the last one" names no area
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
