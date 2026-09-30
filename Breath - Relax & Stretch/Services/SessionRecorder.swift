import Foundation
import SwiftData
import os

/// Everything a completed session (stretch routine or breathing pattern) needs
/// recorded: the SwiftData `Session` row, `UserProfile` stats/streak/badges,
/// HealthKit, and Calendar. `SessionPlayerView` and
/// `BreathingView` each drove this pipeline independently and had already
/// drifted once (breathing passed no `bodyPartsCovered`) — this is the single
/// place it happens now.
@MainActor
enum SessionRecorder {

    enum HealthKitKind {
        case stretch
        case breathing
    }

    struct Input {
        var routineID: UUID
        var startedAt: Date
        var completedAt: Date
        var completionPercent: Double
        var pointsEarned: Int
        var exerciseIDs: [UUID] = []
        var sessionLabel: String? = nil
        var roundsCompleted: Int = 0
        var bodyPartsCovered: Set<String> = []
        var difficultiesCovered: Set<Int> = []
        var isBorrowedRoutine: Bool = false
        var calendarTitle: String
        var healthKitKind: HealthKitKind
    }

    /// The streak state after a `record()` call — split out from a bare Int
    /// so callers (the post-session summary screen) can tell a genuine
    /// streak bump from a second session completed the same day, which
    /// leaves `streak` unchanged and shouldn't replay the "streak up" beat.
    struct Outcome {
        var streak: Int
        var streakIncreased: Bool
        var newlyEarnedBadges: [String] = []
    }

    /// Persists the session, updates profile stats/streak/badges, and fans out
    /// to HealthKit/Calendar. Returns the profile's streak state after
    /// the update (zero/unchanged if no profile exists yet) so callers can
    /// use it without a second fetch.
    @discardableResult
    static func record(
        _ input: Input,
        modelContext: ModelContext,
        calendarSyncEnabled: Bool
    ) -> Outcome {
        let session = Session(
            routineID: input.routineID,
            startedAt: input.startedAt,
            completionPercent: input.completionPercent,
            pointsEarned: input.pointsEarned
        )
        session.completedAt = input.completedAt
        session.exerciseIDs = input.exerciseIDs
        session.sessionLabel = input.sessionLabel
        session.roundsCompleted = input.roundsCompleted
        modelContext.insert(session)
        // Sessions are append-only — never edited or deleted after this, so
        // this is the only place a session ever needs to enqueue. See
        // docs/superpowers/specs/2026-09-23-routine-session-sync-engine-design.md.
        SyncOutbox().enqueue(.session, id: session.uuid, op: .upsert, in: modelContext)

        var outcome = Outcome(streak: 0, streakIncreased: false)
        let descriptor = FetchDescriptor<UserProfile>()
        if let profile = try? modelContext.fetch(descriptor).first {
            profile.totalPoints += input.pointsEarned
            let elapsedSeconds = input.completedAt.timeIntervalSince(input.startedAt)
            let earnedMinutes = elapsedSeconds >= 30 ? max(1, Int((elapsedSeconds / 60).rounded())) : 0
            profile.totalMinutes += earnedMinutes
            let previousStreak = profile.streak
            GamificationService.updateStreak(for: profile)

            let calendar = Calendar.current
            let hour = calendar.component(.hour, from: input.startedAt)
            if hour < 8 { profile.earlyBirdSessionCount += 1 }
            if hour >= 22 { profile.nightOwlSessionCount += 1 }
            if calendar.isDateInWeekend(input.startedAt) { profile.weekendSessionCount += 1 }
            for group in GamificationService.majorMuscleGroups
            where input.bodyPartsCovered.contains(where: { $0.localizedCaseInsensitiveContains(group) })
                && !profile.categoriesTouched.contains(group) {
                profile.categoriesTouched.append(group)
            }
            for difficulty in input.difficultiesCovered where !profile.difficultiesTouched.contains(difficulty) {
                profile.difficultiesTouched.append(difficulty)
            }
            switch input.healthKitKind {
            case .breathing: profile.hasCompletedBreathing = true
            case .stretch:   profile.hasCompletedStretch = true
            }

            var newBadges = GamificationService.newBadges(for: profile, bodyPartsCovered: input.bodyPartsCovered)
            GamificationService.applyBadges(newBadges, to: profile)
            if input.isBorrowedRoutine, GamificationService.awardBadge("Borrowed & Built", to: profile) {
                newBadges.append("Borrowed & Built")
            }
            outcome = Outcome(
                streak: profile.streak,
                streakIncreased: profile.streak > previousStreak,
                newlyEarnedBadges: newBadges)
        }

        do {
            try modelContext.save()
        } catch {
            Logger(subsystem: "com.jasonlu.breath", category: "sessionRecorder").warning("Save failed: \(error)")
        }

        // Cancels today's streak-risk notification now that a session was
        // just logged (scheduleStreakRiskCheck no-ops the reschedule since
        // isStreakAtRisk is false right after recording, but always clears
        // any previously pending request first). Matches the
        // notificationsEnabled gate TodayView's reschedule uses.
        if UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true,
           let profile = try? modelContext.fetch(FetchDescriptor<UserProfile>()).first {
            let hour = UserDefaults.standard.object(forKey: "reminderHour") as? Int ?? 8
            Task {
                await NotificationService.shared.scheduleStreakRiskCheck(profile: profile, hour: hour)
            }
        }

        // HealthKit — no-op unless the user connected Apple Health in Settings;
        // never prompts here.
        Task {
            switch input.healthKitKind {
            case .stretch:
                await HealthKitService.shared.logStretchSession(startedAt: input.startedAt, completedAt: input.completedAt)
            case .breathing:
                await HealthKitService.shared.logBreathingSession(startedAt: input.startedAt, completedAt: input.completedAt)
            }
        }

        // Community — best-effort upload to the user's own *private* profiles
        // row (last_session_at lets the streak-warning server job know this
        // user already practiced today). Only if the user opted in to the
        // leaderboard is a pseudonymous stats row refreshed too. Snapshot
        // scalar fields now; `profile` is a SwiftData @Model and shouldn't
        // be captured into the Task below.
        if let profile = try? modelContext.fetch(FetchDescriptor<UserProfile>()).first {
            let snapshot = RemoteProfile(
                id: AuthManager.shared.backendID,
                displayName: profile.displayName,
                totalPoints: profile.totalPoints,
                streak: profile.streak,
                totalMinutes: profile.totalMinutes,
                lastSessionAt: input.completedAt,
                pointsSpent: profile.pointsSpent,
                streakFreezeTokens: profile.streakFreezeTokens
            )
            Task {
                guard SupabaseService.isConfigured, AuthManager.shared.isBackendAuthenticated else { return }
                try? await SupabaseService.shared.uploadProfile(snapshot)
                if let handle = LeaderboardPreference.handle {
                    try? await SupabaseService.shared.joinLeaderboard(RemoteLeaderboardRow(
                        userID: snapshot.id, handle: handle,
                        totalPoints: snapshot.totalPoints, streak: snapshot.streak,
                        totalMinutes: snapshot.totalMinutes))
                }
            }
        }

        // Calendar — opt-in, mirrors the session as an event
        if calendarSyncEnabled {
            CalendarService.shared.logCompletedSession(
                title: input.calendarTitle, start: input.startedAt, end: input.completedAt)
        }

        return outcome
    }
}
