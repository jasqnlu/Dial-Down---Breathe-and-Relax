import Foundation
import Observation

struct AskMessage: Identifiable, Equatable {
    enum Role { case user, reply }

    let id: UUID
    let role: Role
    /// The user's words, or the reply resolved to plain text (accessibility, tests).
    let text: String
    let reply: AskReply?

    init(id: UUID = UUID(), role: Role, text: String, reply: AskReply? = nil) {
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
        messages.append(AskMessage(role: .reply, text: reply.plainText, reply: reply))
    }

    /// Swaps a "concerning" safety reply for a gentle (difficulty 1) routine.
    /// Urgent replies have no such path and are left untouched.
    func showGentleAnyway(for messageID: UUID, catalog: [Exercise]) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }),
              case .safety(.concerning, let intent)? = messages[index].reply else { return }
        let reply = pipeline.gentleRoutine(for: intent, catalog: catalog)
        messages[index] = AskMessage(id: messageID, role: .reply, text: reply.plainText, reply: reply)
    }
}

// MARK: - Reply text

extension AskReply {
    /// The reply as a localized plain string. Views render the same copy through
    /// `LocalizedStringKey` so the in-app language applies.
    var plainText: String {
        switch self {
        case .routine(let routine, let intent):
            let minutes = routine.displayMinutes
            if intent.areas.isEmpty {
                return String(localized: "Here's a gentle \(minutes)-minute routine.")
            }
            return String(localized: "Here's a gentle \(minutes)-minute routine for your \(intent.areaList()).")
        case .safety(let level, _):
            return level == .urgent ? Self.urgentText : Self.concerningText + " " + Self.urgentText
        case .clarify:
            return String(localized: "Tell me where you feel it or what you'd like — for example, \"stiff neck\" or \"help me sleep\".")
        case .offTopic:
            return String(localized: "I can help you find stretches and breathing exercises.")
        case .noMatch:
            return String(localized: "I couldn't find stretches for that yet.")
        }
    }

    static var concerningText: String {
        String(localized: "This sounds like more than everyday tightness. It's worth checking with a doctor before stretching.")
    }
    static var urgentText: String {
        String(localized: "If the pain is severe or came on suddenly, please call emergency services.")
    }
}

extension AskRoutine {
    /// Total length in whole minutes, rounded up (at least 1).
    var displayMinutes: Int { max(1, (totalSeconds + 59) / 60) }
}

extension AskIntent {
    /// Localized area names joined as a list ("neck and shoulders").
    func areaList(locale: Locale = .current) -> String {
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
