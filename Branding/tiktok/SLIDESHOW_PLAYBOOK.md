# Dial Down TikTok slideshow playbook

How to make a TikTok photo carousel for Dial Down in the "7 weird habits that feel illegal but actually work"
format. `slide-show 1/` is the reference build. Its source is `Tools/branding/tiktok_slideshow_1/`: copy that,
don't start from scratch.

## What's in this folder

| Folder | Format | Built by |
|---|---|---|
| `slide-1.png` … `slide-7.png` (root) | Set 1: app screenshots in phone frames, centred headlines | `Tools/branding/build_tiktok_slides.py` (PIL) |
| `sentences/` | Set 2: designed slides, an app crop stands in for a word | `Tools/branding/build_tiktok_sentences.py` |
| `slide-show 1/` | Native "7 weird habits" listicle (**use this format**) | `Tools/branding/build_tiktok_slideshow_1.py` |
| `slide-show 2/`–`4/` | Style tests on the same skeleton (see "Style tests" below) | same script, `--page tiktok_slideshow_N/slides.html` |

## Style tests

Sets 1–4 each change the caption style (and sets 3–4 the structure) so viewership can show what works. Post them
under the same conditions (similar time of day, same account, a trending sound) and compare swipe-through and
saves, not only views. Record results here and make the winner the default.

Day 1 (all posted 2026-10-15, 5–6 PM): the outline and boxed TikTok Sans styles beat the shadow-only ones (2, 4)
on like rate. Sets 5–8 branch off the two leaders (3 and 1). One day of a few hundred views is a weak signal, so
re-check after a week.

| Set | Topic / structure | Caption style | Font | Results |
|---|---|---|---|---|
| 1 | stress relief · "7 weird habits" listicle | Classic: white, 7px black outline | TikTok Sans 600 | Day 1: 129 views, 5 likes (3.9%); Oct 20: 129 views, 5 likes |
| 2 | sleep · "7 weird habits" listicle | Typewriter: white, soft shadow, no outline | Courier Prime 700 | Day 1: 96 views, 2 likes (2.1%); Oct 20: 96 views, 2 likes |
| 3 | desk worker · POV + numbered tips | Background: black text on white rounded boxes | TikTok Sans 600 | Day 1: **206 views, 7 likes** (3.4%), best; Oct 20: 206 views, **7 likes**, most likes |
| 4 | body check · hook question + release per slide | Serif: white, soft shadow, release in italic | Playfair Display 600 / 500 italic | Day 1: 140 views, 3 likes (2.1%); Oct 20: 144 views, 3 likes |
| 5 | work from home · POV + numbered tips (branch of 3) | Background boxes | TikTok Sans 600 | Oct 20: 122 views, 0 likes |
| 6 | studying · POV + numbered tips (branch of 3) | Background boxes | TikTok Sans 600 | Oct 20: 117 views, 1 like |
| 7 | work stress · "7 weird habits" listicle (branch of 1) | Classic outline | TikTok Sans 600 | Oct 20: 265 views, 4 likes |
| 8 | posture · "7 weird habits" listicle (branch of 1) | Classic outline | TikTok Sans 600 | Oct 20: 230 views, 2 likes |
| 9 | work stress · bad-email reset, 3 actions + app (5 slides) | Classic outline | TikTok Sans 600 | Oct 20: 208 views, 1 like |
| 10 | desk/posture · "pick the one you need", 3 labelled options + app (5 slides) | Classic outline + bold label line | TikTok Sans 600/700 | Oct 20: 91 views, 0 likes |
| 11 | after-work reset · timestamped routine, 4 steps + app (6 slides) | Background boxes + bold timestamp box | TikTok Sans 600/700 | Oct 20: 9 views, 0 likes |
| 12 | box breathing · one-technique tutorial, one phase per slide + app (7 slides) | Classic outline + giant outlined count ("4", 440px) | TikTok Sans 600/700 | Oct 20: 0 views, 0 likes |
| 13 | work stress · "before the reply", 5 slides, no app slide | Classic outline (2–3 lines) | TikTok Sans 600 | Oct 20: 228 views, 1 like |
| 14 | desk/movement · wall-check follow-up, 5 slides + app as slide 6 | Classic outline (2–3 lines) | TikTok Sans 600 | Oct 20: **408 views**, 3 likes, most views |
| 15 | work stress · after the meeting, shoulders, 5 slides + app as slide 6 | Classic outline (2–3 lines) | TikTok Sans 600 | Oct 20: 165 views, 0 likes |
| 16 | desk job · three numbered desk checks, 5 slides + app as slide 6 | Classic outline (2–3 lines) | TikTok Sans 600 | Oct 20: 133 views, 0 likes |
| 17 | wall check step by step, 5 slides + app (branch of 14) | Classic outline (2–3 lines) | TikTok Sans 600 | |
| 18 | meetings · "7 weird habits" listicle (branch of 7) | Classic outline | TikTok Sans 600 | |
| 19 | calls all day · POV + numbered tips (branch of 3) | Background boxes | TikTok Sans 600 | |
| 20 | work stress · "before i open my inbox", 5 slides + app (branch of 13 + 14) | Classic outline (2–3 lines) | TikTok Sans 600 | |
| 21 | neck · "7 weird habits" listicle (branch of 8) | Classic outline | TikTok Sans 600 | |
| 22 | afternoon slump · "7 weird 3pm habits" listicle (branch of 1) | Classic outline | TikTok Sans 600 | |
| 23 | lower back · "7 weird habits" listicle (branch of 8) | Classic outline | TikTok Sans 600 | |
| 24 | hips from sitting · POV + numbered tips (branch of 3/19) | Background boxes | TikTok Sans 600 | |
| 25 | after work · "what i do in the car", 5 slides + app (branch of 13/20) | Classic outline (2–3 lines) | TikTok Sans 600 | |
| 26 | shoulders · "7 weird habits" listicle (branch of 8/15) | Classic outline | TikTok Sans 600 | |
| 27 | work stress · POV "quick chat" + numbered tips (branch of 3) | Background boxes | TikTok Sans 600 | |
| 28 | wrists/typing · "7 weird keyboard habits" listicle (branch of 16) | Classic outline | TikTok Sans 600 | |
| 29 | calls · 2 minute reset between calls, 5 slides + app (branch of 14/19) | Classic outline (2–3 lines) | TikTok Sans 600 | Oct 30: 84 views, 0 likes |
| 30 | sunday night · "7 weird sunday night habits that make monday easier" (hook wording test) | Classic outline | TikTok Sans 600 | |
| 31 | mobility · "7 weird things physios do" listicle (branch of 1/8) | Classic outline | TikTok Sans 600 | Oct 30: 165 views, 2 likes |
| 32 | morning · "7 weird morning habits" listicle, new noun (branch of 1/8) | Classic outline | TikTok Sans 600 | Oct 30: 89 views, 1 like |
| 33 | sleep · "7 weird sleep habits" listicle (branch of 1/8); redo of set 2 in the classic style | Classic outline | TikTok Sans 600 | Oct 30: 116 views, 1 like |
| 34 | tight hips · "7 weird hip habits" listicle (branch of 1/8); classic version of set 24 | Classic outline | TikTok Sans 600 | Oct 30: 162 views, 0 likes; Oct 31: 162 views, 0 likes |
| 35 | legs/hamstrings · "7 weird leg habits" listicle (branch of 1/8) | Classic outline | TikTok Sans 600 | Oct 30: 178 views, 1 like; Oct 31: 179 views, 1 like |
| 36 | upper back · "7 weird back habits" listicle (branch of 1/8) | Classic outline | TikTok Sans 600 | Oct 30: **208 views**, 2 likes, best of 30–36; Oct 31: **210 views, 2 likes**, best of 34–40 |
| 37 | feet & ankles · "7 weird foot habits" listicle (branch of 34–36) | Classic outline | TikTok Sans 600 | Oct 31: 154 views, 1 like |
| 38 | glutes · "7 weird glute habits" listicle (branch of 34–36) | Classic outline | TikTok Sans 600 | Oct 31: 123 views, 1 like |
| 39 | spine · "7 weird spine habits" listicle (branch of 34–36) | Classic outline | TikTok Sans 600 | Oct 31: 176 views, 0 likes |
| 40 | general · "7 weird stretching habits", chest openers (branch of 36's doorway) | Classic outline | TikTok Sans 600 | Oct 31: 138 views, 0 likes |
| 41 | chest · "7 weird chest habits" listicle (branch of 36) | Classic outline | TikTok Sans 600 | |
| 42 | hamstrings · "7 weird hamstring habits" listicle (branch of 35) | Classic outline | TikTok Sans 600 | |
| 43 | desk · "7 weird desk habits", chair stretches (branch of 36 + early desk winners) | Classic outline | TikTok Sans 600 | Nov 1: 114 views, 0 likes |
| 44 | arms/wrists · "7 weird arm habits" listicle (branch of 36) | Classic outline | TikTok Sans 600 | Nov 1: 108 views, 0 likes; Nov 2: 111 views, 0 likes |
| 45 | calves · "7 weird calf habits" listicle (branch of 35/37) | Classic outline | TikTok Sans 600 | Nov 1: 116 views, 1 like; Nov 2: **125 views, 1 like**, best of 44–50 |
| 46 | quads · "7 weird quad habits" listicle (branch of 35) | Classic outline | TikTok Sans 600 | Nov 1: 113 views, 0 likes; Nov 2: 118 views, 0 likes |
| 47 | posture · "7 weird posture habits" v2, everyday cues (branch of 8) | Classic outline | TikTok Sans 600 | Nov 2: 99 views, 0 likes |
| 48 | work stress · "7 weird work stress habits" v2 (branch of 7) | Classic outline | TikTok Sans 600 | Nov 2: 109 views, 1 like |
| 49 | core · "7 weird core habits", new body-part noun (branch of 35/36) | Classic outline | TikTok Sans 600 | Nov 2: 0 views (7th post that day; see results check) |
| 50 | couch · "7 weird couch habits", place-based noun (branch of 45's water-bottle caption) | Classic outline | TikTok Sans 600 | Nov 2: 0 views (8th post that day; see results check) |
| 51 | kitchen · "7 weird kitchen habits", place-based noun (branch of 45's water bottle) | Classic outline | TikTok Sans 600 | |
| 52 | stairs · "7 weird stair habits", place-based noun (branch of 45/46) | Classic outline | TikTok Sans 600 | |
| 53 | bed · "7 weird bed habits", in-bed stretches, pet photos (branch of 46's lie-on-your-side caption) | Classic outline | TikTok Sans 600 | |
| 54 | wall · "7 weird wall habits" (branch of 14, the all-time best) | Classic outline | TikTok Sans 600 | |
| 55 | shower · "7 weird shower habits", place-based noun (branch of 51–54) | Classic outline | TikTok Sans 600 | |
| 56 | car · "7 weird car habits", parked-car resets (branch of 25's car story) | Classic outline | TikTok Sans 600 | |
| 57 | floor · "7 weird floor habits", floor stretches, pet photos (branch of 53) | Classic outline | TikTok Sans 600 | |
| 58 | towel · "7 weird towel habits", object noun (branch of 45's water bottle) | Classic outline | TikTok Sans 600 | |
| 59 | pillow · "7 weird pillow habits", in-bed/couch pillow moves, pet photos (branch of 53) | Classic outline | TikTok Sans 600 | |
| 60 | doorway · "7 weird doorway habits", door-frame stretches (branch of 36's doorway caption + 54's wall) | Classic outline | TikTok Sans 600 | |
| 61 | phone · "7 weird phone habits", object noun, phone-posture resets (branch of 45's water bottle) | Classic outline | TikTok Sans 600 | |
| 62 | walking · "7 weird walking habits", everyday-activity noun (branch of 52's stairs + 56's car) | Classic outline | TikTok Sans 600 | |

**Results check (2026-10-30, sets 29 and 31–36):** body-part stretch listicles won again: upper back (36) 208, legs (35)
178, physio (31) 165, hips (34) 162. Sleep (33) 116, morning (32) 89 and the between-calls reset (29) 84 trailed; set 30 wasn't in the screenshot. The top
captions each name one move as "the ___ one" ("the doorway one", "the fold-and-hang one"). Sets 37–40 keep that
recipe with new body parts. Keep captions in that "the ___ one" form.

**Results check (2026-10-31, sets 34–40):** upper back (36) still leads at 210 views / 2 likes, then legs (35) 179,
spine (39) 176, hips (34) 162, feet (37) 154. The broad "stretching" noun (40) got 138 and glutes (38) 123, so a
specific body-part noun beats a general one. Sets 41–46 stay on specific nouns and branch off 35/36.
Openverse search was down (504s) when they were built; their new photos came straight from the WordPress Photo
Directory API (all CC0), the rest are reused from earlier sets.

**Results check (2026-11-01, sets 43–46):** all four flat at 108–116 views (calves 116 / 1 like, desk 114, quads 113,
arms 108), below 34–40. They went up 10:30–10:34, one to four minutes apart, yet landed at almost the same number,
so there's no clear sign that close posting hurt them. Narrow body-part nouns seem to be wearing out. Sets 47–50 go back to the all-time top
topics with fresh moves (posture, set 8; work stress, set 7), try one new body part (core) and one place-based noun
(couch) after the water-bottle caption got the batch's only like. **Spacing is unproven:** the only evidence for
spacing posts out is sets 11/12 (2 posts), and the owner saw fewer views when posting an hour apart. Test it: post 2
of these sets close together and 2 an hour or more apart, then compare 24 h views. Openverse
was still down; photos came from the WordPress Photo Directory API. Apply EXIF rotation when saving those: phone
photos come in sideways otherwise.

**Results check (2026-11-02, sets 44–50):** everything that got distributed sits at 99–125 views: calves (45) 125 / 1 like,
quads (46) 118, arms (44) 111, work stress v2 (48) 109 / 1 like, posture v2 (47) 99. Core (49) and couch (50) got **0 views**.
Sets 43–46 went up ~10:30 AM Nov 1 and 47–50 at ~10:05 PM, so 49 and 50 were the 7th and 8th posts of the same day,
while 47 and 48 (5th and 6th, posted in the same minute as 49/50) did get views. That fits a **daily cap of about 6 posts**
better than "no more than 4 at once". Until it's disproven: post at most 4 a day, and re-post 49 and 50 on a later day
rather than counting them as flops. The best captions of the batch name an everyday object or place ("the water bottle
one", "lie on your side ... before you fall asleep"), so sets 51–54 test place/object nouns: kitchen, stairs, bed, wall.
Openverse was still down; all their photos are new, from the WordPress Photo Directory API.
Sets 55–58 (2026-11-03) carry on the place/object test with shower, car, floor and towel. Openverse was back up;
their photos mix Openverse picks (rawpixel, StockSnap) with WordPress Photo Directory ones.
Sets 59–62 (2026-11-04) add pillow, doorway, phone and walking. Openverse was down again (HTTP 500), so all their
photos are new WordPress Photo Directory picks (checked against every earlier set's `credits.json` for reuse).

Sets 13–16 are the four carousel tests in `~/Documents/Codex/2026-10-16/ope/outputs/four-carousel-tests.md`
(copy and captions verbatim from there). Log results at 4 h, 24 h and 7 days, per platform, as that file describes.

**Results check (2026-10-20, all 16 sets):** desk, work-stress and posture topics took the top six by views
(14, 7, 8, 13, 9, 3). Sleep (2), WFH (5) and studying (6) lagged. Set 3's boxed POV tips still has the most likes;
the first-person story sets (13–16) pull views but few likes. Sets 11 and 12 (9 and 0 views) went up one minute
apart. That might be back-to-back posting or their content; 2 posts can't tell them apart.
Sets 17–22 each branch off one of the winners.

Sets 9–10 are the carousel half of a 4-post batch (the other two, a wall-check attempt and a post-meeting shoulder
reset, are 10–15 s videos filmed by hand). For this batch, record 4 h and 24 h views, average watch time,
completion and saves per post. It tests concepts and formats together, so it won't isolate which change caused a result.

Shadow-only styles (2, 4) need dark or evenly toned photos behind the text. The boxed style (3) works on anything,
including bright office shots.

## Why this format

It copies a viral pattern (@scratch.ai's "7 weird golf habits that feel illegal but actually work") that reads as
creator content, not an ad: real moody photos, captions in TikTok's own text style, and the product appearing only
as the last "habit". Polished ad styling (brand colours, layouts, logos on every slide) breaks the illusion and
lowers swipe-through. Keep it native.

## Anatomy: 8 slides

1. **Hook.** One striking photo. Two centred lines: `7 weird <noun> habits that / feel illegal but actually work`.
   Use a noun before "habits" ("stress relief", "posture", "sleep"), not an adjective ("relaxing" read as soft).
2. **Slides 2–7: one habit each.** Full-bleed photo, two lowercase lines, no number on the slide.
3. **Slide 8: the app, as habit 7.** Blurred photo, app icon, `7`, a seven-line paragraph in sentence case,
   `which one will you try` larger, then a real app screenshot in a rounded card.

## Copy rules

- Lowercase, no full stops, like someone typed it in TikTok. Each line ≤ ~24 characters at 60px (about 820px wide).
  Split at a natural phrase break and never strand a word at a line end ("unclench your jaw every / time…" was wrong).
- **Habits must be real and safe.** Commonly recommended techniques, phrased to sound odd: cyclic sighing ("sigh out
  loud on purpose"), box breathing ("breathe in a square like a navy seal"), humming on the exhale, legs up,
  jaw unclenching, pec stretch for upper back. No medical claims, no "cures", nothing risky.
- **App claims only from verified facts.** Check the code before adding any new one. Source paths below are
  inside the `Breath - Relax & Stretch/` app folder; screenshots are in `AppStoreScreenshots/6.9-inch/`.

| Fact | Source |
|---|---|
| Free, no subscriptions or in-app purchases | `Legal/TermsOfUse.html` §3 |
| 326 stretches, 46 breathing exercises | `Resources/SeedData.json` (`type` field) |
| Median stretch hold 40 s | `SeedData.json` `durationSeconds` |
| Box breathing 4-4-4-4, 5 rounds default (80 s) | `Views/Breathing/BreathingModels.swift` |
| Tap a spot on a 3D body; asks which one if you hit two | body map screenshot `10.12.09 PM` |
| Box, 4-7-8, belly, energising patterns; voice cues | `BreathingModels.swift`, session player |
| "Navy SEALs use box breathing" | `Models/BodyTrivia.swift` |
| Session player counts down every hold for you | `Views/Session/SessionPlayerView.swift` (`secondsRemaining`) |
| "Office Stretches After Work" premade routine, 17 exercises | Routines screenshot `10.14.05 PM` |
| Exercise library sorted into 8 body parts (neck, shoulders, chest, back, core, arms, hips & glutes, legs) | `Models/ExerciseCategory.swift`, exercises screenshot `10.13.10 PM` |

- Run the slide-8 paragraph through the `humanizer` skill so it sounds like a creator. Current version:
  > Start using the Dial Down app. / You tap the spot that's tight / on a 3D body and it pulls up / stretches for
  > that exact spot. / It has box and 4-7-8 breathing too. / It's free, no subscription. / You can get it on the App Store.

## Visual spec (1080×1920)

All values live in `Tools/branding/tiktok_slideshow_1/slides.html`.

| Element | Spec |
|---|---|
| Caption font | TikTok Sans 600 (Google Fonts), white |
| Outline | `-webkit-text-stroke: 7px #000; paint-order: stroke fill;` (stroke draws behind the fill, so letters keep their weight) |
| Habit lines | 60px, centred, `top: 868px` and `top: 993px` (two separate lines, ~125px apart) |
| Hook | 58px, `top: 905px`, line-height 1.16, side insets 70px |
| Slide 8 | icon 190px at top 170 · `7` 56px at 400 · paragraph 45px/1.19 at 488 · ask 70px/700 at 900 · screenshot card 600px wide at top 1000, radius 34px |
| Photos | `object-fit: cover`, no scrims, no filters except slide 8's blur(7px) |

**TikTok safe zones:** the bottom ~25% (y > 1440) is caption and music, and the right column (x > ~940,
y ~900–1500) is like/comment/share. Keep every caption inside x 90–990 and above y 1440. On slide 8, crop the
screenshot so its key content sits at y 1000–1440 (now `margin-top: -482px` opens it on the body-map hotspots).

**Legibility:** the outline handles bright and dark photos, but not busy texture (rain drops, foliage, bright
shoes) directly behind the text. Fix it by choosing or reframing the photo, never with a scrim (scrims look non-native).

## Photos

Use CC0 only, so nothing needs crediting on TikTok. StockSnap, rawpixel and the WordPress Photo Directory have the
warm, filmic lifestyle look. Faceless or back-turned subjects suit the format.

1. Make contact sheets and look at them (scratchpad output):
   ```bash
   python3 Tools/branding/tiktok_photo_hunt.py --out <scratchpad>/hunt "woman stretching" "golden hour" "rainy window" "ocean"
   ```
   Then Read each `sheet-N.jpg`. Search moods and objects, not concepts ("phone in bed", not "jaw tension").
2. Download picks into the set's `photos/` folder. This records the licence in `credits.json`:
   ```bash
   node ~/.claude/skills/design-taste-frontend/scripts/assets.mjs --get <ref from catalog.json> --to Tools/branding/tiktok_slideshow_N/photos --name <name>
   ```

**Gotchas we hit:**
- **rawpixel `image_1300` renditions are watermarked.** Use the `editor_1024` file that `--get` fetches.
- rawpixel serves **WebP bytes even when named `.jpg`**. Convert: `sips -s format jpeg x.webp --out x.jpg`.
- StockSnap free files max out at **960px wide**, so expect a 1.3–1.9× upscale at 1080×1920. TikTok recompresses,
  so it's acceptable, but prefer photos with soft or smooth texture where it shows least (sky, water, haze).
- A photo narrower than 9:16 has no vertical slack under `cover`, so `object-position` can't move it up or down.
  Reframe with `transform: scale(1.3); transform-origin: 50% 0` instead (as on slide 6).
- App screenshot filenames contain a **narrow no-break space (U+202F)** before "PM". URL-encode it as `%E2%80%AF`,
  not `%20`, or the image silently fails to load.

## Build a new set

```bash
cp -R Tools/branding/tiktok_slideshow_1 Tools/branding/tiktok_slideshow_2     # then edit slides.html + photos/
cd Tools/branding
python3 build_tiktok_slideshow_1.py --page tiktok_slideshow_2/slides.html --out "../../Branding/tiktok/slide-show 2"
```

This renders each `<section class="slide">` through headless Chromium (Playwright's, found automatically) and needs
network access for TikTok Sans. Replace or delete the old photos and their `credits.json` entries when you swap them.

## Review loop (do it every time)

1. Tile the renders into one overview image (PIL, 360×640 per slide) and Read it. Then Read each slide at full size.
2. Check: captions in two clean lines, nothing in the safe zones, no watermark, no busy texture behind text,
   photo matches its line, and slide 8's screenshot reads.
3. **Have a subagent review it** against the reference format and this checklist: fidelity to native TikTok text,
   legibility, safe zones, photo quality, copy safety and claims, slide-8 hierarchy. Ask for ranked issues with
   pixel-level fixes plus a "don't change" list. Apply what holds up, say what you skipped and why.
   Tell the subagent not to load any taste skill (`design-taste-frontend` etc.). Those judge websites, and their
   rules (brand polish, layout variety) pull against the native look this format depends on.

## Title and caption (do it every time)

After the review loop, hand the copy to a **subagent** that hasn't seen the drafting. Give it the paths of the
final `slide-N.png` renders and this section, have it Read every slide, and have it write copy based on what the
slides actually show, not on the plan. It must not load any taste skill. Save the result to
`Branding/tiktok/slide-show N/caption.md` (see `slide-show 1/caption.md` for the layout).

- **Title** (≤ 90 characters): the hook made shorter, in lowercase. Don't repeat the full slide-1 text word for word.
- **Caption**: one or two lowercase lines in creator voice. Point at one particular habit by what it is
  ("the square one"), not by its slide number, and give a soft save or try prompt. No app name, link or
  "download". Slide 8 does the plug, and a sales caption breaks the native illusion.
- **Hashtags**: 4–6, all lowercase, about the topic of the habits (#stressrelief, #breathwork, #boxbreathing,
  #stretching). No medical tags (#anxietycure, #painrelief), no #ad-style or brand tags, no #fyp padding.
- Same safety rules as the slides: no medical claims, and no app facts outside the verified table.
- Ask for two or three options with a recommended one, then pick one and say why.

## Sound

Suggestions only. The sound gets picked in TikTok at posting time, never baked into a file.

- **Feel:** slow, spacey, moody (atmospheric trap or R&B instrumentals in the Don Toliver lane, lo-fi, ambient).
  It should match the dark photos and let people swipe calmly. Avoid hard drops and anything with busy vocals.
- **Prefer what's trending:** a sound on the rise this week, from the sound picker's Trending tab or TikTok
  Creative Center (last 7 days), beats a famous track that peaked months ago.
- **Add it from TikTok's library.** If it gets claimed, the worst case is the audio gets muted. Uploading your own
  copy of a song can get the post taken down.
- **Business account, or no risk wanted:** pick from the Commercial Music Library. Popular label tracks
  (instrumental or slowed uploads included) aren't cleared for promoting an app.

## Don'ts

- Don't fake App Store UI, ratings, review counts or downloads. When Dial Down shows up in App Store search,
  a real search screenshot can replace the slide-8 inset (that's what the reference uses).
- Don't use Apple's "Download on the App Store" badge unless it's the official artwork used per Apple's guidelines.
  The app icon is the safe default.
- Don't add numbers to habit slides, brand colours, logos, or scrims. Don't use people's faces you can't license.
- Don't invent app features or stats. If it isn't in the table above, verify it in the code first.

## Ideas for the next sets

Same skeleton, new noun: "7 weird desk habits…", "7 weird sleep habits…", "7 weird posture habits…",
"7 weird things physios do…". The plug slide can show a different real screen per topic: the breathing screen
for sleep, the exercise library bubbles for desk/posture.
