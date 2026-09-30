import Foundation

/// Best-effort profile upload outside a session, e.g. right after buying a
/// streak saver, so the purchase reaches other devices without waiting for
/// the next session.
enum ProfileSyncService {
    @MainActor
    static func upload(_ profile: UserProfile) {
        #if DEBUG
        // UI-test seeding must never write a seeded profile to a real
        // signed-in simulator account.
        if UserDefaults.standard.dictionaryRepresentation().keys.contains(where: { $0.hasPrefix("uiTestSeed") }) { return }
        #endif
        let snapshot = RemoteProfile(
            id: AuthManager.shared.backendID,
            displayName: profile.displayName,
            totalPoints: profile.totalPoints,
            streak: profile.streak,
            totalMinutes: profile.totalMinutes,
            lastSessionAt: profile.lastSessionDate
        )
        let savers = RemoteProfileSavers(id: snapshot.id, profile: profile)
        Task {
            guard SupabaseService.isConfigured, AuthManager.shared.isBackendAuthenticated else { return }
            try? await SupabaseService.shared.uploadProfile(snapshot)
            try? await SupabaseService.shared.uploadProfileSavers(savers)
        }
    }
}
