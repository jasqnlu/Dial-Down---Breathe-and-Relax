-- Breath: Relax & Stretch — Supabase schema
--
-- Paste this whole file into Supabase Dashboard → SQL Editor → New query → Run.
-- Creates all four tables the app talks to (SupabaseService.swift) plus RLS
-- policies, in one shot. After running this, just copy your Project URL and
-- anon key from Dashboard → Settings → API into SupabaseService.swift.
--
-- IDENTITY NOTE: the app identifies users by an anonymous per-install UUID
-- (AuthManager.anonymousID) — author_id / user_id / profiles.id are opaque
-- UUIDs. Emails are NEVER sent to these tables; several of them are publicly
-- readable, so treat every column here as public data.
--
-- SECURITY NOTE (updated 2026-07-06): Supabase Auth is now wired end-to-end
-- for Sign in with Apple — AuthManager exchanges the Apple identity token for
-- a Supabase session (SupabaseService.signInWithApple), persists/refreshes it
-- in the keychain, and attaches it as the Authorization bearer. All write
-- policies below therefore require `auth.uid()` to match the row's owner
-- column. Consequences:
--   • Guests and local email/Google accounts have NO Supabase session: they
--     can read public data but their uploads are rejected (the app treats
--     every upload as best-effort, so nothing breaks client-side).
--   • Rows written under the old anonymous-UUID scheme are orphaned — no
--     token can ever match them. Fine pre-launch; wipe the tables when
--     applying this version of the file.
--   • REQUIRED DASHBOARD STEP: enable the Apple provider under
--     Authentication → Providers, with the app's bundle ID as the client ID,
--     or every token exchange returns 4xx (the app then just stays local).
--
-- The `drop policy if exists` lines migrate a project that ran the previous
-- (anon-writable) version of this file; they no-op on a fresh project.

-- ───────────────────────── exercises ─────────────────────────
-- Public, read-only catalog. The app falls back to its bundled SeedData.json
-- when this is empty or unreachable, so this table is optional — only needed
-- if you want to push catalog updates without an App Store release.

create table if not exists exercises (
  id                 uuid primary key default gen_random_uuid(),
  name               text not null,
  type               text not null,             -- 'stretch' | 'breath' | 'both'
  target_body_parts  text[] not null default '{}',
  duration_seconds   int4 not null,
  difficulty         int4 not null,              -- 1=easy, 2=medium, 3=hard
  instructions       text[] not null default '{}',
  media_url          text,
  caution            text
);

alter table exercises enable row level security;

create policy "exercises are publicly readable"
  on exercises for select
  using (true);

-- No insert/update policy: the catalog is maintained from the dashboard
-- (service role), never by app clients.

-- ───────────────────────── routines ─────────────────────────
-- User-created routines. is_public = true ones show up in BorrowRoutineView.

create table if not exists routines (
  id                 uuid primary key,
  name               text not null check (char_length(name) <= 80),
  exercise_ids       text[] not null default '{}' check (array_length(exercise_ids, 1) <= 50),
  author_id          text check (char_length(author_id) <= 40),   -- anonymous UUID, never an email
  author_name        text check (char_length(author_name) <= 80),
  borrowed_from_id   text check (char_length(borrowed_from_id) <= 40),
  is_public          bool not null default false,
  borrow_count       int4 not null default 0 check (borrow_count between 0 and 1000000)
);

alter table routines enable row level security;

-- Sync engine (2026-09-23): last-write-wins needs a timestamp to compare,
-- and a delete needs a tombstone so a device that missed it doesn't
-- resurrect the row on its next pull. exercise_duration_overrides/
-- is_pinned_to_today/pinned_order are user-editable fields that were
-- missing from this table entirely (pinning/duration edits never had
-- anywhere to sync to). See docs/superpowers/specs/
-- 2026-09-23-routine-session-sync-engine-design.md.
alter table routines add column if not exists updated_at timestamptz not null default now();
alter table routines add column if not exists deleted_at timestamptz;
alter table routines add column if not exists exercise_duration_overrides jsonb not null default '{}'::jsonb;
alter table routines add column if not exists is_pinned_to_today bool not null default false;
alter table routines add column if not exists pinned_order int4 not null default 0;

drop policy if exists "anyone can upsert routines" on routines;
drop policy if exists "anyone can update routines" on routines;
drop policy if exists "authors can insert their routines" on routines;
drop policy if exists "authors can update their routines" on routines;
drop policy if exists "authors can delete their routines" on routines;

-- Reconciled 2026-09-10 against the live project: the policies below (named
-- to match what's actually on the project) restore write access with
-- auth.uid() scoping. Client callers (SupabaseService.uploadRoutine() etc.)
-- do not exist yet — see TODO.md §3 "Restore write paths" — but the RLS
-- side is ready for when they're added.

create policy "public routines are readable by anyone"
  on routines for select
  using (is_public = true);

create policy "Users can read public routines or their own"
  on routines for select
  using (is_public = true or auth.uid()::text = author_id);

create policy "Users can insert their own routines"
  on routines for insert
  with check (auth.uid()::text = author_id);

create policy "Users can update their own routines"
  on routines for update
  using (auth.uid()::text = author_id);

create policy "Users can delete their own routines"
  on routines for delete
  using (auth.uid()::text = author_id);

-- ───────────────────────── sessions ─────────────────────────
-- Completed session history, one row per session, uploaded best-effort.

create table if not exists sessions (
  id                  uuid primary key,
  user_id             text not null check (char_length(user_id) <= 40),  -- anonymous UUID, never an email
  routine_id          text not null check (char_length(routine_id) <= 40),
  started_at          timestamptz not null,
  completed_at        timestamptz,
  completion_percent  float8 not null check (completion_percent between 0 and 100),
  points_earned       int4 not null check (points_earned between 0 and 100000)
);

alter table sessions enable row level security;

drop policy if exists "anyone can insert sessions" on sessions;
drop policy if exists "users can insert their sessions" on sessions;

-- Reconciled 2026-09-10 against the live project: write/read policies below
-- (named to match the live project) are already applied server-side, ahead
-- of the client write path — see TODO.md §3 "Restore write paths".

create policy "Users can insert their own sessions"
  on sessions for insert
  with check (auth.uid()::text = user_id);

create policy "Users can read their own sessions"
  on sessions for select
  using (auth.uid()::text = user_id);

create policy "Users can update their own sessions"
  on sessions for update
  using (auth.uid()::text = user_id);

create policy "Users can delete their own sessions"
  on sessions for delete
  using (auth.uid()::text = user_id);

-- ───────────────────────── profiles ─────────────────────────
-- Public leaderboard rows — only points/streak/minutes/display name.
-- id is the anonymous per-install UUID; emails never reach this table.

create table if not exists profiles (
  id             text primary key check (char_length(id) <= 40),
  display_name   text not null default '' check (char_length(display_name) <= 80),
  total_points   int4 not null default 0 check (total_points between 0 and 100000000),
  streak         int4 not null default 0 check (streak between 0 and 100000),
  total_minutes  int4 not null default 0 check (total_minutes between 0 and 100000000)
);

alter table profiles enable row level security;

create policy "profiles are publicly readable"
  on profiles for select
  using (true);

drop policy if exists "anyone can upsert their profile" on profiles;
drop policy if exists "anyone can update profiles" on profiles;
drop policy if exists "anyone can delete a profile by id" on profiles;
drop policy if exists "users can insert their profile" on profiles;
drop policy if exists "users can update their profile" on profiles;
drop policy if exists "users can delete their profile" on profiles;

create policy "users can insert their profile"
  on profiles for insert
  with check (auth.uid() is not null and id = auth.uid()::text);

create policy "users can update their profile"
  on profiles for update
  using (auth.uid() is not null and id = auth.uid()::text)
  with check (auth.uid() is not null and id = auth.uid()::text);

-- Account deletion is done server-side by the `delete-account` Edge Function
-- (service role). This client delete policy remains for other client paths
-- (e.g. leaving the leaderboard, disabling reminders).
create policy "users can delete their profile"
  on profiles for delete
  using (auth.uid() is not null and id = auth.uid()::text);

-- ───────────────────────── profiles (additions) ─────────────────────────
-- Added 2026-09-12 for streak-about-to-break push notifications. Best-effort
-- upload from SessionRecorder.record() on every completed session.
alter table profiles add column if not exists last_session_at timestamptz;

-- ───────────────────────── push_tokens ─────────────────────────
-- One row per signed-in device. Not publicly readable — only the service
-- role (used exclusively by the send-streak-warnings Edge Function) ever
-- reads this table; RLS still lets an owner manage their own row directly
-- for register/unregister, matching every other write path in this file.

create table if not exists push_tokens (
  user_id         text primary key check (char_length(user_id) <= 40), -- auth.uid(), matches profiles.id
  device_token    text not null check (char_length(device_token) <= 200),
  timezone        text not null default 'UTC' check (char_length(timezone) <= 64), -- IANA name, e.g. "America/Los_Angeles"
  last_warned_date date, -- last local calendar date this user was sent a streak-risk push; prevents double-send
  updated_at      timestamptz not null default now()
);

alter table push_tokens enable row level security;

create policy "users can upsert their own push token"
  on push_tokens for insert
  with check (auth.uid()::text = user_id);

create policy "users can update their own push token"
  on push_tokens for update
  using (auth.uid()::text = user_id)
  with check (auth.uid()::text = user_id);

create policy "users can delete their own push token"
  on push_tokens for delete
  using (auth.uid()::text = user_id);

-- No select policy: nobody needs to read this back through the client API.
-- The Edge Function reads it via the service role, which bypasses RLS.

-- ───────────────────────── get_streak_warning_candidates() ─────────────────────────
-- Per-row IANA-timezone math lives here (not in the Edge Function) because
-- Postgres's `at time zone` handles DST correctly and PostgREST filters
-- can't express "local hour is 20" across arbitrary timezones in one call.
-- security definer + a locked-down search_path so it's safe to run with the
-- privileges of whoever created it (the migration, effectively postgres);
-- execute is revoked from everyone except service_role below, so only the
-- Edge Function (which authenticates as service_role) can call it.
create or replace function get_streak_warning_candidates()
returns table (
  user_id      text,
  device_token text,
  timezone     text
)
language sql
security definer
set search_path = public
as $$
  select pt.user_id, pt.device_token, pt.timezone
  from push_tokens pt
  join profiles pr on pr.id = pt.user_id
  where pr.streak >= 2
    and extract(hour from (now() at time zone pt.timezone)) = 20
    and (
      pr.last_session_at is null
      or pr.last_session_at < date_trunc('day', now() at time zone pt.timezone) at time zone pt.timezone
    )
    and (
      pt.last_warned_date is null
      or pt.last_warned_date <> (now() at time zone pt.timezone)::date
    )
$$;

revoke all on function get_streak_warning_candidates() from public;
grant execute on function get_streak_warning_candidates() to service_role;

-- ───────────────────────── streak-warning cron ─────────────────────────
-- pg_cron/pg_net are available on this plan but not enabled by default.
-- supabase_vault is already enabled — the service-role key must live there,
-- never inlined as a literal in this file, since cron.job definitions are
-- visible to anyone with sufficient database privileges.
create extension if not exists pg_cron;
create extension if not exists pg_net;

-- One-time, run manually via the Dashboard SQL editor (not part of this
-- file, since it's a secret):
--   select vault.create_secret('<service-role-key>', 'service_role_key');

select cron.schedule(
  'streak-warning-check',
  '*/15 * * * *', -- every 15 minutes
  $$
  select net.http_post(
    url := 'https://wmsutfittuxrvcwuywrk.supabase.co/functions/v1/send-streak-warnings',
    headers := jsonb_build_object(
      'Authorization',
      'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key')
    )
  );
  $$
);

-- ──────────────── streak-warning cron (revised 2026-09-12) ────────────────
-- Re-registers the same job name; cron.schedule upserts by name, so this
-- supersedes the block above rather than adding a second job (kept as a
-- separate block, in this file's usual append-only style, so the history of
-- why each change happened stays readable). Two changes:
--
--   1. Sends the x-cron-secret shared secret the Edge Function now requires.
--      The function is deployed with verify_jwt = true, which already blocks
--      anonymous callers, but any signed-in user of the app holds a valid
--      project JWT — this second factor is what makes the endpoint genuinely
--      cron-only, as the spec's security section states.
--   2. timeout_milliseconds := 60000. net.http_post defaults to 5000ms, and
--      the function walks its candidates sequentially (one APNs round trip
--      plus a DB update each), so 5s starts truncating the batch as soon as
--      there are more than a handful of due users.
--
-- Like service_role_key, the secret itself is never in this file. One-time,
-- run manually via the Dashboard SQL editor with a freshly generated random
-- value, then set the SAME value as the function's CRON_SHARED_SECRET secret:
--   select vault.create_secret('<random-secret>', 'cron_shared_secret');
--   supabase secrets set CRON_SHARED_SECRET='<random-secret>' --project-ref wmsutfittuxrvcwuywrk
-- Until both exist the job posts an empty secret and the function answers 401
-- — failing closed, which is the intended behaviour for a missing secret.
select cron.schedule(
  'streak-warning-check',
  '*/15 * * * *', -- every 15 minutes
  $$
  select net.http_post(
    url := 'https://wmsutfittuxrvcwuywrk.supabase.co/functions/v1/send-streak-warnings',
    headers := jsonb_build_object(
      'Authorization',
      'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
      'x-cron-secret',
      coalesce((select decrypted_secret from vault.decrypted_secrets where name = 'cron_shared_secret'), '')
    ),
    timeout_milliseconds := 60000
  );
  $$
);

-- ───────────── RLS perf + correctness fixes (2026-09-15) ─────────────
-- Prompted by `supabase get_advisors` ahead of launch. Two categories:
--
--   1. PERF (auth_rls_initplan, 11 findings across routines/sessions/
--      push_tokens): a bare `auth.uid()` in USING/WITH CHECK is re-evaluated
--      per row scanned; `(select auth.uid())` lets Postgres cache it once per
--      query as an InitPlan instead. No behavior change.
--   2. PERF (multiple_permissive_policies): exercises and routines each had
--      two SELECT policies doing overlapping work (a broad "public" policy
--      and a narrower duplicate) — every extra permissive policy is
--      evaluated on every matching query. Dropped the narrower one in each
--      case since the remaining policy is already a superset.
--
-- Also fixed in the same pass, found while rewriting these: "Users can
-- update their own routines" and "...sessions" had a USING clause but no
-- WITH CHECK. USING only gates which existing rows an UPDATE can target —
-- without WITH CHECK a user could update a row they own and reassign its
-- author_id/user_id to someone else's id, and RLS would not stop the write.
-- Both now carry matching USING/WITH CHECK clauses.
--
-- NOT fixed here: the advisor's `extension_in_public` finding for pg_net.
-- pg_net is not relocatable (`alter extension pg_net set schema` errors with
-- "does not support SET SCHEMA" — same restriction Postgres applies to
-- PostGIS). The real fix is `drop extension pg_net cascade` + recreate in
-- `extensions`, which would drop `net.http_post` out from under the
-- streak-warning-check cron job above until recreated. Confirmed via
-- pg_proc that `net.http_post` already lives in the fixed `net` schema, not
-- `public` — the finding is about the extension's own catalog entry, not an
-- actually-exposed function — so this was left alone as not worth the
-- coordinated downtime pre-launch.
--
-- Applied to the live project as migration rls_perf_and_security_fixes;
-- `supabase get_advisors` (performance) returns zero findings afterward.

drop policy "Anyone can read exercises" on public.exercises;
drop policy "public routines are readable by anyone" on public.routines;

alter policy "Users can read public routines or their own" on public.routines
  using (is_public = true or (select auth.uid())::text = author_id);

alter policy "Users can insert their own routines" on public.routines
  with check ((select auth.uid())::text = author_id);

alter policy "Users can update their own routines" on public.routines
  using ((select auth.uid())::text = author_id)
  with check ((select auth.uid())::text = author_id);

alter policy "Users can delete their own routines" on public.routines
  using ((select auth.uid())::text = author_id);

alter policy "Users can read their own sessions" on public.sessions
  using ((select auth.uid())::text = user_id);

alter policy "Users can insert their own sessions" on public.sessions
  with check ((select auth.uid())::text = user_id);

alter policy "Users can update their own sessions" on public.sessions
  using ((select auth.uid())::text = user_id)
  with check ((select auth.uid())::text = user_id);

alter policy "Users can delete their own sessions" on public.sessions
  using ((select auth.uid())::text = user_id);

alter policy "users can upsert their own push token" on public.push_tokens
  with check ((select auth.uid())::text = user_id);

alter policy "users can update their own push token" on public.push_tokens
  using ((select auth.uid())::text = user_id)
  with check ((select auth.uid())::text = user_id);

alter policy "users can delete their own push token" on public.push_tokens
  using ((select auth.uid())::text = user_id);

-- ───────── Private profiles + opt-in leaderboard (2026-09-19) ─────────
-- Root cause of "Apple accounts don't have their data saved" (see
-- docs/investigations/2026-09-19-apple-account-data-not-saved.md): the live
-- project had RLS policies but NO table privileges for anon/authenticated,
-- and Postgres checks GRANTs before RLS, so every request was a 403 and no
-- policy ever ran. This block restores the grants, and — because names now
-- live in `profiles` — makes that table owner-only instead of public.
--
-- Privacy model:
--   * profiles     PRIVATE. Real name, stats, last_session_at. Only the owner
--                  can read/write their own row; anon has no access at all.
--   * leaderboard  OPT-IN. A row exists only if the user switched it on. It
--                  holds a generated handle plus points/streak/minutes and
--                  never a real name. RLS lets an owner see only their own
--                  row; everyone else reads it through get_leaderboard(),
--                  which does not return user ids.
--   * The streak-warning job keeps working: get_streak_warning_candidates()
--     is SECURITY DEFINER and reads profiles regardless of RLS.

-- 1. Table privileges the existing policies already assume. RLS still scopes
--    every row to its owner; these only let the request reach RLS at all.
grant usage on schema public to anon, authenticated, service_role;

grant select on public.exercises to anon, authenticated;
-- Public routines are readable by anyone (is_public = true); writes are
-- authors only. NOTE: routines.author_name is visible on public routines —
-- never store a real name there when the upload path is built.
grant select on public.routines to anon, authenticated;
grant insert, update, delete on public.routines to authenticated;
grant select, insert, update, delete on public.sessions to authenticated;
grant select, insert, update, delete on public.profiles to authenticated;
grant select, insert, update, delete on public.push_tokens to authenticated;
grant all on all tables in schema public to service_role;

-- 2. profiles: real-name columns (PR #26) and owner-only policies.
alter table profiles add column if not exists first_name text check (char_length(first_name) <= 40);
alter table profiles add column if not exists last_name  text check (char_length(last_name)  <= 40);
-- Streak saver purchases: points_spent only ever grows; tokens are capped at 3.
alter table profiles add column if not exists points_spent int4 not null default 0
  check (points_spent between 0 and 100000000);
alter table profiles add column if not exists streak_freeze_tokens int4 not null default 0
  check (streak_freeze_tokens between 0 and 3);

drop policy if exists "profiles are publicly readable" on profiles;
drop policy if exists "users can read their own profile" on profiles;
drop policy if exists "users can insert their profile" on profiles;
drop policy if exists "users can update their profile" on profiles;
drop policy if exists "users can delete their profile" on profiles;

create policy "users can read their own profile"
  on profiles for select to authenticated
  using ((select auth.uid())::text = id);

create policy "users can insert their profile"
  on profiles for insert to authenticated
  with check ((select auth.uid())::text = id);

create policy "users can update their profile"
  on profiles for update to authenticated
  using ((select auth.uid())::text = id)
  with check ((select auth.uid())::text = id);

create policy "users can delete their profile"
  on profiles for delete to authenticated
  using ((select auth.uid())::text = id);

-- 3. push_tokens: PostgREST upserts are INSERT ... ON CONFLICT DO UPDATE,
--    which needs SELECT on the existing row. Owner-only, so nothing new is
--    exposed; the Edge Function still reads via service_role.
drop policy if exists "users can read their own push token" on push_tokens;
create policy "users can read their own push token"
  on push_tokens for select to authenticated
  using ((select auth.uid())::text = user_id);

-- 4. leaderboard: opt-in, pseudonymous.
create table if not exists leaderboard (
  user_id        text primary key check (char_length(user_id) <= 40), -- auth.uid(); never returned to other users
  handle         text not null check (char_length(handle) between 2 and 32),
  total_points   int4 not null default 0 check (total_points between 0 and 100000000),
  streak         int4 not null default 0 check (streak between 0 and 100000),
  total_minutes  int4 not null default 0 check (total_minutes between 0 and 100000000),
  updated_at     timestamptz not null default now()
);

alter table leaderboard enable row level security;

grant select, insert, update, delete on public.leaderboard to authenticated;

create policy "users can read their own leaderboard row"
  on leaderboard for select to authenticated
  using ((select auth.uid())::text = user_id);

create policy "users can join the leaderboard"
  on leaderboard for insert to authenticated
  with check ((select auth.uid())::text = user_id);

create policy "users can update their leaderboard row"
  on leaderboard for update to authenticated
  using ((select auth.uid())::text = user_id)
  with check ((select auth.uid())::text = user_id);

create policy "users can leave the leaderboard"
  on leaderboard for delete to authenticated
  using ((select auth.uid())::text = user_id);

-- Other users' rows are only reachable through this function, which returns
-- no user ids (is_me marks the caller's own row). security definer so it can
-- read past the owner-only RLS; search_path locked; limit clamped so it can't
-- be used to dump the table in one call; signed-in users only.
create or replace function get_leaderboard(row_limit int default 50)
returns table (
  handle        text,
  total_points  int4,
  streak        int4,
  total_minutes int4,
  is_me         boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select l.handle, l.total_points, l.streak, l.total_minutes,
         l.user_id = (select auth.uid())::text
  from leaderboard l
  order by l.total_points desc, l.updated_at asc
  limit least(greatest(row_limit, 1), 100)
$$;

revoke all on function get_leaderboard(int) from public, anon;
grant execute on function get_leaderboard(int) to authenticated;
