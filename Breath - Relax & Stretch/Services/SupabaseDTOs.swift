import Foundation

// MARK: - Supabase Remote DTOs
//
// Kept in their own file so Swift 6 never infers @MainActor isolation on
// the synthesised Codable conformances (which would happen if these structs
// shared a file with the `actor SupabaseService` declaration).

struct RemoteExercise: Codable, Sendable {
    let id: String
    let name: String
    let type: String
    let targetBodyParts: [String]
    let durationSeconds: Int
    let difficulty: Int
    let instructions: [String]
    let mediaURL: String?
    let caution: String?

    enum CodingKeys: String, CodingKey {
        case id, name, type, difficulty, instructions, caution
        case targetBodyParts = "target_body_parts"
        case durationSeconds = "duration_seconds"
        case mediaURL        = "media_url"
    }
}

struct RemoteProfile: Codable, Sendable, Identifiable {
    let id: String              // stable identifier — AuthManager.backendID (anonymous UUID), never an email
    let displayName: String
    let totalPoints: Int
    let streak: Int
    let totalMinutes: Int
    /// Local wall-clock time of the most recent completed session, used
    /// server-side (via get_streak_warning_candidates) to tell whether a
    /// user has already practiced today in their own timezone.
    let lastSessionAt: Date?
    /// Nullable in the database. `var … = nil` keeps existing memberwise call
    /// sites compiling, and nil is omitted from the encoded body so a session
    /// upload (which never sets names) can't overwrite the saved name.
    var firstName: String? = nil
    var lastName: String? = nil
    /// Nullable so older rows/clients that lack the columns still decode, and
    /// nil is omitted from the encoded body so an upload that doesn't know
    /// these values can never overwrite them.
    var pointsSpent: Int? = nil
    var streakFreezeTokens: Int? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case displayName  = "display_name"
        case totalPoints  = "total_points"
        case streak
        case totalMinutes = "total_minutes"
        case lastSessionAt = "last_session_at"
        case firstName    = "first_name"
        case lastName     = "last_name"
        case pointsSpent  = "points_spent"
        case streakFreezeTokens = "streak_freeze_tokens"
    }
}

/// Upsert body for the name step. Only identity columns are sent so
/// `resolution=merge-duplicates` leaves points/streak/minutes untouched.
struct RemoteProfileName: Codable, Sendable {
    let id: String
    let displayName: String
    let firstName: String
    let lastName: String

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case firstName   = "first_name"
        case lastName    = "last_name"
    }
}

/// Upsert body for `push_tokens`. `user_id` *must* be sent explicitly: it's
/// the table's primary key, `not null` with no default (see
/// supabase_schema.sql), so PostgREST rejects a body without it. RLS still
/// enforces that it matches `auth.uid()` — sending it is how the row gets
/// addressed, not how it gets authorized.
struct RemotePushToken: Codable, Sendable {
    let userID: String
    let deviceToken: String
    let timezone: String

    enum CodingKeys: String, CodingKey {
        case userID      = "user_id"
        case deviceToken = "device_token"
        case timezone
    }
}

// MARK: - Sync engine (2026-09-23)
//
// See docs/superpowers/specs/2026-09-23-routine-session-sync-engine-design.md.
// `RemoteSession` was removed once before, along with the original
// `SupabaseService.uploadSession()` — it existed solely to support that dead
// write path (no in-app caller). This is the real one, wired to `SyncEngine`.

struct RemoteRoutine: Codable, Sendable, Identifiable {
    let id: String                 // Routine.uuid, stringified
    let name: String
    let exerciseIDs: [String]
    let authorID: String           // AuthManager.backendID — must equal auth.uid() for RLS
    let borrowedFromID: String?
    /// Keyed by exercise uuid string, not `Routine.exerciseDurationOverrides`'s
    /// `[UUID: Int]` — Foundation's JSONEncoder only writes a real JSON
    /// object for `String`/`Int`-keyed dictionaries; a `UUID` key would
    /// silently encode as a flat alternating array instead, which wouldn't
    /// read as a sensible `jsonb` column. The `SyncEngine` conversion layer
    /// is what translates `UUID` keys to/from `String` at this boundary.
    let exerciseDurationOverrides: [String: Int]
    let isPinnedToToday: Bool
    let pinnedOrder: Int
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case exerciseIDs               = "exercise_ids"
        case authorID                  = "author_id"
        case borrowedFromID            = "borrowed_from_id"
        case exerciseDurationOverrides = "exercise_duration_overrides"
        case isPinnedToToday           = "is_pinned_to_today"
        case pinnedOrder               = "pinned_order"
        case updatedAt                 = "updated_at"
        case deletedAt                 = "deleted_at"
    }
}

struct RemoteSession: Codable, Sendable, Identifiable {
    let id: String                 // Session.uuid, stringified
    let userID: String             // AuthManager.backendID — must equal auth.uid() for RLS
    let routineID: String
    let startedAt: Date
    let completedAt: Date?
    let completionPercent: Double
    let pointsEarned: Int

    enum CodingKeys: String, CodingKey {
        case id
        case userID            = "user_id"
        case routineID         = "routine_id"
        case startedAt         = "started_at"
        case completedAt       = "completed_at"
        case completionPercent = "completion_percent"
        case pointsEarned      = "points_earned"
    }
}

// MARK: - Opt-in leaderboard

/// One row as returned by the `get_leaderboard()` function. Deliberately has
/// no user id and no name: `handle` is a generated pseudonym and `isMe` is
/// computed server-side, so a client can neither display nor leak identity
/// the server never sent.
struct RemoteLeaderboardEntry: Codable, Sendable {
    let handle: String
    let totalPoints: Int
    let streak: Int
    let totalMinutes: Int
    let isMe: Bool

    enum CodingKeys: String, CodingKey {
        case handle
        case totalPoints  = "total_points"
        case streak
        case totalMinutes = "total_minutes"
        case isMe         = "is_me"
    }
}

/// The caller's own `leaderboard` row. Its existence is the opt-in: joining
/// upserts it, leaving deletes it. `userID` must equal `auth.uid()` (RLS).
struct RemoteLeaderboardRow: Codable, Sendable {
    let userID: String
    let handle: String
    let totalPoints: Int
    let streak: Int
    let totalMinutes: Int

    enum CodingKeys: String, CodingKey {
        case userID       = "user_id"
        case handle
        case totalPoints  = "total_points"
        case streak
        case totalMinutes = "total_minutes"
    }
}
