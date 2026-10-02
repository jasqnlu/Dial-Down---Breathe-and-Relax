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
<ul><li><a href="support.html">Support</a></li><li><a href="privacy.html">Privacy Policy</a></li><li><a href="terms.html">Terms of Use</a></li><li><a href="credits.html">Credits</a></li></ul></body></html>
HTML
# The App Store "Support URL". Generated here rather than kept in Legal/ so
# it isn't bundled into the app.
cat > "$WT/support.html" <<'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Support – Dial Down</title>
<style>
  :root { color-scheme: light dark; }
  body {
    font: -apple-system-body, -apple-system, BlinkMacSystemFont, "Helvetica Neue", Arial, sans-serif;
    line-height: 1.5;
    margin: 0 auto;
    max-width: 680px;
    padding: 20px 20px 48px;
    color: #1c1c1e;
    background: #ffffff;
  }
  @media (prefers-color-scheme: dark) {
    body { color: #f2f2f7; background: #000000; }
    a { color: #64a8ff; }
  }
  h1 { font-size: 1.4em; margin-bottom: 4px; }
  h2 { font-size: 1.1em; margin-top: 28px; }
  p, li { font-size: 0.95em; }
  .contact { font-size: 1.05em; }
</style>
</head>
<body>
  <h1>Dial Down – Breathe and Relax: Support</h1>

  <p class="contact">
    Questions, bug reports, or feedback? Email
    <a href="mailto:dialdownn@gmail.com?subject=Dial%20Down%20Support">dialdownn@gmail.com</a>.
    We usually reply within a few days.
  </p>
  <p>
    If you're reporting a problem, it helps to include your iPhone or iPad model, its iOS
    version, and the steps that led to the issue.
  </p>

  <h2>Common questions</h2>

  <h3>Do I need an account?</h3>
  <p>
    No. Tap <strong>Start breathing</strong> on the welcome screen to use the app without one.
    Signing in (Apple, Google, or email) backs up your progress so you can restore it on
    another device, and lets you join the optional leaderboard.
  </p>

  <h3>How do I delete my account?</h3>
  <p>
    In the app, go to <strong>Profile → Account → Delete Account</strong>. This permanently
    deletes your account and its data from our servers and erases the app's data on your
    device. If you signed in with Apple, you'll be asked to confirm with Apple first. You can
    also email us to request deletion.
  </p>

  <h3>Reminders aren't arriving</h3>
  <p>
    Check that <strong>Profile → Settings → Reminders → Daily Reminders</strong> is on, and
    that notifications for Dial Down are allowed in the iOS Settings app
    (<strong>Settings → Notifications → Dial Down</strong>).
  </p>

  <h3>Apple Health isn't updating</h3>
  <p>
    Open the iOS Settings app, go to <strong>Privacy &amp; Security → Health → Dial Down</strong>,
    and make sure the data types you want to share are turned on.
  </p>

  <h2>More</h2>
  <ul>
    <li><a href="privacy.html">Privacy Policy</a></li>
    <li><a href="terms.html">Terms of Use</a></li>
    <li><a href="credits.html">Credits</a></li>
  </ul>
</body>
</html>
HTML

cd "$WT"
# Stage first so brand-new pages count as changes (plain `git diff` ignores
# untracked files). Staging in the throwaway worktree is harmless for a dry run.
git add privacy.html terms.html credits.html index.html support.html
if git diff --cached --quiet; then
  echo "Site already matches the app's legal pages."
  exit 0
fi
git --no-pager diff --cached --stat
if [ "$DRY_RUN" = "--dry-run" ]; then
  echo "(dry run, nothing published)"
  exit 0
fi

git commit -q -m "Sync legal pages from $(git -C "$ROOT" rev-parse --short HEAD)"
git push -q origin HEAD:gh-pages
echo "Published. GitHub Pages rebuilds in about a minute:"
echo "  $SITE/privacy.html"
echo "  $SITE/support.html"
