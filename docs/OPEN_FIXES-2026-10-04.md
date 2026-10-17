# Open fixes and verification checklist

Written 2026-10-04. Covers the three issues from the write-up (RLS `WITH CHECK`,
the `send-streak-warnings` edge function, stable exercise UUIDs) plus the
account-deletion hardening from Oct 1. Items are split into what the repo
already contains and what still has to be confirmed or done by hand.

Nothing here was checked against the deployed Supabase project. Every
"unconfirmed" item below needs a person with project access.

## Results, 2026-10-12

Checked against the live project (`wmsutfittuxrvcwuywrk`) with read-only
queries and the Supabase CLI. Ticked boxes below were confirmed in this pass.

**New problem found: the streak-warning cron job is being rejected.** The
vault entry `service_role_key` is 24 characters long and is not a JWT (a
service-role JWT is three dot-separated parts, a few hundred characters). It
was last updated 2026-09-13. Every response `pg_net` still holds (24 calls,
the last six hours) is a gateway 401 `UNAUTHORIZED_INVALID_JWT_FORMAT`, so the
function never runs and no streak warnings are sent. `cron.job_run_details`
says "succeeded" because it only records that the HTTP call was queued.
Fix: store the real service-role key in the vault entry, then watch
`net._http_response` for a 200.

**Fixed 2026-10-12 15:07 UTC.** The vault entry now holds the legacy
service-role JWT. The 15:15 UTC cron run returned 200 `no candidates`, which
also covers caller case 3 (service-role key plus the correct secret).

Confirmed:
- All five UPDATE policies in `public` (`routines`, `sessions`, `push_tokens`,
  `profiles`, `leaderboard`) have a `WITH CHECK` equal to `USING`. RLS is on
  for all six tables.
- Function secrets `CRON_SHARED_SECRET` and `APNS_AUTH_KEY_P8` exist. Vault
  entries `cron_shared_secret` and `service_role_key` exist. The SHA-256 of
  the vault `cron_shared_secret` equals the function secret's digest, so the
  shared secret matches.
- The cron job is the revised one (`x-cron-secret`, 60 s timeout, every 15 min).
- No Authorization header returns 401 from the gateway.
- `reject_missing_owner` is on all five tables; `service_role` has DELETE on
  `leaderboard`.
- Deployed `delete-account` (v4) and `send-streak-warnings` (v10) sources are
  identical to the repo, test files aside.
- Live `routines` and `sessions` columns match `supabase_schema.sql`.
- Seed-uuid fix committed and opened as PR #42; local `main` fast-forwarded;
  unit suite passed (659 tests); a fresh simulator install seeds correctly.
- `xcodecloud/manifest.json` is tracked (in PR #42).

**Live security tests, 2026-10-12 15:46 UTC: 16 of 16 passed.** Two throwaway
accounts, signed up with the public anon key and removed afterwards through
`delete-account`; no users or rows were left behind.
- A user cannot reassign their own routine or session to another user (403,
  SQLSTATE 42501), cannot insert a routine owned by someone else, and cannot
  edit another user's routine. Their own edits still work.
- A signed-in user's JWT gets a 401 from `send-streak-warnings` itself, with
  no `x-cron-secret` or a wrong one.
- After `delete-account`, inserts into `routines`, `sessions` and `profiles`
  with the old token are rejected with SQLSTATE 23503, and a retried delete
  still reports success.
The test script is not in the repo yet.

**Schema drift.** The live `routines` table differs from
`supabase_schema.sql`: `exercise_ids` has no default (file: `default '{}'`),
`author_id` is `NOT NULL` (file: nullable), and `id` defaults to
`gen_random_uuid()` (file: no default). Nothing is exposed by this; the file
does not describe what is deployed.

Still open: the real upgrade-path test, the remapping decision and its
measurement, whether to rotate the shared secret, and merging PR #42.

## Status at a glance

| # | Issue | Code in repo | Live / verified | Remaining |
|---|-------|--------------|-----------------|-----------|
| 1 | RLS missing `WITH CHECK` (`870796c`) | Done | Commit says applied; no rejection test | Write and run a cross-user PATCH test |
| 2 | Edge function open to anyone (`e8ebda4`) | Done | Secrets unconfirmed | Confirm secrets, cron job, signed-in 401 |
| 3 | Unstable exercise UUIDs (`0453e36`, `04965da`) | New installs done; migration inserts fixed but uncommitted | Not tested on a real upgraded install | Commit, decide on remapping old rows |
| 4 | Deleted-account trigger (`3e89b43`) | Done | Commit says it must be applied by hand | Confirm it is applied |

## 1. RLS `WITH CHECK` (`870796c`)

The update policies on `routines`, `sessions` and `push_tokens` now carry a
`WITH CHECK` that matches `USING`, so a user cannot rewrite `author_id` or
`user_id` to someone else's id.

- [x] Confirm the live policies have a `WITH CHECK`:
  ```sql
  select tablename, policyname, cmd, qual, with_check
  from pg_policies
  where schemaname = 'public'
    and tablename in ('routines', 'sessions', 'push_tokens')
    and cmd = 'UPDATE';
  ```
  Every row should have a non-null `with_check`.
- [x] Write a regression test: sign in as user A, PATCH one of A's own routines
  (and one session) with `{"author_id": "<user B id>"}` /
  `{"user_id": "<user B id>"}`, expect a policy-violation error, then confirm
  the row still belongs to A. No such test exists in the repo.
- [x] Review any policy added after Sep 15 (the sync work added columns and
  tables) for the same `USING`-without-`WITH CHECK` pattern.
- [ ] Optional: the `pg_net` `extension_in_public` advisor finding was left
  alone on purpose (not relocatable; dropping it would break the cron job).
  Re-evaluate after launch.

## 2. `send-streak-warnings` lock (`e8ebda4`)

`verify_jwt = true` plus an `x-cron-secret` shared secret. If the function's
secret is unset it answers 500 to everyone, cron included, so a missing secret
silently stops streak warnings.

- [x] Confirm the function secret exists (names only are listed):
  ```sh
  supabase secrets list --project-ref wmsutfittuxrvcwuywrk
  ```
  Look for `CRON_SHARED_SECRET` and `APNS_AUTH_KEY_P8`.
- [x] Confirm the vault entries exist (names only, do not select the values):
  ```sql
  select name from vault.decrypted_secrets
  where name in ('cron_shared_secret', 'service_role_key');
  ```
- [x] Confirm the two secret values match. Easiest check: trigger the cron job
  once and read the function logs; a 401 means they differ or the vault entry
  is missing, a 500 "not configured" means the function secret is unset.
- [x] Confirm the cron job is the revised one (sends `x-cron-secret`, 60 s
  timeout):
  ```sql
  select jobname, schedule, command from cron.job
  where jobname = 'streak-warning-check';
  ```
- [x] Test the three caller cases against the live URL:
  1. No Authorization header: expect 401 from the gateway.
  2. A signed-in user's JWT, no `x-cron-secret`: expect 401 from the function.
  3. Service-role key plus the correct secret: expect 200. Run this one only
     deliberately, since it can send real pushes to due users.
  Only case 1 is recorded in the commit.
- [ ] Rotate the shared secret if it was ever pasted into a chat, terminal
  history or an issue.

## 3. Stable exercise UUIDs (`0453e36`, `04965da`)

Fresh installs seed each exercise with the catalog's permanent `id` as its
UUID. The uncommitted change makes migrations that insert exercises on
upgraded installs do the same (new `Exercise.seedUUID(seedID:name:)` helper,
used in `seedIfNeeded` and in the v4 and v9 inserts in `SeedMigrator.swift`;
4 new tests in `SeedMigratorTests.swift`; full unit suite passed, 659 tests).

- [x] Review the working-tree diff, move it onto a branch, commit, and open a
  PR. Suggested branch name: `fix/migration-seed-uuid`.
  `git switch -c fix/migration-seed-uuid` carries the uncommitted changes.
- [x] Pull `origin/main` (local `main` is 2 commits behind).
- [ ] Test on a real upgrade path: install an older build, create a routine,
  upgrade to this build, and check that migration-added exercises get the seed
  UUID and the routine still resolves.
- [ ] **Decision needed: existing rows.** Installs seeded before the fix, and
  exercises a migration added before this change, still have random IDs. Nothing
  rewrites a stored `uuid`. Options:
  - **Do nothing.** Acceptable if there are no real users with older data, or
    few enough that it does not matter. Note the limitation in any write-up.
  - **Write a remapping migration.** For each row whose `uuid` differs from
    `Exercise.seedUUID(seedID:name:)`, rewrite the uuid and every reference to
    the old one:
    - `Routine.exerciseIDs` and `Routine.exerciseDurationOverrides` keys
    - `Session.exerciseIDs`
    - queued `PendingSyncOp` payloads
    - the matching rows already in Supabase (`routines`, `sessions`)
    Risks: another device that has not migrated yet will push the old ids back
    up, so the remap has to be idempotent and tolerate both id sets for a while.
    Needs its own tests and a dry run.
- [ ] Measure first: count how many exercise rows on a real upgraded install
  have `uuid != seedUUID(...)`. That tells you whether the remap is worth it.

## 4. Deleted-account insert trigger (`3e89b43`) and delete-account function (`49cebe0`)

The trigger stops a still-valid access token from re-creating rows after the
account is deleted. The commit states it must be applied to the live project
by hand.

- [x] Confirm the trigger exists on all five tables:
  ```sql
  select tgrelid::regclass as table_name, tgname
  from pg_trigger
  where tgname = 'reject_missing_owner' and not tgisinternal;
  ```
  Expect 5 rows (`sessions`, `routines`, `profiles`, `push_tokens`,
  `leaderboard`).
- [x] Confirm the `delete-account` function is deployed from the current code
  (retry-safe version from `49cebe0`).
- [x] Confirm `service_role` can reach the leaderboard (`8b78cc6` added the
  grant after the table is created):
  ```sql
  select has_table_privilege('service_role', 'public.leaderboard', 'DELETE');
  ```
- [x] End-to-end test with a throwaway account: delete it, then try to insert a
  row with its old token and expect SQLSTATE 23503.
- [x] Sync was reported broken by a live table missing the sync-engine columns
  (`78baab6`). Confirm the `routines` and `sessions` columns from
  `supabase_schema.sql` exist in the live project.

## Housekeeping

- [x] The `xcodecloud/` folder under `Breath - Relax & Stretch.xcodeproj/xcshareddata/`
  is untracked. Commit it or add it to `.gitignore`.
- [ ] If the write-up is submitted anywhere, keep the limitation about existing
  installs in it unless the remap above is done.
- [x] Re-run the full unit suite after pulling `origin/main`:
  ```sh
  xcodebuild test -project "Breath - Relax & Stretch.xcodeproj" \
    -scheme BreathRelaxStretch \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    -only-testing:"Breath - Relax & StretchTests"
  ```
