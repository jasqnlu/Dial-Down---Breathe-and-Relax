# Streak Saver Purchase — Design

Date: 2026-09-28
Status: Draft, awaiting review

## Goal

Let users spend points to stock up streak savers, so a streak that dies from
inactivity can be restored. Streak savers already exist in the code as
`streakFreezeTokens`. Today they are earned only for free (1 per 7 sessions).
This feature adds a points-based way to buy them.

## Decisions (agreed)

- **Separate spendable balance.** `totalPoints` stays a lifetime counter, so
  badges (Century, High Achiever, Elite Breather) and stats are unaffected by
  spending.
- **Price:** 150 points per saver.
- **Cap:** at most 3 savers held at once (`streakFreezeTokens <= 3`).
- **Free token stays:** 1 per 7 sessions, and it counts toward the cap.
- **Restore stays manual.** No automatic spending.
- **UI:** a "Streak Savers" section in Profile settings, plus a buy option in
  the "Streak Lost" alert.

## Non-goals

Real-money purchases, gifting, auto-use of savers.

## Design

### 1. Data model (`Models/UserProfile.swift`)

- Add `var pointsSpent: Int = 0` (inline default, so lightweight migration).
- Computed `var spendablePoints: Int { max(0, totalPoints - pointsSpent) }`.
- `totalPoints` and `pointsSpent` are both monotonically increasing. This makes
  the existing "max wins" reconciliation safe: a stale device can never
  resurrect spent points.
- `UserProfile.dedupe` sums `totalPoints`, so it also sums `pointsSpent`.
  `streakFreezeTokens` and `sessionsTowardNextFreezeToken` are not merged there
  today, so dedupe takes the max of `streakFreezeTokens` (clamped to the cap).

### 2. Service logic (`Services/GamificationService.swift`)

- `static let saverCost = 150`, `static let maxSavers = 3`.
- `canBuySaver(_ profile) -> Bool`: `spendablePoints >= saverCost` and
  `streakFreezeTokens < maxSavers`.
- `saverPurchaseBlockReason(_ profile) -> SaverBlockReason?`: `.atMax` or
  `.needMorePoints(Int)`, used by the UI to explain a disabled button.
- `buySaver(for:) -> Bool`: if `canBuySaver`, `pointsSpent += saverCost` and
  `streakFreezeTokens += 1`; returns whether it bought. No-op otherwise.
- `updateStreak`: when the 7-session counter rolls over, only add a token if
  `streakFreezeTokens < maxSavers`. The counter still resets, so the free token
  is skipped rather than deferred.
- `restoreStreak`, `checkForBrokenStreak`, `dismissStreakBreak`: unchanged.

### 3. UI

- **`ProfileSettingsTab`**: new "Streak Savers" `Section`, placed before "My
  Goals". Rows: current streak, savers held (`n / 3`), spendable points. A
  **Buy Saver — 150 pts** button, disabled when `saverPurchaseBlockReason` is
  non-nil, with the reason as footer text ("Need 42 more points" / "You're
  holding the maximum"). Tapping shows a confirmation dialog before spending.
  Match existing header styling (`.luminaLabel`, `luminaOnSurfaceVariant`).
- **`TodayView` "Streak Lost" alert**: if the user has 0 savers and
  `canBuySaver`, show **Buy & Restore (150 pts)**, which calls `buySaver` then
  `restoreStreak`. Existing "Restore Streak (n left)" and "Dismiss" unchanged.
- New user-facing strings go through the app's localization the same way as
  other strings (see the in-app language switching notes: `String`-typed `Text`
  props are not localized, so use `LocalizedStringKey`).

### 4. Sync and export

- `RemoteProfile` / upload in `SessionRecorder.record()` and the pull in
  `RootView.pullRemoteProfile()`: add `points_spent` and `streak_freeze_tokens`.
  Pull merges with max for both.
- **Supabase migration:** add `points_spent int not null default 0` and
  `streak_freeze_tokens int not null default 0` to `profiles`. The migration
  file is written but **not applied** without explicit user approval.
- Buying a saver must upload the profile promptly (not only after the next
  session), otherwise a purchase on one device is invisible to another until
  then. Call the same upload used by `SessionRecorder` after a purchase.
- `DataExportView`: add `pointsSpent` to the CSV and JSON exports.

## Error handling and edge cases

- Purchase attempted while offline: works locally; the upload is retried by the
  existing sync path.
- Two devices buy at once: both increments of `pointsSpent` cannot be summed by
  a max merge, so one purchase can be lost in the merge. Accepted for v1; the
  worst case is the user keeps a saver they paid for once. Noted for follow-up.
- `spendablePoints` clamps at 0 if a merge briefly makes `pointsSpent` exceed
  `totalPoints`.

## Testing

Swift Testing cases in `GamificationServiceTests`:

- buy succeeds and deducts 150 / adds one saver
- buy fails with insufficient points (no state change)
- buy fails at cap (no state change)
- two consecutive buys, then a third blocked at the cap
- `totalPoints` and badge eligibility unchanged after buying
- free token is skipped at the cap; session counter still resets
- `saverPurchaseBlockReason` values
- `dedupe` sums `pointsSpent`

Manual: verify the settings section and the alert in the simulator using the
repo's `verify` skill (launch-arg state injection).

## Files touched

`Models/UserProfile.swift`, `Services/GamificationService.swift`,
`Views/Profile/ProfileSettingsTab.swift`, `Views/Home/TodayView.swift`,
`Services/SupabaseDTOs.swift`, `Services/SessionRecorder.swift`,
`Breath__Relax___StretchApp.swift`, `Views/Profile/DataExportView.swift`,
a new Supabase migration, and `GamificationServiceTests.swift`.

## Amendments (found while writing the plan)

- **Saver count is not max-merged.** `streakFreezeTokens` goes down when a saver
  is used, so the "max wins" pull merge would resurrect used savers. Instead the
  remote count is adopted only on a brand-new device (no local progress);
  otherwise the local value is authoritative and is uploaded. `pointsSpent`
  (monotonic) is max-merged as designed.
- **Migration location.** The repo has no migrations folder; schema changes are
  appended to `supabase_schema.sql` as `alter table … add column if not exists`.
  The new lines are written there and not applied.
- **Sync fields are optional** on `RemoteProfile` (`nil` is omitted from the
  upload body) so older rows/clients neither fail to decode nor overwrite the
  values.
- The existing test `freezeTokensAccumulateUncapped` is renamed to
  `freezeTokensAccumulateUpToCap`; its expectation (3 after 21 sessions) is
  unchanged.
