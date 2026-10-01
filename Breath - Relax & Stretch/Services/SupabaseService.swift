import Foundation

// MARK: - HTTP seam
// Lets tests inject a fake session instead of hitting the real network —
// mirrors the KeychainStore seam already used for session persistence.
protocol SupabaseHTTPSession: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: SupabaseHTTPSession {}

// MARK: - SupabaseService

actor SupabaseService {
    static let shared = SupabaseService()

    /// `internal` (not `private`) for the same reason as AuthManager.init —
    /// tests construct instances with a FakeKeychainStore; production code
    /// should still go through `.shared`.
    init(
        keychain: KeychainStore = SecItemKeychainStore(service: "com.breathapp.supabase"),
        urlSession: SupabaseHTTPSession = URLSession.shared
    ) {
        self.keychain = keychain
        self.urlSession = urlSession
    }

    // The API base URL (https://<project-ref>.supabase.co) — NOT the dashboard
    // page URL. Dashboard → Settings → API → Project URL.
    // Static lets on an actor are nonisolated — no @MainActor contamination.
    private static let supabaseURL     = "https://wmsutfittuxrvcwuywrk.supabase.co"
    // Decision (open question closed, do not reopen): committing this anon key is
    // intentional, not a leak — Supabase anon/publishable keys are designed to be
    // client-embedded, RLS policies are the actual security boundary, and every
    // Supabase quick-start ships this way. Move it to a config file only if that
    // ever changes.
    private static let supabaseAnonKey = "sb_publishable_fpbIp20MIAf3OV1Two6DhQ_MpZvy2Dc"

    /// True once real credentials are filled in above. While false, the app
    /// skips all remote calls and runs purely on the bundled seed catalog —
    /// so everything works offline / before the backend exists. Validates the
    /// URL is an actual *.supabase.co API host so a pasted dashboard link
    /// can't silently pass as "configured" and 404 every request.
    nonisolated static var isConfigured: Bool {
        !supabaseAnonKey.isEmpty && !supabaseAnonKey.contains("YOUR_ANON_KEY")
            && isValidAPIHost(supabaseURL)
    }

    /// Extracted as its own testable function so config-sanity tests don't
    /// depend on whatever supabaseURL happens to be set to — this is what
    /// would have caught it being the dashboard URL instead of the API host.
    nonisolated static func isValidAPIHost(_ urlString: String) -> Bool {
        URL(string: urlString)?.host?.hasSuffix(".supabase.co") == true
    }

    // MARK: - JSON coders (PostgREST wire format)
    //
    // Every PostgREST request/response in this file goes through these two,
    // so a `Date` field added to any DTO in future is handled correctly by
    // default. Swift's out-of-the-box strategy is `.deferredToDate` — a bare
    // epoch-seconds `Double` — which Postgres `timestamptz` columns reject on
    // write and which can't parse the ISO-8601 strings PostgREST sends back.
    //
    // Deliberately NOT used for the keychain session blob (storeSession /
    // loadSessionIfNeeded): that's a private local round-trip whose already
    // written-to-disk values are epoch doubles, and switching its strategy
    // would make every existing signed-in user's stored session undecodable.

    /// Encoder for anything sent to PostgREST. `.iso8601` emits
    /// `2026-09-04T15:33:20Z`, which Postgres accepts for `timestamptz`.
    nonisolated static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    /// Decoder for anything read back from PostgREST.
    ///
    /// Not plain `.iso8601`: Postgres renders `timestamptz` with microsecond
    /// precision (`2026-09-04T15:33:20.123456+00:00`), and
    /// `ISO8601DateFormatter` only parses fractional seconds when explicitly
    /// configured with `.withFractionalSeconds` — which then *stops* parsing
    /// whole-second timestamps (`2026-09-04T15:33:20+00:00`), which Postgres
    /// emits whenever the stored value happens to have no sub-second part.
    /// Both shapes are real server output, so both must decode.
    nonisolated static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: raw) { return date }
            let whole = ISO8601DateFormatter()
            whole.formatOptions = [.withInternetDateTime]
            if let date = whole.date(from: raw) { return date }
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Expected an ISO-8601 timestamp, got \"\(raw)\"."
            ))
        }
        return decoder
    }

    // MARK: - Session state
    // A SupabaseSession exists only for users who signed in with Apple (the
    // id_token exchange below). Guests / local email accounts have none —
    // their requests carry the anon key and can only reach public-read data
    // once the auth.uid() RLS policies in supabase_schema.sql are applied.

    private let keychain: KeychainStore
    private let urlSession: SupabaseHTTPSession
    private static let sessionAccount = "supabase.session"

    private var session: SupabaseSession?
    private var didLoadSession = false

    // Note: these two use plain JSONEncoder/JSONDecoder, *not* makeEncoder/
    // makeDecoder — see the comment on those. This blob never leaves the
    // device, and its already-persisted `expiresAt` values are epoch doubles.
    private func loadSessionIfNeeded() {
        guard !didLoadSession else { return }
        didLoadSession = true
        guard let json = keychain.loadCredential(account: Self.sessionAccount),
              let data = json.data(using: .utf8),
              let stored = try? JSONDecoder().decode(SupabaseSession.self, from: data) else { return }
        session = stored
    }

    private func storeSession(_ new: SupabaseSession?) {
        session = new
        didLoadSession = true
        if let new,
           let data = try? JSONEncoder().encode(new),
           let json = String(data: data, encoding: .utf8) {
            keychain.save(account: Self.sessionAccount, value: json)
        } else {
            keychain.delete(account: Self.sessionAccount)
        }
    }

    /// The Supabase user id (`auth.uid()`) of the current session, if any.
    var supabaseUserID: String? {
        loadSessionIfNeeded()
        return session?.userID
    }

    // MARK: - Exercises

    /// Fetches all exercises from the remote library.
    ///
    /// Expected Supabase table `exercises` (Dashboard → Table editor):
    ///   id                uuid          primary key  (default gen_random_uuid())
    ///   name              text          not null
    ///   type              text          not null     ('stretch' | 'breath' | 'both')
    ///   target_body_parts text[]        not null
    ///   duration_seconds  int4          not null
    ///   difficulty        int4          not null     (1–3)
    ///   instructions      text[]        not null
    ///   media_url         text          null
    ///   caution           text          null
    /// Enable RLS with a "read for all" select policy so the anon key can fetch.
    func fetchExercises() async throws -> [RemoteExercise] {
        let data = try await get(path: "/rest/v1/exercises?select=*&order=name")
        return try Self.makeDecoder().decode([RemoteExercise].self, from: data)
    }

    // MARK: - Community (private profile + opt-in leaderboard)

    /// Upserts the local profile to `profiles`, which is **private**: RLS lets
    /// only the owner read or write their own row, and `anon` has no access.
    /// It mirrors stats (and the real name) so the streak-warning server job
    /// can see them; nothing here is visible to other users. The leaderboard
    /// is a separate, opt-in table — see `joinLeaderboard`.
    ///
    /// `id` is the Supabase auth uid (`AuthManager.backendID`). Table shape
    /// and policies live in supabase_schema.sql.
    func uploadProfile(_ profile: RemoteProfile) async throws {
        // RemoteProfile.encode(to:) is @MainActor-isolated (Swift 6 inference);
        // hop to main actor for the encode, then continue in the actor.
        let data = try await MainActor.run { try Self.makeEncoder().encode(profile) }
        try await post(path: "/rest/v1/profiles", body: data, upsert: true)
    }

    /// Best-effort second upsert for the streak-saver columns. Kept apart from
    /// `uploadProfile` so a database without the columns yet cannot break the
    /// core upload. Callers use `try?`.
    func uploadProfileSavers(_ savers: RemoteProfileSavers) async throws {
        let data = try await MainActor.run { try Self.makeEncoder().encode(savers) }
        try await post(path: "/rest/v1/profiles", body: data, upsert: true)
    }

    // MARK: - Sync engine (routines + sessions)
    // See docs/superpowers/specs/2026-09-23-routine-session-sync-engine-design.md.
    // A "delete" in the outbox still calls uploadRoutine — deletes are soft
    // (deletedAt set on the local row), so from the wire's perspective a
    // delete and an edit are both just "upsert this row's current state."
    // There's no separate delete endpoint for routines/sessions.

    func uploadRoutine(_ routine: RemoteRoutine) async throws {
        let data = try await MainActor.run { try Self.makeEncoder().encode(routine) }
        try await post(path: "/rest/v1/routines", body: data, upsert: true)
    }

    /// Fetches every routine this account owns, including soft-deleted ones
    /// (deletedAt is how the sync engine's pull-merge propagates a delete to
    /// other devices — filtering them out here would hide that signal).
    func fetchRoutines(ownerID: String) async throws -> [RemoteRoutine] {
        let encoded = ownerID.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(.init(charactersIn: "-._~"))) ?? ""
        let data = try await get(path: "/rest/v1/routines?author_id=eq.\(encoded)&select=*")
        return try Self.makeDecoder().decode([RemoteRoutine].self, from: data)
    }

    func uploadSession(_ session: RemoteSession) async throws {
        let data = try await MainActor.run { try Self.makeEncoder().encode(session) }
        try await post(path: "/rest/v1/sessions", body: data, upsert: true)
    }

    func fetchSessions(userID: String) async throws -> [RemoteSession] {
        let encoded = userID.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(.init(charactersIn: "-._~"))) ?? ""
        let data = try await get(path: "/rest/v1/sessions?user_id=eq.\(encoded)&select=*")
        return try Self.makeDecoder().decode([RemoteSession].self, from: data)
    }

    // MARK: - Push tokens (streak-about-to-break notifications)

    /// Upserts this device's APNs token + IANA timezone. Requires a Supabase
    /// Auth session (`AuthManager.isBackendAuthenticated`) — RLS rejects the
    /// write otherwise, which is fine: this call is always best-effort
    /// (`try?`) at every call site, exactly like `uploadProfile`.
    ///
    /// Expected Supabase table `push_tokens` — see supabase_schema.sql.
    ///
    /// `user_id` is read from `AuthManager.backendID` — the same identity
    /// `uploadProfile`'s callers key `profiles.id` on, which is exactly what
    /// `push_tokens.user_id` joins against server-side. It's read inside the
    /// `MainActor.run` hop this method already needs for encoding (AuthManager
    /// is `@MainActor`), so no actor isolation is crossed unsafely.
    func registerPushToken(deviceToken: String, timezone: String) async throws {
        let data = try await MainActor.run {
            let payload = RemotePushToken(
                userID: AuthManager.shared.backendID,
                deviceToken: deviceToken,
                timezone: timezone
            )
            return try Self.makeEncoder().encode(payload)
        }
        try await post(path: "/rest/v1/push_tokens", body: data, upsert: true)
    }

    /// Deletes this user's push_tokens row (e.g. the notifications toggle
    /// was switched off). Deletes by the currently authenticated user's own
    /// row — the RLS delete policy only ever lets a session remove
    /// `auth.uid()`'s own row, so no id needs to be passed.
    func deletePushToken() async throws {
        guard let userID = supabaseUserID else { return }
        let encoded = userID.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(.init(charactersIn: "-._~"))) ?? ""
        try await delete(path: "/rest/v1/push_tokens?user_id=eq.\(encoded)")
    }

    /// Top of the opt-in leaderboard, via `get_leaderboard()`. The function
    /// returns handles and stats only — no user ids, no names — and requires a
    /// signed-in session (anon can't call it).
    func fetchLeaderboard(limit: Int = 50) async throws -> [RemoteLeaderboardEntry] {
        let body = try JSONSerialization.data(withJSONObject: ["row_limit": limit])
        let data = try await post(path: "/rest/v1/rpc/get_leaderboard", body: body, upsert: false) ?? Data()
        return try Self.makeDecoder().decode([RemoteLeaderboardEntry].self, from: data)
    }

    /// The caller's own leaderboard row, or nil if they haven't opted in. RLS
    /// scopes the table to the owner, so no filter is needed. This is how a
    /// fresh sign-in or a new device restores the opt-in choice.
    func fetchOwnLeaderboardRow() async throws -> RemoteLeaderboardRow? {
        let data = try await get(path: "/rest/v1/leaderboard?select=*&limit=1")
        return try Self.makeDecoder().decode([RemoteLeaderboardRow].self, from: data).first
    }

    /// Opts in (or refreshes stats when already opted in). Inserting this row
    /// *is* the opt-in.
    func joinLeaderboard(_ row: RemoteLeaderboardRow) async throws {
        let data = try await MainActor.run { try Self.makeEncoder().encode(row) }
        try await post(path: "/rest/v1/leaderboard", body: data, upsert: true)
    }

    /// Opts out by deleting the caller's own row.
    func leaveLeaderboard() async throws {
        guard let userID = supabaseUserID else { return }
        let encoded = userID.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(.init(charactersIn: "-._~"))) ?? ""
        try await delete(path: "/rest/v1/leaderboard?user_id=eq.\(encoded)")
    }

    // MARK: - Registration (name step)

    /// Fetches this account's own `profiles` row, or nil when none exists.
    /// `profiles` is private (owner-only RLS), so this needs a Supabase
    /// session; without one the request is rejected (see RegistrationCoordinator).
    func fetchProfile(id: String) async throws -> RemoteProfile? {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(.init(charactersIn: "-._~"))) ?? ""
        let data = try await get(path: "/rest/v1/profiles?id=eq.\(encoded)&select=*&limit=1")
        return try Self.makeDecoder().decode([RemoteProfile].self, from: data).first
    }

    /// Upserts just the identity columns for this account. This write is what
    /// makes the account "registered". Requires a Supabase session (RLS:
    /// id = auth.uid()); callers treat failure as best-effort.
    func upsertProfileName(id: String, name: PersonName) async throws {
        let data = try await MainActor.run {
            try Self.makeEncoder().encode(RemoteProfileName(
                id: id, displayName: name.fullName,
                firstName: name.first, lastName: name.last))
        }
        try await post(path: "/rest/v1/profiles", body: data, upsert: true)
    }

    // Note: sessions had a write path (uploadSession) that was removed as
    // dead code — nothing in the app called it. See supabase_schema.sql for
    // the matching RLS policy removal.

    // MARK: - Auth

    private struct TokenGrant: Decodable {
        struct UserMetadata: Decodable { let name: String? }
        struct User: Decodable {
            let id: String
            let user_metadata: UserMetadata?
        }
        let access_token: String
        let refresh_token: String
        let expires_in: Double
        let user: User
    }

    /// Exchanges an OIDC id_token (Apple or Google) for a Supabase Auth
    /// session and returns the Supabase user id (`auth.uid()`). `nonce` is
    /// the raw nonce whose hash was sent to the provider — Supabase verifies
    /// the pair when the provider's id_token includes a nonce claim.
    private func signInWithIdToken(provider: String, idToken: String, nonce: String?) async throws -> String {
        struct Body: Encodable {
            let provider: String
            let id_token: String
            let nonce: String?
        }
        let body = try JSONEncoder().encode(Body(provider: provider, id_token: idToken, nonce: nonce))
        let grant = try await tokenRequest(grantType: "id_token", body: body)
        return grant.user.id
    }

    /// Exchanges a Sign in with Apple identity token for a Supabase Auth
    /// session. Requires the Apple provider enabled in Supabase Dashboard →
    /// Authentication → Providers with this app's bundle ID.
    @discardableResult
    func signInWithApple(identityToken: String, nonce: String? = nil) async throws -> String {
        try await signInWithIdToken(provider: "apple", idToken: identityToken, nonce: nonce)
    }

    /// Exchanges a Google id_token for a Supabase Auth session. Requires the
    /// Google provider enabled in Supabase Dashboard → Authentication →
    /// Providers, with both the iOS and Web OAuth Client IDs listed (Web
    /// first) under Client IDs — see Task 6.
    @discardableResult
    func signInWithGoogle(idToken: String, nonce: String? = nil) async throws -> String {
        try await signInWithIdToken(provider: "google", idToken: idToken, nonce: nonce)
    }

    /// Runs a POST against an auth endpoint that returns a full session
    /// directly (signup with email confirmation disabled, or a token grant
    /// with a query-string grant_type). Distinct from `tokenRequest`
    /// (which always targets `/auth/v1/token`) so this can target
    /// `/auth/v1/signup` too, and so its richer error-body mapping doesn't
    /// change `tokenRequest`'s existing `SupabaseError.httpError` contract
    /// that `refreshSession` pattern-matches on.
    private func authRequest(path: String, grantQuery: String? = nil, body: Data) async throws -> TokenGrant {
        let fullPath = grantQuery.map { "\(path)?grant_type=\($0)" } ?? path
        var request = bareRequest(path: fullPath, method: "POST")
        request.httpBody = body
        let (data, response) = try await urlSession.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let errorBody = try? JSONDecoder().decode(SupabaseAuthErrorBody.self, from: data)
            throw SupabaseAuthError(
                code: errorBody?.error_code ?? errorBody?.error,
                message: errorBody?.msg ?? errorBody?.error_description
            )
        }
        let grant = try JSONDecoder().decode(TokenGrant.self, from: data)
        storeSession(SupabaseSession(
            accessToken:  grant.access_token,
            refreshToken: grant.refresh_token,
            userID:       grant.user.id,
            expiresAt:    Date().addingTimeInterval(grant.expires_in)
        ))
        return grant
    }

    /// Signs up a new Supabase Auth user with email and password only. No
    /// name is sent: the user's name is collected by the post-sign-in name
    /// step and stored in `profiles`, not in auth metadata. Requires the Email provider enabled and "Confirm
    /// email" disabled in Supabase Dashboard → Authentication → Providers
    /// (see Task 6) — otherwise this returns a pending-confirmation user
    /// with no session, and the throw path here won't fire since that's a
    /// 200 response with a null session, which JSONDecoder would then fail
    /// on decoding as TokenGrant (surfacing as a decode error, which is
    /// correct: the app doesn't support the confirmation-pending state).
    func signUpWithPassword(email: String, password: String) async throws -> String {
        struct Body: Encodable {
            let email: String
            let password: String
        }
        let body = try JSONEncoder().encode(Body(email: email, password: password))
        let grant = try await authRequest(path: "/auth/v1/signup", body: body)
        return grant.user.id
    }

    /// Signs in an existing Supabase Auth user with email/password. Returns
    /// the legacy `name` from `raw_user_meta_data` (present only for accounts
    /// created before sign-up stopped writing it; nil otherwise) alongside the
    /// user id. New accounts get their name from the name step / `profiles`.
    func signInWithPassword(email: String, password: String) async throws -> (userID: String, name: String?) {
        struct Body: Encodable {
            let email: String
            let password: String
        }
        let body = try JSONEncoder().encode(Body(email: email, password: password))
        let grant = try await authRequest(path: "/auth/v1/token", grantQuery: "password", body: body)
        return (grant.user.id, grant.user.user_metadata?.name)
    }

    /// Best-effort server-side revocation of the refresh token, then clears
    /// the local session. Never throws — signing out locally must always work.
    func signOut() async {
        loadSessionIfNeeded()
        if let token = session?.accessToken {
            var request = bareRequest(path: "/auth/v1/logout", method: "POST")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            _ = try? await urlSession.data(for: request)
        }
        storeSession(nil)
    }

    /// Refreshes an expiring session. A 4xx from the refresh endpoint means
    /// the refresh token was revoked/expired server-side — the session is
    /// dead, so it's cleared rather than retried forever.
    private func refreshSession(_ current: SupabaseSession) async throws -> SupabaseSession? {
        struct Body: Encodable { let refresh_token: String }
        let body = try JSONEncoder().encode(Body(refresh_token: current.refreshToken))
        do {
            _ = try await tokenRequest(grantType: "refresh_token", body: body)
            return session
        } catch SupabaseError.httpError(let code) where (400..<500).contains(code) {
            storeSession(nil)
            return nil
        }
    }

    /// Runs a token grant against /auth/v1/token and stores the session.
    /// Uses bareRequest (anon Authorization) so a refresh can never recurse
    /// through the data-request path that triggered it.
    private func tokenRequest(grantType: String, body: Data) async throws -> TokenGrant {
        var request = bareRequest(path: "/auth/v1/token?grant_type=\(grantType)", method: "POST")
        request.httpBody = body
        let (data, response) = try await urlSession.data(for: request)
        try validate(response)
        let grant = try JSONDecoder().decode(TokenGrant.self, from: data)
        storeSession(SupabaseSession(
            accessToken:  grant.access_token,
            refreshToken: grant.refresh_token,
            userID:       grant.user.id,
            expiresAt:    Date().addingTimeInterval(grant.expires_in)
        ))
        return grant
    }

    /// A valid (refreshed if needed) access token, or nil when signed out or
    /// the refresh failed transiently — callers then fall back to the anon key.
    private func currentAccessToken() async -> String? {
        loadSessionIfNeeded()
        guard let current = session else { return nil }
        guard current.needsRefresh() else { return current.accessToken }
        return (try? await refreshSession(current))?.accessToken
    }

    // MARK: - Account deletion

    /// Calls the `delete-account` Edge Function, which revokes Sign in with
    /// Apple (when a code is given), deletes every row this user owns, then
    /// the auth user itself. On any failure it throws and leaves the local
    /// session alone so the caller can keep the user signed in to retry; on
    /// success the now-dead session is cleared.
    func deleteAccount(appleAuthorizationCode: String?) async throws {
        guard let token = await currentAccessToken() else {
            throw AccountDeletionError.notSignedIn
        }
        var request = bareRequest(path: "/functions/v1/delete-account", method: "POST")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            DeleteAccountBody(appleAuthorizationCode: appleAuthorizationCode))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw AccountDeletionError.network
        }
        guard let http = response as? HTTPURLResponse else { throw AccountDeletionError.server }
        guard (200..<300).contains(http.statusCode) else {
            let code = (try? JSONDecoder().decode(DeleteAccountErrorBody.self, from: data))?.error
            throw AccountDeletionError(serverCode: code, status: http.statusCode)
        }
        storeSession(nil)
    }

    // MARK: - HTTP helpers

    @discardableResult
    private func post(path: String, body: Data, upsert: Bool) async throws -> Data? {
        var request = await makeRequest(path: path, method: "POST")
        request.httpBody = body
        if upsert { request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer") }
        let (data, response) = try await urlSession.data(for: request)
        try validate(response)
        return data
    }

    private func delete(path: String) async throws {
        let request = await makeRequest(path: path, method: "DELETE")
        let (_, response) = try await urlSession.data(for: request)
        try validate(response)
    }

    private func get(path: String) async throws -> Data {
        let request = await makeRequest(path: path, method: "GET")
        let (data, response) = try await urlSession.data(for: request)
        try validate(response)
        return data
    }

    /// apikey + Content-Type only — no Authorization. Auth endpoints build on
    /// this directly so token grants never depend on having a token.
    private func bareRequest(path: String, method: String) -> URLRequest {
        var request = URLRequest(url: URL(string: Self.supabaseURL + path)!)
        request.httpMethod = method
        request.setValue(Self.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func makeRequest(path: String, method: String) async -> URLRequest {
        var request = bareRequest(path: path, method: method)
        let bearer = await currentAccessToken() ?? Self.supabaseAnonKey
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw SupabaseError.httpError(code)
        }
    }
}

// MARK: - Auth errors

/// Maps GoTrue's error response body to a readable message. GoTrue has
/// shipped two error body shapes across versions (`error_code`/`msg` and the
/// older `error`/`error_description`), so both are read; whichever is
/// present wins.
struct SupabaseAuthError: LocalizedError {
    let code: String?
    let message: String?

    var errorDescription: String? {
        switch code {
        case "user_already_exists":  return "An account with that email already exists."
        case "invalid_credentials":  return "Incorrect email or password."
        case "weak_password":        return message ?? "Password is too weak."
        default:                     return "Something went wrong, please try again."
        }
    }
}

private struct SupabaseAuthErrorBody: Decodable {
    let error_code: String?
    let msg: String?
    let error: String?
    let error_description: String?
}

// MARK: - Errors

enum SupabaseError: LocalizedError {
    case httpError(Int)
    var errorDescription: String? {
        switch self {
        case .httpError(let code): return "Supabase request failed with status \(code)."
        }
    }
}

// MARK: - Auth seam
// Lets AuthManager depend on an abstraction instead of the concrete actor,
// so tests can inject a fake instead of hitting the network — mirrors the
// KeychainStore seam.
protocol SupabaseAuthenticating: Sendable {
    func signInWithApple(identityToken: String, nonce: String?) async throws -> String
    func signInWithGoogle(idToken: String, nonce: String?) async throws -> String
    func signUpWithPassword(email: String, password: String) async throws -> String
    func signInWithPassword(email: String, password: String) async throws -> (userID: String, name: String?)
}

extension SupabaseService: SupabaseAuthenticating {}

/// Profile read/write seam for the registration flow, so
/// `RegistrationCoordinator` can be tested without the network.
protocol SupabaseProfileStoring: Sendable {
    func fetchProfile(id: String) async throws -> RemoteProfile?
    func upsertProfileName(id: String, name: PersonName) async throws
}

extension SupabaseService: SupabaseProfileStoring {}

/// Account-deletion seam so AuthManager's delete flow is testable without
/// the network.
protocol SupabaseAccountDeleting: Sendable {
    func deleteAccount(appleAuthorizationCode: String?) async throws
}

extension SupabaseService: SupabaseAccountDeleting {}

// DTOs live in SupabaseDTOs.swift — kept separate so Swift 6 never
// infers @MainActor isolation on their synthesised Codable conformances.
