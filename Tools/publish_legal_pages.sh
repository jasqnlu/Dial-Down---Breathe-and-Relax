#!/bin/bash
# Publishes the app's bundled legal pages to the GitHub Pages site
# (https://jasqnlu.github.io/Dial-Down---Breathe-and-Relax/), served from
# the `gh-pages` branch. The in-app copies in "Breath - Relax & Stretch/Legal"
# are the single source of truth: run this after editing any of them so the
# hosted Privacy Policy URL (used in App Store Connect) never drifts.
#
#   Tools/publish_legal_pages.sh            # publish
#   Tools/publish_legal_pages.sh --dry-run  # show what would change
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
LEGAL="$ROOT/Breath - Relax & Stretch/Legal"
SITE="https://jasqnlu.github.io/Dial-Down---Breathe-and-Relax"
DRY_RUN=${1:-}

WT=$(mktemp -d)
git -C "$ROOT" fetch -q origin gh-pages
git -C "$ROOT" worktree add -q --detach "$WT" origin/gh-pages
trap 'git -C "$ROOT" worktree remove --force "$WT"' EXIT

cp "$LEGAL/PrivacyPolicy.html" "$WT/privacy.html"
cp "$LEGAL/TermsOfUse.html"    "$WT/terms.html"
cp "$LEGAL/Credits.html"       "$WT/credits.html"
cat > "$WT/index.html" <<'HTML'
<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Dial Down – Breathe and Relax</title>
<style>:root{color-scheme:light dark}body{font:1em -apple-system,BlinkMacSystemFont,"Helvetica Neue",Arial,sans-serif;line-height:1.6;margin:0;padding:24px 20px}</style></head>
<body><h1>Dial Down – Breathe and Relax</h1>
<ul><li><a href="privacy.html">Privacy Policy</a></li><li><a href="terms.html">Terms of Use</a></li><li><a href="credits.html">Credits</a></li></ul></body></html>
HTML

cd "$WT"
if git diff --quiet; then
  echo "Site already matches the app's legal pages."
  exit 0
fi
git --no-pager diff --stat
if [ "$DRY_RUN" = "--dry-run" ]; then
  echo "(dry run, nothing published)"
  exit 0
fi

git add privacy.html terms.html credits.html index.html
git commit -q -m "Sync legal pages from $(git -C "$ROOT" rev-parse --short HEAD)"
git push -q origin HEAD:gh-pages
echo "Published. GitHub Pages rebuilds in about a minute:"
echo "  $SITE/privacy.html"
