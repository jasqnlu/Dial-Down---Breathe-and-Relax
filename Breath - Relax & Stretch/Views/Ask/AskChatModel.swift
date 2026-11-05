import Foundation
import Observation

struct AskMessage: Identifiable, Equatable {
    enum Role { case user, reply }

    let id: UUID
    let role: Role
    /// The user's words (empty for replies, which the sheet renders from `reply`
    /// in the in-app language).
    let text: String
    let reply: AskReply?

    init(id: UUID = UUID(), role: Role, text: String = "", reply: AskReply? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.reply = reply
    }
}

@MainActor
@Observable
final class AskChatModel {
    private(set) var messages: [AskMessage] = []
    private(set) var isThinking = false
    /// Safety messages whose "show gentle stretches anyway" option has been used.
    private(set) var gentleShownFor: Set<UUID> = []
    /// Dictation that arrived while a reply was being worked out; the sheet moves it
    /// into its text field (see `takePendingDraft()`).
    private(set) var pendingDraft: String?
    private let pipeline: AskPipeline

    init(pipeline: AskPipeline) {
        self.pipeline = pipeline
    }

    func send(_ text: String, catalog: [Exercise]) async {
        guard !isThinking else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            messages.append(AskMessage(role: .user, text: trimmed))
        }
        isThinking = true
        let reply = await pipeline.respond(to: trimmed, catalog: catalog)
        isThinking = false
        messages.append(AskMessage(role: .reply, reply: reply))
    }

    /// Sends dictated words, or keeps them as a draft if a reply is still being worked out.
    func acceptDictation(_ text: String, catalog: [Exercise]) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if isThinking {
            pendingDraft = [pendingDraft, trimmed].compactMap { $0 }.joined(separator: " ")
        } else {
            await send(trimmed, catalog: catalog)
        }
    }

    /// Hands over (and clears) dictation kept while thinking.
    func takePendingDraft() -> String? {
        defer { pendingDraft = nil }
        return pendingDraft
    }

    /// Adds a gentle (difficulty 1) routine below a "concerning" safety reply, which
    /// stays in place so its advice and emergency button remain visible. Works once
    /// per safety message. Urgent replies have no such path and are left untouched.
    func showGentleAnyway(for messageID: UUID, catalog: [Exercise]) {
        guard !gentleShownFor.contains(messageID),
              let message = messages.first(where: { $0.id == messageID }),
              case .safety(.concerning, let intent)? = message.reply else { return }
        gentleShownFor.insert(messageID)
        messages.append(AskMessage(role: .reply, reply: pipeline.gentleRoutine(for: intent, catalog: catalog)))
    }
}

extension AskRoutine {
    /// Total length in whole minutes, rounded up (at least 1).
    var displayMinutes: Int { max(1, (totalSeconds + 59) / 60) }
}

extension AskIntent {
    /// Localized area names joined as a list ("neck and shoulders").
    func areaList(locale: Locale) -> String {
        areas.map { $0.displayName.resolved(in: locale) }
            .formatted(.list(type: .and).locale(locale))
    }
}

extension LocalizedStringResource {
    /// Resolves in `locale` (the in-app language), not the system one.
    func resolved(in locale: Locale) -> String {
        var copy = self
        copy.locale = locale
        return String(localized: copy)
    }
}

extension AskArea {
    var displayName: LocalizedStringResource {
        switch self {
        case .neck:       LocalizedStringResource("neck")
        case .head:       LocalizedStringResource("head")
        case .jaw:        LocalizedStringResource("jaw")
        case .eyes:       LocalizedStringResource("eyes")
        case .upperBack:  LocalizedStringResource("upper back")
        case .shoulders:  LocalizedStringResource("shoulders")
        case .chest:      LocalizedStringResource("chest")
        case .core:       LocalizedStringResource("core")
        case .obliques:   LocalizedStringResource("obliques")
        case .lats:       LocalizedStringResource("lats")
        case .lowerBack:  LocalizedStringResource("lower back")
        case .biceps:     LocalizedStringResource("biceps")
        case .triceps:    LocalizedStringResource("triceps")
        case .forearms:   LocalizedStringResource("forearms")
        case .hands:      LocalizedStringResource("hands")
        case .glutes:     LocalizedStringResource("glutes")
        case .hipFlexors: LocalizedStringResource("hip flexors")
        case .hips:       LocalizedStringResource("hips")
        case .adductors:  LocalizedStringResource("inner thighs")
        case .quads:      LocalizedStringResource("quads")
        case .hamstrings: LocalizedStringResource("hamstrings")
        case .calves:     LocalizedStringResource("calves")
        case .shins:      LocalizedStringResource("shins")
        case .feet:       LocalizedStringResource("feet")
        }
    }
}
