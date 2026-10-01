# App Store readiness — verified against `main` (2026-09-08)

The repo had a checklist from July 6 (`docs/archive/TODO-2026-07-06.md`) marking a bunch of
compliance items "fixed." This doc re-checked each claim against the actual code as of today
rather than taking it at face value. Some items really are done; a few are worse than the old
doc says; a couple are new discoveries.

## 🚨 Blockers — must fix before submitting

1. ~~Legal documents are still marked as unreviewed placeholders~~ **Fixed 2026-09-08.**
   `Breath - Relax & Stretch/Legal/PrivacyPolicy.html` and `TermsOfUse.html` had the placeholder
   comment removed, the date set to September 8, 2026, and the contact address set to
   `dialdownn@gmail.com`. The privacy stance itself was already accurate before this pass:
   local-first by default (SwiftData, nothing leaves the device unless you sign in), and the
   optional Supabase sync only uploads a display name + points/streak/minutes keyed to an
   anonymous UUID — confirmed by the code comments in `SupabaseService.swift` and
   `PrivacyInfo.xcprivacy` ("no email; id is the anonymous per-install UUID... not used for
   tracking"). `NSPrivacyTracking` is `false` and no tracking domains are declared.
   **Still outstanding:** a human (ideally with legal review) should still read both documents
   end-to-end and confirm the text matches actual behavior at ship time — that hasn't happened,
   only the mechanical de-placeholdering has.

2. ~~Two placeholder App Group IDs still shipping~~ **Moot as of 2026-09-10.** The widget/watch
   idea was dropped entirely — a full 3D body map isn't plausible at home-screen-widget or
   watch-complication scale. `WidgetDataService.swift`, `BreathWidget/`, `BreathWatch/`, and
   `BreathWatchComplication/` were deleted (none were ever wired into an Xcode target, so the
   placeholder App Group ID never shipped anywhere real).

3. ~~StoreKit Configuration scheme step~~ **Moot as of 2026-09-09.** The donation "tip jar"
   (`StoreManager.swift`, `TipJarView.swift`, `Configuration.storekit`, and the scheme's
   StoreKit Configuration references) was removed entirely — the App has no purchases,
   subscriptions, or donation mechanism of any kind. Terms of Use and Privacy Policy were
   updated to say so explicitly.

4. ~~Body-map anatomy assets carry a CC BY-SA 4.0 obligation that isn't visible to users yet.~~
   **Fixed 2026-09-08.** `ASSET_CREDITS.md` (already in the repo) correctly documents that the 3D
   body-map model — derived from Z-Anatomy / BodyParts3D — and every exercise animation rendered
   from it are derivative works requiring attribution, a link to the license, a statement of
   changes made, and share-alike licensing of those specific assets. Two things worth staying
   precise about:
   - **This does *not* mean the app's source code has to be relicensed under CC BY-SA.**
     `ASSET_CREDITS.md` §"On open-sourcing the application" already makes this distinction:
     ShareAlike binds *adaptations of the licensed work itself* (the meshes, JSON metadata, and
     `.mp4` renders) — it has no GPL-style "linking" clause that would reach code merely bundling
     those assets. This project happens to be open source anyway, which independently satisfies
     the license and the Z-Anatomy maintainers' stated wish, but that's a separate, voluntary
     choice from what the license actually requires.
   - **What the license does require was a user-visible attribution, which was missing.** Added
     a `Settings → About → Credits` entry (`ProfileSettingsTab.swift`) that presents a new
     `Breath - Relax & Stretch/Legal/Credits.html` via the existing `LegalDocumentView`/
     `LegalWebView` sheet infrastructure (the same one used for Terms/Privacy). It reproduces the
     Z-Anatomy / BodyParts3D credit, authors table, CC BY-SA 4.0 license link, and "changes made"
     statement from `ASSET_CREDITS.md` §1, plus the Manrope/SIL OFL credit.

- ~~In-app account deletion didn't delete the server account~~ **Code complete 2026-10-01 on branch feature/account-deletion — pending deploy + live test.** The new `delete-account` Supabase Edge Function (`supabase/functions/delete-account/`) revokes Sign in with Apple first (Apple users re-confirm at delete time), then deletes every row the user owns and the Supabase auth user; the app only wipes local data after the server confirms. **Still outstanding:** set the Apple secrets, apply the `reject_missing_owner` trigger block at the end of `supabase_schema.sql` (stops in-flight syncs re-creating rows for a deleted account), deploy the function, and run the live email + Apple deletion tests (see `docs/superpowers/plans/2026-10-01-account-deletion.md` Task 7).

## ⚠️ High-priority, ship-quality risk (not auto-rejected, but will hurt reviews/ratings)

5. ~~Localization is only ~28% complete~~ **Fixed 2026-09-09.** All 369 string-catalog keys now
   have es/fr/zh-Hans translations (100% coverage, up from 109/390). Machine-translated by
   Claude in this pass, not reviewed by a native speaker — that review is still worth doing
   before shipping, especially for the medical-disclaimer and body-map copy, but there is no
   longer any untranslated English text falling through to those locales.

6. ~~Migration still matches exercises by name, just hashed.~~ **Fixed 2026-09-09, narrower
   than it looked.** `SeedMigrator.swift` had already matched by the stable `seedID` (the
   JSON `"id"` field) since v6 — the remaining gap was one line: `seedIfNeeded()`
   (`Breath__Relax___StretchApp.swift`) still set the *actual* `Exercise.uuid` (what
   `Session.exerciseIDs`, `Routine.exerciseIDs`, and Supabase's `RemoteExercise.id` compare
   across devices) from `Exercise.stableSeedUUID(forName:)` — name-derived — instead of the
   seed catalog's own permanent `"id"`. Now it parses that id directly as the uuid, falling
   back to the name-hash only if a seed entry is somehow missing one. Added
   `SeedDataTests.everyExerciseHasAValidUniqueID` to guard the invariant this now depends on
   (every `SeedData.json` entry has a valid, unique `"id"` — verified: all 372 do).

7. **Bundle size on the 3D model — partially improved, not solved.** `BodySkinMuscle.obj` was
   12 MB of full-precision (6-decimal) ASCII floats with no materials/UVs. Trimmed vertex/
   normal precision to 4 decimals (max resulting vertex drift: 0.00005 units on a model 2
   units tall — imperceptible, confirmed against `MuscleNodeNamesTests` and the muscle-hit-
   resolver suite, all still passing) — **~11.6 MB, down from 12 MB**. The bigger win is still
   open: converting to a binary format (`.scn`/`.usdz`) would cut this several times further,
   but requires rewriting `BodyMeshLoader.parseAnatomyOBJ`'s hand-rolled OBJ-text parser to
   load via SceneKit's native scene loader while preserving the 269 named sub-objects
   `MuscleNodeNames.swift` keys hit-testing off — real work, not a mechanical conversion, and
   risks the kind of marking-alignment drift this codebase has hit before.

8. ~~"Female" body-type picker still says "coming soon"~~ **Resolved 2026-09-09.** The gender/
   body-type picker was removed entirely rather than deferred — `GenderPickerPage.swift` is
   deleted, onboarding is now 5 pages, and the "Body Type" picker in Profile → Settings is
   gone. The app always used a single (male) anatomy model regardless of the picker's
   selection, so no behavior changed.

## ✅ Confirmed done since the old TODO (no action needed)

- `PrivacyInfo.xcprivacy` exists in the main app target with correct reason codes.
- Terms/Privacy links are wired correctly.
- Google Sign-In client ID is real (not a placeholder) — `GoogleAuthService.swift:23` has an
  actual `apps.googleusercontent.com` ID.
- Demo videos are now largely wired: 355/372 exercises have `animationName` set (previous
  note had this at 14/207 — big progress).
- HealthKit, Calendar (EventKit), and Face ID usage-description strings are all present and
  specific (not boilerplate) in the build settings' `INFOPLIST_KEY_*` entries.

## Still-pending manual Xcode/account setup (Jason-only, unverifiable from the repo)

- ~~iCloud/CloudKit capability + container~~ **Not needed — doc error, corrected 2026-09-09.**
  TODO.md already recorded the 2026-07-10 decision to use Supabase for sync instead of
  CloudKit; this doc's own list just hadn't been updated to drop it. `ModelConfiguration`
  is already `cloudKitDatabase: .none`. No action here.
- ~~Widget Extension target creation~~ / ~~Apple Watch app target + complication target~~
  **Dropped 2026-09-10** — see blocker #2 above.
- `breath://` URL scheme registration
- Running/re-running `supabase_schema.sql` for the Apple auth provider's tightened RLS
  policies

Capability/entitlement state lives in the Apple Developer account and Supabase dashboard, so
these need a manual pass through Signing & Capabilities before archiving a build.
