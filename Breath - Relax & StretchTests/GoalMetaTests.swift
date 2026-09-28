import Testing
@testable import BreathRelaxStretch

struct GoalMetaTests {

    @Test func wakeUpAndUnwindPoolsExist() {
        #expect(GoalMeta.all.contains { $0.id == "wake_up" })
        #expect(GoalMeta.all.contains { $0.id == "unwind" })
    }

    @Test func wakeUpAndUnwindExerciseNamesExistInSeedData() throws {
        let seedNames = Set(try SeedDataTests.loadExercises().compactMap { $0["name"] as? String })
        let wakeUp = try #require(GoalMeta.all.first { $0.id == "wake_up" })
        let unwind = try #require(GoalMeta.all.first { $0.id == "unwind" })
        for name in wakeUp.exerciseNames + unwind.exerciseNames {
            #expect(seedNames.contains(name), "\(name) not found in SeedData.json")
        }
    }

    // MARK: - Neglect-weighted recommend

    private func makeExercise(name: String, targetBodyParts: [String] = []) -> Exercise {
        Exercise(name: name, type: .stretch, targetBodyParts: targetBodyParts,
                 durationSeconds: 60, difficulty: 1, instructions: [])
    }

    @Test func emptyNeglectedGroupsMatchesUnweightedOrder() {
        let a = makeExercise(name: "A", targetBodyParts: ["Legs"])
        let b = makeExercise(name: "B", targetBodyParts: ["Core"])
        let c = makeExercise(name: "C", targetBodyParts: ["Back"])
        let goal = GoalMeta(id: "g", displayName: "G", exerciseNames: ["A", "B", "C"])
        let all = [a, b, c]

        let unweighted = GoalMeta.recommend(from: all, activeGoalIDs: [goal.id], limit: 2, goals: [goal])
        let weighted = GoalMeta.recommend(from: all, activeGoalIDs: [goal.id], limit: 2, neglectedGroups: [], goals: [goal])
        #expect(unweighted.map(\.name) == weighted.map(\.name))
    }

    @Test func neglectedGroupBoostsMatchingExerciseIntoLimit() {
        // "C" targets the neglected group but sits outside the top-2 window
        // in plain goal order; the neglect boost should pull it inside.
        let a = makeExercise(name: "A", targetBodyParts: ["Core"])
        let b = makeExercise(name: "B", targetBodyParts: ["Core"])
        let c = makeExercise(name: "C", targetBodyParts: ["Legs"])
        let goal = GoalMeta(id: "g", displayName: "G", exerciseNames: ["A", "B", "C"])
        let all = [a, b, c]

        let result = GoalMeta.recommend(
            from: all, activeGoalIDs: [goal.id], limit: 2, neglectedGroups: ["Legs"], neglectWeight: 1.0, goals: [goal])
        #expect(result.map(\.name).contains("C"))
    }

    @Test func neglectWeightZeroLeavesOrderUnchanged() {
        let a = makeExercise(name: "A", targetBodyParts: ["Core"])
        let b = makeExercise(name: "B", targetBodyParts: ["Legs"])
        let goal = GoalMeta(id: "g", displayName: "G", exerciseNames: ["A", "B"])
        let all = [a, b]

        let result = GoalMeta.recommend(
            from: all, activeGoalIDs: [goal.id], limit: 2, neglectedGroups: ["Legs"], neglectWeight: 0, goals: [goal])
        #expect(result.map(\.name) == ["A", "B"])
    }

    @Test func tiedScoresPreserveOriginalOrder() {
        let a = makeExercise(name: "A", targetBodyParts: ["Core"])
        let b = makeExercise(name: "B", targetBodyParts: ["Core"])
        let goal = GoalMeta(id: "g", displayName: "G", exerciseNames: ["A", "B"])
        let all = [a, b]

        let result = GoalMeta.recommend(
            from: all, activeGoalIDs: [goal.id], limit: 2, neglectedGroups: [], goals: [goal])
        #expect(result.map(\.name) == ["A", "B"])
    }
}
