import Testing
import Foundation
@testable import BreathRelaxStretch

// Regression coverage for the "looks configured, isn't" bug class: the
// dashboard URL (supabase.com/dashboard/project/...) is a real, non-placeholder
// URL, so a check that only looked for the literal "YOUR_PROJECT" placeholder
// string incorrectly reported isConfigured == true and let the app attempt
// real network calls against a host that returns HTML/404, not JSON.
struct SupabaseServiceTests {

    @Test func rejectsTheDashboardURLSpecifically() {
        #expect(!SupabaseService.isValidAPIHost("https://supabase.com/dashboard/project/wmsutfittuxrvcwuywrk"))
    }

    @Test func acceptsARealProjectAPIHost() {
        #expect(SupabaseService.isValidAPIHost("https://wmsutfittuxrvcwuywrk.supabase.co"))
    }

    @Test func rejectsMalformedOrHostlessURLs() {
        #expect(!SupabaseService.isValidAPIHost("not a url"))
        #expect(!SupabaseService.isValidAPIHost(""))
    }

    @Test func rejectsLookalikeHostsThatArentActuallySupabaseCo() {
        // A host merely containing "supabase.co" isn't enough — must be a real subdomain of it.
        #expect(!SupabaseService.isValidAPIHost("https://supabase.co.evil.com"))
        #expect(!SupabaseService.isValidAPIHost("https://notsupabase.co"))
    }

    @Test func currentlyConfiguredCredentialsPassTheRealCheck() {
        // Guards against this regressing back to a non-API host in the future.
        #expect(SupabaseService.isConfigured)
    }

    @Test func signInWithGoogleReturnsTheUserIDFromASuccessfulGrant() async throws {
        let session = FakeHTTPSession(responses: [
            .success(status: 200, body: Self.tokenGrantJSON(userID: "google-uid-1"))
        ])
        let service = SupabaseService(
            keychain: FakeSupabaseKeychainStore(),
            urlSession: session
        )
        let uid = try await service.signInWithGoogle(idToken: "fake-id-token", nonce: "fake-nonce")
        #expect(uid == "google-uid-1")
    }

    @Test func signInWithGoogleThrowsOnAnHTTPErrorStatus() async throws {
        let session = FakeHTTPSession(responses: [
            .success(status: 400, body: Data("{}".utf8))
        ])
        let service = SupabaseService(
            keychain: FakeSupabaseKeychainStore(),
            urlSession: session
        )
        await #expect(throws: (any Error).self) {
            _ = try await service.signInWithGoogle(idToken: "fake-id-token", nonce: "fake-nonce")
        }
    }

    @Test func signUpWithPasswordReturnsTheUserIDFromASuccessfulGrant() async throws {
        let session = FakeHTTPSession(responses: [
            .success(status: 200, body: Self.tokenGrantJSON(userID: "new-user-1"))
        ])
        let service = SupabaseService(keychain: FakeSupabaseKeychainStore(), urlSession: session)
        let uid = try await service.signUpWithPassword(email: "ada@example.com", password: "password123")
        #expect(uid == "new-user-1")
    }

    @Test func signUpWithPasswordMapsUserAlreadyExistsToAReadableMessage() async throws {
        let session = FakeHTTPSession(responses: [
            .success(status: 422, body: Data("""
            {"code":422,"error_code":"user_already_exists","msg":"User already registered"}
            """.utf8))
        ])
        let service = SupabaseService(keychain: FakeSupabaseKeychainStore(), urlSession: session)
        do {
            _ = try await service.signUpWithPassword(email: "ada@example.com", password: "password123")
            Issue.record("Expected signUpWithPassword to throw")
        } catch {
            #expect((error as? LocalizedError)?.errorDescription == "An account with that email already exists.")
        }
    }

    @Test func signInWithPasswordReturnsUserIDAndNameFromMetadata() async throws {
        let session = FakeHTTPSession(responses: [
            .success(status: 200, body: Data("""
            {
              "access_token": "fake-access-token",
              "refresh_token": "fake-refresh-token",
              "expires_in": 3600,
              "user": { "id": "existing-user-1", "user_metadata": { "name": "Ada Lovelace" } }
            }
            """.utf8))
        ])
        let service = SupabaseService(keychain: FakeSupabaseKeychainStore(), urlSession: session)
        let result = try await service.signInWithPassword(email: "ada@example.com", password: "password123")
        #expect(result.userID == "existing-user-1")
        #expect(result.name == "Ada Lovelace")
    }

    @Test func signInWithPasswordMapsInvalidCredentialsToAReadableMessage() async throws {
        let session = FakeHTTPSession(responses: [
            .success(status: 400, body: Data("""
            {"error_code":"invalid_credentials","msg":"Invalid login credentials"}
            """.utf8))
        ])
        let service = SupabaseService(keychain: FakeSupabaseKeychainStore(), urlSession: session)
        do {
            _ = try await service.signInWithPassword(email: "ada@example.com", password: "wrong")
            Issue.record("Expected signInWithPassword to throw")
        } catch {
            #expect((error as? LocalizedError)?.errorDescription == "Incorrect email or password.")
        }
    }

    // MARK: - profiles name fields

    @Test @MainActor func fetchProfileDecodesTheNameColumns() async throws {
        let session = FakeHTTPSession(responses: [
            .success(status: 200, body: Data("""
            [{"id":"u1","display_name":"Ada Lovelace","total_points":10,"streak":2,"total_minutes":30,"first_name":"Ada","last_name":"Lovelace"}]
            """.utf8))
        ])
        let service = SupabaseService(keychain: FakeSupabaseKeychainStore(), urlSession: session)
        let row = try await service.fetchProfile(id: "u1")
        #expect(row?.firstName == "Ada")
        #expect(row?.lastName == "Lovelace")
        #expect(row?.displayName == "Ada Lovelace")
    }

    @Test @MainActor func fetchProfileToleratesRowsWithoutNameColumns() async throws {
        let session = FakeHTTPSession(responses: [
            .success(status: 200, body: Data("""
            [{"id":"u1","display_name":"Old Name","total_points":0,"streak":0,"total_minutes":0}]
            """.utf8))
        ])
        let service = SupabaseService(keychain: FakeSupabaseKeychainStore(), urlSession: session)
        let row = try await service.fetchProfile(id: "u1")
        #expect(row?.firstName == nil)
        #expect(row?.lastName == nil)
    }

    @Test @MainActor func fetchProfileReturnsNilWhenThereIsNoRow() async throws {
        let session = FakeHTTPSession(responses: [.success(status: 200, body: Data("[]".utf8))])
        let service = SupabaseService(keychain: FakeSupabaseKeychainStore(), urlSession: session)
        #expect(try await service.fetchProfile(id: "u1") == nil)
    }

    @Test @MainActor func fetchProfileFiltersByIdWithStrictEncoding() async throws {
        let session = FakeHTTPSession(responses: [.success(status: 200, body: Data("[]".utf8))])
        let service = SupabaseService(keychain: FakeSupabaseKeychainStore(), urlSession: session)
        _ = try await service.fetchProfile(id: "a&b=c")
        let url = try #require(session.requests.first?.url?.absoluteString)
        #expect(url.contains("/rest/v1/profiles?id=eq.a%26b%3Dc"))
        #expect(url.contains("limit=1"))
    }

    // MARK: - Sync engine (routines + sessions)

    @Test @MainActor func uploadRoutinePostsToRoutinesAsAnUpsert() async throws {
        let session = FakeHTTPSession(responses: [.success(status: 201, body: Data())])
        let service = SupabaseService(keychain: FakeSupabaseKeychainStore(), urlSession: session)
        let routine = RemoteRoutine(
            id: "r1", name: "Morning", exerciseIDs: ["e1"], authorID: "u1",
            borrowedFromID: nil, exerciseDurationOverrides: ["e1": 45],
            isPinnedToToday: true, pinnedOrder: 0,
            updatedAt: .now, deletedAt: nil
        )
        try await service.uploadRoutine(routine)

        let request = try #require(session.requests.first)
        #expect(request.url?.absoluteString.contains("/rest/v1/routines") == true)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Prefer") == "resolution=merge-duplicates")
    }

    @Test @MainActor func fetchRoutinesDecodesTheRowsIncludingSoftDeletedOnes() async throws {
        let session = FakeHTTPSession(responses: [
            .success(status: 200, body: Data("""
            [
              {"id":"r1","name":"Morning","exercise_ids":["e1"],"author_id":"u1","borrowed_from_id":null,
               "exercise_duration_overrides":{},"is_pinned_to_today":false,"pinned_order":0,
               "updated_at":"2026-09-23T00:00:00Z","deleted_at":null},
              {"id":"r2","name":"Deleted One","exercise_ids":[],"author_id":"u1","borrowed_from_id":null,
               "exercise_duration_overrides":{},"is_pinned_to_today":false,"pinned_order":0,
               "updated_at":"2026-09-23T01:00:00Z","deleted_at":"2026-09-23T01:00:00Z"}
            ]
            """.utf8))
        ])
        let service = SupabaseService(keychain: FakeSupabaseKeychainStore(), urlSession: session)
        let routines = try await service.fetchRoutines(ownerID: "u1")

        #expect(routines.count == 2)
        #expect(routines.first(where: { $0.id == "r2" })?.deletedAt != nil)
    }

    @Test @MainActor func fetchRoutinesFiltersByAuthorID() async throws {
        let session = FakeHTTPSession(responses: [.success(status: 200, body: Data("[]".utf8))])
        let service = SupabaseService(keychain: FakeSupabaseKeychainStore(), urlSession: session)
        _ = try await service.fetchRoutines(ownerID: "u1")
        let url = try #require(session.requests.first?.url?.absoluteString)
        #expect(url.contains("/rest/v1/routines?author_id=eq.u1"))
    }

    @Test @MainActor func uploadSessionPostsToSessionsAsAnUpsert() async throws {
        let session = FakeHTTPSession(responses: [.success(status: 201, body: Data())])
        let service = SupabaseService(keychain: FakeSupabaseKeychainStore(), urlSession: session)
        let remoteSession = RemoteSession(
            id: "s1", userID: "u1", routineID: "r1",
            startedAt: .now, completedAt: .now, completionPercent: 100, pointsEarned: 10
        )
        try await service.uploadSession(remoteSession)

        let request = try #require(session.requests.first)
        #expect(request.url?.absoluteString.contains("/rest/v1/sessions") == true)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Prefer") == "resolution=merge-duplicates")
    }

    @Test @MainActor func fetchSessionsFiltersByUserID() async throws {
        let session = FakeHTTPSession(responses: [.success(status: 200, body: Data("[]".utf8))])
        let service = SupabaseService(keychain: FakeSupabaseKeychainStore(), urlSession: session)
        _ = try await service.fetchSessions(userID: "u1")
        let url = try #require(session.requests.first?.url?.absoluteString)
        #expect(url.contains("/rest/v1/sessions?user_id=eq.u1"))
    }

    @Test @MainActor func fetchProfileThrowsOnAnHTTPErrorStatus() async throws {
        let session = FakeHTTPSession(responses: [.success(status: 500, body: Data("{}".utf8))])
        let service = SupabaseService(keychain: FakeSupabaseKeychainStore(), urlSession: session)
        await #expect(throws: (any Error).self) {
            _ = try await service.fetchProfile(id: "u1")
        }
    }

    @Test @MainActor func upsertProfileNameSendsOnlyIdentityColumnsAsAMergeUpsert() async throws {
        let session = FakeHTTPSession(responses: [.success(status: 201, body: Data())])
        let service = SupabaseService(keychain: FakeSupabaseKeychainStore(), urlSession: session)
        try await service.upsertProfileName(id: "u1", name: PersonName(first: "Ada", last: "Lovelace"))

        let request = try #require(session.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/rest/v1/profiles")
        #expect(request.value(forHTTPHeaderField: "Prefer") == "resolution=merge-duplicates")
        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["id"] as? String == "u1")
        #expect(json["display_name"] as? String == "Ada Lovelace")
        #expect(json["first_name"] as? String == "Ada")
        #expect(json["last_name"] as? String == "Lovelace")
        #expect(json["total_points"] == nil)   // merge-duplicates must not reset stats
    }

    @Test @MainActor func remoteProfileOmitsNameKeysWhenTheyAreNil() throws {
        // SessionRecorder uploads RemoteProfile on every session; if nil names
        // were encoded as null they would wipe the names the name step saved.
        let profile = RemoteProfile(id: "u1", displayName: "Ada Lovelace", totalPoints: 1,
                                    streak: 1, totalMinutes: 1, lastSessionAt: nil)
        let data = try SupabaseService.makeEncoder().encode(profile)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["first_name"] == nil)
        #expect(json["last_name"] == nil)
    }

    private static func tokenGrantJSON(userID: String) -> Data {
        Data("""
        {
          "access_token": "fake-access-token",
          "refresh_token": "fake-refresh-token",
          "expires_in": 3600,
          "user": { "id": "\(userID)" }
        }
        """.utf8)
    }
}

// MARK: - Test doubles

private final class FakeSupabaseKeychainStore: KeychainStore {
    var storage: [String: String] = [:]
    func save(account: String, value: String) { storage[account] = value }
    func delete(account: String) { storage.removeValue(forKey: account) }
    func loadCredential(account: String) -> String? { storage[account] }
}

/// Replays canned `(status, body)` pairs in call order, one per `data(for:)`
/// invocation — enough for these single-request auth flows without needing a
/// real request-matching mock.
private final class FakeHTTPSession: SupabaseHTTPSession, @unchecked Sendable {
    enum Canned {
        case success(status: Int, body: Data)
        case failure(URLError)
    }
    private var responses: [Canned]
    private var recorded: [URLRequest] = []
    private let lock = NSLock()

    var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    init(responses: [Canned]) { self.responses = responses }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lock.lock()
        recorded.append(request)
        guard !responses.isEmpty else {
            lock.unlock()
            throw URLError(.unknown)
        }
        let next = responses.removeFirst()
        lock.unlock()
        switch next {
        case .success(let status, let body):
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status,
                httpVersion: nil, headerFields: nil
            )!
            return (body, response)
        case .failure(let error):
            throw error
        }
    }
}

// MARK: - Opt-in leaderboard

extension SupabaseServiceTests {

    /// A keychain holding a live session for `userID`, so calls that need
    /// `supabaseUserID` (leave) behave as they do when signed in.
    private func signedInKeychain(userID: String) throws -> FakeSupabaseKeychainStore {
        let keychain = FakeSupabaseKeychainStore()
        let stored = SupabaseSession(
            accessToken: "access", refreshToken: "refresh",
            userID: userID, expiresAt: Date().addingTimeInterval(3600))
        let json = try #require(String(data: try JSONEncoder().encode(stored), encoding: .utf8))
        keychain.save(account: "supabase.session", value: json)
        return keychain
    }

    @Test @MainActor func fetchLeaderboardCallsTheRPCAndDecodesHandleOnlyRows() async throws {
        let session = FakeHTTPSession(responses: [
            .success(status: 200, body: Data("""
            [{"handle":"Calm Otter 4821","total_points":90,"streak":4,"total_minutes":60,"is_me":true},
             {"handle":"Quiet Fox 1234","total_points":40,"streak":1,"total_minutes":20,"is_me":false}]
            """.utf8))
        ])
        let service = SupabaseService(keychain: FakeSupabaseKeychainStore(), urlSession: session)
        let rows = try await service.fetchLeaderboard(limit: 25)

        #expect(rows.map(\.handle) == ["Calm Otter 4821", "Quiet Fox 1234"])
        #expect(rows.map(\.isMe) == [true, false])
        #expect(rows.first?.totalPoints == 90)

        let request = try #require(session.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/rest/v1/rpc/get_leaderboard")
        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["row_limit"] as? Int == 25)
    }

    @Test @MainActor func fetchLeaderboardNeverReadsThePrivateProfilesTable() async throws {
        let session = FakeHTTPSession(responses: [.success(status: 200, body: Data("[]".utf8))])
        let service = SupabaseService(keychain: FakeSupabaseKeychainStore(), urlSession: session)
        _ = try await service.fetchLeaderboard()
        let url = try #require(session.requests.first?.url?.absoluteString)
        #expect(!url.contains("/profiles"))
    }

    @Test @MainActor func fetchLeaderboardThrowsOnAnHTTPErrorStatus() async throws {
        let session = FakeHTTPSession(responses: [.success(status: 403, body: Data("{}".utf8))])
        let service = SupabaseService(keychain: FakeSupabaseKeychainStore(), urlSession: session)
        await #expect(throws: (any Error).self) {
            _ = try await service.fetchLeaderboard()
        }
    }

    @Test @MainActor func fetchOwnLeaderboardRowReturnsNilWhenNotOptedIn() async throws {
        let session = FakeHTTPSession(responses: [.success(status: 200, body: Data("[]".utf8))])
        let service = SupabaseService(keychain: FakeSupabaseKeychainStore(), urlSession: session)
        #expect(try await service.fetchOwnLeaderboardRow() == nil)
        #expect(session.requests.first?.url?.path == "/rest/v1/leaderboard")
    }

    @Test @MainActor func fetchOwnLeaderboardRowDecodesTheOptedInRow() async throws {
        let session = FakeHTTPSession(responses: [
            .success(status: 200, body: Data("""
            [{"user_id":"u1","handle":"Calm Otter 4821","total_points":90,"streak":4,"total_minutes":60}]
            """.utf8))
        ])
        let service = SupabaseService(keychain: FakeSupabaseKeychainStore(), urlSession: session)
        let row = try await service.fetchOwnLeaderboardRow()
        #expect(row?.handle == "Calm Otter 4821")
        #expect(row?.userID == "u1")
    }

    @Test @MainActor func joinLeaderboardUpsertsTheCallersOwnRowAsAMergeUpsert() async throws {
        let session = FakeHTTPSession(responses: [.success(status: 201, body: Data())])
        let service = SupabaseService(keychain: FakeSupabaseKeychainStore(), urlSession: session)
        try await service.joinLeaderboard(RemoteLeaderboardRow(
            userID: "u1", handle: "Calm Otter 4821",
            totalPoints: 90, streak: 4, totalMinutes: 60))

        let request = try #require(session.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/rest/v1/leaderboard")
        #expect(request.value(forHTTPHeaderField: "Prefer") == "resolution=merge-duplicates")
        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["user_id"] as? String == "u1")
        #expect(json["handle"] as? String == "Calm Otter 4821")
        #expect(json["total_points"] as? Int == 90)
        // The whole point of the opt-in design: no real-name fields ever sent.
        #expect(json["display_name"] == nil)
        #expect(json["first_name"] == nil)
        #expect(json["last_name"] == nil)
    }

    @Test @MainActor func leaveLeaderboardDeletesOnlyTheSignedInUsersRow() async throws {
        let session = FakeHTTPSession(responses: [.success(status: 204, body: Data())])
        let service = SupabaseService(keychain: try signedInKeychain(userID: "u1"), urlSession: session)
        try await service.leaveLeaderboard()

        let request = try #require(session.requests.first)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.path == "/rest/v1/leaderboard")
        #expect(request.url?.absoluteString.contains("user_id=eq.u1") == true)
    }

    @Test @MainActor func leaveLeaderboardIsANoOpWithoutASession() async throws {
        let session = FakeHTTPSession(responses: [])
        let service = SupabaseService(keychain: FakeSupabaseKeychainStore(), urlSession: session)
        try await service.leaveLeaderboard()
        #expect(session.requests.isEmpty)   // never sends an unfiltered DELETE
    }
}

// MARK: - Account deletion

extension SupabaseServiceTests {

    @Test @MainActor func deleteAccountPostsTheCodeWithTheUserTokenAndClearsTheSession() async throws {
        let keychain = try signedInKeychain(userID: "u1")
        let session = FakeHTTPSession(responses: [
            .success(status: 200, body: Data(#"{"deleted":true}"#.utf8))
        ])
        let service = SupabaseService(keychain: keychain, urlSession: session)

        try await service.deleteAccount(appleAuthorizationCode: "code-1")

        let request = try #require(session.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/functions/v1/delete-account")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access")
        let requestBody = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
        #expect(json["apple_authorization_code"] as? String == "code-1")
        #expect(keychain.loadCredential(account: "supabase.session") == nil)
    }

    /// On weak Wi-Fi the default 60 s timeout leaves the user staring at a
    /// spinner; 30 s is ample for the server's few-second deletion, and a
    /// timed-out success is safe to retry (the function is idempotent).
    @Test @MainActor func deleteAccountGivesUpAfterThirtySeconds() async throws {
        let session = FakeHTTPSession(responses: [.success(status: 200, body: Data("{}".utf8))])
        let service = SupabaseService(keychain: try signedInKeychain(userID: "u1"), urlSession: session)

        try await service.deleteAccount(appleAuthorizationCode: nil)

        #expect(session.requests.first?.timeoutInterval == 30)
    }

    @Test @MainActor func deleteAccountOmitsTheCodeKeyForNonAppleAccounts() async throws {
        let session = FakeHTTPSession(responses: [.success(status: 200, body: Data("{}".utf8))])
        let service = SupabaseService(keychain: try signedInKeychain(userID: "u1"), urlSession: session)

        try await service.deleteAccount(appleAuthorizationCode: nil)

        let body = try #require(session.requests.first?.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["apple_authorization_code"] == nil)
    }

    @Test @MainActor func deleteAccountWithoutASessionThrowsNotSignedInWithoutCallingTheNetwork() async {
        let session = FakeHTTPSession(responses: [])
        let service = SupabaseService(keychain: FakeSupabaseKeychainStore(), urlSession: session)

        await #expect(throws: AccountDeletionError.notSignedIn) {
            try await service.deleteAccount(appleAuthorizationCode: nil)
        }
        #expect(session.requests.isEmpty)
    }

    @Test @MainActor func deleteAccountMapsAppleRevokeFailureAndKeepsTheSession() async throws {
        let keychain = try signedInKeychain(userID: "u1")
        let session = FakeHTTPSession(responses: [
            .success(status: 502, body: Data(#"{"error":"apple_revoke_failed"}"#.utf8))
        ])
        let service = SupabaseService(keychain: keychain, urlSession: session)

        await #expect(throws: AccountDeletionError.appleRevokeFailed) {
            try await service.deleteAccount(appleAuthorizationCode: "c")
        }
        #expect(keychain.loadCredential(account: "supabase.session") != nil)
    }

    @Test @MainActor func deleteAccountMapsServerCodesAndStatuses() async throws {
        let cases: [(Int, String, AccountDeletionError)] = [
            (400, #"{"error":"apple_reauth_required"}"#, .appleReauthRequired),
            (401, #"{"error":"unauthorized"}"#, .notSignedIn),
            (500, #"{"error":"delete_failed"}"#, .server),
            (503, "<html>gateway</html>", .server),
        ]
        for (status, body, expected) in cases {
            let session = FakeHTTPSession(responses: [.success(status: status, body: Data(body.utf8))])
            let service = SupabaseService(keychain: try signedInKeychain(userID: "u1"), urlSession: session)
            await #expect(throws: expected) {
                try await service.deleteAccount(appleAuthorizationCode: "c")
            }
        }
    }

    @Test @MainActor func deleteAccountMapsATransportErrorToNetwork() async throws {
        let session = FakeHTTPSession(responses: [.failure(URLError(.notConnectedToInternet))])
        let service = SupabaseService(keychain: try signedInKeychain(userID: "u1"), urlSession: session)

        await #expect(throws: AccountDeletionError.network) {
            try await service.deleteAccount(appleAuthorizationCode: nil)
        }
    }
}
