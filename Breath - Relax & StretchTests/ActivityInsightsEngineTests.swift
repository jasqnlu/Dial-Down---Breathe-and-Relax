import Testing
import Foundation
@testable import BreathRelaxStretch

struct ActivityInsightsEngineTests {

    // MARK: - Fixtures

    private func makeExercise(name: String = "Test", targetBodyParts: [String]) -> Exercise {
        Exercise(name: name, type: .stretch, targetBodyParts: targetBodyParts,
                 durationSeconds: 60, difficulty: 1, instructions: [])
    }

    private func makeSession(exerciseIDs: [UUID], daysAgo: Int, now: Date) -> Session {
        let calendar = Calendar.current
        let completedAt = calendar.date(byAdding: .day, value: -daysAgo, to: now)!
        let session = Session(routineID: UUID(), startedAt: completedAt, completionPercent: 1.0, pointsEarned: 10)
        session.completedAt = completedAt
        session.exerciseIDs = exerciseIDs
        return session
    }

    private func makeProfile(streak: Int, lastSession: Date?) -> UserProfile {
        let p = UserProfile(profileID: "test", displayName: "Tester")
        p.streak = streak
        p.lastSessionDate = lastSession
        return p
    }

    // MARK: - Coverage scores

    @Test func groupWithNoSessionsScoresZero() {
        let now = Date()
        let scores = ActivityInsightsEngine.coverageScores(sessions: [], exercisesByID: [:], now: now)
        #expect(scores["Legs"] == 0)
    }

    @Test func sessionTodayScoresFullWeight() {
        let now = Date()
        let legs = makeExercise(targetBodyParts: ["Legs"])
        let session = makeSession(exerciseIDs: [legs.uuid], daysAgo: 0, now: now)
        let scores = ActivityInsightsEngine.coverageScores(
            sessions: [session], exercisesByID: [legs.uuid: legs], now: now, windowDays: 14)
        #expect(scores["Legs"] == 1.0)
    }

    @Test func sessionAtEdgeOfWindowScoresNearZero() {
        let now = Date()
        let legs = makeExercise(targetBodyParts: ["Legs"])
        let session = makeSession(exerciseIDs: [legs.uuid], daysAgo: 14, now: now)
        let scores = ActivityInsightsEngine.coverageScores(
            sessions: [session], exercisesByID: [legs.uuid: legs], now: now, windowDays: 14)
        #expect(scores["Legs"] == 0)
    }

    @Test func sessionOutsideWindowIsIgnored() {
        let now = Date()
        let legs = makeExercise(targetBodyParts: ["Legs"])
        let session = makeSession(exerciseIDs: [legs.uuid], daysAgo: 20, now: now)
        let scores = ActivityInsightsEngine.coverageScores(
            sessions: [session], exercisesByID: [legs.uuid: legs], now: now, windowDays: 14)
        #expect(scores["Legs"] == 0)
    }

    @Test func multipleSessionsAccumulateWeight() {
        let now = Date()
        let legs = makeExercise(targetBodyParts: ["Legs"])
        let sessions = [
            makeSession(exerciseIDs: [legs.uuid], daysAgo: 0, now: now),
            makeSession(exerciseIDs: [legs.uuid], daysAgo: 7, now: now),
        ]
        let scores = ActivityInsightsEngine.coverageScores(
            sessions: sessions, exercisesByID: [legs.uuid: legs], now: now, windowDays: 14)
        // 1.0 (today) + 0.5 (7 days ago, halfway through a 14-day window)
        #expect(scores["Legs"] == 1.5)
    }

    // MARK: - Neglected groups

    @Test func groupsBelowThresholdAreNeglected() {
        let scores = ["Legs": 0.1, "Core": 2.0, "Back": 0.4]
        let neglected = ActivityInsightsEngine.neglectedGroups(from: scores, threshold: 0.5)
        #expect(Set(neglected) == ["Legs", "Back"])
    }

    @Test func neglectedGroupsAreSortedLeastCoveredFirst() {
        let scores = ["Legs": 0.4, "Back": 0.1]
        let neglected = ActivityInsightsEngine.neglectedGroups(from: scores, threshold: 0.5)
        #expect(neglected == ["Back", "Legs"])
    }

    @Test func noGroupsBelowThresholdReturnsEmpty() {
        let scores = ["Legs": 2.0, "Core": 3.0]
        #expect(ActivityInsightsEngine.neglectedGroups(from: scores, threshold: 0.5).isEmpty)
    }

    // MARK: - Streak risk

    @Test func noStreakIsNeverAtRisk() {
        let p = makeProfile(streak: 0, lastSession: nil)
        #expect(!ActivityInsightsEngine.isStreakAtRisk(profile: p))
    }

    @Test func streakWithTodaysSessionIsNotAtRisk() {
        let p = makeProfile(streak: 5, lastSession: Date())
        #expect(!ActivityInsightsEngine.isStreakAtRisk(profile: p))
    }

    @Test func activeStreakWithoutTodaysSessionIsAtRisk() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let p = makeProfile(streak: 5, lastSession: yesterday)
        #expect(ActivityInsightsEngine.isStreakAtRisk(profile: p))
    }
}
