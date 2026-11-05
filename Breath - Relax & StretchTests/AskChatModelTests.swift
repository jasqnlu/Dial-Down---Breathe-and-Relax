import Testing
@testable import BreathRelaxStretch

@MainActor
struct AskChatModelTests {
    private func intent(_ areas: [AskArea] = [], seriousness: SafetyLevel = .ok) -> AskIntent {
        AskIntent(areas: areas, goal: nil, minutes: nil, seriousness: seriousness, isOffTopic: false)
    }

    private func catalog() -> [Exercise] {
        ["Pelvic Tilt", "Lumbar Roll", "Knee Hug", "Bridge"].map {
            Exercise(name: $0, type: .stretch, targetBodyParts: ["Lower Back"],
                     durationSeconds: 60, difficulty: 1, instructions: [])
        }
    }

    private func model(_ extracted: AskIntent? = nil) -> AskChatModel {
        AskChatModel(pipeline: AskPipeline(
            primary: extracted.map { StubExtractor(mode: .fixed($0)) }))
    }

    @Test func sendAppendsUserThenReply() async {
        let m = model()
        await m.send("lower back pain", catalog: catalog())
        #expect(m.messages.map(\.role) == [.user, .reply])
        #expect(m.messages[0].text == "lower back pain")
        guard case .routine = m.messages[1].reply else { Issue.record("got \(String(describing: m.messages[1].reply))"); return }
        #expect(!m.isThinking)
    }

    @Test func gentleAnywayReplacesSafetyWithRoutine() async {
        let m = model()
        await m.send("sharp pain in my lower back", catalog: catalog())
        guard case .safety(.concerning, _) = m.messages.last?.reply else {
            Issue.record("got \(String(describing: m.messages.last?.reply))"); return
        }
        let id = m.messages.last!.id
        let count = m.messages.count
        m.showGentleAnyway(for: id, catalog: catalog())
        #expect(m.messages.count == count)
        guard case .routine(let routine, _) = m.messages.last?.reply else {
            Issue.record("got \(String(describing: m.messages.last?.reply))"); return
        }
        #expect(routine.isGentle)
    }

    @Test func gentleAnywayIgnoredForUrgent() async {
        let m = model()
        await m.send("chest pain", catalog: catalog())
        guard case .safety(.urgent, _) = m.messages.last?.reply else {
            Issue.record("got \(String(describing: m.messages.last?.reply))"); return
        }
        let before = m.messages
        m.showGentleAnyway(for: m.messages.last!.id, catalog: catalog())
        #expect(m.messages == before)
    }

    @Test func emptySendRepliesClarify() async {
        let m = model()
        await m.send("  ", catalog: catalog())
        #expect(m.messages.count == 1)
        #expect(m.messages[0].role == .reply)
        #expect(m.messages[0].reply == .clarify)
    }
}
