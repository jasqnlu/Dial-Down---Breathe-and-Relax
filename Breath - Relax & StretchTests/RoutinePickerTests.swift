import Foundation
import Testing
@testable import BreathRelaxStretch

@MainActor
struct RoutinePickerTests {
    private func intent(_ areas: [AskArea] = [], goal: AskGoal? = nil, minutes: Int? = nil,
                        count: Int? = nil) -> AskIntent {
        AskIntent(areas: areas, goal: goal, minutes: minutes, seriousness: .ok, isOffTopic: false,
                  count: count)
    }

    private func seconds(_ routine: AskRoutine?) -> [Int] {
        guard let routine else { return [] }
        return routine.exercises.map { routine.seconds(for: $0) }
    }

    private func make(_ name: String, _ parts: [String], type: ExerciseType = .stretch,
                      difficulty: Int = 1, seconds: Int = 60) -> Exercise {
        Exercise(name: name, type: type, targetBodyParts: parts,
                 durationSeconds: seconds, difficulty: difficulty, instructions: [])
    }

    private func names(_ routine: AskRoutine?) -> [String] { routine?.exercises.map(\.name) ?? [] }

    @Test func lowerBackPainUsesGoalOrderFirst() {
        let catalog = [
            make("Pelvic Tilt", ["Lower Back"]),
            make("Cat-Cow Flow", ["Spinal Erectors"]),
            make("Lumbar Roll", ["Lower Back"]),
        ]
        let routine = RoutinePicker.pick(intent: intent([.lowerBack], goal: .pain_relief), from: catalog)
        #expect(names(routine) == ["Cat-Cow Flow", "Pelvic Tilt", "Lumbar Roll"])
    }

    @Test func pairsStayTogether() {
        let catalog = [
            make("Right Seated Spinal Twist", ["Lower Back"]),
            make("Left Seated Spinal Twist", ["Lower Back"]),
            make("Pelvic Tilt", ["Lower Back"]),
        ]
        let result = names(RoutinePicker.pick(intent: intent([.lowerBack]), from: catalog))
        let l = result.firstIndex(of: "Left Seated Spinal Twist")
        let r = result.firstIndex(of: "Right Seated Spinal Twist")
        #expect(l != nil && r != nil)
        #expect(r == l.map { $0 + 1 })
    }

    @Test func neverIncludesBreathForAreaRequest() {
        let catalog = [
            make("Lumbar Roll", ["Lower Back"]),
            make("Back Breathing", ["Lower Back"], type: .breath),
        ]
        #expect(names(RoutinePicker.pick(intent: intent([.lowerBack]), from: catalog)) == ["Lumbar Roll"])
    }

    @Test func goalOnlyAllowsBreath() {
        let catalog = [make("Box Breathing", [], type: .breath)]
        let routine = RoutinePicker.pick(intent: intent(goal: .better_breathing), from: catalog)
        #expect(names(routine) == ["Box Breathing"])
    }

    @Test func gentleKeepsOnlyDifficultyOne() {
        let catalog = [
            make("Easy Roll", ["Lower Back"], difficulty: 1),
            make("Hard Roll", ["Lower Back"], difficulty: 2),
        ]
        let gentle = RoutinePicker.pick(intent: intent([.lowerBack]), from: catalog, gentle: true)
        #expect(names(gentle) == ["Easy Roll"])
        #expect(gentle?.isGentle == true)
        let onlyHard = RoutinePicker.pick(intent: intent([.lowerBack]), from: [catalog[1]], gentle: true)
        #expect(onlyHard == nil)
    }

    @Test func defaultTargetsAboutFiveMinutes() {
        let catalog = (0..<10).map { make("Back Move \($0)", ["Lower Back"]) }
        let routine = RoutinePicker.pick(intent: intent([.lowerBack]), from: catalog)
        #expect(routine?.exercises.count == 5)
        #expect(routine?.totalSeconds == 300)
    }

    @Test func minutesClamped() {
        let catalog = (0..<40).map { make("Back Move \($0)", ["Lower Back"]) }
        let big = RoutinePicker.pick(intent: intent([.lowerBack], minutes: 60), from: catalog)
        #expect((big?.totalSeconds ?? .max) <= 20 * 60 + 60)
        let zero = RoutinePicker.pick(intent: intent([.lowerBack], minutes: 0), from: catalog)
        let none = RoutinePicker.pick(intent: intent([.lowerBack], minutes: nil), from: catalog)
        #expect(zero == none)
        #expect(zero?.totalSeconds == 300)
    }

    @Test func emptyCatalogReturnsNil() {
        #expect(RoutinePicker.pick(intent: intent([.lowerBack]), from: []) == nil)
    }

    @Test func sidedRequestStillBothSides() {
        let catalog = [
            make("Left Hip Opener", ["Left Hip"]),
            make("Right Hip Opener", ["Right Hip"]),
        ]
        #expect(names(RoutinePicker.pick(intent: intent([.hips]), from: catalog)) ==
                ["Left Hip Opener", "Right Hip Opener"])
    }

    @Test func oneSidedMatchIsCompletedFromCatalog() {
        let catalog = [
            make("Left Hip Opener", ["Left Hip"]),
            make("Right Hip Opener", ["Right Chest"]),
        ]
        // Only "Left Hip" is requested via the resolver's direct match on the left twin.
        let routine = RoutinePicker.pick(intent: intent([.hips]), from: catalog)
        #expect(names(routine) == ["Left Hip Opener", "Right Hip Opener"])
    }

    @Test func gentleDropsPairWhenPartnerTooHard() {
        let catalog = [
            make("Left Hip Opener", ["Left Hip"], difficulty: 1),
            make("Right Hip Opener", ["Right Hip"], difficulty: 2),
        ]
        #expect(RoutinePicker.pick(intent: intent([.hips]), from: catalog, gentle: true) == nil)
    }

    @Test func oneSidedWithoutPartnerIsDropped() {
        let catalog = [make("Left Hip Opener", ["Left Hip"])]
        #expect(RoutinePicker.pick(intent: intent([.hips]), from: catalog) == nil)
    }

    @Test func explicitMinutesIgnoreFourSlotMinimum() {
        let catalog = (0..<10).map { make("Back Move \($0)", ["Lower Back"]) }
        #expect(RoutinePicker.pick(intent: intent([.lowerBack], minutes: 1), from: catalog)?.totalSeconds == 60)
        #expect(RoutinePicker.pick(intent: intent([.lowerBack], minutes: 3), from: catalog)?.totalSeconds == 180)
    }

    @Test func sixSlotCapWithoutMinutes() {
        let catalog = (0..<10).map { make("Back Move \($0)", ["Lower Back"], seconds: 30) }
        #expect(RoutinePicker.pick(intent: intent([.lowerBack]), from: catalog)?.exercises.count == 6)
    }

    // MARK: - Exact count

    @Test func countPicksExactlyThatMany() {
        let catalog = (0..<10).map { make("Back Move \($0)", ["Lower Back"]) }
        // Without a count this catalog gives 5 (the 5-minute default).
        let routine = RoutinePicker.pick(intent: intent([.lowerBack], count: 3), from: catalog)
        #expect(names(routine) == ["Back Move 0", "Back Move 1", "Back Move 2"])
        #expect(seconds(routine) == [60, 60, 60])
    }

    @Test func countCanExceedSixSlotCap() {
        let catalog = (0..<10).map { make("Back Move \($0)", ["Lower Back"], seconds: 30) }
        #expect(RoutinePicker.pick(intent: intent([.lowerBack], count: 8), from: catalog)?.exercises.count == 8)
    }

    @Test func countBelowFourSlotMinimum() {
        let catalog = (0..<10).map { make("Back Move \($0)", ["Lower Back"]) }
        #expect(names(RoutinePicker.pick(intent: intent([.lowerBack], count: 1), from: catalog)) == ["Back Move 0"])
    }

    @Test func leftRightPairCountsAsOneExercise() {
        let catalog = [
            make("Left Hip Opener", ["Left Hip"]),
            make("Right Hip Opener", ["Right Hip"]),
            make("Butterfly", ["Left Hip", "Right Hip"]),
        ]
        // 2 exercises = the pair (two rows of the catalog) + Butterfly, in resolver order.
        let routine = RoutinePicker.pick(intent: intent([.hips], count: 2), from: catalog)
        #expect(Set(names(routine)) == ["Left Hip Opener", "Right Hip Opener", "Butterfly"])
        #expect(routine?.exercises.count == 3)
    }

    @Test func countLargerThanPoolReturnsWhatExists() {
        let catalog = (0..<2).map { make("Back Move \($0)", ["Lower Back"]) }
        #expect(RoutinePicker.pick(intent: intent([.lowerBack], count: 5), from: catalog)?.exercises.count == 2)
    }

    // MARK: - Count + minutes: split the time evenly

    @Test func countAndMinutesSplitEvenly() {
        let catalog = (0..<10).map { make("Back Move \($0)", ["Lower Back"], seconds: 45) }
        let routine = RoutinePicker.pick(intent: intent([.lowerBack], minutes: 3, count: 3), from: catalog)
        #expect(seconds(routine) == [60, 60, 60])
        #expect(routine?.totalSeconds == 180)
    }

    @Test func splitGivesBothSidesOfAPairTheSameTime() {
        let catalog = [
            make("Left Hip Opener", ["Left Hip"], seconds: 45),
            make("Right Hip Opener", ["Right Hip"], seconds: 45),
            make("Butterfly", ["Left Hip", "Right Hip"], seconds: 45),
        ]
        // 2 exercises in 2 minutes: the pair shares one minute, Butterfly gets the other.
        let routine = RoutinePicker.pick(intent: intent([.hips], minutes: 2, count: 2), from: catalog)
        let byName = Dictionary(uniqueKeysWithValues: (routine?.exercises ?? []).map { ($0.name, routine!.seconds(for: $0)) })
        #expect(byName == ["Left Hip Opener": 30, "Right Hip Opener": 30, "Butterfly": 60])
        #expect(routine?.totalSeconds == 120)
    }

    @Test func unevenSplitStillAddsUpExactly() {
        let catalog = (0..<10).map { make("Back Move \($0)", ["Lower Back"]) }
        // 120 s over 7: 10 s steps, the extra goes to the first ones.
        let routine = RoutinePicker.pick(intent: intent([.lowerBack], minutes: 2, count: 7), from: catalog)
        #expect(seconds(routine) == [20, 20, 20, 20, 20, 10, 10])
        #expect(routine?.totalSeconds == 120)
    }

    @Test func splitNeverGivesAnExerciseNoTime() {
        let catalog = (0..<10).map { make("Back Move \($0)", ["Lower Back"]) }
        // 10 exercises in 1 minute can't split into 10 s steps; each gets the 10 s floor, not 0.
        let routine = RoutinePicker.pick(intent: intent([.lowerBack], minutes: 1, count: 10), from: catalog)
        #expect(seconds(routine) == Array(repeating: 10, count: 10))
    }

    // MARK: - Minutes only: land exactly on the time asked for

    @Test func minutesOnlyTrimsOvershoot() {
        // 50 s each: 4 reach 200 s for a 180 s ask. Trim 20 s to land on exactly 3:00.
        let catalog = (0..<10).map { make("Back Move \($0)", ["Lower Back"], seconds: 50) }
        let routine = RoutinePicker.pick(intent: intent([.lowerBack], minutes: 3), from: catalog)
        #expect(routine?.exercises.count == 4)
        #expect(routine?.totalSeconds == 180)
        #expect(seconds(routine) == [50, 50, 40, 40])
    }

    @Test func minutesOnlyDropsLastSlotWhenThatIsCloser() {
        // 100 s each for 2 min: one is 100 (20 under), two is 200 (80 over). Keep one, pad to 120.
        let catalog = (0..<4).map { make("Back Move \($0)", ["Lower Back"], seconds: 100) }
        let routine = RoutinePicker.pick(intent: intent([.lowerBack], minutes: 2), from: catalog)
        #expect(seconds(routine) == [120])
    }

    @Test func minutesOnlyDoesNotStretchAShortPool() {
        let catalog = (0..<2).map { make("Back Move \($0)", ["Lower Back"]) }
        let routine = RoutinePicker.pick(intent: intent([.lowerBack], minutes: 5), from: catalog)
        #expect(seconds(routine) == [60, 60])
    }

    @Test func noMinutesKeepsAuthoredDurations() {
        let catalog = (0..<10).map { make("Back Move \($0)", ["Lower Back"], seconds: 50) }
        let routine = RoutinePicker.pick(intent: intent([.lowerBack]), from: catalog)
        #expect(routine?.durationOverrides.isEmpty == true)
    }

    // MARK: - Building on a draft

    @Test func excludedExercisesAreNeverPicked() {
        let catalog = (0..<4).map { make("Back Move \($0)", ["Lower Back"]) }
        let inDraft: Set<UUID> = [catalog[0].uuid, catalog[1].uuid]
        let routine = RoutinePicker.pick(intent: intent([.lowerBack], count: 2), from: catalog, excluding: inDraft)
        #expect(names(routine) == ["Back Move 2", "Back Move 3"])
    }

    @Test func slotsGroupAdjacentPairs() {
        let list = [make("Bridge", []), make("Left Hip Opener", []), make("Right Hip Opener", []),
                    make("Left Calf Stretch", []), make("Knee Hug", [])]
        #expect(RoutinePicker.slots(of: list).map { $0.map(\.name) } ==
                [["Bridge"], ["Left Hip Opener", "Right Hip Opener"], ["Left Calf Stretch"], ["Knee Hug"]])
    }

    @Test func pairKeyStripsSidePrefix() {
        #expect(RoutinePicker.pairKey("Left Hip Opener") == "Hip Opener")
        #expect(RoutinePicker.pairKey("Right Hip Opener") == "Hip Opener")
        #expect(RoutinePicker.pairKey("Pelvic Tilt") == "Pelvic Tilt")
    }
}
