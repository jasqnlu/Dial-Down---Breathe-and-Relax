import Foundation
import Testing
@testable import BreathRelaxStretch

/// The running mini routine the Ask chat builds up, one request at a time.
@MainActor
struct AskDraftTests {
    private func make(_ name: String, _ parts: [String], seconds: Int = 60) -> Exercise {
        Exercise(name: name, type: .stretch, targetBodyParts: parts,
                 durationSeconds: seconds, difficulty: 1, instructions: [])
    }

    private func intent(_ areas: [AskArea] = [], minutes: Int? = nil, count: Int? = nil,
                        edit: AskEdit? = nil, wantsNewRoutine: Bool = false) -> AskIntent {
        AskIntent(areas: areas, goal: nil, minutes: minutes, seriousness: .ok, isOffTopic: false,
                  count: count, wantsNewRoutine: wantsNewRoutine, edit: edit)
    }

    private func routine(_ exercises: [Exercise], overrides: [UUID: Int] = [:]) -> AskRoutine {
        AskRoutine(exercises: exercises, isGentle: false, durationOverrides: overrides)
    }

    private func names(_ draft: AskDraft) -> [String] { draft.exercises.map(\.name) }

    // Neck x3, lower back x3, plus a Left/Right hip pair.
    private let neck = ["Chin Tuck", "Neck Tilt", "Neck Roll"].map { name in
        Exercise(name: name, type: .stretch, targetBodyParts: ["Neck"], durationSeconds: 60,
                 difficulty: 1, instructions: [])
    }
    private let back = ["Pelvic Tilt", "Knee Hug", "Bridge"].map { name in
        Exercise(name: name, type: .stretch, targetBodyParts: ["Lower Back"], durationSeconds: 60,
                 difficulty: 1, instructions: [])
    }
    private let hipLeft = Exercise(name: "Left Hip Opener", type: .stretch, targetBodyParts: ["Left Hip"],
                                   durationSeconds: 30, difficulty: 1, instructions: [])
    private let hipRight = Exercise(name: "Right Hip Opener", type: .stretch, targetBodyParts: ["Right Hip"],
                                    durationSeconds: 30, difficulty: 1, instructions: [])
    private var catalog: [Exercise] { neck + back + [hipLeft, hipRight] }

    // MARK: - Adding and replacing

    @Test func addsAppendInOrderAndKeepTimes() {
        var draft = AskDraft()
        draft.add(routine([neck[0], neck[1]], overrides: [neck[0].uuid: 45]), intent: intent([.neck]))
        draft.add(routine([back[0]]), intent: intent([.lowerBack]))
        #expect(names(draft) == ["Chin Tuck", "Neck Tilt", "Pelvic Tilt"])
        #expect(draft.totalSeconds == 45 + 60 + 60)
        #expect(draft.lastIntent?.areas == [.lowerBack])
    }

    @Test func replaceThrowsAwayTheOldRoutine() {
        var draft = AskDraft()
        draft.add(routine([neck[0]], overrides: [neck[0].uuid: 45]), intent: intent([.neck]))
        draft.replace(with: routine([back[0]]), intent: intent([.lowerBack]))
        #expect(names(draft) == ["Pelvic Tilt"])
        #expect(draft.durationOverrides.isEmpty)
    }

    @Test func routineCarriesExercisesAndTimes() {
        var draft = AskDraft()
        draft.add(routine([neck[0]], overrides: [neck[0].uuid: 45]), intent: intent([.neck]))
        #expect(draft.routine.exercises.map(\.name) == ["Chin Tuck"])
        #expect(draft.routine.totalSeconds == 45)
    }

    // MARK: - Clear

    @Test func startOverClears() {
        var draft = AskDraft()
        draft.add(routine(neck), intent: intent([.neck]))
        #expect(draft.apply(intent(wantsNewRoutine: true), catalog: catalog) == .cleared)
        #expect(draft.isEmpty)
        #expect(draft.lastIntent == nil)
    }

    // MARK: - Remove

    @Test func removeDefaultsToTheLastExercise() {
        var draft = AskDraft()
        draft.add(routine(neck), intent: intent([.neck]))
        #expect(draft.apply(intent(edit: .remove), catalog: catalog) == .removed(["Neck Roll"]))
        #expect(names(draft) == ["Chin Tuck", "Neck Tilt"])
    }

    @Test func removeTakesBothSidesOfAPair() {
        var draft = AskDraft()
        draft.add(routine([neck[0], hipLeft, hipRight]), intent: intent([.hips]))
        #expect(draft.apply(intent(edit: .remove), catalog: catalog) == .removed(["Hip Opener"]))
        #expect(names(draft) == ["Chin Tuck"])
    }

    @Test func removeByAreaTakesEveryMatch() {
        var draft = AskDraft()
        draft.add(routine([neck[0], back[0], neck[1]]), intent: intent([.neck]))
        #expect(draft.apply(intent([.neck], edit: .remove), catalog: catalog) == .removed(["Chin Tuck", "Neck Tilt"]))
        #expect(names(draft) == ["Pelvic Tilt"])
    }

    @Test func removeACountFromTheEnd() {
        var draft = AskDraft()
        draft.add(routine(neck), intent: intent([.neck]))
        #expect(draft.apply(intent(count: 2, edit: .remove), catalog: catalog) == .removed(["Neck Tilt", "Neck Roll"]))
        #expect(names(draft) == ["Chin Tuck"])
    }

    @Test func removeDropsTheRemovedTimes() {
        var draft = AskDraft()
        draft.add(routine([neck[0], neck[1]], overrides: [neck[1].uuid: 90]), intent: intent([.neck]))
        _ = draft.apply(intent(edit: .remove), catalog: catalog)
        #expect(draft.durationOverrides.isEmpty)
    }

    @Test func removeWithNothingToRemove() {
        var draft = AskDraft()
        #expect(draft.apply(intent(edit: .remove), catalog: catalog) == .nothingToChange)
        draft.add(routine([neck[0]]), intent: intent([.neck]))
        #expect(draft.apply(intent([.hips], edit: .remove), catalog: catalog) == .nothingToChange)
        #expect(names(draft) == ["Chin Tuck"])
    }

    // MARK: - Swap

    @Test func swapReplacesTheLastWithAnotherFromTheSameArea() {
        var draft = AskDraft()
        draft.add(routine([back[0], neck[0]], overrides: [neck[0].uuid: 45]), intent: intent([.neck]))
        let change = draft.apply(intent(edit: .swap), catalog: catalog)
        guard case .swapped(let from, let to) = change else { Issue.record("got \(change)"); return }
        #expect(from == "Chin Tuck")
        #expect(["Neck Tilt", "Neck Roll"].contains(to), "another neck stretch, not one already in")
        #expect(names(draft) == ["Pelvic Tilt", to], "swapped in place")
        #expect(draft.totalSeconds == 60 + 45, "the swapped-in exercise keeps the slot's time")
    }

    @Test func swapByAreaPicksTheLastMatch() {
        var draft = AskDraft()
        draft.add(routine([back[0], neck[0]]), intent: intent([.neck]))
        let change = draft.apply(intent([.lowerBack], edit: .swap), catalog: catalog)
        guard case .swapped(let from, let to) = change else { Issue.record("got \(change)"); return }
        #expect(from == "Pelvic Tilt")
        #expect(["Knee Hug", "Bridge"].contains(to))
        #expect(names(draft) == [to, "Chin Tuck"])
    }

    @Test func swapWithNoAlternativeChangesNothing() {
        var draft = AskDraft()
        draft.add(routine(neck), intent: intent([.neck]))
        #expect(draft.apply(intent(edit: .swap), catalog: catalog) == .nothingToChange)
        #expect(names(draft) == ["Chin Tuck", "Neck Tilt", "Neck Roll"])
    }

    // MARK: - Timing

    @Test func minutesAloneRetimesTheWholeRoutine() {
        var draft = AskDraft()
        draft.add(routine(neck + [back[0]]), intent: intent([.neck]))
        #expect(draft.apply(intent(minutes: 6), catalog: catalog) == .retimed(totalSeconds: 360))
        #expect(draft.totalSeconds == 360)
        #expect(draft.exercises.count == 4)
    }

    @Test func shorterAndLonger() {
        var draft = AskDraft()
        draft.add(routine(neck + [back[0]]), intent: intent([.neck]))   // 4:00
        #expect(draft.apply(intent(edit: .shorter), catalog: catalog) == .retimed(totalSeconds: 180))
        #expect(draft.apply(intent(edit: .longer), catalog: catalog) == .retimed(totalSeconds: 230))
    }

    @Test func retimeKeepsPairSidesEqual() {
        var draft = AskDraft()
        draft.add(routine([hipLeft, hipRight, neck[0]]), intent: intent([.hips]))   // 0:30 + 0:30 + 1:00
        _ = draft.apply(intent(minutes: 3), catalog: catalog)
        #expect(draft.totalSeconds == 180)
        #expect(draft.seconds(for: hipLeft) == draft.seconds(for: hipRight))
    }

    @Test func timingEditsOnAnEmptyDraftChangeNothing() {
        var draft = AskDraft()
        #expect(draft.apply(intent(minutes: 5), catalog: catalog) == .nothingToChange)
        #expect(draft.apply(intent(edit: .shorter), catalog: catalog) == .nothingToChange)
    }
}
