import Testing
@testable import BreathRelaxStretch

@MainActor
struct RoutinePickerTests {
    private func intent(_ areas: [AskArea] = [], goal: AskGoal? = nil, minutes: Int? = nil) -> AskIntent {
        AskIntent(areas: areas, goal: goal, minutes: minutes, seriousness: .ok, isOffTopic: false)
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

    @Test func pairKeyStripsSidePrefix() {
        #expect(RoutinePicker.pairKey("Left Hip Opener") == "Hip Opener")
        #expect(RoutinePicker.pairKey("Right Hip Opener") == "Hip Opener")
        #expect(RoutinePicker.pairKey("Pelvic Tilt") == "Pelvic Tilt")
    }
}
