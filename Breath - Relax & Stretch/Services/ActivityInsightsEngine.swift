import Foundation

/// Descriptive statistics over the user's own session history — no ML, no
/// training, no external data. Drives the "neglected muscle group" boost in
/// GoalMeta.recommend and the streak-risk/imbalance push notifications.
/// Pure computation: callers fetch `Session`/`Exercise`/`UserProfile` from
/// SwiftData and pass them in; nothing here touches persistence.
struct ActivityInsightsEngine {

    static let coverageWindowDays = 14

    /// Per-major-muscle-group coverage score over the trailing `windowDays`,
    /// keyed by the same `GamificationService.majorMuscleGroups` buckets a
    /// session's/profile's body parts are already matched against. Each
    /// session contributes a linearly-decaying weight — 1.0 for a session
    /// today, fading to 0 at the edge of the window — to every major group
    /// any of its exercises target. Groups untouched in the window score 0.
    static func coverageScores(
        sessions: [Session],
        exercisesByID: [UUID: Exercise],
        now: Date = Date(),
        windowDays: Int = coverageWindowDays
    ) -> [String: Double] {
        var scores = Dictionary(uniqueKeysWithValues: GamificationService.majorMuscleGroups.map { ($0, 0.0) })
        let calendar = Calendar.current

        for session in sessions {
            guard let completedAt = session.completedAt else { continue }
            let daysAgo = calendar.dateComponents([.day], from: completedAt, to: now).day ?? Int.max
            guard daysAgo >= 0, daysAgo <= windowDays else { continue }
            let weight = 1.0 - (Double(daysAgo) / Double(windowDays))

            let bodyParts = Set(session.exerciseIDs.compactMap { exercisesByID[$0]?.targetBodyParts }.flatMap { $0 })
            for group in GamificationService.majorMuscleGroups
            where bodyParts.contains(where: { $0.localizedCaseInsensitiveContains(group) }) {
                scores[group, default: 0] += weight
            }
        }
        return scores
    }

    /// Major muscle groups whose coverage score falls below `threshold`,
    /// least-covered first — candidates for the recommendation boost and the
    /// imbalance notification.
    static func neglectedGroups(from scores: [String: Double], threshold: Double) -> [String] {
        scores.filter { $0.value < threshold }
            .sorted { $0.value < $1.value }
            .map(\.key)
    }

    /// True when the user has an active streak but hasn't logged a session
    /// today yet — still salvageable, worth a nudge. A deterministic rule,
    /// not a statistical estimate: "did they practice today" has an exact
    /// answer.
    static func isStreakAtRisk(profile: UserProfile, now: Date = Date()) -> Bool {
        guard profile.streak > 0, let last = profile.lastSessionDate else { return false }
        return !Calendar.current.isDate(last, inSameDayAs: now)
    }
}
