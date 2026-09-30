import Foundation

/// Best-effort profile upload outside a session, e.g. right after buying a
/// streak saver, so the purchase reaches other devices without waiting for
/// the next session.
enum ProfileSyncService {
    @MainActor
    static func upload(_ profile: UserProfile) {
        let snapshot = RemoteProfile(
            id: AuthManager.shared.backendID,
            displayName: profile.displayName,
            totalPoints: profile.totalPoints,
            streak: profile.streak,
            totalMinutes: profile.totalMinutes,
            lastSessionAt: profile.lastSessionDate,
            pointsSpent: profile.pointsSpent,
            streakFreezeTokens: profile.streakFreezeTokens
        )
        Task {
            guard SupabaseService.isConfigured, AuthManager.shared.isBackendAuthenticated else { return }
            try? await SupabaseService.shared.uploadProfile(snapshot)
        }
    }
}
