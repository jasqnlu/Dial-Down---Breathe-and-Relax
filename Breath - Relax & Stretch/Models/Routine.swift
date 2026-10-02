import Foundation
import SwiftData

@Model
final class Routine {
    // Inline defaults required for CloudKit (iCloud) sync compatibility.
    var uuid: UUID = UUID()
    var name: String = ""
    var exerciseIDs: [UUID] = []
    var borrowedFromID: UUID? = nil
    var createdAt: Date = Date()
    /// Per-exercise duration overrides, keyed by exercise UUID — seconds.
    /// Absent key means "use the exercise's own durationSeconds." Set via
    /// RoutineBuilderView's +/− stepper, read by SessionPlayerView during
    /// playback (see `effectiveDuration(for:)`).
    var exerciseDurationOverrides: [UUID: Int] = [:]
    /// Whether this routine is one of the user's "Today" launch candidates
    /// — replaces the old single `pinnedTodayRoutineID` AppStorage string,
    /// which could only ever point at one routine. Several routines can be
    /// pinned at once; `pinnedOrder` breaks the tie for which one Today
    /// actually shows/starts. Additive, defaulted field — no explicit
    /// SwiftData migration needed (see the inline-defaults comment above).
    var isPinnedToToday: Bool = false
    /// Priority among pinned routines, ascending — 0 is shown first. Only
    /// meaningful when `isPinnedToToday` is true; irrelevant (but left as
    /// whatever it last was) once unpinned, so re-pinning doesn't need to
    /// invent a fresh value from scratch.
    var pinnedOrder: Int = 0
    /// `AuthManager.backendID` of whoever created this routine — Supabase
    /// auth.uid() when signed in, the local anonymous UUID otherwise. Empty
    /// string means "not yet claimed" (routines created before this field
    /// existed); `Breath__Relax___StretchApp.claimOwnerlessRoutines()` backfills
    /// those once at launch. Every query site filters on this so one
    /// device's routines don't leak across different signed-in accounts.
    var ownerID: String = ""
    /// Bumped on every local mutation (rename, exercise list edit, duration
    /// override, pin/unpin, reorder). The sync engine compares this against
    /// the remote row's `updated_at` — whichever is newer wins the whole
    /// row. See docs/superpowers/specs/2026-09-23-routine-session-sync-engine-design.md.
    var updatedAt: Date = Date()
    /// Soft-delete marker: set instead of removing the row, so a pull-merge
    /// on another device can tell "this was deleted" apart from "never
    /// synced" and delete its own copy too. Every fetch that lists routines
    /// for display must filter `deletedAt == nil`.
    var deletedAt: Date? = nil

    init(
        uuid: UUID = UUID(),
        name: String,
        exerciseIDs: [UUID] = [],
        borrowedFromID: UUID? = nil,
        exerciseDurationOverrides: [UUID: Int] = [:],
        isPinnedToToday: Bool = false,
        pinnedOrder: Int = 0,
        ownerID: String = ""
    ) {
        self.uuid = uuid
        self.name = name
        self.exerciseIDs = exerciseIDs
        self.borrowedFromID = borrowedFromID
        self.createdAt = Date()
        self.exerciseDurationOverrides = exerciseDurationOverrides
        self.isPinnedToToday = isPinnedToToday
        self.pinnedOrder = pinnedOrder
        self.ownerID = ownerID
        self.updatedAt = Date()
    }

    /// Saves a newly created routine AND queues it for upload. Every place
    /// that creates a routine should use this instead of a bare
    /// `context.insert` — two creation paths once inserted without queueing,
    /// so those routines never synced. (Routines pulled *from* the server are
    /// inserted directly by `SyncEngine` and must not be re-queued.)
    @MainActor
    func insertAndQueueForSync(in context: ModelContext) {
        context.insert(self)
        markUpdated(in: context)
    }

    /// Marks this routine changed and queues it for the next sync drain.
    /// Every mutation site (rename, exercise edit, pin/unpin, reorder, and
    /// the `.delete` case below) should go through this instead of touching
    /// `updatedAt`/`deletedAt` directly, so nothing forgets to enqueue.
    @MainActor
    func markUpdated(in context: ModelContext) {
        updatedAt = Date()
        SyncOutbox().enqueue(.routine, id: uuid, op: .upsert, in: context)
    }

    /// Soft-deletes and queues the tombstone for sync. Callers should NOT
    /// also call `modelContext.delete(_:)` — the row has to stay (with
    /// `deletedAt` set) until it's synced, otherwise there's nothing left
    /// for `markUpdated`'s upsert-turned-delete collapse in `SyncOutbox` to
    /// read when the outbox drains.
    @MainActor
    func markDeleted(in context: ModelContext) {
        deletedAt = Date()
        updatedAt = Date()
        SyncOutbox().enqueue(.routine, id: uuid, op: .delete, in: context)
    }
}
