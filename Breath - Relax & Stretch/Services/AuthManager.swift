import Foundation
import Combine
import AuthenticationServices
import Security
import LocalAuthentication
import CryptoKit
import os

/// What the Sign in with Apple re-confirm sheet hands back before Delete
/// Account (see AppleReauthenticator). `authorizationCode` is the one-time
/// code the server trades with Apple to revoke this app's authorization;
/// `identityToken` + `rawNonce` let a user whose original Supabase exchange
/// failed get a session first; `appleUserID` locates the cached Apple email.
nonisolated struct AppleReauthCredential: Sendable, Equatable {
    let appleUserID: String
    let authorizationCode: String
    let identityToken: String
    let rawNonce: String?
}

// MARK: - Auth Provider

enum AuthProvider: String, Codable {
    case apple  = "apple"
    case google = "google"
    case email  = "email"
    case guest  = "guest"
}

// MARK: - Keychain seam
// Abstraction over Security.framework's SecItem calls so tests can swap in an
// in-memory store — the real keychain is unreliable/unavailable in the test
// runner's sandbox.

// `nonisolated`: the project defaults declarations to @MainActor isolation,
// but the keychain seam is also used from inside the SupabaseService actor
// (session persistence), so it must stay actor-agnostic.
nonisolated protocol KeychainStore {
    func save(account: String, value: String)
    func delete(account: String)
    func loadCredential(account: String) -> String?
}

nonisolated struct SecItemKeychainStore: KeychainStore {
    let service: String

    func save(account: String, value: String) {
        let data = Data(value.utf8)
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData:   data,
            // AfterFirstUnlock: Supabase session refresh must work whenever
            // the app runs, not only while the screen is unlocked.
            // ThisDeviceOnly: password hashes and refresh tokens must not
            // migrate to a new device via backup/device-transfer restores.
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    func delete(account: String) {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    func loadCredential(account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData:  true,
            kSecMatchLimit:  kSecMatchLimitOne
        ]
        var item: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - AuthManager

@MainActor
final class AuthManager: ObservableObject {

    static let shared = AuthManager()

    // MARK: Published state
    @Published private(set) var isSignedIn: Bool    = false
    @Published private(set) var needsUnlock: Bool   = false
    @Published private(set) var displayName: String = ""
    @Published private(set) var userEmail: String   = ""
    @Published private(set) var provider: AuthProvider = .email

    @Published private(set) var firstName: String = ""
    @Published private(set) var lastName: String  = ""

    /// True when local (Apple) sign-in succeeded but the backend exchange
    /// didn't — the account is usable offline, but sync/leaderboard/streak
    /// pull from other devices won't work until it's retried. Google and
    /// email/password never enter this state: `handleGoogleSignIn`/`signIn`/
    /// `signUp` only persist local sign-in *after* the backend exchange
    /// succeeds, so a failure there is reported synchronously to the caller
    /// instead. Apple's credential arrives from a system delegate callback
    /// with nowhere synchronous to report to, so the exchange runs in a
    /// background `Task` and this flag is how its outcome surfaces.
    @Published private(set) var backendSyncFailed = false
    /// Transient pulse set true right after a manual retry succeeds, so the
    /// UI can show a brief "Connected" confirmation. The UI is expected to
    /// reset it back to false once it's done showing that.
    @Published var justReconnected = false

    /// The most recent failed Apple credential, kept in memory only (never
    /// persisted) so `retryBackendConnection()` can resend it. Apple identity
    /// tokens are single-use with a ~10 minute TTL, so a retry attempted long
    /// after the original failure will just fail again — there is no stored-
    /// token retry across app launches, matching `handleAppleCredential`'s
    /// existing behavior of telling the user to sign in with Apple again.
    private var pendingAppleRetry: (identityToken: String, nonce: String?)?

    /// Complete only once the name step has run — provider-supplied names
    /// (Apple/Google/email) deliberately never populate these.
    var personName: PersonName { PersonName(first: firstName, last: lastName) }

    /// What to prefill the name step with: the provider/legacy display name,
    /// split. Placeholders ("Apple User", "Guest", "User") give `.empty`.
    var providerPrefill: PersonName { PersonName.split(fullName: displayName) }

    /// First name for greetings; empty for guests and placeholder names.
    var greetingName: String {
        guard !isGuest else { return "" }
        return firstName.isEmpty ? PersonName.split(fullName: displayName).first : firstName
    }

    var isGuest: Bool { isSignedIn && provider == .guest }

    // MARK: UserDefaults keys
    private let kIsSignedIn   = "auth.isSignedIn"
    private let kDisplayName  = "auth.displayName"
    private let kFirstName    = "auth.firstName"
    private let kLastName     = "auth.lastName"
    private let kEmail        = "auth.email"
    private let kProvider     = "auth.provider"
    private let kAppLockEnabled = "auth.appLockEnabled"
    private let kTwoFAEnabled = "auth.twoFAEnabled" // legacy key migrated to kAppLockEnabled
    private let kAnonymousID  = "auth.anonymousID"
    private let kSupabaseUserID = "auth.supabaseUserID" // auth.uid() — not a secret; the tokens live in the keychain

    // MARK: - Anonymous identity
    // Backend-facing identity. A random UUID minted once per install and used
    // as profiles.id / routines.author_id / sessions.user_id — never the email,
    // because those tables are publicly readable. Survives sign-in/sign-out so
    // a guest who later creates an account keeps their leaderboard row.
    var anonymousID: String {
        let d = UserDefaults.standard
        if let existing = d.string(forKey: kAnonymousID) { return existing }
        let fresh = UUID().uuidString
        d.set(fresh, forKey: kAnonymousID)
        return fresh
    }

    // MARK: - Backend identity
    // What community rows (profiles.id, routines.author_id, sessions.user_id)
    // are keyed on. With a Supabase Auth session (Sign in with Apple) this is
    // the Supabase user id, so the auth.uid() RLS policies authorize writes;
    // otherwise it falls back to the anonymous per-install UUID, whose writes
    // the backend now rejects — community uploads are best-effort by design.
    var backendID: String {
        UserDefaults.standard.string(forKey: kSupabaseUserID) ?? anonymousID
    }

    /// True when a Supabase Auth session backs this user (writes to the
    /// community tables will be authorized as them).
    var isBackendAuthenticated: Bool {
        UserDefaults.standard.string(forKey: kSupabaseUserID) != nil
    }

    private let keychain: KeychainStore
    private let supabase: SupabaseAuthenticating
    private let accountDeleter: SupabaseAccountDeleting

    /// Raw nonce for the in-flight Sign in with Apple request; its SHA-256 is
    /// embedded in the Apple identity token, and Supabase verifies the pair.
    private var pendingAppleNonce: String?

    /// `internal` (not `private`) so `@testable import` can construct
    /// instances with a fake keychain/supabase; production code should still
    /// go through `.shared`.
    init(
        keychain: KeychainStore = SecItemKeychainStore(service: "com.breathapp.auth"),
        supabase: SupabaseAuthenticating = SupabaseService.shared,
        accountDeleter: SupabaseAccountDeleting = SupabaseService.shared
    ) {
        self.keychain = keychain
        self.supabase = supabase
        self.accountDeleter = accountDeleter
        loadPersistedState()
    }

    // MARK: - Persistence

    private func loadPersistedState() {
        let d = UserDefaults.standard
        migrateLegacyAppLockKeyIfNeeded(defaults: d)
        isSignedIn  = d.bool(forKey: kIsSignedIn)
        displayName = d.string(forKey: kDisplayName) ?? ""
        firstName   = d.string(forKey: kFirstName) ?? ""
        lastName    = d.string(forKey: kLastName) ?? ""
        userEmail   = d.string(forKey: kEmail) ?? ""
        if let raw = d.string(forKey: kProvider), let p = AuthProvider(rawValue: raw) {
            provider = p
        }
        if isSignedIn && appLockEnabled {
            needsUnlock = true
        }
    }

    private func persist(name: String, email: String, providerVal: AuthProvider) {
        let d = UserDefaults.standard
        d.set(true,                 forKey: kIsSignedIn)
        d.set(name,                 forKey: kDisplayName)
        d.set(email,                forKey: kEmail)
        d.set(providerVal.rawValue, forKey: kProvider)
        displayName    = name
        userEmail      = email
        provider       = providerVal
        isSignedIn     = true
        // Note: App Lock is deliberately NOT triggered here — the user just
        // completed an interactive sign-in. The lock gates cold launches only
        // (see loadPersistedState).
    }

    // MARK: - Name

    /// Records the name from the name step (or restored from the server).
    func setName(_ name: PersonName) {
        let d = UserDefaults.standard
        d.set(name.first,    forKey: kFirstName)
        d.set(name.last,     forKey: kLastName)
        d.set(name.fullName, forKey: kDisplayName)
        firstName   = name.first
        lastName    = name.last
        displayName = name.fullName
    }

    // MARK: - Guest mode

    /// Use the app without an account. Everything stays on-device; the
    /// anonymous UUID is the only identity. Fully upgradeable later via the
    /// regular sign-in paths (which simply overwrite name/email/provider).
    func continueAsGuest() {
        persist(name: displayName.isEmpty ? "Guest" : displayName,
                email: "",
                providerVal: .guest)
    }

    // MARK: - App Lock (biometric gate on launch — not a second auth factor)

    var appLockEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: kAppLockEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: kAppLockEnabled) }
    }

    private func migrateLegacyAppLockKeyIfNeeded(defaults d: UserDefaults) {
        guard d.object(forKey: kAppLockEnabled) == nil,
              d.object(forKey: kTwoFAEnabled) != nil
        else { return }
        d.set(d.bool(forKey: kTwoFAEnabled), forKey: kAppLockEnabled)
        d.removeObject(forKey: kTwoFAEnabled)
    }

    func completeUnlock() {
        needsUnlock = false
    }

    // MARK: - Sign in with Apple

    /// Configures the ASAuthorization request: scopes plus a fresh nonce
    /// (SHA-256 on the request, raw kept for the Supabase exchange) so the
    /// identity token can't be replayed by a third party.
    func prepareAppleSignInRequest(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName, .email]
        let raw = Self.randomNonce()
        pendingAppleNonce = raw
        request.nonce = SHA256.hash(data: Data(raw.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    func handleAppleCredential(_ credential: ASAuthorizationAppleIDCredential) {
        var name = ""
        if let fn = credential.fullName?.givenName {
            name = fn
            if let ln = credential.fullName?.familyName { name += " \(ln)" }
        }
        if name.isEmpty { name = displayName.isEmpty ? "Apple User" : displayName }

        // Apple only returns `email` on the very first sign-in for a given app;
        // every sign-in after that returns nil, so falling back to `userEmail`
        // breaks after a reinstall (local state gone, nothing to fall back to).
        // credential.user is Apple's stable per-app identifier and is returned
        // on every sign-in, so we use it as a Keychain key to recover the email
        // Apple gave us the first time.
        let appleEmailAccount = "apple-email:\(credential.user)"
        let email: String
        if let freshEmail = credential.email, !freshEmail.isEmpty {
            email = freshEmail
            keychain.save(account: appleEmailAccount, value: freshEmail)
        } else if let recoveredEmail = keychain.loadCredential(account: appleEmailAccount) {
            email = recoveredEmail
        } else {
            email = userEmail
        }

        persist(name: name, email: email, providerVal: .apple)

        // Exchange the Apple identity token for a Supabase Auth session so
        // backend writes are authorized as this user (auth.uid() RLS). Runs
        // in the background because local sign-in has already been persisted
        // above and there's no synchronous caller left to report to — on
        // failure `backendSyncFailed` is how the UI finds out (see
        // BackendSyncBanner) instead of the exchange failing silently.
        let nonce = pendingAppleNonce
        pendingAppleNonce = nil
        guard SupabaseService.isConfigured,
              let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8) else { return }
        Task { [weak self] in
            await self?.exchangeAppleToken(identityToken: identityToken, nonce: nonce)
        }
    }

    /// Runs the Apple → Supabase exchange and records the outcome.
    /// `pendingAppleRetry` is kept on failure (not just logged) so
    /// `retryBackendConnection()` can resend the same token — it's still
    /// single-use/~10-minute-TTL, so a retry long after the original failure
    /// will just fail again, same as it would if the user signed in fresh.
    ///
    /// `internal` (not `private`), same reason as `AuthManager.init` — tests
    /// drive this directly since `ASAuthorizationAppleIDCredential` has no
    /// public initializer, so `handleAppleCredential` itself can't be called
    /// from a test.
    func exchangeAppleToken(identityToken: String, nonce: String?) async {
        do {
            let uid = try await supabase.signInWithApple(identityToken: identityToken, nonce: nonce)
            UserDefaults.standard.set(uid, forKey: kSupabaseUserID)
            objectWillChange.send() // backendID/isBackendAuthenticated changed
            let wasFailed = backendSyncFailed
            backendSyncFailed = false
            pendingAppleRetry = nil
            if wasFailed { justReconnected = true }
        } catch {
            Logger(subsystem: "com.jasonlu.breath", category: "supabaseAuth")
                .warning("Apple → Supabase token exchange failed: \(error)")
            backendSyncFailed = true
            pendingAppleRetry = (identityToken, nonce)
        }
    }

    /// Resends the most recent failed Apple exchange. No-op if there's
    /// nothing pending (e.g. the failure was Google's or email/password's,
    /// which never reach this state in the first place — see
    /// `backendSyncFailed`'s doc comment).
    func retryBackendConnection() async {
        guard let pending = pendingAppleRetry else { return }
        await exchangeAppleToken(identityToken: pending.identityToken, nonce: pending.nonce)
    }

    /// Random URL-safe nonce for Sign in with Apple. The slight modulo bias
    /// is irrelevant here — the nonce only needs to be unpredictable, not
    /// uniformly distributed.
    nonisolated static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-._")
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        guard status == errSecSuccess else {
            // SecRandom failing is effectively impossible; fall back to a
            // UUID rather than sending a predictable constant.
            return UUID().uuidString
        }
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    // MARK: - Sign in with Google

    /// Exchanges the Google id_token for a real Supabase Auth session before
    /// persisting local sign-in state, so a failed exchange (offline,
    /// provider misconfigured, revoked token) surfaces as an error instead
    /// of silently creating a cosmetic-only local account. Returns nil on
    /// success, error string on failure — same convention as signUp/signIn.
    func handleGoogleSignIn(idToken: String, nonce: String, name: String, email: String) async -> String? {
        guard SupabaseService.isConfigured else {
            return "Google sign-in isn't available right now. Please try again later."
        }
        do {
            let uid = try await supabase.signInWithGoogle(idToken: idToken, nonce: nonce)
            UserDefaults.standard.set(uid, forKey: kSupabaseUserID)
            objectWillChange.send() // backendID/isBackendAuthenticated changed
            persist(name: name, email: email, providerVal: .google)
            return nil
        } catch {
            return (error as? LocalizedError)?.errorDescription
                ?? "Couldn't sign in with Google. Please try again."
        }
    }

    // MARK: - Email / Password

    /// Lowercases and trims an email so it's stable as an identifier
    /// regardless of how the user capitalized it at sign-up vs. sign-in.
    private func normalizedEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Returns nil on success, error string on failure. Delegates to
    /// Supabase Auth entirely — no local password storage.
    func signUp(email: String, password: String) async -> String? {
        let email = normalizedEmail(email)
        guard email.contains("@") else { return "Enter a valid email address." }
        guard password.count >= 8 else { return "Password must be at least 8 characters." }
        guard SupabaseService.isConfigured else {
            return "Account creation isn't available right now. Please try again later."
        }
        do {
            let uid = try await supabase.signUpWithPassword(email: email, password: password)
            UserDefaults.standard.set(uid, forKey: kSupabaseUserID)
            objectWillChange.send()
            // Name is collected by the name step right after sign-up.
            persist(name: "", email: email, providerVal: .email)
            return nil
        } catch {
            return (error as? LocalizedError)?.errorDescription
                ?? "Couldn't create your account. Please try again."
        }
    }

    /// Returns nil on success, error string on failure. `name` comes back
    /// from Supabase's `raw_user_meta_data` (set at signup) since there is
    /// no local copy of it once email/password auth lives entirely there.
    func signIn(email: String, password: String) async -> String? {
        let email = normalizedEmail(email)
        guard SupabaseService.isConfigured else {
            return "Sign-in isn't available right now. Please try again later."
        }
        do {
            let (uid, name) = try await supabase.signInWithPassword(email: email, password: password)
            UserDefaults.standard.set(uid, forKey: kSupabaseUserID)
            objectWillChange.send()
            persist(name: name ?? "User", email: email, providerVal: .email)
            return nil
        } catch {
            return (error as? LocalizedError)?.errorDescription
                ?? "Incorrect email or password."
        }
    }

    // MARK: - Sign out

    func signOut() {
        endSupabaseSession()
        clearLocalSignIn()
    }

    private func clearLocalSignIn() {
        let d = UserDefaults.standard
        d.removeObject(forKey: kIsSignedIn)
        d.removeObject(forKey: kDisplayName)
        d.removeObject(forKey: kFirstName)
        d.removeObject(forKey: kLastName)
        d.removeObject(forKey: kEmail)
        d.removeObject(forKey: kProvider)
        // Local cache only — signing out never deletes the server row, so the
        // opt-in restores on next sign-in. Cleared so the next account on this
        // device doesn't inherit this one's leaderboard choice.
        LeaderboardPreference.clear()
        isSignedIn  = false
        needsUnlock = false
        displayName = ""
        firstName   = ""
        lastName    = ""
        userEmail   = ""
    }

    /// Drops the Supabase user id and (best-effort) revokes the session's
    /// refresh token server-side.
    private func endSupabaseSession() {
        UserDefaults.standard.removeObject(forKey: kSupabaseUserID)
        backendSyncFailed = false
        pendingAppleRetry = nil
        guard SupabaseService.isConfigured else { return }
        Task.detached {
            // Best-effort, and ordered *before* the revoke: the push_tokens delete
            // policy is `auth.uid()::text = user_id`, so the row can only be
            // removed while the session that owns it is still valid. Left
            // behind, a token nothing can ever address again keeps receiving
            // streak pushes for an account that signed out.
            try? await SupabaseService.shared.deletePushToken()
            await SupabaseService.shared.signOut()
        }
    }

    // MARK: - Delete account
    // App Store Guideline 5.1.1(v): in-app deletion must delete the account
    // itself, and Sign in with Apple accounts must also have their Apple
    // authorization revoked. The delete-account Edge Function does both
    // server-side. Decision 2026-10-01: nothing local is cleared unless the
    // server confirms; on any failure this throws and the user stays signed
    // in to retry. The caller wipes local data (LocalDataEraser) after this
    // returns.

    func deleteAccount(appleReauth: AppleReauthCredential?) async throws {
        if provider == .apple && appleReauth == nil {
            throw AccountDeletionError.appleReauthRequired
        }

        if SupabaseService.isConfigured {
            // An Apple user whose original token exchange failed has no
            // stored Supabase id but may still have a server account. Get a
            // session from the fresh re-auth token first, never a local-only
            // delete that would orphan it.
            if !isBackendAuthenticated, let reauth = appleReauth {
                do {
                    let uid = try await supabase.signInWithApple(
                        identityToken: reauth.identityToken, nonce: reauth.rawNonce)
                    UserDefaults.standard.set(uid, forKey: kSupabaseUserID)
                } catch {
                    throw AccountDeletionError.server
                }
            }
            // Not backend-authenticated here means the account never existed
            // server-side, so there's nothing remote to delete.
            if isBackendAuthenticated {
                try await accountDeleter.deleteAccount(
                    appleAuthorizationCode: appleReauth?.authorizationCode)
            }
        }

        // Server confirmed (or there was no server account). Clear auth state.
        if let appleUserID = appleReauth?.appleUserID {
            keychain.delete(account: "apple-email:\(appleUserID)")
        }
        let d = UserDefaults.standard
        d.removeObject(forKey: kTwoFAEnabled)
        d.removeObject(forKey: kAnonymousID)
        d.removeObject(forKey: kSupabaseUserID)
        backendSyncFailed = false
        pendingAppleRetry = nil
        clearLocalSignIn()
        objectWillChange.send() // backendID/isBackendAuthenticated changed
    }

    // MARK: - Biometrics

    func authenticateWithBiometrics() async -> Bool {
        let ctx = LAContext()
        var err: NSError?
        let policy: LAPolicy = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
            ? .deviceOwnerAuthenticationWithBiometrics
            : .deviceOwnerAuthentication
        guard ctx.canEvaluatePolicy(policy, error: &err) else { return false }
        do {
            return try await ctx.evaluatePolicy(policy, localizedReason: "Verify it's you to continue")
        } catch {
            return false
        }
    }

}
