import Foundation
import SwiftData

@Model
final class UserProfile {
    // Inline defaults required for CloudKit (iCloud) sync compatibility.
    var profileID: String = ""
    var displayName: String = ""
    var totalMinutes: Int = 0
    var totalPoints: Int = 0
    /// Lifetime points spent on streak savers. Only ever increases, so the
    /// "max wins" cross-device merge can never resurrect spent points.
    var pointsSpent: Int = 0
    var streak: Int = 0
    var lastSessionDate: Date? = nil
    var badges: [String] = []
    var streakFreezeTokens: Int = 0
    var sessionsTowardNextFreezeToken: Int = 0
    var pendingStreakBreak: Int = 0
    var earlyBirdSessionCount: Int = 0
    var nightOwlSessionCount: Int = 0
    var weekendSessionCount: Int = 0
    var categoriesTouched: [String] = []
    var difficultiesTouched: [Int] = []
    var hasCompletedBreathing: Bool = false
    var hasCompletedStretch: Bool = false

    init(profileID: String, displayName: String) {
        self.profileID = profileID
        self.displayName = displayName
    }

    /// Points available to spend. Lifetime `totalPoints` (badges, stats) is
    /// untouched by spending. Clamped so a bad merge can't go negative.
    var spendablePoints: Int { max(0, totalPoints - pointsSpent) }

    /// SwiftData can't enforce `.unique` on `profileID` once a CloudKit
    /// container is configured, so if sync ever produces two rows before a
    /// merge resolves, code that reads "the" profile via `.first` would
    /// non-deterministically split a user's stats across two rows. Call this
    /// once on launch to fold any duplicates into a single surviving row.
    static func dedupe(in context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<UserProfile>())) ?? []
        guard all.count > 1 else { return }

        let survivor = all[0]
        for duplicate in all.dropFirst() {
            survivor.totalPoints += duplicate.totalPoints
            survivor.totalMinutes += duplicate.totalMinutes
            survivor.streak = max(survivor.streak, duplicate.streak)
            for badge in duplicate.badges where !survivor.badges.contains(badge) {
                survivor.badges.append(badge)
            }
            if let dupDate = duplicate.lastSessionDate,
               dupDate > (survivor.lastSessionDate ?? .distantPast) {
                survivor.lastSessionDate = dupDate
            }
            context.delete(duplicate)
        }

        do {
            try context.save()
        } catch {
            #if DEBUG
            print("⚠️ SwiftData save failed in UserProfile.dedupe: \(error)")
            #endif
        }
    }
}
