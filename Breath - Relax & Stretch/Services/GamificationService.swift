import Foundation

struct GamificationService {

    // MARK: - Points

    static func points(for exercise: Exercise?, completion: Double) -> Int {
        guard let exercise else { return 0 }
        let durationMinutes = Double(exercise.durationSeconds) / 60.0
        let difficultyMultiplier: Double = switch exercise.difficulty {
            case 1:  1.0
            case 2:  1.5
            case 3:  2.0
            default: 1.0
        }
        let completionBonus: Double = completion >= 1.0 ? 1.2 : completion >= 0.75 ? 1.0 : 0.7
        return max(1, Int(durationMinutes * difficultyMultiplier * completionBonus * 10))
    }

    /// Averages each exercise's individual completion into one session-wide
    /// value, instead of a session's completionPercent reflecting only
    /// whichever exercise happened to finish (or get skipped) last.
    static func aggregateCompletion(_ perExerciseCompletions: [Double]) -> Double {
        guard !perExerciseCompletions.isEmpty else { return 0 }
        return perExerciseCompletions.reduce(0, +) / Double(perExerciseCompletions.count)
    }

    /// Scales skip completion by actual elapsed time vs. the exercise's
    /// configured duration, so tapping skip immediately doesn't earn the same
    /// credit as skipping seconds before the exercise would have finished.
    /// A small floor keeps a glance-and-skip from earning literally nothing.
    static func skipCompletion(elapsedSeconds: Int, durationSeconds: Int) -> Double {
        guard durationSeconds > 0 else { return 0.5 }
        let fraction = Double(elapsedSeconds) / Double(durationSeconds)
        return max(0.1, min(1.0, fraction))
    }

    // MARK: - Streak

    static func updateStreak(for profile: UserProfile) {
        profile.pendingStreakBreak = 0

        let calendar = Calendar.current
        if let last = profile.lastSessionDate {
            if calendar.isDateInYesterday(last) {
                profile.streak += 1
            } else if !calendar.isDateInToday(last) {
                profile.streak = 1
            }
            // If already completed a session today, don't change streak
        } else {
            profile.streak = 1
        }
        profile.lastSessionDate = Date()

        profile.sessionsTowardNextFreezeToken += 1
        if profile.sessionsTowardNextFreezeToken >= 7 {
            profile.sessionsTowardNextFreezeToken = 0
            if profile.streakFreezeTokens < maxSavers {
                profile.streakFreezeTokens += 1
            }
        }
    }

    // MARK: - Streak Freeze

    /// Detects an unresolved break in the streak caused by inactivity (not by
    /// completing a session — that's handled above in `updateStreak`). Call
    /// this on app foreground, not on session completion. Idempotent: once a
    /// break is pending, repeated calls return the same value until resolved
    /// via `restoreStreak` or `dismissStreakBreak`.
    @discardableResult
    static func checkForBrokenStreak(for profile: UserProfile) -> Int? {
        if profile.pendingStreakBreak > 0 { return profile.pendingStreakBreak }
        guard let last = profile.lastSessionDate else { return nil }
        let calendar = Calendar.current
        guard !calendar.isDateInToday(last), !calendar.isDateInYesterday(last) else { return nil }
        guard profile.streak >= 2 else { return nil }
        profile.pendingStreakBreak = profile.streak
        profile.streak = 0
        return profile.pendingStreakBreak
    }

    /// Spends one freeze token to restore the streak lost in
    /// `checkForBrokenStreak`. No-op if there's no pending break or no
    /// tokens banked.
    static func restoreStreak(for profile: UserProfile) {
        guard profile.streakFreezeTokens > 0, profile.pendingStreakBreak > 0 else { return }
        profile.streakFreezeTokens -= 1
        profile.streak = profile.pendingStreakBreak
        profile.pendingStreakBreak = 0
        profile.lastSessionDate = Date()
    }

    /// Acknowledges a lost streak without spending a token.
    static func dismissStreakBreak(for profile: UserProfile) {
        profile.pendingStreakBreak = 0
    }

    // MARK: - Buying Savers

    static let saverCost = 150
    static let maxSavers = 3

    enum SaverBlockReason: Equatable {
        case atMax
        case needMorePoints(Int)
    }

    /// Why a purchase is blocked, or nil when allowed. Holding the maximum
    /// takes precedence over being short on points.
    static func saverPurchaseBlockReason(_ profile: UserProfile) -> SaverBlockReason? {
        if profile.streakFreezeTokens >= maxSavers { return .atMax }
        if profile.spendablePoints < saverCost {
            return .needMorePoints(saverCost - profile.spendablePoints)
        }
        return nil
    }

    static func canBuySaver(_ profile: UserProfile) -> Bool {
        saverPurchaseBlockReason(profile) == nil
    }

    /// Spends `saverCost` points for one streak saver. No-op (returns false)
    /// when blocked. Lifetime `totalPoints` is deliberately left alone.
    @discardableResult
    static func buySaver(for profile: UserProfile) -> Bool {
        guard canBuySaver(profile) else { return false }
        profile.pointsSpent += saverCost
        profile.streakFreezeTokens += 1
        return true
    }

    /// For the "Streak Lost" alert when the user holds no savers: buy one and
    /// immediately use it on the pending break. Nothing changes on failure.
    @discardableResult
    static func buyAndRestore(for profile: UserProfile) -> Bool {
        guard profile.pendingStreakBreak > 0, buySaver(for: profile) else { return false }
        restoreStreak(for: profile)
        return true
    }

    // MARK: - Badges

    /// The coarse muscle-group buckets "Full Body" and "Well Rounded" are
    /// evaluated against. Kept as a shared constant so a session's covered
    /// body parts and a profile's lifetime-touched categories are always
    /// bucketed the same way.
    static let majorMuscleGroups = ["Neck", "Shoulders", "Chest", "Back", "Core",
                                     "Arms", "Forearm", "Legs", "Hips", "Glutes"]

    /// Returns badges newly earned after a session.
    /// - Parameters:
    ///   - profile: The user profile to evaluate (already updated with this session's stats).
    ///   - bodyPartsCovered: Body parts targeted across all exercises in the session.
    static func newBadges(for profile: UserProfile, bodyPartsCovered: Set<String> = []) -> [String] {
        var new: [String] = []

        func award(_ badge: String) {
            if !profile.badges.contains(badge) { new.append(badge) }
        }

        award("First Breath")

        // Streak milestones
        if profile.streak >= 3   { award("Streak Starter") }
        if profile.streak >= 7   { award("Weekly Warrior") }
        if profile.streak >= 14  { award("Two Week Streak") }
        if profile.streak >= 30  { award("Month of Mindfulness") }
        if profile.streak >= 60  { award("Streak Legend") }
        if profile.streak >= 100 { award("Unstoppable") }

        // Time milestones
        if profile.totalMinutes >= 30   { award("30 Min Club") }
        if profile.totalMinutes >= 60   { award("Hour Hero") }
        if profile.totalMinutes >= 300  { award("5 Hour Club") }
        if profile.totalMinutes >= 600  { award("Ten Hour Club") }
        if profile.totalMinutes >= 1200 { award("Marathoner") }
        if profile.totalMinutes >= 2000 { award("2000 Club") }

        // Time-of-day / habit-shape milestones
        if profile.earlyBirdSessionCount >= 5 { award("Early Bird") }
        if profile.nightOwlSessionCount >= 5  { award("Night Owl") }
        if profile.weekendSessionCount >= 5   { award("Weekend Warrior") }

        // Variety milestones
        if Set(profile.categoriesTouched).isSuperset(of: majorMuscleGroups) { award("Well Rounded") }
        if Set(profile.difficultiesTouched).isSuperset(of: [1, 2, 3]) { award("Difficulty Climber") }
        if profile.hasCompletedBreathing && profile.hasCompletedStretch { award("Best of Both") }

        // Points milestones
        if profile.totalPoints >= 100  { award("Century") }
        if profile.totalPoints >= 500  { award("High Achiever") }
        if profile.totalPoints >= 1000 { award("Elite Breather") }

        // Full body — session must touch 5+ distinct major muscle groups
        if !bodyPartsCovered.isEmpty {
            let coveredCount = majorMuscleGroups.filter { group in
                bodyPartsCovered.contains { $0.localizedCaseInsensitiveContains(group) }
            }.count
            if coveredCount >= 5 { award("Full Body") }
        }

        return new
    }

    /// Awards a single badge immediately (e.g. on first routine save).
    /// Returns true if the badge was newly applied; false if already earned.
    @discardableResult
    static func awardBadge(_ badge: String, to profile: UserProfile) -> Bool {
        guard !profile.badges.contains(badge) else { return false }
        profile.badges.append(badge)
        return true
    }

    static func applyBadges(_ badges: [String], to profile: UserProfile) {
        for badge in badges where !profile.badges.contains(badge) {
            profile.badges.append(badge)
        }
    }
}
