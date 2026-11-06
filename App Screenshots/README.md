# App Screenshots

Current screens of Dial Down (`seperate-main` restyle), iPhone 17 simulator, dark mode, English.
Captured 2026-11-06 at commit 2d786c9.

| File | Screen |
| --- | --- |
| 01-today | Today tab |
| 02-exercises | Exercises tab (Body view) |
| 03-breathe | Breathe tab |
| 04-routines | Routines tab |
| 05-profile | Profile tab |
| 10-ask-bar | Ask Dial Down: type-or-talk bar |
| 11-ask-side-chat | Ask side chat, routine tray filled by two requests |
| 12-ask-full-screen | Ask chat full screen |
| 13-ask-customize | Customize the Ask routine |
| 14-ask-pill | Ask chat shrunk to a pill |
| 15-ask-closed-badge | Ask chat closed; the button shows the routine's exercise count |

The App Store sets in `AppStoreScreenshots/` are older (2026-10-01) and were not changed.

## Regenerate

```sh
TEST_RUNNER_APP_SCREENSHOTS=1 xcodebuild test \
  -project "Breath - Relax & Stretch.xcodeproj" -scheme BreathRelaxStretch \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:"Breath - Relax & StretchUITests/AppScreenshotsUITests" \
  -resultBundlePath shots.xcresult
xcrun xcresulttool export attachments --path shots.xcresult --output-path shots
```

Each attachment is named after its file here (see `shots/manifest.json`).
