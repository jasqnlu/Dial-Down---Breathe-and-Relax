# Streak Saver Purchase Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users spend points (150 each, max 3 held) to buy streak savers (`streakFreezeTokens`), from a new Profile-settings section and from the "Streak Lost" alert.

**Architecture:** `UserProfile` gains a monotonic `pointsSpent` counter; `spendablePoints = totalPoints - pointsSpent`, so lifetime stats and badges are untouched. All rules live in pure static functions on `GamificationService` (unit-tested). Sync piggybacks on the existing `profiles` row (`RemoteProfile`, `pullRemoteProfile`), with the merge extracted into a testable `UserProfile.mergeRemote`.

**Tech Stack:** Swift, SwiftUI, SwiftData, Swift Testing (`import Testing`), Supabase PostgREST.

**Spec:** `docs/superpowers/specs/2026-09-28-streak-saver-purchase-design.md` (with the corrections listed in its "Amendments" section).

## Global Constraints

- Price `150` points; cap `3` savers held; both are constants on `GamificationService` (`saverCost`, `maxSavers`).
- The free token (1 per 7 sessions) stays, counts toward the cap, and is skipped (not deferred) at the cap; `sessionsTowardNextFreezeToken` still resets.
- `totalPoints` is never decremented. Badges and leaderboard read `totalPoints` only.
- Tests use Swift Testing, module `BreathRelaxStretch`. Test files live in `Breath - Relax & StretchTests/` (repo-root sibling folder; a wrong path silently compiles nothing — confirm the case count in the output).
- Test command (~40s):
  `xcodebuild test -project "Breath - Relax & Stretch.xcodeproj" -scheme BreathRelaxStretch -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:"Breath - Relax & StretchTests"`
- Baseline before this work: fully green. Any failing test is a regression.
- The Supabase schema change is **written, not applied**. Never run it against the project without explicit user approval.
- New user-facing strings use string literals in `Text`/`Label`/`Button` (localizable). Never pass a `String` variable to `Text`. Add new keys to `Breath - Relax & Stretch/Resources/Localizable.xcstrings` only if the existing workflow in that file requires an entry (English source strings work without one).
- Commits end with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- After code changes, run `graphify update .` from the repo root.

## Review Focus

- Buying with exactly 150 spendable points succeeds and leaves 0 (boundary).
- `pointsSpent` greater than `totalPoints` (bad merge) must clamp `spendablePoints` to 0, never negative.
- A spent saver must not be resurrected by a pull on a device that already has progress (tokens are not max-merged).
- A brand-new device (empty local profile) pulling a remote row adopts the remote saver count and `pointsSpent`, clamped to the cap.
- Buying while a streak break is pending and 0 savers held (`buyAndRestore`) restores the streak and spends exactly 150 once.
- `RemoteProfile` with nil new fields omits them from the upload body, so a name-only or older-client upload cannot zero them.

## File Structure

- Modify `Breath - Relax & Stretch/Models/UserProfile.swift` — `pointsSpent`, `spendablePoints`, dedupe merge, `mergeRemote`.
- Modify `Breath - Relax & Stretch/Services/GamificationService.swift` — constants, `canBuySaver`, `saverPurchaseBlockReason`, `buySaver`, `buyAndRestore`, capped free token.
- Modify `Breath - Relax & Stretch/Services/SupabaseDTOs.swift` — two optional `RemoteProfile` fields.
- Create `Breath - Relax & Stretch/Services/ProfileSyncService.swift` — upload after purchase.
- Modify `Breath - Relax & Stretch/Services/SessionRecorder.swift` — include new fields in the session upload.
- Modify `Breath - Relax & Stretch/Breath__Relax___StretchApp.swift` — `pullRemoteProfile` calls `mergeRemote`.
- Modify `supabase_schema.sql` — two `alter table` lines (not applied).
- Modify `Breath - Relax & Stretch/Views/Profile/DataExportView.swift` — export `pointsSpent`.
- Modify `Breath - Relax & Stretch/Views/Profile/ProfileSettingsTab.swift` and `Views/Home/TodayView.swift` — UI.
- Tests: `GamificationServiceTests.swift`, `UserProfileTests.swift`, new `RemoteProfileTests.swift` (all under `Breath - Relax & StretchTests/`).

---

### Task 1: Purchase rules and capped free token

**Files:**
- Modify: `Breath - Relax & Stretch/Models/UserProfile.swift`
- Modify: `Breath - Relax & Stretch/Services/GamificationService.swift`
- Test: `Breath - Relax & StretchTests/GamificationServiceTests.swift`

**Interfaces:**
- Produces:
  - `UserProfile.pointsSpent: Int`, `UserProfile.spendablePoints: Int`
  - `GamificationService.saverCost: Int` (150), `GamificationService.maxSavers: Int` (3)
  - `enum GamificationService.SaverBlockReason: Equatable { case atMax; case needMorePoints(Int) }`
  - `GamificationService.canBuySaver(_ profile: UserProfile) -> Bool`
  - `GamificationService.saverPurchaseBlockReason(_ profile: UserProfile) -> SaverBlockReason?`
  - `@discardableResult GamificationService.buySaver(for profile: UserProfile) -> Bool`
  - `@discardableResult GamificationService.buyAndRestore(for profile: UserProfile) -> Bool`

- [ ] **Step 1: Write the failing tests**

Add `pointsSpent: Int = 0` to the `makeProfile` helper signature (after `points`) and `p.pointsSpent = pointsSpent` in its body. Append these tests inside `GamificationServiceTests` (before the final `}`):

```swift
    // MARK: - Buying streak savers

    @Test func spendablePointsIsTotalMinusSpent() {
        let p = makeProfile(points: 400, pointsSpent: 150)
        #expect(p.spendablePoints == 250)
    }

    @Test func spendablePointsClampsAtZero() {
        let p = makeProfile(points: 100, pointsSpent: 250)
        #expect(p.spendablePoints == 0)
    }

    @Test func buySaverDeductsPointsAndAddsToken() {
        let p = makeProfile(points: 400)
        #expect(GamificationService.buySaver(for: p) == true)
        #expect(p.pointsSpent == 150)
        #expect(p.streakFreezeTokens == 1)
        #expect(p.totalPoints == 400)
    }

    @Test func buySaverWorksAtExactPrice() {
        let p = makeProfile(points: 150)
        #expect(GamificationService.buySaver(for: p) == true)
        #expect(p.spendablePoints == 0)
    }

    @Test func buySaverFailsWithoutEnoughPoints() {
        let p = makeProfile(points: 149)
        #expect(GamificationService.buySaver(for: p) == false)
        #expect(p.pointsSpent == 0)
        #expect(p.streakFreezeTokens == 0)
    }

    @Test func buySaverFailsAtCap() {
        let p = makeProfile(points: 1000, streakFreezeTokens: 3)
        #expect(GamificationService.buySaver(for: p) == false)
        #expect(p.pointsSpent == 0)
        #expect(p.streakFreezeTokens == 3)
    }

    @Test func buyingUpToCapThenBlocked() {
        let p = makeProfile(points: 1000)
        #expect(GamificationService.buySaver(for: p))
        #expect(GamificationService.buySaver(for: p))
        #expect(GamificationService.buySaver(for: p))
        #expect(GamificationService.buySaver(for: p) == false)
        #expect(p.streakFreezeTokens == 3)
        #expect(p.pointsSpent == 450)
    }

    @Test func buyingDoesNotChangeBadgeEligibility() {
        let p = makeProfile(points: 500)
        GamificationService.buySaver(for: p)
        let badges = GamificationService.newBadges(for: p)
        #expect(badges.contains("High Achiever"))
    }

    @Test func blockReasonValues() {
        #expect(GamificationService.saverPurchaseBlockReason(makeProfile(points: 1000)) == nil)
        #expect(GamificationService.saverPurchaseBlockReason(makeProfile(points: 108)) == .needMorePoints(42))
        #expect(GamificationService.saverPurchaseBlockReason(makeProfile(points: 1000, streakFreezeTokens: 3)) == .atMax)
        // At the cap wins over insufficient points.
        #expect(GamificationService.saverPurchaseBlockReason(makeProfile(points: 0, streakFreezeTokens: 3)) == .atMax)
    }

    @Test func buyAndRestoreRestoresPendingBreak() {
        let p = makeProfile(points: 200, pendingStreakBreak: 6)
        #expect(GamificationService.buyAndRestore(for: p) == true)
        #expect(p.streak == 6)
        #expect(p.pendingStreakBreak == 0)
        #expect(p.pointsSpent == 150)
        #expect(p.streakFreezeTokens == 0) // bought one, spent one
    }

    @Test func buyAndRestoreFailsWithoutPointsAndKeepsBreakPending() {
        let p = makeProfile(points: 10, pendingStreakBreak: 6)
        #expect(GamificationService.buyAndRestore(for: p) == false)
        #expect(p.pendingStreakBreak == 6)
        #expect(p.pointsSpent == 0)
    }

    @Test func freeTokenSkippedAtCapButCounterResets() {
        let p = makeProfile(streakFreezeTokens: 3, lastSession: noon(daysAgo: 1))
        for _ in 0..<7 {
            GamificationService.updateStreak(for: p)
        }
        #expect(p.streakFreezeTokens == 3)
        #expect(p.sessionsTowardNextFreezeToken == 0)
    }
```

Also rename the existing `freezeTokensAccumulateUncapped` test to `freezeTokensAccumulateUpToCap` (behavior is unchanged: 21 sessions still yields 3).

- [ ] **Step 2: Run tests to verify they fail**

Run the test command from Global Constraints.
Expected: build FAILS (`pointsSpent`, `buySaver`, etc. not defined).

- [ ] **Step 3: Implement**

In `Models/UserProfile.swift`, after `var totalPoints: Int = 0` add:

```swift
    /// Lifetime points spent on streak savers. Only ever increases, so the
    /// "max wins" cross-device merge can never resurrect spent points.
    var pointsSpent: Int = 0
```

and after the `init`, before the dedupe doc comment:

```swift
    /// Points available to spend. Lifetime `totalPoints` (badges, stats) is
    /// untouched by spending. Clamped so a bad merge can't go negative.
    var spendablePoints: Int { max(0, totalPoints - pointsSpent) }
```

In `Services/GamificationService.swift`, replace the `sessionsTowardNextFreezeToken` block in `updateStreak`:

```swift
        profile.sessionsTowardNextFreezeToken += 1
        if profile.sessionsTowardNextFreezeToken >= 7 {
            profile.sessionsTowardNextFreezeToken = 0
            if profile.streakFreezeTokens < maxSavers {
                profile.streakFreezeTokens += 1
            }
        }
```

and add, after `dismissStreakBreak` (inside the Streak Freeze MARK):

```swift
    // MARK: - Buying Savers

    static let saverCost = 150
    static let maxSavers = 3

    enum SaverBlockReason: Equatable {
        case atMax
        case needMorePoints(Int)
    }

    /// Why a purchase is blocked, or nil when allowed. Holding the maximum
    /// takes precedence over being short on points.
    static func saverPurchaseBlockReason(_ profile: UserProfile) -> SaverBlockReason? {
        if profile.streakFreezeTokens >= maxSavers { return .atMax }
        if profile.spendablePoints < saverCost {
            return .needMorePoints(saverCost - profile.spendablePoints)
        }
        return nil
    }

    static func canBuySaver(_ profile: UserProfile) -> Bool {
        saverPurchaseBlockReason(profile) == nil
    }

    /// Spends `saverCost` points for one streak saver. No-op (returns false)
    /// when blocked. Lifetime `totalPoints` is deliberately left alone.
    @discardableResult
    static func buySaver(for profile: UserProfile) -> Bool {
        guard canBuySaver(profile) else { return false }
        profile.pointsSpent += saverCost
        profile.streakFreezeTokens += 1
        return true
    }

    /// For the "Streak Lost" alert when the user holds no savers: buy one and
    /// immediately use it on the pending break. Nothing changes on failure.
    @discardableResult
    static func buyAndRestore(for profile: UserProfile) -> Bool {
        guard profile.pendingStreakBreak > 0, buySaver(for: profile) else { return false }
        restoreStreak(for: profile)
        return true
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run the test command. Expected: PASS; total case count increased by 11.

- [ ] **Step 5: Commit**

```bash
git add "Breath - Relax & Stretch/Models/UserProfile.swift" "Breath - Relax & Stretch/Services/GamificationService.swift" "Breath - Relax & StretchTests/GamificationServiceTests.swift"
git commit -m "feat: buy streak savers with points (150 pts, max 3)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Sync, merge and export

**Files:**
- Modify: `Breath - Relax & Stretch/Models/UserProfile.swift` (dedupe, `mergeRemote`)
- Modify: `Breath - Relax & Stretch/Services/SupabaseDTOs.swift:28-51`
- Create: `Breath - Relax & Stretch/Services/ProfileSyncService.swift`
- Modify: `Breath - Relax & Stretch/Services/SessionRecorder.swift:~148`
- Modify: `Breath - Relax & Stretch/Breath__Relax___StretchApp.swift:~599-617`
- Modify: `supabase_schema.sql` (after the `last_name` line, ~446)
- Modify: `Breath - Relax & Stretch/Views/Profile/DataExportView.swift` (CSV ~254-268, JSON ~310-319, `ProfileExportRow` ~377-400)
- Test: `Breath - Relax & StretchTests/UserProfileTests.swift`, new `Breath - Relax & StretchTests/RemoteProfileTests.swift`

**Interfaces:**
- Consumes: `UserProfile.pointsSpent`, `GamificationService.maxSavers` (Task 1).
- Produces:
  - `RemoteProfile.pointsSpent: Int?`, `RemoteProfile.streakFreezeTokens: Int?` (both default nil)
  - `UserProfile.mergeRemote(_ remote: RemoteProfile)`
  - `@MainActor ProfileSyncService.upload(_ profile: UserProfile)`

- [ ] **Step 1: Write the failing tests**

Create `Breath - Relax & StretchTests/RemoteProfileTests.swift`:

```swift
import Testing
import Foundation
@testable import BreathRelaxStretch

struct RemoteProfileTests {

    private func encode(_ p: RemoteProfile) throws -> [String: Any] {
        let data = try JSONEncoder().encode(p)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func nilSaverFieldsAreOmittedFromUpload() throws {
        let p = RemoteProfile(id: "x", displayName: "A", totalPoints: 1, streak: 1,
                              totalMinutes: 1, lastSessionAt: nil)
        let json = try encode(p)
        #expect(json["points_spent"] == nil)
        #expect(json["streak_freeze_tokens"] == nil)
    }

    @Test func saverFieldsEncodeWithSnakeCaseKeys() throws {
        let p = RemoteProfile(id: "x", displayName: "A", totalPoints: 1, streak: 1,
                              totalMinutes: 1, lastSessionAt: nil,
                              pointsSpent: 150, streakFreezeTokens: 2)
        let json = try encode(p)
        #expect(json["points_spent"] as? Int == 150)
        #expect(json["streak_freeze_tokens"] as? Int == 2)
    }

    @Test func rowsWithoutSaverColumnsStillDecode() throws {
        let raw = #"{"id":"x","display_name":"A","total_points":1,"streak":1,"total_minutes":1}"#
        let p = try JSONDecoder().decode(RemoteProfile.self, from: Data(raw.utf8))
        #expect(p.pointsSpent == nil)
        #expect(p.streakFreezeTokens == nil)
    }
}
```

Append to `UserProfileTests` (before the final `}`):

```swift
    private func remote(points: Int = 0, streak: Int = 0, minutes: Int = 0,
                        spent: Int? = nil, tokens: Int? = nil) -> RemoteProfile {
        RemoteProfile(id: "a", displayName: "A", totalPoints: points, streak: streak,
                      totalMinutes: minutes, lastSessionAt: nil,
                      pointsSpent: spent, streakFreezeTokens: tokens)
    }

    @Test func dedupeSumsPointsSpentAndTakesMaxTokensCapped() throws {
        let context = makeContext()
        let a = UserProfile(profileID: "a", displayName: "A")
        a.pointsSpent = 150; a.streakFreezeTokens = 2
        let b = UserProfile(profileID: "a", displayName: "A")
        b.pointsSpent = 300; b.streakFreezeTokens = 3
        context.insert(a); context.insert(b)
        try? context.save()

        UserProfile.dedupe(in: context)

        let survivor = try #require((try? context.fetch(FetchDescriptor<UserProfile>()))?.first)
        #expect(survivor.pointsSpent == 450)
        #expect(survivor.streakFreezeTokens == 3)
    }

    @Test func mergeRemoteTakesMaxOfMonotonicFields() {
        let p = UserProfile(profileID: "a", displayName: "A")
        p.totalPoints = 500; p.pointsSpent = 150; p.streak = 4; p.totalMinutes = 10
        p.mergeRemote(remote(points: 300, streak: 9, minutes: 5, spent: 300))
        #expect(p.totalPoints == 500)
        #expect(p.streak == 9)
        #expect(p.totalMinutes == 10)
        #expect(p.pointsSpent == 300)
    }

    @Test func mergeRemoteDoesNotResurrectSpentSaversOnDeviceWithProgress() {
        let p = UserProfile(profileID: "a", displayName: "A")
        p.totalPoints = 500; p.streak = 4; p.streakFreezeTokens = 0   // user used their saver
        p.mergeRemote(remote(points: 500, streak: 4, tokens: 2))       // stale remote count
        #expect(p.streakFreezeTokens == 0)
    }

    @Test func mergeRemoteAdoptsSaversOnFreshDevice() {
        let p = UserProfile(profileID: "a", displayName: "A")
        p.mergeRemote(remote(points: 600, streak: 5, spent: 300, tokens: 2))
        #expect(p.streakFreezeTokens == 2)
        #expect(p.pointsSpent == 300)
        #expect(p.spendablePoints == 300)
    }

    @Test func mergeRemoteClampsAdoptedSaversToCap() {
        let p = UserProfile(profileID: "a", displayName: "A")
        p.mergeRemote(remote(tokens: 99))
        #expect(p.streakFreezeTokens == GamificationService.maxSavers)
    }

    @Test func mergeRemoteToleratesMissingSaverFields() {
        let p = UserProfile(profileID: "a", displayName: "A")
        p.pointsSpent = 150; p.streakFreezeTokens = 1
        p.mergeRemote(remote(points: 400))
        #expect(p.pointsSpent == 150)
        #expect(p.streakFreezeTokens == 1)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run the test command. Expected: build FAILS (`RemoteProfile` has no `pointsSpent`; `mergeRemote` undefined).

- [ ] **Step 3: Implement**

`SupabaseDTOs.swift` — in `RemoteProfile`, after `var lastName: String? = nil` add:

```swift
    /// Nullable so older rows/clients that lack the columns still decode, and
    /// nil is omitted from the encoded body so an upload that doesn't know
    /// these values can never overwrite them.
    var pointsSpent: Int? = nil
    var streakFreezeTokens: Int? = nil
```

and in `CodingKeys` add:

```swift
        case pointsSpent  = "points_spent"
        case streakFreezeTokens = "streak_freeze_tokens"
```

`UserProfile.swift` — in `dedupe`, after `survivor.totalPoints += duplicate.totalPoints` add:

```swift
            survivor.pointsSpent += duplicate.pointsSpent
            survivor.streakFreezeTokens = min(GamificationService.maxSavers,
                max(survivor.streakFreezeTokens, duplicate.streakFreezeTokens))
```

and add this method to the class (before `dedupe`):

```swift
    /// Folds a remote `profiles` row into this profile. Monotonic fields take
    /// the max. `streakFreezeTokens` goes up *and down* (buying vs. using), so
    /// a max-merge would resurrect used savers; the remote count is adopted
    /// only on a brand-new device (no local progress yet), otherwise the local
    /// value is authoritative and gets uploaded.
    func mergeRemote(_ remote: RemoteProfile) {
        let isFreshDevice = totalPoints == 0 && streak == 0 && lastSessionDate == nil
            && streakFreezeTokens == 0

        totalPoints = max(totalPoints, remote.totalPoints)
        totalMinutes = max(totalMinutes, remote.totalMinutes)
        streak = max(streak, remote.streak)
        if let remoteSpent = remote.pointsSpent {
            pointsSpent = max(pointsSpent, remoteSpent)
        }
        if let remoteDate = remote.lastSessionAt,
           remoteDate > (lastSessionDate ?? .distantPast) {
            lastSessionDate = remoteDate
        }
        if isFreshDevice, let remoteTokens = remote.streakFreezeTokens {
            streakFreezeTokens = min(GamificationService.maxSavers, max(0, remoteTokens))
        }
    }
```

`Breath__Relax___StretchApp.swift` — in `pullRemoteProfile`, replace the block from `profile.totalPoints = max(...)` through the closing brace of the `if let remoteDate` with:

```swift
        profile.mergeRemote(remote)
```

`SessionRecorder.swift` — in the `RemoteProfile(` snapshot add, after `lastSessionAt: input.completedAt`:

```swift
                lastSessionAt: input.completedAt,
                pointsSpent: profile.pointsSpent,
                streakFreezeTokens: profile.streakFreezeTokens
```

(replace the existing `lastSessionAt: input.completedAt` line; keep the trailing `)`.)

Create `Services/ProfileSyncService.swift`:

```swift
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
```

`supabase_schema.sql` — after the `last_name` alter (~line 446) add (do NOT run it):

```sql
-- Streak saver purchases: points_spent only ever grows; tokens are capped at 3.
alter table profiles add column if not exists points_spent int4 not null default 0
  check (points_spent between 0 and 100000000);
alter table profiles add column if not exists streak_freeze_tokens int4 not null default 0
  check (streak_freeze_tokens between 0 and 3);
```

`DataExportView.swift` — CSV header: append `,pointsSpent`; row: append `"\(p.pointsSpent)"` after `"\(p.pendingStreakBreak)"` (add a comma to the previous element); JSON dict: add `"pointsSpent": p.pointsSpent` after `pendingStreakBreak`; `ProfileExportRow`: add `let pointsSpent: Int` and `pointsSpent = p.pointsSpent` in `init`.

- [ ] **Step 4: Run tests to verify they pass**

Run the test command. Expected: PASS (existing `UserProfileTests`/sync tests still green).

- [ ] **Step 5: Commit**

```bash
git add -A "Breath - Relax & Stretch" "Breath - Relax & StretchTests" supabase_schema.sql
git commit -m "feat: sync streak saver purchases, extract UserProfile.mergeRemote

Schema change written to supabase_schema.sql but not applied.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: UI (Settings section and Streak Lost alert)

**Files:**
- Modify: `Breath - Relax & Stretch/Views/Profile/ProfileSettingsTab.swift` (new section before `// Goals`, ~line 62)
- Modify: `Breath - Relax & Stretch/Views/Home/TodayView.swift:341-347`

**Interfaces:**
- Consumes: `GamificationService.canBuySaver`, `saverPurchaseBlockReason`, `buySaver`, `buyAndRestore`, `saverCost`, `maxSavers`, `UserProfile.spendablePoints`, `ProfileSyncService.upload` (Tasks 1–2).

- [ ] **Step 1: Settings section**

In `ProfileSettingsTab`, add imports `import SwiftData` at the top, and properties next to the other `@State`:

```swift
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @State private var confirmingSaverPurchase = false

    private var profile: UserProfile? { profiles.first }
```

Add this as the first `Section` in `body`'s `Group`, above `// Goals`:

```swift
            // Streak savers
            if let profile {
                Section {
                    LabeledContent {
                        Text("\(profile.streak)")
                    } label: {
                        Label("Current Streak", systemImage: "flame.fill")
                    }
                    LabeledContent {
                        Text("\(profile.streakFreezeTokens) / \(GamificationService.maxSavers)")
                    } label: {
                        Label("Streak Savers", systemImage: "shield.lefthalf.filled")
                    }
                    LabeledContent {
                        Text("\(profile.spendablePoints)")
                    } label: {
                        Label("Points to Spend", systemImage: "star.circle.fill")
                    }
                    Button {
                        confirmingSaverPurchase = true
                    } label: {
                        Label("Buy Streak Saver — \(GamificationService.saverCost) pts",
                              systemImage: "plus.circle.fill")
                    }
                    .disabled(!GamificationService.canBuySaver(profile))
                    .accessibilityIdentifier("settings.buySaver")
                } header: {
                    Text("Streak Savers")
                        .font(.luminaLabel)
                        .foregroundStyle(Color.luminaOnSurfaceVariant)
                } footer: {
                    switch GamificationService.saverPurchaseBlockReason(profile) {
                    case .atMax:
                        Text("You're holding the maximum number of savers.")
                    case .needMorePoints(let needed):
                        Text("Need \(needed) more points. You also earn a free saver every 7 sessions.")
                    case nil:
                        Text("A saver restores your streak if it lapses. You earn a free one every 7 sessions.")
                    }
                }
                .confirmationDialog(
                    "Spend \(GamificationService.saverCost) points on a streak saver?",
                    isPresented: $confirmingSaverPurchase,
                    titleVisibility: .visible
                ) {
                    Button("Buy Saver") {
                        if GamificationService.buySaver(for: profile) {
                            try? modelContext.save()
                            ProfileSyncService.upload(profile)
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                }
            }
```

- [ ] **Step 2: Streak Lost alert**

In `TodayView.swift`, inside the `.alert("Streak Lost"…)` actions, after the existing `if let profile, profile.streakFreezeTokens > 0 { … }` block add:

```swift
            if let profile, profile.streakFreezeTokens == 0, GamificationService.canBuySaver(profile) {
                Button("Buy & Restore (\(GamificationService.saverCost) pts)") {
                    if GamificationService.buyAndRestore(for: profile) {
                        try? modelContext.save()
                        ProfileSyncService.upload(profile)
                    }
                    brokenStreakValue = nil
                }
            }
```

Also call `ProfileSyncService.upload(profile)` after the existing `GamificationService.restoreStreak(for: profile)` + `try? modelContext.save()` so a used saver is uploaded too.

- [ ] **Step 3: Build**

Run: `xcodebuild build -project "Breath - Relax & Stretch.xcodeproj" -scheme BreathRelaxStretch -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: BUILD SUCCEEDED. Fix any type/isolation errors before continuing.

- [ ] **Step 4: Verify in the simulator**

Follow `.claude/skills/verify/SKILL.md` (launch-arg state injection). Confirm with screenshots:
1. Settings shows the section with correct streak/savers/points; the button is disabled with "Need N more points" when under 150 points, and with the max message at 3 savers.
2. With 200+ points, tapping Buy shows the dialog; confirming updates savers and points.
3. With a pending break, 0 savers and 150+ points, the "Streak Lost" alert shows "Buy & Restore" and restores the streak.

If the skill's launch args can't seed `pointsSpent`/`streakFreezeTokens`, extend the seeding in the same place the existing profile seeding lives and note it in the commit.

- [ ] **Step 5: Run the full test suite, then commit**

Run the test command; expected all green.

```bash
git add -A "Breath - Relax & Stretch"
git commit -m "feat: streak saver purchase UI in settings and Streak Lost alert

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

Then run `graphify update .` from the repo root.

---

## Self-Review

- Spec coverage: data model → T1; service logic and capped free token → T1; UI (settings + alert) → T3; sync, export, schema, upload-on-purchase, dedupe → T2; testing list → T1/T2 plus manual T3. The two-device purchase limitation is a documented non-goal.
- Deviation from spec (recorded under Amendments in the spec): tokens are adopted from remote only on a fresh device, because they go down as well as up.
- Migration lives in `supabase_schema.sql` (the repo has no migrations folder). Written, not applied.
- Types consistent: `SaverBlockReason`, `buySaver`, `buyAndRestore`, `mergeRemote`, `ProfileSyncService.upload` match across tasks.
