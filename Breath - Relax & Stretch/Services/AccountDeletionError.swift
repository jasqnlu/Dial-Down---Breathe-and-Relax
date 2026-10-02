import Foundation

/// Why Delete Account didn't go through. Every case means *nothing was
/// deleted*: the app keeps the user signed in so they can retry
/// (decision 2026-10-01). `nonisolated` because SupabaseService (an actor)
/// creates these.
nonisolated enum AccountDeletionError: LocalizedError, Equatable {
    case notSignedIn
    case appleReauthRequired
    case appleRevokeFailed
    case network
    case server

    /// Maps the delete-account Edge Function's `{"error": ...}` body, falling
    /// back to the HTTP status when the body isn't one of ours (e.g. a
    /// gateway error page).
    init(serverCode: String?, status: Int) {
        switch (serverCode, status) {
        case ("apple_reauth_required", _): self = .appleReauthRequired
        case ("apple_revoke_failed", _):   self = .appleRevokeFailed
        case (_, 401):                     self = .notSignedIn
        default:                           self = .server
        }
    }

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return String(localized: "Your session has expired. Sign out, sign back in, then try deleting again.")
        case .appleReauthRequired:
            return String(localized: "Please confirm with Sign in with Apple to delete your account.")
        case .appleRevokeFailed:
            return String(localized: "Couldn't reach Apple to remove Sign in with Apple. Your account wasn't deleted. Please try again.")
        case .network:
            return String(localized: "You're offline. Your account wasn't deleted. Connect to the internet and try again.")
        case .server:
            return String(localized: "Something went wrong on our end. Your account wasn't deleted. Please try again.")
        }
    }
}
