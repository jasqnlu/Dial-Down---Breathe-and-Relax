import Testing
import Foundation
@testable import BreathRelaxStretch

// Covers the point/streak/badge math in GamificationService. These are the
// rules that drive nearly every reward in the app, so the exact numbers below
// are the contract — if the formula changes, these should fail on purpose.
struct GamificationServiceTests {

    // MARK: - Fixtures

    private func makeExercise(duration: Int = 60, difficulty: Int = 1) -> Exercise {
        Exercise(name: "Test",
                 type: .stretch,
                 targetBodyParts: [],
                 durationSeconds: duration,
                 difficulty: difficulty,
                 instructions: [])
    }

    private func makeProfile(streak: Int = 0,
                             minutes: Int = 0,
                             points: Int = 0,
                             pointsSpent: Int = 0,
                             badges: [String] = [],
                             lastSession: Date? = nil,
                             pendingStreakBreak: Int = 0,
                             streakFreezeTokens: Int = 0,
                             earlyBirdSessionCount: Int = 0,
                             nightOwlSessionCount: Int = 0,
                             weekendSessionCount: Int = 0,
                             categoriesTouched: [String] = [],
                             difficultiesTouched: [Int] = [],
                             hasCompletedBreathing: Bool = false,
                             hasCompletedStretch: Bool = false) -> UserProfile {
        let p = UserProfile(profileID: "test", displayName: "Tester")
        p.streak = streak
        p.totalMinutes = minutes
        p.totalPoints = points
        p.pointsSpent = pointsSpent
        p.badges = badges
        p.lastSessionDate = lastSession
        p.pendingStreakBreak = pendingStreakBreak
        p.streakFreezeTokens = streakFreezeTokens
        p.earlyBirdSessionCount = earlyBirdSessionCount
        p.nightOwlSessionCount = nightOwlSessionCount
        p.weekendSessionCount = weekendSessionCount
        p.categoriesTouched = categoriesTouched
        p.difficultiesTouched = difficultiesTouched
        p.hasCompletedBreathing = hasCompletedBreathing
        p.hasCompletedStretch = hasCompletedStretch
        return p
    }

    // MARK: - Points

    @Test func pointsForNilExerciseIsZero() {
        #expect(GamificationService.points(for: nil, completion: 1.0) == 0)
    }

    @Test func pointsScaleWithDifficulty() {
        let e = makeExercise(duration: 60, difficulty: 1)
        // 1 min * 1.0 difficulty * 1.2 full-completion bonus * 10
        #expect(GamificationService.points(for: e, completion: 1.0) == 12)
        #expect(GamificationService.points(for: makeExercise(duration: 60, difficulty: 2), completion: 1.0) == 18)
        #expect(GamificationService.points(for: makeExercise(duration: 60, difficulty: 3), completion: 1.0) == 24)
    }

    @Test func pointsScaleWithDuration() {
        // 2 min * 1.0 * 1.2 * 10 = 24
        #expect(GamificationService.points(for: makeExercise(duration: 120, difficulty: 1), completion: 1.0) == 24)
    }

    @Test func completionBonusTiers() {
        let e = makeExercise(duration: 60, difficulty: 1)
        #expect(GamificationService.points(for: e, completion: 1.0)  == 12) // >= 1.0  -> x1.2
        #expect(GamificationService.points(for: e, completion: 0.75) == 10) // >= 0.75 -> x1.0 (boundary)
        #expect(GamificationService.points(for: e, completion: 0.74) == 7)  // <  0.75 -> x0.7
        #expect(GamificationService.points(for: e, completion: 0.0)  == 7)
    }

    // MARK: - Completion aggregation

    @Test func aggregateCompletionAveragesAllExercises() {
        #expect(GamificationService.aggregateCompletion([1.0, 0.5, 0.7]) == (1.0 + 0.5 + 0.7) / 3)
    }

    @Test func aggregateCompletionOfEmptySessionIsZero() {
        #expect(GamificationService.aggregateCompletion([]) == 0)
    }

    @Test func aggregateCompletionSingleExerciseIsItself() {
        #expect(GamificationService.aggregateCompletion([0.42]) == 0.42)
    }

    // MARK: - Skip completion

    @Test func skipCompletionScalesWithElapsedFraction() {
        #expect(GamificationService.skipCompletion(elapsedSeconds: 30, durationSeconds: 60) == 0.5)
        #expect(GamificationService.skipCompletion(elapsedSeconds: 45, durationSeconds: 60) == 0.75)
        #expect(GamificationService.skipCompletion(elapsedSeconds: 60, durationSeconds: 60) == 1.0)
    }

    @Test func skipCompletionImmediateSkipHitsFloorNotZero() {
        #expect(GamificationService.skipCompletion(elapsedSeconds: 0, durationSeconds: 60) == 0.1)
        #expect(GamificationService.skipCompletion(elapsedSeconds: 1, durationSeconds: 60) == 0.1)
    }

    @Test func skipCompletionNeverExceedsOne() {
        #expect(GamificationService.skipCompletion(elapsedSeconds: 999, durationSeconds: 60) == 1.0)
    }

    @Test func skipCompletionZeroDurationFallsBackToHalf() {
        #expect(GamificationService.skipCompletion(elapsedSeconds: 0, durationSeconds: 0) == 0.5)
    }

    @Test func unknownDifficultyFallsBackToBaseMultiplier() {
        // difficulty 5 isn't a known tier, so it uses the 1.0 default — same as difficulty 1.
        let base = GamificationService.points(for: makeExercise(duration: 60, difficulty: 1), completion: 1.0)
        #expect(GamificationService.points(for: makeExercise(duration: 60, difficulty: 5), completion: 1.0) == base)
    }

    @Test func pointsTruncateRatherThanRound() {
        // 1.5 min * 1.5 * 0.7 * 10 = 15.75 -> truncated to 15
        #expect(GamificationService.points(for: makeExercise(duration: 90, difficulty: 2), completion: 0.74) == 15)
    }

    @Test func pointsNeverDropBelowOne() {
        // A 1-second half-finished session rounds to 0 but is floored to 1.
        #expect(GamificationService.points(for: makeExercise(duration: 1, difficulty: 1), completion: 0.5) == 1)
    }

    // MARK: - Streak

    private func noon(daysAgo: Int) -> Date {
        let cal = Calendar.current
        let base = cal.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
        return cal.date(byAdding: .day, value: -daysAgo, to: base)!
    }

    @Test func firstEverSessionStartsStreakAtOne() {
        let p = makeProfile(lastSession: nil)
        GamificationService.updateStreak(for: p)
        #expect(p.streak == 1)
        #expect(Calendar.current.isDateInToday(p.lastSessionDate ?? .distantPast))
    }

    @Test func consecutiveDayIncrementsStreak() {
        let p = makeProfile(streak: 5, lastSession: noon(daysAgo: 1))
        GamificationService.updateStreak(for: p)
        #expect(p.streak == 6)
    }

    @Test func secondSessionSameDayLeavesStreakUnchanged() {
        let p = makeProfile(streak: 5, lastSession: noon(daysAgo: 0))
        GamificationService.updateStreak(for: p)
        #expect(p.streak == 5)
    }

    @Test func missedDayResetsStreakToOne() {
        let p = makeProfile(streak: 10, lastSession: noon(daysAgo: 3))
        GamificationService.updateStreak(for: p)
        #expect(p.streak == 1)
    }

    // MARK: - Badges (newBadges only reports, it does not mutate the profile)

    @Test func freshProfileEarnsOnlyFirstBreath() {
        #expect(GamificationService.newBadges(for: makeProfile()) == ["First Breath"])
    }

    @Test func newBadgesDoesNotMutateProfile() {
        let p = makeProfile(streak: 7)
        _ = GamificationService.newBadges(for: p)
        #expect(p.badges.isEmpty)
    }

    @Test func streakMilestonesUnlockInOrder() {
        #expect(GamificationService.newBadges(for: makeProfile(streak: 3)) == ["First Breath", "Streak Starter"])
        #expect(GamificationService.newBadges(for: makeProfile(streak: 7)) == ["First Breath", "Streak Starter", "Weekly Warrior"])
        #expect(GamificationService.newBadges(for: makeProfile(streak: 30)) ==
                ["First Breath", "Streak Starter", "Weekly Warrior", "Two Week Streak", "Month of Mindfulness"])
    }

    @Test func alreadyEarnedBadgesAreNotReported() {
        // Streak qualifies for the first two, but the user already has them.
        let p = makeProfile(streak: 7, badges: ["First Breath", "Streak Starter"])
        #expect(GamificationService.newBadges(for: p) == ["Weekly Warrior"])
    }

    @Test func minuteAndPointMilestones() {
        #expect(GamificationService.newBadges(for: makeProfile(minutes: 60)) ==
                ["First Breath", "30 Min Club", "Hour Hero"])
        #expect(GamificationService.newBadges(for: makeProfile(points: 500)) ==
                ["First Breath", "Century", "High Achiever"])
    }

    @Test func fullBodyNeedsFiveDistinctMajorGroups() {
        let five: Set<String> = ["Neck", "Shoulders", "Chest", "Back", "Core"]
        #expect(GamificationService.newBadges(for: makeProfile(), bodyPartsCovered: five).contains("Full Body"))

        let four: Set<String> = ["Neck", "Shoulders", "Chest", "Back"]
        #expect(!GamificationService.newBadges(for: makeProfile(), bodyPartsCovered: four).contains("Full Body"))

        #expect(!GamificationService.newBadges(for: makeProfile(), bodyPartsCovered: []).contains("Full Body"))
    }

    @Test func fullBodyCountsGroupsNotIndividualParts() {
        // "Lower Back" and "Upper Back" both map to the single "Back" group, so
        // this set only covers 4 distinct groups and should not earn Full Body.
        let parts: Set<String> = ["Lower Back", "Upper Back", "Neck", "Core", "Hips"]
        #expect(!GamificationService.newBadges(for: makeProfile(), bodyPartsCovered: parts).contains("Full Body"))
    }

    @Test func everythingAtOnceReportsTheFullBadgeSet() {
        let p = makeProfile(streak: 30, minutes: 300, points: 1000)
        let groups: Set<String> = ["Neck", "Shoulders", "Chest", "Back", "Core"]
        #expect(GamificationService.newBadges(for: p, bodyPartsCovered: groups) == [
            "First Breath", "Streak Starter", "Weekly Warrior", "Two Week Streak", "Month of Mindfulness",
            "30 Min Club", "Hour Hero", "5 Hour Club",
            "Century", "High Achiever", "Elite Breather",
            "Full Body"
        ])
    }

    @Test func higherStreakMilestonesUnlockInOrder() {
        #expect(GamificationService.newBadges(for: makeProfile(streak: 14)).contains("Two Week Streak"))
        #expect(GamificationService.newBadges(for: makeProfile(streak: 60)).contains("Streak Legend"))
        #expect(GamificationService.newBadges(for: makeProfile(streak: 100)).contains("Unstoppable"))
        #expect(!GamificationService.newBadges(for: makeProfile(streak: 13)).contains("Two Week Streak"))
    }

    @Test func higherMinuteMilestonesUnlockInOrder() {
        #expect(GamificationService.newBadges(for: makeProfile(minutes: 600)).contains("Ten Hour Club"))
        #expect(GamificationService.newBadges(for: makeProfile(minutes: 1200)).contains("Marathoner"))
        #expect(GamificationService.newBadges(for: makeProfile(minutes: 2000)).contains("2000 Club"))
        #expect(!GamificationService.newBadges(for: makeProfile(minutes: 599)).contains("Ten Hour Club"))
    }

    @Test func earlyBirdBadgeNeedsFiveMorningSessions() {
        #expect(GamificationService.newBadges(for: makeProfile(earlyBirdSessionCount: 5)).contains("Early Bird"))
        #expect(!GamificationService.newBadges(for: makeProfile(earlyBirdSessionCount: 4)).contains("Early Bird"))
    }

    @Test func nightOwlBadgeNeedsFiveLateSessions() {
        #expect(GamificationService.newBadges(for: makeProfile(nightOwlSessionCount: 5)).contains("Night Owl"))
        #expect(!GamificationService.newBadges(for: makeProfile(nightOwlSessionCount: 4)).contains("Night Owl"))
    }

    @Test func weekendWarriorBadgeNeedsFiveWeekendSessions() {
        #expect(GamificationService.newBadges(for: makeProfile(weekendSessionCount: 5)).contains("Weekend Warrior"))
        #expect(!GamificationService.newBadges(for: makeProfile(weekendSessionCount: 4)).contains("Weekend Warrior"))
    }

    @Test func wellRoundedNeedsAllTenMajorMuscleGroups() {
        let nine = Array(GamificationService.majorMuscleGroups.dropLast())
        #expect(!GamificationService.newBadges(for: makeProfile(categoriesTouched: nine)).contains("Well Rounded"))

        let allTen = GamificationService.majorMuscleGroups
        #expect(GamificationService.newBadges(for: makeProfile(categoriesTouched: allTen)).contains("Well Rounded"))
    }

    @Test func difficultyClimberNeedsAllThreeDifficulties() {
        #expect(!GamificationService.newBadges(for: makeProfile(difficultiesTouched: [1, 2])).contains("Difficulty Climber"))
        #expect(GamificationService.newBadges(for: makeProfile(difficultiesTouched: [1, 2, 3])).contains("Difficulty Climber"))
    }

    @Test func bestOfBothNeedsBreathingAndStretchCompleted() {
        #expect(!GamificationService.newBadges(for: makeProfile(hasCompletedBreathing: true, hasCompletedStretch: false)).contains("Best of Both"))
        #expect(!GamificationService.newBadges(for: makeProfile(hasCompletedBreathing: false, hasCompletedStretch: true)).contains("Best of Both"))
        #expect(GamificationService.newBadges(for: makeProfile(hasCompletedBreathing: true, hasCompletedStretch: true)).contains("Best of Both"))
    }

    // MARK: - awardBadge / applyBadges (these DO mutate the profile)

    @Test func awardBadgeAppendsOnlyOnce() {
        let p = makeProfile()
        #expect(GamificationService.awardBadge("Pioneer", to: p) == true)
        #expect(p.badges == ["Pioneer"])
        #expect(GamificationService.awardBadge("Pioneer", to: p) == false)
        #expect(p.badges == ["Pioneer"])
    }

    @Test func applyBadgesMergesWithoutDuplicates() {
        let p = makeProfile(badges: ["A"])
        GamificationService.applyBadges(["A", "B", "B", "C"], to: p)
        #expect(p.badges == ["A", "B", "C"])
    }

    // MARK: - Streak Freeze

    @Test func noBreakWhenLastSessionWasToday() {
        let p = makeProfile(streak: 5, lastSession: noon(daysAgo: 0))
        #expect(GamificationService.checkForBrokenStreak(for: p) == nil)
        #expect(p.streak == 5)
    }

    @Test func noBreakWhenLastSessionWasYesterday() {
        let p = makeProfile(streak: 5, lastSession: noon(daysAgo: 1))
        #expect(GamificationService.checkForBrokenStreak(for: p) == nil)
        #expect(p.streak == 5)
    }

    @Test func breakDetectedAfterMultipleMissedDays() {
        let p = makeProfile(streak: 6, lastSession: noon(daysAgo: 3))
        #expect(GamificationService.checkForBrokenStreak(for: p) == 6)
        #expect(p.streak == 0)
        #expect(p.pendingStreakBreak == 6)
    }

    @Test func streakOfOneDoesNotTriggerBreakPopup() {
        let p = makeProfile(streak: 1, lastSession: noon(daysAgo: 3))
        #expect(GamificationService.checkForBrokenStreak(for: p) == nil)
        #expect(p.streak == 1)
    }

    @Test func repeatedChecksReturnSamePendingValue() {
        let p = makeProfile(streak: 8, lastSession: noon(daysAgo: 5))
        #expect(GamificationService.checkForBrokenStreak(for: p) == 8)
        p.streak = 999 // something else touched it between checks
        #expect(GamificationService.checkForBrokenStreak(for: p) == 8)
    }

    @Test func restoreStreakSpendsTokenAndRestoresValue() {
        let p = makeProfile(pendingStreakBreak: 6, streakFreezeTokens: 2)
        GamificationService.restoreStreak(for: p)
        #expect(p.streak == 6)
        #expect(p.pendingStreakBreak == 0)
        #expect(p.streakFreezeTokens == 1)
        #expect(Calendar.current.isDateInToday(p.lastSessionDate ?? .distantPast))
    }

    @Test func restoreStreakNoOpWithoutTokens() {
        let p = makeProfile(pendingStreakBreak: 6, streakFreezeTokens: 0)
        GamificationService.restoreStreak(for: p)
        #expect(p.streak == 0)
        #expect(p.pendingStreakBreak == 6)
    }

    @Test func restoreStreakNoOpWithoutPendingBreak() {
        let p = makeProfile(pendingStreakBreak: 0, streakFreezeTokens: 3)
        GamificationService.restoreStreak(for: p)
        #expect(p.streak == 0)
        #expect(p.streakFreezeTokens == 3)
    }

    @Test func dismissStreakBreakClearsPendingWithoutSpendingToken() {
        let p = makeProfile(pendingStreakBreak: 6, streakFreezeTokens: 2)
        GamificationService.dismissStreakBreak(for: p)
        #expect(p.pendingStreakBreak == 0)
        #expect(p.streakFreezeTokens == 2)
        #expect(p.streak == 0)
    }

    @Test func updateStreakClearsStalePendingBreak() {
        let p = makeProfile(streak: 5, lastSession: noon(daysAgo: 1), pendingStreakBreak: 3)
        GamificationService.updateStreak(for: p)
        #expect(p.pendingStreakBreak == 0)
    }

    @Test func freezeTokenAwardedEverySevenSessions() {
        let p = makeProfile(lastSession: noon(daysAgo: 1))
        for _ in 0..<6 {
            GamificationService.updateStreak(for: p)
        }
        #expect(p.streakFreezeTokens == 0)
        #expect(p.sessionsTowardNextFreezeToken == 6)

        GamificationService.updateStreak(for: p)
        #expect(p.streakFreezeTokens == 1)
        #expect(p.sessionsTowardNextFreezeToken == 0)
    }

    @Test func freezeTokensAccumulateUpToCap() {
        let p = makeProfile(lastSession: noon(daysAgo: 1))
        for _ in 0..<21 {
            GamificationService.updateStreak(for: p)
        }
        #expect(p.streakFreezeTokens == 3)
    }

    // MARK: - Buying streak savers

    @Test func spendablePointsIsTotalMinusSpent() {
        let p = makeProfile(points: 400, pointsSpent: 150)
        #expect(p.spendablePoints == 250)
    }

    @Test func spendablePointsClampsAtZero() {
        let p = makeProfile(points: 100, pointsSpent: 250)
        #expect(p.spendablePoints == 0)
    }

    @Test func buySaverDeductsPointsAndAddsToken() {
        let p = makeProfile(points: 400)
        #expect(GamificationService.buySaver(for: p) == true)
        #expect(p.pointsSpent == 150)
        #expect(p.streakFreezeTokens == 1)
        #expect(p.totalPoints == 400)
    }

    @Test func buySaverWorksAtExactPrice() {
        let p = makeProfile(points: 150)
        #expect(GamificationService.buySaver(for: p) == true)
        #expect(p.spendablePoints == 0)
    }

    @Test func buySaverFailsWithoutEnoughPoints() {
        let p = makeProfile(points: 149)
        #expect(GamificationService.buySaver(for: p) == false)
        #expect(p.pointsSpent == 0)
        #expect(p.streakFreezeTokens == 0)
    }

    @Test func buySaverFailsAtCap() {
        let p = makeProfile(points: 1000, streakFreezeTokens: 3)
        #expect(GamificationService.buySaver(for: p) == false)
        #expect(p.pointsSpent == 0)
        #expect(p.streakFreezeTokens == 3)
    }

    @Test func buyingUpToCapThenBlocked() {
        let p = makeProfile(points: 1000)
        #expect(GamificationService.buySaver(for: p))
        #expect(GamificationService.buySaver(for: p))
        #expect(GamificationService.buySaver(for: p))
        #expect(GamificationService.buySaver(for: p) == false)
        #expect(p.streakFreezeTokens == 3)
        #expect(p.pointsSpent == 450)
    }

    @Test func buyingDoesNotChangeBadgeEligibility() {
        let p = makeProfile(points: 500)
        GamificationService.buySaver(for: p)
        let badges = GamificationService.newBadges(for: p)
        #expect(badges.contains("High Achiever"))
    }

    @Test func blockReasonValues() {
        #expect(GamificationService.saverPurchaseBlockReason(makeProfile(points: 1000)) == nil)
        #expect(GamificationService.saverPurchaseBlockReason(makeProfile(points: 108)) == .needMorePoints(42))
        #expect(GamificationService.saverPurchaseBlockReason(makeProfile(points: 1000, streakFreezeTokens: 3)) == .atMax)
        // At the cap wins over insufficient points.
        #expect(GamificationService.saverPurchaseBlockReason(makeProfile(points: 0, streakFreezeTokens: 3)) == .atMax)
    }

    @Test func buyAndRestoreRestoresPendingBreak() {
        let p = makeProfile(points: 200, pendingStreakBreak: 6)
        #expect(GamificationService.buyAndRestore(for: p) == true)
        #expect(p.streak == 6)
        #expect(p.pendingStreakBreak == 0)
        #expect(p.pointsSpent == 150)
        #expect(p.streakFreezeTokens == 0) // bought one, spent one
    }

    @Test func buyAndRestoreFailsWithoutPointsAndKeepsBreakPending() {
        let p = makeProfile(points: 10, pendingStreakBreak: 6)
        #expect(GamificationService.buyAndRestore(for: p) == false)
        #expect(p.pendingStreakBreak == 6)
        #expect(p.pointsSpent == 0)
    }

    @Test func freeTokenSkippedAtCapButCounterResets() {
        let p = makeProfile(lastSession: noon(daysAgo: 1), streakFreezeTokens: 3)
        for _ in 0..<7 {
            GamificationService.updateStreak(for: p)
        }
        #expect(p.streakFreezeTokens == 3)
        #expect(p.sessionsTowardNextFreezeToken == 0)
    }
}
