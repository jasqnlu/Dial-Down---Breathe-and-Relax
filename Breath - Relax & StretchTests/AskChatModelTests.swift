import Foundation
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

    /// Sends a concerning request and returns the safety message.
    private func concerningMessage(_ m: AskChatModel, catalog: [Exercise]) async -> AskMessage? {
        await m.send("sharp pain in my lower back", catalog: catalog)
        guard let last = m.messages.last, case .safety(.concerning, _)? = last.reply else {
            Issue.record("got \(String(describing: m.messages.last?.reply))"); return nil
        }
        return last
    }

    @Test func gentleAnywayAppendsRoutineBelowSafety() async {
        let m = model()
        guard let safety = await concerningMessage(m, catalog: catalog()) else { return }
        let count = m.messages.count
        m.showGentleAnyway(for: safety.id, catalog: catalog())
        #expect(m.messages.count == count + 1)
        #expect(m.messages[count - 1] == safety, "the safety advice must stay in place")
        #expect(m.gentleShownFor.contains(safety.id))
        guard case .routine(let routine, _)? = m.messages.last?.reply else {
            Issue.record("got \(String(describing: m.messages.last?.reply))"); return
        }
        #expect(m.messages.last?.role == .reply)
        #expect(routine.isGentle)
    }

    @Test func gentleAnywayNoMatchKeepsAdviceAndOffersBrowse() async {
        let m = model()
        guard let safety = await concerningMessage(m, catalog: []) else { return }
        let count = m.messages.count
        m.showGentleAnyway(for: safety.id, catalog: [])
        #expect(m.messages.count == count + 1)
        #expect(m.messages[count - 1] == safety)
        guard case .gentleNoMatch(let intent)? = m.messages.last?.reply else {
            Issue.record("got \(String(describing: m.messages.last?.reply))"); return
        }
        #expect(intent.areas == [.lowerBack])
    }

    @Test func secondGentleAnywayTapDoesNothing() async {
        let m = model()
        guard let safety = await concerningMessage(m, catalog: catalog()) else { return }
        m.showGentleAnyway(for: safety.id, catalog: catalog())
        let after = m.messages
        m.showGentleAnyway(for: safety.id, catalog: catalog())
        #expect(m.messages == after)
    }

    @Test func dictationWhileThinkingBecomesDraft() async {
        let m = AskChatModel(pipeline: AskPipeline(
            primary: StubExtractor(mode: .sleeping(.milliseconds(300), intent([.lowerBack])))))
        let first = Task { await m.send("lower back pain", catalog: catalog()) }
        while !m.isThinking { await Task.yield() }
        await m.acceptDictation("and my neck", catalog: catalog())
        #expect(m.messages.count == 1, "nothing is sent while thinking")
        #expect(m.takePendingDraft() == "and my neck")
        #expect(m.takePendingDraft() == nil, "the draft is handed over once")
        await first.value
        #expect(m.messages.map(\.role) == [.user, .reply])
    }

    @Test func dictationWhenIdleSends() async {
        let m = model()
        await m.acceptDictation("lower back pain", catalog: catalog())
        #expect(m.messages.map(\.role) == [.user, .reply])
        #expect(m.pendingDraft == nil)
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

    // MARK: - The running routine (draft)

    /// Five lower-back and three neck stretches, 60 s each.
    private func bigCatalog() -> [Exercise] {
        let back = ["Pelvic Tilt", "Lumbar Roll", "Knee Hug", "Bridge", "Sphinx"].map {
            Exercise(name: $0, type: .stretch, targetBodyParts: ["Lower Back"],
                     durationSeconds: 60, difficulty: 1, instructions: [])
        }
        let neck = ["Chin Tuck", "Neck Tilt", "Neck Roll"].map {
            Exercise(name: $0, type: .stretch, targetBodyParts: ["Neck"],
                     durationSeconds: 60, difficulty: 1, instructions: [])
        }
        return back + neck
    }

    private func parts(_ m: AskChatModel) -> [String] { m.draft.exercises.flatMap(\.targetBodyParts) }

    @Test func requestsAddUpInTheDraft() async {
        let m = model(), cat = bigCatalog()
        await m.send("2 exercises for my lower back", catalog: cat)
        await m.send("2 for my neck", catalog: cat)
        // In request order: the two back stretches stay first, the neck ones follow.
        #expect(parts(m) == ["Lower Back", "Lower Back", "Neck", "Neck"])
    }

    @Test func moreOfTheSameNeverRepeats() async {
        let m = model(), cat = bigCatalog()
        await m.send("2 exercises for my lower back", catalog: cat)
        await m.send("2 more", catalog: cat)
        #expect(parts(m) == ["Lower Back", "Lower Back", "Lower Back", "Lower Back"])
        #expect(Set(m.draft.exercises.map(\.name)).count == 4, "no exercise twice")
        guard case .routine = m.messages.last?.reply else {
            Issue.record("got \(String(describing: m.messages.last?.reply))"); return
        }
    }

    @Test func anotherOneWithNothingToGoOnClarifies() async {
        let m = model()
        await m.send("another one", catalog: bigCatalog())
        #expect(m.messages.last?.reply == .clarify)
        #expect(m.draft.isEmpty)
    }

    @Test func explicitNewRoutineReplacesTheDraft() async {
        let m = model(), cat = bigCatalog()
        await m.send("2 exercises for my lower back", catalog: cat)
        await m.send("create a new routine with 2 neck stretches", catalog: cat)
        #expect(parts(m) == ["Neck", "Neck"])
    }

    @Test func startOverAloneClears() async {
        let m = model(), cat = bigCatalog()
        await m.send("2 exercises for my lower back", catalog: cat)
        await m.send("start over", catalog: cat)
        #expect(m.draft.isEmpty)
        #expect(m.messages.last?.reply == .draftChanged(.cleared))
    }

    @Test func removeEditsTheDraftAndSaysWhat() async {
        let m = model(), cat = bigCatalog()
        await m.send("2 exercises for my lower back", catalog: cat)
        let before = m.draft.exercises.map(\.name)
        await m.send("remove the last one", catalog: cat)
        #expect(m.draft.exercises.map(\.name) == [before[0]])
        #expect(m.messages.last?.reply == .draftChanged(.removed([before[1]])))
    }

    @Test func editOnAnEmptyDraftSaysThereIsNothingToChange() async {
        let m = model()
        await m.send("remove the last one", catalog: bigCatalog())
        #expect(m.messages.last?.reply == .draftChanged(.nothingToChange))
    }

    @Test func gentleAnywayAddsToTheDraft() async {
        let m = model()
        guard let safety = await concerningMessage(m, catalog: catalog()) else { return }
        #expect(m.draft.isEmpty)
        m.showGentleAnyway(for: safety.id, catalog: catalog())
        #expect(!m.draft.isEmpty)
    }

    @Test func customizeRewritesTheDraft() async {
        let m = model(), cat = bigCatalog()
        await m.send("2 exercises for my lower back", catalog: cat)
        let reversed = Array(m.draft.exercises.reversed())
        m.customize(exercises: reversed, durationOverrides: [reversed[0].uuid: 90])
        #expect(m.draft.exercises == reversed)
        #expect(m.draft.totalSeconds == 90 + 60)
    }

    private func ex(_ name: String, _ seconds: Int = 60) -> Exercise {
        Exercise(name: name, type: .stretch, targetBodyParts: [], durationSeconds: seconds,
                 difficulty: 1, instructions: [])
    }

    @Test func pairsCollapseIntoOneRow() {
        let routine = AskRoutine(exercises: [ex("Bridge"), ex("Left Hip Stretch", 30), ex("Right Hip Stretch", 45), ex("Knee Hug")],
                                 isGentle: false)
        let rows = routine.rows(locale: Locale(identifier: "en"))
        #expect(rows.map(\.title) == ["Bridge", "Hip Stretch · L + R", "Knee Hug"])
        #expect(rows.map(\.seconds) == [60, 75, 60])
    }

    @Test func rowsAndTotalUseSplitTimes() {
        let bridge = ex("Bridge"), left = ex("Left Hip Stretch", 30), right = ex("Right Hip Stretch", 45)
        let routine = AskRoutine(exercises: [bridge, left, right], isGentle: false,
                                 durationOverrides: [bridge.uuid: 90, left.uuid: 45])
        #expect(routine.rows(locale: Locale(identifier: "en")).map(\.seconds) == [90, 90])
        #expect(routine.totalSeconds == 180)
    }

    @Test func unmatchedSidesStaySeparate() {
        let routine = AskRoutine(exercises: [ex("Left Hip Stretch"), ex("Left Calf Stretch")], isGentle: false)
        #expect(routine.rows(locale: Locale(identifier: "en")).count == 2)
    }

    @Test func minutesRoundUp() {
        #expect(AskRoutine(exercises: [ex("A", 61)], isGentle: false).displayMinutes == 2)
        #expect(AskRoutine(exercises: [ex("A", 60)], isGentle: false).displayMinutes == 1)
        #expect(AskRoutine(exercises: [ex("A", 10)], isGentle: false).displayMinutes == 1)
    }

    @Test func areaNamesFollowGivenLocale() {
        let intent = AskIntent(areas: [.neck, .shoulders], goal: nil, minutes: nil, seriousness: .ok, isOffTopic: false)
        #expect(intent.areaList(locale: Locale(identifier: "es")).contains("cuello"))
    }
}
