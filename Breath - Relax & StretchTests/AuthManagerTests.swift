import Testing
import Foundation
@testable import BreathRelaxStretch

// AuthManager's real keychain (Security.framework SecItem calls) is
// unreliable/unavailable in the test runner's sandbox, so these construct
// AuthManager with a `FakeKeychainStore` instead of `.shared`. `isSignedIn`/
// `displayName`/etc. are still backed by `UserDefaults.standard` though, and
// Swift Testing runs every @Test in the same process — so each test resets
// those keys first to avoid leaking state from whichever test ran before it.
// .serialized: AuthManager persists to the process-global UserDefaults.standard,
// so running these tests concurrently (Swift Testing's default) races writes
// from one test against another's assertions.
@Suite(.serialized)
@MainActor
struct AuthManagerTests {

    private static let keysToReset = [
        "auth.isSignedIn", "auth.displayName", "auth.email",
        "auth.provider", "auth.appLockEnabled", "auth.twoFAEnabled", "auth.anonymousID",
        "auth.supabaseUserID", "auth.firstName", "auth.lastName"
    ]

    init() {
        let d = UserDefaults.standard
        for key in Self.keysToReset { d.removeObject(forKey: key) }
    }

    private func makeManager(
        supabase: SupabaseAuthenticating = FakeSupabaseAuthenticating(),
        deleter: SupabaseAccountDeleting = FakeAccountDeleter(),
        keychain: FakeKeychainStore = FakeKeychainStore()
    ) -> AuthManager {
        AuthManager(keychain: keychain, supabase: supabase, accountDeleter: deleter)
    }

    // MARK: - signUp

    @Test func signUpSucceedsAndPersistsIdentity() async {
        let fake = FakeSupabaseAuthenticating()
        fake.signUpWithPasswordResult = .success("new-user-1")
        let manager = makeManager(supabase: fake)

        let result = await manager.signUp(email: "ada@example.com", password: "password123")

        #expect(result == nil)
        #expect(manager.isSignedIn)
        #expect(manager.displayName == "")
        #expect(manager.userEmail == "ada@example.com")
        #expect(manager.provider == .email)
        #expect(manager.backendID == "new-user-1")
        #expect(manager.isBackendAuthenticated)
    }

    @Test func signUpRejectsInvalidEmail() async {
        let manager = makeManager()
        let result = await manager.signUp(email: "not-an-email", password: "password123")
        #expect(result == "Enter a valid email address.")
    }

    @Test func signUpRejectsShortPassword() async {
        let manager = makeManager()
        let result = await manager.signUp(email: "a@b.com", password: "short")
        #expect(result == "Password must be at least 8 characters.")
    }

    @Test func signUpSurfacesTheSupabaseErrorAndDoesNotSignIn() async {
        let fake = FakeSupabaseAuthenticating()
        fake.signUpWithPasswordResult = .failure(SupabaseAuthError(code: "user_already_exists", message: nil))
        let manager = makeManager(supabase: fake)

        let result = await manager.signUp(email: "ada@example.com", password: "password123")

        #expect(result == "An account with that email already exists.")
        #expect(!manager.isSignedIn)
        #expect(!manager.isBackendAuthenticated)
    }

    // MARK: - Name (first/last)

    @Test func setNameStoresPartsAndComposesDisplayName() {
        let manager = makeManager()
        manager.setName(PersonName(first: " Ada ", last: "Lovelace"))
        #expect(manager.firstName == "Ada")
        #expect(manager.lastName == "Lovelace")
        #expect(manager.displayName == "Ada Lovelace")
        #expect(manager.personName.isComplete)
    }

    @Test func setNamePersistsAcrossInstances() {
        makeManager().setName(PersonName(first: "Ada", last: "Lovelace"))
        let reloaded = makeManager()
        #expect(reloaded.firstName == "Ada")
        #expect(reloaded.lastName == "Lovelace")
        #expect(reloaded.displayName == "Ada Lovelace")
    }

    @Test func providerSuppliedNamesPrefillButNeverCountAsAStoredName() async {
        let fake = FakeSupabaseAuthenticating()
        fake.signInWithGoogleResult = .success("g1")
        let manager = makeManager(supabase: fake)
        _ = await manager.handleGoogleSignIn(idToken: "t", nonce: "n", name: "Ada Lovelace", email: "a@b.com")
        #expect(manager.providerPrefill == PersonName(first: "Ada", last: "Lovelace"))
        #expect(!manager.personName.isComplete)   // must still go through the name step
    }

    @Test func providerPrefillIgnoresPlaceholderNames() {
        let manager = makeManager()
        manager.continueAsGuest()                 // displayName becomes "Guest"
        #expect(manager.providerPrefill == .empty)
    }

    @Test func signOutClearsTheName() {
        let manager = makeManager()
        manager.setName(PersonName(first: "Ada", last: "Lovelace"))
        manager.signOut()
        #expect(manager.firstName.isEmpty)
        #expect(manager.lastName.isEmpty)
        #expect(manager.displayName.isEmpty)
    }

    @Test func greetingNameIsTheFirstNameAndEmptyForGuests() async {
        let manager = makeManager()
        manager.setName(PersonName(first: "Ada", last: "Lovelace"))
        #expect(manager.greetingName == "Ada")

        let guest = makeManager()
        guest.continueAsGuest()
        #expect(guest.greetingName == "")
    }

    @Test func greetingNameFallsBackToTheFirstWordOfADisplayNameAndSkipsPlaceholders() async {
        let fake = FakeSupabaseAuthenticating()
        fake.signInWithGoogleResult = .success("g1")
        let manager = makeManager(supabase: fake)
        _ = await manager.handleGoogleSignIn(idToken: "t", nonce: "n", name: "Ada Lovelace", email: "a@b.com")
        #expect(manager.greetingName == "Ada")

        let apple = makeManager()
        apple.continueAsGuest()
        #expect(apple.greetingName == "")
    }

    // MARK: - signIn

    @Test func signInSucceedsAndRestoresNameFromMetadata() async {
        let fake = FakeSupabaseAuthenticating()
        fake.signInWithPasswordResult = .success((userID: "existing-user-1", name: "Ada Lovelace"))
        let manager = makeManager(supabase: fake)

        let result = await manager.signIn(email: "ada@example.com", password: "password123")

        #expect(result == nil)
        #expect(manager.isSignedIn)
        #expect(manager.displayName == "Ada Lovelace")
        #expect(manager.backendID == "existing-user-1")
        #expect(manager.isBackendAuthenticated)
    }

    @Test func signInFallsBackToAGenericNameWhenMetadataHasNone() async {
        let fake = FakeSupabaseAuthenticating()
        fake.signInWithPasswordResult = .success((userID: "existing-user-1", name: nil))
        let manager = makeManager(supabase: fake)

        _ = await manager.signIn(email: "ada@example.com", password: "password123")

        #expect(manager.displayName == "User")
    }

    @Test func signInSurfacesTheSupabaseErrorAndDoesNotSignIn() async {
        let fake = FakeSupabaseAuthenticating()
        fake.signInWithPasswordResult = .failure(SupabaseAuthError(code: "invalid_credentials", message: nil))
        let manager = makeManager(supabase: fake)

        let result = await manager.signIn(email: "ada@example.com", password: "wrongpassword")

        #expect(result == "Incorrect email or password.")
        #expect(!manager.isSignedIn)
        #expect(!manager.isBackendAuthenticated)
    }

    // MARK: - backendID (Supabase auth.uid() vs anonymous fallback)

    @Test func backendIDFallsBackToAnonymousID() {
        let manager = makeManager()
        #expect(manager.backendID == manager.anonymousID)
        #expect(!manager.isBackendAuthenticated)
    }

    @Test func backendIDPrefersStoredSupabaseUserID() {
        let manager = makeManager()
        UserDefaults.standard.set("supabase-uid-123", forKey: "auth.supabaseUserID")
        #expect(manager.backendID == "supabase-uid-123")
        #expect(manager.isBackendAuthenticated)
    }

    @Test func signOutDropsTheSupabaseIdentity() async {
        let fake = FakeSupabaseAuthenticating()
        fake.signUpWithPasswordResult = .success("supabase-uid-123")
        let manager = makeManager(supabase: fake)
        _ = await manager.signUp(email: "ada@example.com", password: "password123")

        manager.signOut()
        #expect(!manager.isBackendAuthenticated)
        #expect(manager.backendID == manager.anonymousID)
    }

    // MARK: - Delete account

    private func appleReauth() -> AppleReauthCredential {
        AppleReauthCredential(appleUserID: "apple-user-1", authorizationCode: "code-1",
                              identityToken: "id-token", rawNonce: "nonce")
    }

    /// Simulates an Apple user restored from UserDefaults: handleAppleCredential
    /// needs a real ASAuthorizationAppleIDCredential, which tests can't build.
    private func persistAppleSignIn(supabaseUserID: String?) {
        let d = UserDefaults.standard
        d.set(true, forKey: "auth.isSignedIn")
        d.set("Ada", forKey: "auth.displayName")
        d.set("apple", forKey: "auth.provider")
        if let supabaseUserID { d.set(supabaseUserID, forKey: "auth.supabaseUserID") }
    }

    @Test func deleteAccountCallsTheServerThenClearsLocalSignIn() async throws {
        let auth = FakeSupabaseAuthenticating()
        auth.signUpWithPasswordResult = .success("supabase-uid-123")
        let deleter = FakeAccountDeleter()
        let manager = makeManager(supabase: auth, deleter: deleter)
        _ = await manager.signUp(email: "ada@example.com", password: "password123")

        try await manager.deleteAccount(appleReauth: nil)

        #expect(deleter.calls == [nil])
        #expect(!manager.isSignedIn)
        #expect(!manager.isBackendAuthenticated)
    }

    @Test func deleteAccountFailureKeepsTheUserSignedIn() async {
        let auth = FakeSupabaseAuthenticating()
        auth.signUpWithPasswordResult = .success("supabase-uid-123")
        let deleter = FakeAccountDeleter()
        deleter.result = .failure(AccountDeletionError.network)
        let manager = makeManager(supabase: auth, deleter: deleter)
        _ = await manager.signUp(email: "ada@example.com", password: "password123")

        await #expect(throws: AccountDeletionError.network) {
            try await manager.deleteAccount(appleReauth: nil)
        }
        #expect(manager.isSignedIn)
        #expect(manager.isBackendAuthenticated)
        #expect(manager.userEmail == "ada@example.com")
    }

    @Test func appleUserWithoutReauthIsRejectedBeforeAnyNetworkCall() async {
        persistAppleSignIn(supabaseUserID: "apple-uid")
        let deleter = FakeAccountDeleter()
        let manager = makeManager(deleter: deleter)

        await #expect(throws: AccountDeletionError.appleReauthRequired) {
            try await manager.deleteAccount(appleReauth: nil)
        }
        #expect(deleter.calls.isEmpty)
        #expect(manager.isSignedIn)
    }

    @Test func appleUserPassesTheCodeAndForgetsTheStoredAppleEmail() async throws {
        persistAppleSignIn(supabaseUserID: "apple-uid")
        let keychain = FakeKeychainStore()
        keychain.save(account: "apple-email:apple-user-1", value: "ada@privaterelay.appleid.com")
        let deleter = FakeAccountDeleter()
        let manager = makeManager(deleter: deleter, keychain: keychain)

        try await manager.deleteAccount(appleReauth: appleReauth())

        #expect(deleter.calls == ["code-1"])
        #expect(keychain.loadCredential(account: "apple-email:apple-user-1") == nil)
        #expect(!manager.isSignedIn)
    }

    @Test func appleUserWithoutBackendSessionExchangesFirst() async throws {
        persistAppleSignIn(supabaseUserID: nil)
        let auth = FakeSupabaseAuthenticating()
        auth.signInWithAppleResult = .success("apple-uid-late")
        let deleter = FakeAccountDeleter()
        let manager = makeManager(supabase: auth, deleter: deleter)

        try await manager.deleteAccount(appleReauth: appleReauth())

        #expect(deleter.calls == ["code-1"])
        #expect(!manager.isSignedIn)
    }

    @Test func appleUserWhoseLateExchangeFailsIsNotDeleted() async {
        persistAppleSignIn(supabaseUserID: nil)
        let deleter = FakeAccountDeleter()
        let manager = makeManager(deleter: deleter) // signInWithApple fails by default

        await #expect(throws: AccountDeletionError.server) {
            try await manager.deleteAccount(appleReauth: appleReauth())
        }
        #expect(deleter.calls.isEmpty)
        #expect(manager.isSignedIn)
    }

    @Test func appleLateExchangeWhileOfflineReportsNetworkNotServer() async {
        persistAppleSignIn(supabaseUserID: nil)
        let auth = FakeSupabaseAuthenticating()
        auth.signInWithAppleResult = .failure(URLError(.notConnectedToInternet))
        let deleter = FakeAccountDeleter()
        let manager = makeManager(supabase: auth, deleter: deleter)

        await #expect(throws: AccountDeletionError.network) {
            try await manager.deleteAccount(appleReauth: appleReauth())
        }
        #expect(deleter.calls.isEmpty)
        #expect(manager.isSignedIn)
    }

    @Test func signOutResetsTheProviderToTheDefault() {
        persistAppleSignIn(supabaseUserID: nil)
        let manager = makeManager()
        #expect(manager.provider == .apple)

        manager.signOut()

        #expect(manager.provider == .email)
    }

    @Test func localOnlyAccountIsClearedWithoutAServerCall() async throws {
        let d = UserDefaults.standard
        d.set(true, forKey: "auth.isSignedIn")
        d.set("email", forKey: "auth.provider")
        let deleter = FakeAccountDeleter()
        let manager = makeManager(deleter: deleter)

        try await manager.deleteAccount(appleReauth: nil)

        #expect(deleter.calls.isEmpty)
        #expect(!manager.isSignedIn)
    }

    // MARK: - Google sign-in (real Supabase account)

    @Test func handleGoogleSignInCreatesABackendSessionOnSuccess() async {
        let fake = FakeSupabaseAuthenticating()
        fake.signInWithGoogleResult = .success("google-uid-1")
        let manager = makeManager(supabase: fake)

        let result = await manager.handleGoogleSignIn(
            idToken: "fake-id-token", nonce: "fake-nonce",
            name: "Ada", email: "ada@example.com"
        )

        #expect(result == nil)
        #expect(manager.isSignedIn)
        #expect(manager.provider == .google)
        #expect(manager.displayName == "Ada")
        #expect(manager.backendID == "google-uid-1")
        #expect(manager.isBackendAuthenticated)
    }

    @Test func handleGoogleSignInSurfacesTheSupabaseErrorAndDoesNotSignIn() async {
        let fake = FakeSupabaseAuthenticating()
        fake.signInWithGoogleResult = .failure(SupabaseAuthError(code: "invalid_grant", message: nil))
        let manager = makeManager(supabase: fake)

        let result = await manager.handleGoogleSignIn(
            idToken: "fake-id-token", nonce: "fake-nonce",
            name: "Ada", email: "ada@example.com"
        )

        #expect(result != nil)
        #expect(!manager.isSignedIn)
        #expect(!manager.isBackendAuthenticated)
    }

    // MARK: - Apple backend sync (exchange failure/retry)

    @Test func appleExchangeFailureSetsBackendSyncFailedWithoutAffectingLocalSignIn() async {
        let fake = FakeSupabaseAuthenticating()
        fake.signInWithAppleResult = .failure(SupabaseAuthError(code: "invalid_grant", message: nil))
        let manager = makeManager(supabase: fake)

        await manager.exchangeAppleToken(identityToken: "fake-token", nonce: "fake-nonce")

        #expect(manager.backendSyncFailed)
        #expect(!manager.justReconnected)
        #expect(!manager.isBackendAuthenticated)
    }

    @Test func appleExchangeSuccessNeverSetsJustReconnectedOnAFirstTryPass() async {
        let fake = FakeSupabaseAuthenticating()
        fake.signInWithAppleResult = .success("apple-uid-1")
        let manager = makeManager(supabase: fake)

        await manager.exchangeAppleToken(identityToken: "fake-token", nonce: "fake-nonce")

        #expect(!manager.backendSyncFailed)
        #expect(!manager.justReconnected)   // silent on a normal first-try success
        #expect(manager.isBackendAuthenticated)
        #expect(manager.backendID == "apple-uid-1")
    }

    @Test func retryAfterFailureSucceedsAndPulsesJustReconnected() async {
        let fake = FakeSupabaseAuthenticating()
        fake.signInWithAppleResult = .failure(SupabaseAuthError(code: "invalid_grant", message: nil))
        let manager = makeManager(supabase: fake)
        await manager.exchangeAppleToken(identityToken: "fake-token", nonce: "fake-nonce")
        #expect(manager.backendSyncFailed)

        fake.signInWithAppleResult = .success("apple-uid-1")
        await manager.retryBackendConnection()

        #expect(!manager.backendSyncFailed)
        #expect(manager.justReconnected)
        #expect(manager.isBackendAuthenticated)
        #expect(manager.backendID == "apple-uid-1")
    }

    @Test func retryWithNothingPendingIsANoOp() async {
        let fake = FakeSupabaseAuthenticating()
        let manager = makeManager(supabase: fake)

        await manager.retryBackendConnection()

        #expect(!manager.backendSyncFailed)
        #expect(!manager.isBackendAuthenticated)
    }

    @Test func retryThatFailsAgainKeepsBackendSyncFailedAndDoesNotPulseJustReconnected() async {
        let fake = FakeSupabaseAuthenticating()
        fake.signInWithAppleResult = .failure(SupabaseAuthError(code: "invalid_grant", message: nil))
        let manager = makeManager(supabase: fake)
        await manager.exchangeAppleToken(identityToken: "fake-token", nonce: "fake-nonce")

        await manager.retryBackendConnection()

        #expect(manager.backendSyncFailed)
        #expect(!manager.justReconnected)
        #expect(!manager.isBackendAuthenticated)
    }

    @Test func signOutClearsAPendingBackendSyncFailure() async {
        let fake = FakeSupabaseAuthenticating()
        fake.signInWithAppleResult = .failure(SupabaseAuthError(code: "invalid_grant", message: nil))
        let manager = makeManager(supabase: fake)
        await manager.exchangeAppleToken(identityToken: "fake-token", nonce: "fake-nonce")
        #expect(manager.backendSyncFailed)

        manager.signOut()

        #expect(!manager.backendSyncFailed)
        // The stale token must not still be retryable after sign-out.
        fake.signInWithAppleResult = .success("should-not-be-used")
        await manager.retryBackendConnection()
        #expect(!manager.isBackendAuthenticated)
    }

    @Test func signOutDoesNotResetDeviceLevelOnboarding() {
        let key = "hasCompletedOnboarding"
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        UserDefaults.standard.set(true, forKey: key)
        let manager = makeManager()
        manager.continueAsGuest()
        manager.signOut()
        #expect(UserDefaults.standard.bool(forKey: key))
    }
}

// MARK: - Test doubles

private final class FakeKeychainStore: KeychainStore {
    var storage: [String: String] = [:]
    func save(account: String, value: String) { storage[account] = value }
    func delete(account: String) { storage.removeValue(forKey: account) }
    func loadCredential(account: String) -> String? { storage[account] }
}

private final class FakeSupabaseAuthenticating: SupabaseAuthenticating, @unchecked Sendable {
    var signInWithAppleResult: Result<String, Error> = .failure(SupabaseAuthError(code: nil, message: nil))
    var signInWithGoogleResult: Result<String, Error> = .failure(SupabaseAuthError(code: nil, message: nil))
    var signUpWithPasswordResult: Result<String, Error> = .failure(SupabaseAuthError(code: nil, message: nil))
    var signInWithPasswordResult: Result<(userID: String, name: String?), Error> =
        .failure(SupabaseAuthError(code: nil, message: nil))

    func signInWithApple(identityToken: String, nonce: String?) async throws -> String {
        try signInWithAppleResult.get()
    }
    func signInWithGoogle(idToken: String, nonce: String?) async throws -> String {
        try signInWithGoogleResult.get()
    }
    func signUpWithPassword(email: String, password: String) async throws -> String {
        try signUpWithPasswordResult.get()
    }
    func signInWithPassword(email: String, password: String) async throws -> (userID: String, name: String?) {
        try signInWithPasswordResult.get()
    }
}

private final class FakeAccountDeleter: SupabaseAccountDeleting, @unchecked Sendable {
    var result: Result<Void, Error> = .success(())
    private(set) var calls: [String?] = []

    func deleteAccount(appleAuthorizationCode: String?) async throws {
        calls.append(appleAuthorizationCode)
        try result.get()
    }
}
