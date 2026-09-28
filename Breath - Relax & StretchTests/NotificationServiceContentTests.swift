import Testing
import Foundation
import UserNotifications
@testable import BreathRelaxStretch

// Covers only the pure content-decision functions — whether/what to notify.
// Actual UNUserNotificationCenter scheduling (like the pre-existing
// scheduleReminders) isn't unit tested; that's a thin wrapper around a
// system API with no branching logic of its own to verify here.
struct NotificationServiceContentTests {

    private func makeProfile(streak: Int, lastSession: Date?) -> UserProfile {
        let p = UserProfile(profileID: "test", displayName: "Tester")
        p.streak = streak
        p.lastSessionDate = lastSession
        return p
    }

    // MARK: - Streak risk

    @Test func streakRiskContentNilWhenNotAtRisk() {
        let p = makeProfile(streak: 5, lastSession: Date())
        #expect(NotificationService.streakRiskContent(profile: p) == nil)
    }

    @Test func streakRiskContentPresentWhenAtRisk() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let p = makeProfile(streak: 5, lastSession: yesterday)
        let content = NotificationService.streakRiskContent(profile: p)
        #expect(content != nil)
        #expect(content?.body.contains("5") == true)
    }

    // MARK: - Imbalance summary

    @Test func imbalanceSummaryContentNilWhenNoNeglectedGroups() {
        #expect(NotificationService.imbalanceSummaryContent(neglectedGroups: []) == nil)
    }

    @Test func imbalanceSummaryContentNamesLeastCoveredGroup() {
        let content = NotificationService.imbalanceSummaryContent(neglectedGroups: ["Legs", "Back"])
        #expect(content != nil)
        #expect(content?.body.contains("Legs") == true)
    }
}
