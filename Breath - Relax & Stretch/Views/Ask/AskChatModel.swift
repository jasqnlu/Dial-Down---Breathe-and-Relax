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
            return String(localized: "Here's a gentle \(minutes)-minute routine for your \(intent.areaList).")
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
    var areaList: String {
        areas.map(\.displayName).formatted(.list(type: .and))
    }
}

extension AskArea {
    var displayName: String {
        switch self {
        case .neck:       String(localized: "neck")
        case .head:       String(localized: "head")
        case .jaw:        String(localized: "jaw")
        case .eyes:       String(localized: "eyes")
        case .upperBack:  String(localized: "upper back")
        case .shoulders:  String(localized: "shoulders")
        case .chest:      String(localized: "chest")
        case .core:       String(localized: "core")
        case .obliques:   String(localized: "obliques")
        case .lats:       String(localized: "lats")
        case .lowerBack:  String(localized: "lower back")
        case .biceps:     String(localized: "biceps")
        case .triceps:    String(localized: "triceps")
        case .forearms:   String(localized: "forearms")
        case .hands:      String(localized: "hands")
        case .glutes:     String(localized: "glutes")
        case .hipFlexors: String(localized: "hip flexors")
        case .hips:       String(localized: "hips")
        case .adductors:  String(localized: "inner thighs")
        case .quads:      String(localized: "quads")
        case .hamstrings: String(localized: "hamstrings")
        case .calves:     String(localized: "calves")
        case .shins:      String(localized: "shins")
        case .feet:       String(localized: "feet")
        }
    }
}
