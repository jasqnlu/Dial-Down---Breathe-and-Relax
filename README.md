# Dial Down – Breathe and Relax

A calm iPhone app for breathing, stretching and body awareness. Tap a muscle on a 3D body map, see exactly which stretches work it, and follow guided sessions that pair movement with breath.

*(Formerly "Breath: Relax & Stretch" — the repository and Xcode project still use that name.)*

<p align="center">
  <img src="docs/images/today.png" width="200" alt="Today tab with the daily session and recommendations" />
  <img src="docs/images/body-map.png" width="200" alt="3D body map with muscle regions highlighted" />
  <img src="docs/images/exercise-graph.png" width="200" alt="Exercise library as a node graph" />
  <img src="docs/images/breathing.png" width="200" alt="Guided breathing patterns" />
</p>

## What it does

- **3D body map** — rotate an anatomical figure, tap a region or muscle, and jump straight to the exercises that target it. Mark your problem areas and the app tailors its suggestions.
- **372 exercises** — stretches grouped by Neck, Shoulders, Chest, Back, Core, Arms, Hips & Glutes and Legs. Most include a looping demo video rendered from the same anatomy model, with the working muscles highlighted.
- **Exercise graph** — a zoomable node-graph view of the whole library, alongside search, filters and a "For You" section.
- **Guided breathing** — Box, 4-7-8, Belly and Energising patterns, plus a custom pattern editor, with an animated pacing guide.
- **Session player** — step through a routine with countdowns, side-switch cues for one-sided stretches, optional voice cues and haptics.
- **Routines** — build your own, start from premade ones, share or import a routine, and challenge a friend.
- **Progress** — points, streaks, badges, charts, a flexibility check-in and an opt-in leaderboard. Optional HealthKit and Calendar integration and streak reminders.
- **Sync** — optionally sign in (Apple, Google or email) to back up your sessions and routines and sync them across devices.
- **Yours to keep** — use it without an account, export all your data, or delete your account in-app (Profile → Account), which erases the server copy and revokes Sign in with Apple.
- **Languages** — English, Spanish, French and Simplified Chinese, with an in-app language picker.

## Privacy

Local-first by design. Without an account, nothing leaves the device: sessions, routines, streaks and body-map marks live in SwiftData. Signing in is optional. If you do, your name, progress stats, session history and routines are synced to the backend under your account ID (your email is held by the auth provider), and the opt-in leaderboard shows only a generated nickname. Apple Health data, calendar data, the profile photo and body-map marks never leave the device. No tracking, no ads, no purchases.

- Privacy Policy: [hosted](https://jasqnlu.github.io/Dial-Down---Breathe-and-Relax/privacy.html) · [source](Breath%20-%20Relax%20%26%20Stretch/Legal/PrivacyPolicy.html)
- Terms of Use: [hosted](https://jasqnlu.github.io/Dial-Down---Breathe-and-Relax/terms.html) · [source](Breath%20-%20Relax%20%26%20Stretch/Legal/TermsOfUse.html)
- Support: [jasqnlu.github.io/Dial-Down---Breathe-and-Relax/support.html](https://jasqnlu.github.io/Dial-Down---Breathe-and-Relax/support.html)

## Tech

- **SwiftUI + SwiftData**, no third-party dependencies. Supabase is spoken to over raw `URLSession`.
- **SceneKit** for the 3D body map; the anatomy mesh is parsed off the main thread and hit-tested against muscle proxy volumes.
- **Lumina** — the in-house design system (`Views/Theme/`): dynamic colour tokens, a semantic Manrope type scale, shared card / pill / chip components, Dynamic Type and Reduce Motion support.
- **Auth** — Sign in with Apple, Google, or email, with an optional app lock (Face ID).
- **Sync** — a persisted SwiftData outbox (`SyncOutbox` / `SyncEngine`) pushes routines and sessions when online and pulls and merges them last-write-wins, so the app keeps working offline.
- **Backend** — [Supabase](https://supabase.com): Postgres with row-level security, plus two Deno Edge Functions. `send-streak-warnings` sends scheduled streak-reminder pushes. `delete-account` revokes Sign in with Apple and then deletes the user's rows and auth record, failing closed so nothing is half-deleted. Schema in [`supabase_schema.sql`](supabase_schema.sql).
- **Asset pipeline** — the exercise demo videos are produced by Blender scripts in [`Tools/blender/`](Tools/blender), so they can be regenerated from source.

### Layout

```
Breath - Relax & Stretch/        App target
  Models/                        SwiftData models and domain types
  Services/                      Auth, Supabase, notifications, HealthKit, gamification
  Views/                         Home, BodyMap, Exercises, Breathing, Routines, Session, Profile, Onboarding, Theme
  Resources/                     Seed data, 3D models, demo videos, string catalog
  Legal/                         Privacy Policy, Terms, Credits (bundled HTML; also published to the website)
Breath - Relax & StretchTests/   Unit tests
Breath - Relax & StretchUITests/ UI tests
supabase/                        Edge Functions (Deno) and config
Tools/blender/                   Anatomy export and animation rendering scripts
Tools/publish_legal_pages.sh     Publishes Legal/ and the support page to GitHub Pages
docs/                            Design notes, plans and readiness checklists
```

## Building

Requirements: a recent Xcode with the iOS 26 SDK. The app targets **iPhone, iOS 26.0 and later** (on iPad it runs the iPhone layout).

1. Clone the repo and open `Breath - Relax & Stretch.xcodeproj`.
2. Choose an iPhone simulator and run. The app works offline with no extra setup.
3. To run on a device, or to use Sign in with Apple, set your own Team and bundle identifier under *Signing & Capabilities*.
4. Run the tests from Xcode (⌘U), or with `xcodebuild test` against a simulator destination.
5. Edge Function tests need [Deno](https://deno.com) 2: `cd supabase/functions/delete-account && deno test`.

The Supabase URL and publishable key in `SupabaseService.swift` point at the author's project; row-level security is what protects the data. To use your own backend:

1. Create a Supabase project and run `supabase_schema.sql` in the SQL Editor. The file is applied by hand, so keep the live database in step with it; a missing column once broke routine sync.
2. Enable the Apple auth provider, and swap your URL and key into `SupabaseService.swift`.
3. Deploy the functions with `supabase functions deploy <name>`, and set their secrets with `supabase secrets set`:
   - `delete-account` needs `APPLE_TEAM_ID`, `APPLE_CLIENT_ID` (the bundle ID), `APPLE_SIWA_KEY_ID` and `APPLE_SIWA_KEY_P8` (a Sign in with Apple key).
   - `send-streak-warnings` needs `APNS_AUTH_KEY_P8` and `CRON_SHARED_SECRET`.

### Updating the legal pages

The in-app `Legal/*.html` files are the source of truth for the hosted Privacy Policy and Terms (the URLs App Store Connect uses). After changing one, merge it, then run `Tools/publish_legal_pages.sh` (add `--dry-run` to preview) to update the website on the `gh-pages` branch.

## Project status

Version 1.0 for iPhone was submitted to the App Store in October 2026. A proper iPad layout is planned for a later update. See [`TODO.md`](TODO.md) for other work in progress.

## License

- **Source code** — [Mozilla Public License 2.0](LICENSE). Modified versions of MPL-licensed files must stay under MPL-2.0 when distributed; you can combine them with code under other licenses.
- **Body-map anatomy and exercise animations** — the 3D body map is built from [Z-Anatomy](https://www.z-anatomy.com), which is itself built on [BodyParts3D](https://dbarchive.biosciencedbc.jp/en/bodyparts3d/download.html) (© Kousaku Okubo / DBCLS). Both are licensed **CC BY-SA**, so the meshes, the metadata derived from them, and every exercise video rendered from them are distributed under [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/) rather than MPL-2.0. This covers `Resources/Models3D/`, `Resources/Animations/`, `skinmuscle_node_names.json`, `musclegroup_hitboxes.json` and `Tools/blender/generated/`. The source was modified: skin patches welded into one shell, muscles decimated for mobile, objects regrouped into the app's muscle categories, and the result posed and rendered into the demo loops. Full credits and the list of changes are in [`ASSET_CREDITS.md`](ASSET_CREDITS.md).
- **Typeface** — [Manrope](https://github.com/sharanda/manrope), SIL Open Font License 1.1.

If you fork or redistribute anything derived from the anatomy assets, you must credit Z-Anatomy and BodyParts3D, link the CC BY-SA 4.0 license, say what you changed, and license your derivative under CC BY-SA 4.0 too.
