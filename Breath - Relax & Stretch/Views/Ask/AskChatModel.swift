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
    /// The mini routine this chat is building. Requests add to it; "start over"-style
    /// requests replace it. Lives as long as this model (in memory only).
    private(set) var draft = AskDraft()
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
        let reply = await pipeline.respond(to: trimmed, catalog: catalog, excluding: draft.ids)
        isThinking = false
        messages.append(AskMessage(role: .reply, reply: absorb(reply, catalog: catalog)))
    }

    /// Folds a pipeline reply into the draft and returns what the chat should show.
    private func absorb(_ reply: AskReply, catalog: [Exercise]) -> AskReply {
        switch reply {
        case .routine(let routine, let intent):
            if intent.wantsNewRoutine {
                draft.replace(with: routine, intent: intent)
            } else {
                draft.add(routine, intent: intent)
            }
            return reply
        case .edit(let intent):
            return resolve(intent, catalog: catalog)
        default:
            return reply
        }
    }

    private func resolve(_ intent: AskIntent, catalog: [Exercise]) -> AskReply {
        let isMoreOfTheSame = intent.edit == nil && !intent.wantsNewRoutine && intent.count != nil
        if isMoreOfTheSame {
            // "2 more", "another one": the area and goal of the last request.
            guard let last = draft.lastIntent else { return .clarify }
            var filled = intent
            filled.areas = last.areas
            filled.goal = last.goal
            return absorb(pipeline.routine(for: filled, catalog: catalog, excluding: draft.ids), catalog: catalog)
        }
        // "make it 5 minutes" with nothing built yet is a fresh request we can't place.
        if draft.isEmpty && intent.edit == nil && !intent.wantsNewRoutine { return .clarify }
        return .draftChanged(draft.apply(intent, catalog: catalog))
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
        let reply = pipeline.gentleRoutine(for: intent, catalog: catalog, excluding: draft.ids)
        messages.append(AskMessage(role: .reply, reply: absorb(reply, catalog: catalog)))
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
