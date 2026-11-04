#!/bin/zsh
# Build the app, install it on an iOS simulator, launch it, and save a
# screenshot — the same steps Claude uses to run the app, with no Xcode
# window or Simulator app needed.
#
# Usage (from anywhere):
#   Tools/run-simulator.sh            # launch on Today, skipping onboarding/sign-in
#   Tools/run-simulator.sh 2          # launch on a tab: 0 Today 1 Body 2 Exercises
#                                     #   3 Breathe 4 Routines 5 Profile
#   FRESH=1 Tools/run-simulator.sh    # wipe the app first and show real onboarding
#   DEVICE="iPhone 17 Pro" Tools/run-simulator.sh
#
# Screenshot lands in build/screenshots/ and opens in Preview.
set -euo pipefail

TAB="${1:-0}"
DEVICE="${DEVICE:-iPhone 17}"
BUNDLE_ID="com.jasonlu.Dial--Down--Breath--Stretch"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="$ROOT/build/sim-derived"
SHOTS="$ROOT/build/screenshots"
cd "$ROOT"

echo "▸ Booting simulator: $DEVICE"
xcrun simctl boot "$DEVICE" 2>/dev/null || true   # already booted is fine
xcrun simctl bootstatus "$DEVICE" -b >/dev/null

echo "▸ Building (first build takes a few minutes)…"
xcodebuild build \
  -project "Breath - Relax & Stretch.xcodeproj" \
  -scheme BreathRelaxStretch \
  -destination "platform=iOS Simulator,name=$DEVICE" \
  -derivedDataPath "$DERIVED" \
  -quiet

APP="$DERIVED/Build/Products/Debug-iphonesimulator/BreathRelaxStretch.app"
[[ -d "$APP" ]] || APP="$(find "$DERIVED/Build/Products/Debug-iphonesimulator" -maxdepth 1 -name '*.app' | head -1)"

if [[ "${FRESH:-0}" == "1" ]]; then
  echo "▸ Removing old install (fresh onboarding)"
  xcrun simctl uninstall "$DEVICE" "$BUNDLE_ID" 2>/dev/null || true
  ARGS=()
else
  # Launch arguments override saved settings for this run only:
  # skip onboarding + the app tour, sign in as a guest, open a tab.
  ARGS=(-hasCompletedOnboarding YES -hasSeenAppGuide YES
        -auth.isSignedIn YES -auth.provider guest -debugInitialTab "$TAB")
fi

echo "▸ Installing and launching"
xcrun simctl install "$DEVICE" "$APP"
xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl launch "$DEVICE" "$BUNDLE_ID" "${ARGS[@]}" >/dev/null

# Show a live window if this Xcode has the Simulator app; otherwise the
# simulator keeps running headless and the screenshot is the way to look.
open -a Simulator 2>/dev/null || echo "  (No Simulator app installed — running headless; see screenshot.)"

sleep 6   # first launch seeds the exercise library
mkdir -p "$SHOTS"
SHOT="$SHOTS/screen-$(date +%H%M%S).png"
xcrun simctl io "$DEVICE" screenshot "$SHOT" >/dev/null 2>&1
echo "▸ Screenshot: $SHOT"
open "$SHOT"
