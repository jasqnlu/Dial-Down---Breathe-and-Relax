import Foundation
import FoundationModels

/// Mirror of `SafetyLevel` for guided generation (`@Generable` conflicts with its
/// `Comparable` conformance on an Int-raw enum).
@Generable
enum GeneratedSeriousness {
    case ok, concerning, urgent

    var level: SafetyLevel {
        switch self {
        case .ok: .ok
        case .concerning: .concerning
        case .urgent: .urgent
        }
    }
}

/// Shape the on-device model fills in via guided generation. It never names exercises.
@Generable
struct GeneratedIntent {
    @Guide(description: "Body areas the request mentions. Left and right are the same area. Empty if none.", .maximumCount(4))
    var areas: [AskArea]
    @Guide(description: "The goal the user wants, if any.")
    var goal: AskGoal?
    @Guide(description: "Minutes the user asked for, if they named a duration.")
    var minutes: Int?
    @Guide(description: "How many exercises or stretches the user asked for, if they named a number of them. Not minutes.")
    var count: Int? = nil
    @Guide(description: "True only if the user explicitly asks for a new or different routine, to start over, or for something instead. False when they just ask for more or name a body area.")
    var wantsNewRoutine: Bool = false
    @Guide(description: "How serious the described symptoms are.")
    var seriousness: GeneratedSeriousness
    @Guide(description: "True if the request is not about stretching, breathing, tension or soreness.")
    var isOffTopic: Bool

    func toIntent() -> AskIntent {
        var seen = Set<AskArea>()
        let uniqueAreas = areas.filter { seen.insert($0).inserted }
        let clampedMinutes = minutes.flatMap { $0 >= 1 ? min($0, 20) : nil }
        let clampedCount = count.flatMap { $0 >= 1 ? min($0, AskIntent.maxCount) : nil }
        return AskIntent(areas: uniqueAreas, goal: goal, minutes: clampedMinutes,
                         seriousness: seriousness.level, isOffTopic: isOffTopic,
                         count: clampedCount, wantsNewRoutine: wantsNewRoutine)
    }
}

/// Understands a request with Apple's on-device model. One fresh session per request.
struct ModelIntentExtractor: IntentExtractor {
    static var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    private static let instructions = """
        You help a stretching and breathing app understand a short request. Fill in the \
        requested fields only; never name exercises. Map the user's words to the listed body \
        areas and goals. Treat left and right as the same area.
        Set seriousness to urgent for chest pain, trouble breathing, fainting, unbearable pain, \
        or loss of bladder, bowel or leg control. Set it to concerning for sharp or shooting pain, \
        numbness, tingling, an injury from a fall or accident, swelling, or pain lasting weeks. \
        Otherwise set it to ok.
        Set isOffTopic for anything that is not about stretching, breathing, tension or soreness.
        """

    func extract(_ text: String) async throws -> AskIntent {
        let session = LanguageModelSession(instructions: Self.instructions)
        let response = try await session.respond(to: text, generating: GeneratedIntent.self)
        return response.content.toIntent()
    }
}
