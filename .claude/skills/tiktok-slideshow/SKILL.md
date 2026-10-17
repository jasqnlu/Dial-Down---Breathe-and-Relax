---
name: tiktok-slideshow
description: Make a Dial Down TikTok photo carousel / slideshow in the native "7 weird habits that feel illegal but actually work" format (real CC0 photos, TikTok-style outlined captions, app pitched as habit 7). Use whenever the user asks for TikTok slides, a carousel, a slideshow for social, or another set like slide-show 1.
---

# Dial Down TikTok slideshow

Read `Branding/tiktok/SLIDESHOW_PLAYBOOK.md` first and follow it. It holds the format, copy rules, verified app
facts, the visual spec, the photo workflow and its gotchas, the build command, and the review loop.

Short version (commands run from the repo root):
1. Copy `Tools/branding/tiktok_slideshow_1/` to `Tools/branding/tiktok_slideshow_N/`, then write a new hook and
   six real, safe habits in its `slides.html`.
2. Find CC0 photos with `Tools/branding/tiktok_photo_hunt.py` and look at the contact sheets. Download picks with
   `node ~/.claude/skills/design-taste-frontend/scripts/assets.mjs --get`.
3. Render:
   ```bash
   python3 Tools/branding/build_tiktok_slideshow_1.py --page Tools/branding/tiktok_slideshow_N/slides.html --out "Branding/tiktok/slide-show N"
   ```
4. Look at every slide, then have a subagent review it against the playbook's checklist and fix what holds up.
5. Have a subagent look at the final renders and write the post's title, caption and hashtags, following the
   playbook's "Title and caption" section. Save them to `Branding/tiktok/slide-show N/caption.md`.

Don't use the taste skills (`design-taste-frontend` or the others) to review slides or write copy. They're built
for websites, not native TikTok posts. Step 2 only runs that skill's `assets.mjs` script as a download tool.
