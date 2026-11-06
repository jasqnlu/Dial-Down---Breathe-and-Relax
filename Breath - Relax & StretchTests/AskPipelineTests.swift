import Foundation
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
@Suite(.serialized)
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
            .respond(to: "my back hurts when I bend", catalog: catalog())
        guard case .safety(let level, _) = reply else { Issue.record("got \(reply)"); return }
        #expect(level == .concerning)
    }

    /// Seen on device: the model called "another calf exercise" urgent (calf → blood clot?).
    @Test(arguments: ["Like can you add one another calf exercise to this", "3 exercises for my lower back"])
    func modelCannotRaiseLevelWithoutASymptom(_ text: String) async {
        let reply = await pipeline(.fixed(intent([.lowerBack], seriousness: .urgent)))
            .respond(to: text, catalog: catalog())
        guard case .routine = reply else { Issue.record("\(text): got \(reply)"); return }
    }

    @Test(arguments: ["my calf is warm and hurts", "my back aches a lot", "me duele la espalda", "j'ai mal au dos", "我腰疼"])
    func modelCanRaiseLevelWhenASymptomIsDescribed(_ text: String) async {
        let reply = await pipeline(.fixed(intent([.lowerBack], seriousness: .urgent)))
            .respond(to: text, catalog: catalog())
        #expect(reply == .safety(.urgent, intent: intent([.lowerBack], seriousness: .urgent)), "\(text)")
    }

    /// Seen on device: "add this" read as an edit, answered "Nothing in your routine matches that."
    @Test(arguments: ["Can I get one calf exercise add this", "add a stretch for my lower back",
                      "another lower back one", "2 more for my lower back"])
    func modelEditIsIgnoredWhenTheUserAsksToAdd(_ text: String) async {
        var guess = intent([.lowerBack])
        guess.edit = .remove
        let reply = await pipeline(.fixed(guess)).respond(to: text, catalog: catalog())
        guard case .routine = reply else { Issue.record("\(text): got \(reply)"); return }
    }

    @Test func modelEditStillWorksForParaphrases() async {
        var guess = intent()
        guess.edit = .remove
        let reply = await pipeline(.fixed(guess)).respond(to: "I don't like the last one", catalog: catalog())
        guard case .edit(let used) = reply else { Issue.record("got \(reply)"); return }
        #expect(used.edit == .remove)
    }

    @Test func throwingModelFallsBackToKeywords() async {
        let reply = await pipeline(.throwing).respond(to: "lower back pain", catalog: catalog())
        guard case .routine(let routine, _) = reply else { Issue.record("got \(reply)"); return }
        #expect(!routine.exercises.isEmpty)
        #expect(routine.exercises.allSatisfy { $0.targetBodyParts.contains("Lower Back") })
    }

    /// Builds the static phrase tables before a timed test starts its clock.
    private func warmUp() {
        _ = KeywordIntentExtractor().intent(for: "warm up")
        _ = SafetyScreener.screen("x")
    }

    /// The model would answer `.neck`, so a `.lowerBack` reply proves the keyword
    /// fallback won the race, independent of how fast the machine is.
    @Test func slowModelFallsBackToKeywords() async {
        warmUp()
        let slow = StubExtractor.Mode.sleeping(.seconds(30), intent([.neck]))
        let start = ContinuousClock.now
        let reply = await pipeline(slow, timeout: .milliseconds(100))
            .respond(to: "lower back pain", catalog: catalog())
        guard case .routine(_, let used) = reply else { Issue.record("got \(reply)"); return }
        #expect(used.areas == [.lowerBack])
        #expect(ContinuousClock.now - start < .seconds(10))
    }

    @Test func cancellationIgnoringModelStillTimesOut() async {
        warmUp()
        let start = ContinuousClock.now
        let reply = await pipeline(.stubborn(.seconds(30), intent([.neck])), timeout: .milliseconds(100))
            .respond(to: "lower back pain", catalog: catalog())
        guard case .routine(_, let used) = reply else { Issue.record("got \(reply)"); return }
        #expect(used.areas == [.lowerBack])
        #expect(ContinuousClock.now - start < .seconds(10))
    }

    @Test func emptyModelIntentUsesKeywords() async {
        let reply = await pipeline(.fixed(intent())).respond(to: "lower back pain", catalog: catalog())
        guard case .routine(let routine, _) = reply else { Issue.record("got \(reply)"); return }
        #expect(routine.exercises.allSatisfy { $0.targetBodyParts.contains("Lower Back") })
    }

    @Test func keywordCountFillsInWhenModelMissesIt() async {
        // The model understood the area but not the number; the keyword parser's count is used.
        let reply = await pipeline(.fixed(intent([.lowerBack])))
            .respond(to: "3 exercises for my lower back", catalog: catalog())
        guard case .routine(let routine, let used) = reply else { Issue.record("got \(reply)"); return }
        #expect(used.count == 3)
        #expect(routine.exercises.count == 3)
    }

    @Test func keywordNewRoutineFillsInWhenModelMissesIt() async {
        let reply = await pipeline(.fixed(intent([.lowerBack])))
            .respond(to: "start over with my lower back", catalog: catalog())
        guard case .routine(_, let used) = reply else { Issue.record("got \(reply)"); return }
        #expect(used.wantsNewRoutine)
    }

    // MARK: - Building on a draft

    @Test func requestSkipsExercisesAlreadyInTheDraft() async {
        let cat = catalog()
        let reply = await pipeline(nil).respond(to: "2 exercises for my lower back", catalog: cat,
                                                excluding: [cat[0].uuid, cat[1].uuid])
        guard case .routine(let routine, _) = reply else { Issue.record("got \(reply)"); return }
        #expect(Set(routine.exercises.map(\.name)) == ["Knee Hug", "Bridge"])
    }

    @Test func newRoutineMayReuseDraftExercises() async {
        let cat = catalog()
        let reply = await pipeline(nil).respond(to: "start over with 4 exercises for my lower back",
                                                catalog: cat, excluding: Set(cat.map(\.uuid)))
        guard case .routine(let routine, _) = reply else { Issue.record("got \(reply)"); return }
        #expect(routine.exercises.count == 4)
    }

    @Test(arguments: ["remove the last one", "start over", "make it 5 minutes", "make it shorter",
                      "2 more", "another one", "swap the last one"])
    func draftOnlyRequestsComeBackAsEdits(_ text: String) async {
        let reply = await pipeline(nil).respond(to: text, catalog: catalog())
        guard case .edit = reply else { Issue.record("\(text): got \(reply)"); return }
    }

    @Test func removeByAreaIsAnEditNotANewRoutine() async {
        let reply = await pipeline(nil).respond(to: "remove the lower back ones", catalog: catalog())
        guard case .edit(let intent) = reply else { Issue.record("got \(reply)"); return }
        #expect(intent.edit == .remove)
        #expect(intent.areas == [.lowerBack])
    }

    @Test func modelCallingAnEditOffTopicStillEdits() async {
        // "remove the last one" names no stretch, so the model may call it off-topic.
        let reply = await pipeline(.fixed(intent(offTopic: true)))
            .respond(to: "remove the last one", catalog: catalog())
        guard case .edit(let used) = reply else { Issue.record("got \(reply)"); return }
        #expect(used.edit == .remove)
    }

    @Test func offTopicWithANumberStaysOffTopic() async {
        let reply = await pipeline(.fixed(intent(offTopic: true)))
            .respond(to: "write me a poem in 5 minutes", catalog: catalog())
        #expect(reply == .offTopic)
    }

    @Test func safetyStillComesBeforeEdits() async {
        let reply = await pipeline(nil).respond(to: "remove the last one, I have sharp pain", catalog: catalog())
        guard case .safety = reply else { Issue.record("got \(reply)"); return }
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
