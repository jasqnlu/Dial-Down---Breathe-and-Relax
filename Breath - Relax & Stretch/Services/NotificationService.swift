import Foundation
import UserNotifications

@MainActor
final class NotificationService {

    // MARK: - Singleton

    static let shared = NotificationService()
    private init() {}

    // MARK: - Permission

    func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            return false
        }
    }

    // MARK: - Schedule

    /// Schedules daily reminders at `hour` on each day in `weekdays`.
    /// `weekdays` uses Calendar weekday numbers: 1 = Sunday … 7 = Saturday.
    /// Any previously scheduled reminders are replaced.
    func scheduleReminders(hour: Int, weekdays: Set<Int>) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: allIdentifiers)

        let content = UNMutableNotificationContent()
        content.title = "Time to Breathe & Stretch"
        content.body  = "Your daily wellness session is waiting. Just 5 minutes makes a difference."
        content.sound = .default

        for weekday in weekdays {
            var components = DateComponents()
            components.weekday = weekday
            components.hour    = hour
            components.minute  = 0

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(
                identifier: identifier(for: weekday),
                content: content,
                trigger: trigger
            )
            center.add(request) { error in
                if let error {
                    print("[NotificationService] Failed to schedule weekday \(weekday): \(error)")
                }
            }
        }
    }

    // MARK: - Activity insight notifications

    private static let streakRiskIdentifier = "insight-streak-risk"
    private static let imbalanceSummaryIdentifier = "insight-imbalance-summary"

    /// Content for the streak-risk nudge, or `nil` when there's nothing to
    /// warn about (see `ActivityInsightsEngine.isStreakAtRisk`). A pure
    /// decision function so it's testable without touching
    /// `UNUserNotificationCenter`.
    nonisolated static func streakRiskContent(profile: UserProfile, now: Date = Date()) -> UNMutableNotificationContent? {
        guard ActivityInsightsEngine.isStreakAtRisk(profile: profile, now: now) else { return nil }
        let content = UNMutableNotificationContent()
        content.title = "Don't lose your streak"
        content.body = "Your \(profile.streak)-day streak is still up for grabs today — a few minutes keeps it alive."
        content.sound = .default
        return content
    }

    /// Content for the weekly imbalance nudge, naming the least-covered
    /// group, or `nil` when nothing's neglected.
    nonisolated static func imbalanceSummaryContent(neglectedGroups: [String]) -> UNMutableNotificationContent? {
        guard let group = neglectedGroups.first else { return nil }
        let content = UNMutableNotificationContent()
        content.title = "Balance check"
        content.body = "You haven't trained \(group) much lately — want to add it to your next session?"
        content.sound = .default
        return content
    }

    /// Schedules (or cancels, if not at risk) today's streak-risk reminder.
    /// Call after a session records and on app foreground. Rides on the same
    /// "Daily Reminders" permission as `scheduleReminders` — skips silently
    /// if the user hasn't granted notification permission.
    func scheduleStreakRiskCheck(profile: UserProfile, hour: Int, now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.streakRiskIdentifier])
        guard await authorizationStatus() == .authorized,
              let content = Self.streakRiskContent(profile: profile, now: now) else { return }

        var components = Calendar.current.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: Self.streakRiskIdentifier, content: content, trigger: trigger)
        try? await center.add(request)
    }

    /// Schedules (or cancels, if nothing's neglected) the weekly imbalance
    /// summary for the given weekday/hour.
    func scheduleImbalanceSummary(neglectedGroups: [String], weekday: Int, hour: Int) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.imbalanceSummaryIdentifier])
        guard await authorizationStatus() == .authorized,
              let content = Self.imbalanceSummaryContent(neglectedGroups: neglectedGroups) else { return }

        var components = DateComponents()
        components.weekday = weekday
        components.hour = hour
        components.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: Self.imbalanceSummaryIdentifier, content: content, trigger: trigger)
        try? await center.add(request)
    }

    // MARK: - Cancel

    func cancelReminders() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: allIdentifiers)
    }

    /// Cancels both activity-insight notifications — call when the user
    /// turns off Daily Reminders, matching `cancelReminders`.
    func cancelInsightNotifications() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.streakRiskIdentifier, Self.imbalanceSummaryIdentifier])
    }

    // MARK: - Status

    func authorizationStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }

    // MARK: - Identifiers

    private var allIdentifiers: [String] {
        (1...7).map { identifier(for: $0) }
    }

    private func identifier(for weekday: Int) -> String {
        "reminder-weekday-\(weekday)"
    }
}
