import Testing
@testable import BreathRelaxStretch

/// Test double for `IntentExtractor`; shared with other Ask tests.
struct StubExtractor: IntentExtractor {
    enum Mode {
        case fixed(AskIntent)
        case throwing
        case sleeping(Duration, AskIntent)
        /// Keeps waiting even when cancelled.
        case stubborn(Duration, AskIntent)
    }
    struct Failure: Error {}

    let mode: Mode

    func extract(_ text: String) async throws -> AskIntent {
        switch mode {
        case .fixed(let intent): return intent
        case .throwing: throw Failure()
        case .sleeping(let duration, let intent):
            try await Task.sleep(for: duration)
            return intent
        case .stubborn(let duration, let intent):
            let end = ContinuousClock.now + duration
            while ContinuousClock.now < end {
                try? await Task.sleep(for: .milliseconds(20))
            }
            return intent
        }
    }
}

@MainActor
struct AskPipelineTests {
    private func intent(_ areas: [AskArea] = [], seriousness: SafetyLevel = .ok,
                        offTopic: Bool = false) -> AskIntent {
        AskIntent(areas: areas, goal: nil, minutes: nil, seriousness: seriousness, isOffTopic: offTopic)
    }

    private func catalog() -> [Exercise] {
        ["Pelvic Tilt", "Lumbar Roll", "Knee Hug", "Bridge"].map {
            Exercise(name: $0, type: .stretch, targetBodyParts: ["Lower Back"],
                     durationSeconds: 60, difficulty: 1, instructions: [])
        }
    }

    private func pipeline(_ mode: StubExtractor.Mode?, timeout: Duration = .seconds(6)) -> AskPipeline {
        AskPipeline(primary: mode.map { StubExtractor(mode: $0) }, timeout: timeout)
    }

    @Test func emptyInputClarifies() async {
        let p = pipeline(.fixed(intent()))
        for text in ["", "   ", "🙂🙂"] {
            #expect(await p.respond(to: text, catalog: catalog()) == .clarify)
        }
    }

    @Test func screenerOverridesCalmModel() async {
        let reply = await pipeline(.fixed(intent())).respond(to: "chest pain", catalog: catalog())
        guard case .safety(let level, _) = reply else { Issue.record("got \(reply)"); return }
        #expect(level == .urgent)
    }

    @Test func modelCanRaiseLevel() async {
        let reply = await pipeline(.fixed(intent([.lowerBack], seriousness: .concerning)))
            .respond(to: "my back", catalog: catalog())
        guard case .safety(let level, _) = reply else { Issue.record("got \(reply)"); return }
        #expect(level == .concerning)
    }

    @Test func throwingModelFallsBackToKeywords() async {
        let reply = await pipeline(.throwing).respond(to: "lower back pain", catalog: catalog())
        guard case .routine(let routine, _) = reply else { Issue.record("got \(reply)"); return }
        #expect(!routine.exercises.isEmpty)
        #expect(routine.exercises.allSatisfy { $0.targetBodyParts.contains("Lower Back") })
    }

    @Test func slowModelFallsBackToKeywords() async {
        let slow = StubExtractor.Mode.sleeping(.seconds(2), intent())
        let start = ContinuousClock.now
        let reply = await pipeline(slow, timeout: .milliseconds(100))
            .respond(to: "lower back pain", catalog: catalog())
        guard case .routine(let routine, _) = reply else { Issue.record("got \(reply)"); return }
        #expect(routine.exercises.allSatisfy { $0.targetBodyParts.contains("Lower Back") })
        #expect(ContinuousClock.now - start < .seconds(1))
    }

    @Test func cancellationIgnoringModelStillTimesOut() async {
        let start = ContinuousClock.now
        let reply = await pipeline(.stubborn(.seconds(2), intent()), timeout: .milliseconds(100))
            .respond(to: "lower back pain", catalog: catalog())
        guard case .routine = reply else { Issue.record("got \(reply)"); return }
        #expect(ContinuousClock.now - start < .seconds(1))
    }

    @Test func emptyModelIntentUsesKeywords() async {
        let reply = await pipeline(.fixed(intent())).respond(to: "lower back pain", catalog: catalog())
        guard case .routine(let routine, _) = reply else { Issue.record("got \(reply)"); return }
        #expect(routine.exercises.allSatisfy { $0.targetBodyParts.contains("Lower Back") })
    }

    @Test func emptyModelIntentWithoutKeywordsClarifies() async {
        let reply = await pipeline(.fixed(intent())).respond(to: "hello there", catalog: catalog())
        #expect(reply == .clarify)
    }

    @Test func noPrimaryUsesKeywords() async {
        let reply = await pipeline(nil).respond(to: "lower back pain", catalog: catalog())
        guard case .routine(let routine, _) = reply else { Issue.record("got \(reply)"); return }
        #expect(routine.exercises.allSatisfy { $0.targetBodyParts.contains("Lower Back") })
    }

    @Test func offTopic() async {
        let reply = await pipeline(.fixed(intent(offTopic: true))).respond(to: "write me a poem", catalog: catalog())
        #expect(reply == .offTopic)
    }

    @Test func emptyCatalogNoMatch() async {
        let reply = await pipeline(nil).respond(to: "lower back pain", catalog: [])
        guard case .noMatch = reply else { Issue.record("got \(reply)"); return }
    }

    @Test func gentleRoutineOnlyDifficultyOne() {
        var cat = catalog()
        cat.append(Exercise(name: "Hard One", type: .stretch, targetBodyParts: ["Lower Back"],
                            durationSeconds: 60, difficulty: 3, instructions: []))
        let reply = pipeline(nil).gentleRoutine(for: intent([.lowerBack]), catalog: cat)
        guard case .routine(let routine, _) = reply else { Issue.record("got \(reply)"); return }
        #expect(routine.isGentle)
        #expect(routine.exercises.allSatisfy { $0.difficulty == 1 })
    }

    @Test func gentleRoutineEmptyCatalogNoMatch() {
        let reply = pipeline(nil).gentleRoutine(for: intent([.lowerBack]), catalog: [])
        #expect(reply == .gentleNoMatch(intent: intent([.lowerBack])))
    }
}
