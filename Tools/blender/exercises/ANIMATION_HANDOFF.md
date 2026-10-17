# Exercise Animation — Handoff for a New Session

**Last updated:** 2026-10-17 (ankle joint added to the rig; 26 foot/ankle
exercises re-authored and un-flagged — 137 -> 111 `animationIsApproximate`)

## Ankle joint (2026-10-17): `foot.{L,R}` bones, 26 exercises un-flagged

Prompted by a user report that a leg exercise's animation was inaccurate. The
rig had no ankle: each foot was a convex-hull mitt rigidly weighted to the
shin, so every calf/shin/ankle exercise faked the motion with shin or spine
wiggles. Because the mitt was already 100% weighted to one bone, adding a
joint was cheap.

**Rig change (`_lib.py`):**
- `build_armature` adds `foot.L`/`foot.R` (children of the shins). Head = ankle
  pivot at `FR["ankle"]` (0.031 h) / `ANKLE_Y` (0.008 h), measured from the
  mitt: the mitt top sits at y~0, z~0.083 on the 1.916-tall model. Tail toward
  the toes (`TOE_Y`, `TOE_Z`); the figure faces -Y.
- Mitts are rigidly weighted to `foot.*` instead of `shin.*`.
- `MITT_ONLY_BONES` keeps the foot bones OUT of muscle joint-blending and the
  nearest-bone fallback. Without this, `run_supine`'s wide blend
  (`blend_top_k=3`) gave shin muscles a foot share, which changed bent-knee
  deformation in older supine clips.
- `pin_below_ankle` moves muscle vertices below the ankle pivot onto the foot
  bone (the long toe tendons + Achilles insertion are tagged as shin muscles
  and poked out like bristles when the foot rotated). It is opt-in via
  `pin_feet=uses_feet(cfg)`, so it only runs for scripts that pose `foot.*`.
  Applying it everywhere dropped a small thigh weight share near the ankle and
  shifted the posed bounds, and so the camera framing, of older clips by up
  to 4.6 cm.
- `run_seated` gains opt-in `CENTER_ON_POSE`: aims the camera at the posed
  body rather than the world origin. Long-sit poses (legs straight out) had
  their feet cropped off the frame edge, including in the previously
  shipped towel calf-stretch clips.

**Regression check:** old vs new `_lib.py` stills for standing, seated,
supine, supine-figure-4 (wide blend), quadruped and bridge. Standing/seated/
bridge are pixel-identical; the others differ by <=44 pixels at <=7/255
(float noise from the extra bone in the chain), with identical posed bounds.

**Sign convention (numerically probed):** `foot.*` local X: **negative =
dorsiflex (toes up), positive = point**. Leg bones all share world-X as
their local X, so `foot = -(thigh + shin)` keeps a planted foot flat. Local Z
swings the toes sideways (`+Z` on `foot.R` = toes toward subject's right).

**The 26 re-authored scripts** (all un-flagged, callouts removed from
SeedData.json; v10/v12 sync clears them on existing installs, see
`SeedMigratorTests.v10AndV12ClearFixedAnimationsMessaging`):
Ankle Alphabet + Shin & Ankle Mobiliser (now seated on a chair with the
foot lifted, ankle circle), Ankle Circles L/R (long-sit, leg lifted, ankle
circle), Step-Edge Calf Drop L/R + Stair-Edge Calf Stretch L/R (heel drops),
Standing Ankle Dorsiflexion L/R (back shin tilts forward over a flat foot,
both feet kept level), Standing Tibialis Raise (toes lift, shins still),
Seated Assisted Tibialis L/R + Seated Shin Stretch with Strap L/R (foot
points), Cross-Legged Shin Pull L/R + Plantar Fascia L/R + Seated Calf
Stretch with Towel L/R + Seated Toe-to-Shin L/R (foot dorsiflexes), Seated
Foot Flex-and-Point (shins still, feet alternate), Incline Board (feet held
dorsiflexed), Downward Dog Calf Pump (bent side heel lifts, straight side
presses). Two unflagged duplicates ("Seated Calf Stretch with Towel
(Left/Right)") share the towel clips and get the fix for free.

**Still not fixable on this rig:** toes/fingers (no digit geometry, the mitt is
a hull), hands touching the body, shoulder-blade motion (no clavicle/scapula).
A wrist joint looks feasible the same way (probe 2026-10-17: the hand mitt bends
cleanly, but the finger tendons are tagged "Forearm" and need the same
below-the-joint pinning); that would cover about 11 more exercises.

## Accuracy re-audit (2026-09-05)

User asked to scan every exercise flagged `animationIsApproximate` (137 of
355 animated exercises) for animations that don't actually match what
they're supposed to look like, and to try alternate motions/cameras to fix
any that are genuinely broken (vs. leaving deliberate rig-limitation
approximations alone).

**Method:** for each flagged exercise's shipped mp4, extracted grayscale
stills at 4 points around the loop (2%/25%/50%/75%) and computed a
pairwise pixel-diff score — a cheap proxy for "does this clip actually show
visible motion." Sorted ascending and visually reviewed every clip scoring
low, cross-referencing this doc's existing catalogue of accepted rig
limitations (no independent ankle/toe joints, no scapula, the breathing
chest-scale composition) before treating anything as a bug.

**3 exercises were genuine no-op renders, not accepted approximations —
fixed and re-rendered:**

- **`shoulder_pendulum_swing_left` / `_right`** — the working arm's swing
  (20-35deg pitch off a straight-down rest) was invisible: `CAMERA_AZIMUTH =
  90` (side view) put the swinging arm behind the torso silhouette while the
  static, more-extended support arm (raised -70deg toward camera) dominated
  the frame. A rest/mid/peak contact sheet showed 3 visually identical
  frames despite different keyframe data. Fixed by roughly doubling the
  swing amplitude (see each script for exact values) and moving the camera
  to a 3/4 oblique (azimuth 40 for `_left`, mirrored to 320 for `_right` so
  the working arm stays on the open-background side rather than swapping
  which arm it hides behind). Confirmed real motion afterward via pixel diff
  and by eye.
- **`standing_lumbar_side_glide_lateral_shift`** — a 10deg `spine` local-Z
  side-bend (the documented proxy for a lateral pelvis shift this rig can't
  translate) was too small to read in the rendered clip; front-camera
  rest/peak stills were visually indistinguishable. Bumped to 20deg, within
  `left_standing_side_bend.py`'s already-proven visible range (12-28deg) for
  this exact bone/axis. Confirmed visible lean afterward.

**Everything else scoring low on the pixel-diff triage was reviewed and
left alone as a legitimate accepted approximation, not a bug:** the whole
foot/ankle/toe family (Ankle Alphabet, both Ankle Circles for Tibialis
Release, Shin & Ankle Mobiliser, both Kneeling Arch Stretch Toes Curled
Under, both Toe Spread & Stretch, both Plantar Fascia Stretch, both Big Toe
Extension, Towel Scrunch, Standing Tibialis Raise, Standing Toe Curl Towel
Grip, Seated Foot Flex-and-Point Flow, both Step-Edge Calf Drop / Stair-Edge
Calf Stretch — calf/heel drop is fundamentally an ankle motion this rig
doesn't model) and the no-scapula family (both Active Shoulder Shrug &
Release, Standing Shoulder Blade Squeeze) match limitations already
catalogued elsewhere in this doc. `Neck Isometric Front-and-Back Press` and
`Downward-Facing Dog Calf Pump` scored low only because a naive 50%-duration
sample happens to land exactly on a rest keyframe (both have real peaks at
25%/75%) — false positives from the triage method, not bugs; confirmed by
sampling the actual peak frames. The 46 breathing exercises all score
identically (~3.46) since they share one composition — expected, not
reviewed individually again (already audited in the 2026-08-27 entry
below). The wrist family (Wrist Circles, both Wrist Extensor/Flexor
Stretch, both Assisted Wrist Flexion/Extension, Wrist & Forearm Release)
showed real rest-to-reach motion on inspection despite low scores — the
diff metric under-weights thin limb geometry at the render's resolution.

**Lesson for the triage method itself:** a single mid-loop sample can
alias onto a keyframe that happens to equal rest (most compositions here
are rest→peak→rest→peak→rest across frames 0/30/60/90/120, so 50% duration
= frame 60 = rest for every one of them). Sample at least 25%/75% as well,
not just start/middle/end.

## Breathing batch (2026-08-27)

Tackled the 65-exercise backlog left after the 31-exercise batch: 46
breathing techniques (no rig precedent — the rig has no chest-expansion
motion category), 11 jaw/eye/forehead/temple micro-exercises (no facial
joints on this rig at all), and 8 dynamic poses already deferred/dropped in
prior batches for structural reasons (no foot-ground-contact concept, a
multi-pose flow, geometry tearing, camera framing).

**Scope decided with the user up front, before building anything:**
jaw/eye/forehead/temple (11) skipped and documented as needing a facial rig
this project doesn't have — no attempt made, matching every prior batch's
treatment of infeasible categories. Of the 8 dynamic poses, only the 2 that
failed on previously-diagnosed, concrete bugs (Bridge Pose, Frog Rock) were
retried; the other 6 (Cossack Squat L/R, Deep Squat Hold, Standing Sumo
Squat Hold, 90/90 Hip Switch, Sun Salutation Warm-Up) still need a
foot-ground-contact concept or multi-pose-flow model this rig doesn't have,
left deferred.

**New shared-pipeline capability: `animate()` gains `scale_poses`.** Every
prior composition (300+ exercises) only ever needed bone ROTATION — a
breathing chest-rise/fall isn't a rotation, it's the bone growing and
shrinking in place. Added an optional `SCALE_POSES` cfg dict (same
`{frame: {bone: (sx,sy,sz)}}` shape as `POSES`, applied to `pose_bone.scale`
instead of `.rotation_euler`) to `_lib.animate()`, wired through
`run_seated`. Fully backward compatible — every existing script omits it
and is unaffected.

**New composition: `box_breathing.py` (the probe), reused by all 46.**
Ordinary proven seated-chair fold (`run_seated`). `chest` bone pulses
ISOTROPICALLY (1.0 -> 1.13 -> 1.0, all three axes together) rather than on
a single directional axis — this rig's chest bone is a purely-vertical
edit bone and its local X/Z-vs-world mapping was never characterized for
any prior composition, so isotropic sidesteps that ambiguity entirely at
the cost of not distinguishing "front" expansion from "side." A small
spine/head extension (-9°/-6° at peak) reinforces the inhale read
alongside the scale pulse. Side camera (azimuth 90) — the chest is the
widest visible landmark against open background from that angle. Verified
by opening the rest/peak PNGs (not just the log): a real, visible pulse
(chest silhouette measurably fuller, torso leaned back, chin lifted),
confirmed again on a 5-exercise contact-sheet sample after fan-out. All 46
share this ONE composition and are flagged `animationIsApproximate` — no
real diaphragm/ribcage is modeled, this is a stylized breathing cue. `Eye
Palming` is typed `breath` with no target parts and got the same
treatment.

**Bridge Pose, retried and shipped.** Previously dropped for "torn/spiky
foot geometry + a dark gap at the crotch." Rebuilt on `run_supine`
(ROLL_DEG=0) with legs held CONSTANT (not animated) at
`double_knee_to_chest_release.py`'s proven-safe shallow symmetric fold
(thigh -75 / shin 90) — removes the leg-tearing risk entirely, since
nothing animates through a large sweep. Investigated the crotch gap by
rendering at three arch magnitudes (-12°, -6°, -3°) and found it present
even at REST (spine=0, no arch at all) — it's an inherent seam of this
exact leg fold (already shipped in `double_knee_to_chest_release`), not
something the spine-arch motion causes; re-diagnosed and accepted as a
small pre-existing cosmetic artifact rather than a blocker. Camera: tried
FORCE_TOPDOWN first (reasoning a hip lift is the same Z-axis-travel class
as `double_knee_to_chest_release`'s knee lift) and it rendered as a
standing figure — that camera's disambiguation depends on legs folding UP
into the air, which Bridge Pose's don't. Fell back to the plain
`run_supine` oblique default, which reads correctly as lying down. Shipped
with an 8° spine arch (chest -4° counter-arch), confirmed ~45k changed
pixels between rest/peak stills — real, modest motion.

**Frog Rock, retried and shipped, two new bugs found.** Previously dropped
for a badly-framed peak camera. Rebuilt on `run_quadruped`. First attempt
added thigh abduction (local Z) on top of the proven quadruped thigh's
existing local-X lean, to approximate "widen your knees" — rendered as a
broken, diagonally-splayed figure: composing a second Euler axis onto an
already-rotated bone doesn't isolate a clean "spread" from a rest pose (the
same non-commuting-rotation trap `apply_supine_base`'s docstring already
warns about for its own roll component, hit here on a different bone).
Dropped the knee-widening detail entirely rather than debug the compound
rotation. Second bug, after dropping abduction: STILL rendered broken and
diagonal — root cause was `_BASE` omitting `apply_quadruped_base`'s own
documented constant `spine: (r(95),0,0)`; without it `spine` defaults to 0
(upright) while the legs are folded for quadruped, reading as a figure
flung diagonally in midair. Lesson: `apply_quadruped_base` only performs
the object-level Z translation — every `run_quadruped` script needs its
OWN copy of the full per-bone constant set (spine/chest/thigh/shin/head/
upperarm/forearm), it is not implied. Also switched `CAMERA_AZIMUTH` from
90 (copied from a `run_seated` script, `childs_pose.py`) to 30 (proven for
`run_quadruped` via `cat_cow_flow.py`) — 90 is NOT a proven quadruped
angle, azimuth conventions don't transfer across base compositions.
Shipped with a modest spine rock (95° -> 105°, within `cat_cow_flow`'s own
proven 85-110 envelope) — confirmed real motion via a rest/peak pixel diff.

**Verification for this batch:** all 46 breathing renders + both retries
checked programmatically for 0 fallback muscles (all clean), AND had
rest/peak PNGs actually opened and visually reviewed — this is what caught
the two Frog Rock bugs, the FORCE_TOPDOWN misread on Bridge Pose, and
confirmed the breathing pulse and gap-is-preexisting findings, none of
which the log alone would have surfaced. A 5-exercise contact-sheet sample
of the fanned-out (not individually-probed) breathing scripts confirmed no
degradation across the mechanical fan-out. Full `xcodebuild` unit suite
(412 tests) green throughout. New `BreathingBatchUITests` (parallel to
`ThirtyOneExerciseBatchUITests`) verifies an 11-exercise sample opens live
in the app and shows the approximate-animation disclaimer — passed live in
the simulator.

355/372 exercises now animated (was 307). The 17 remaining are 11 jaw/eye/
forehead/temple micro-exercises (no facial rig) and 6 dynamic poses (Cossack
Squat L/R, Deep Squat Hold, Standing Sumo Squat Hold, 90/90 Hip Switch, Sun
Salutation Warm-Up) needing a foot-ground-contact concept or multi-pose-flow
model this rig doesn't have — the entire remaining backlog is now
infeasible-without-new-rig-capability, not just deferred-for-later.

## 31-exercise batch (2026-08-27)

Attempted all 39 of the 96 remaining exercises whose `targetBodyParts` isn't
empty/micro (i.e. everything left except breathing techniques and jaw/eye/
forehead exercises, which stay deferred — no rig precedent for either, same
as every prior batch). Shipped 31; dropped 2 after failing visual QA;
deferred 6 that need a genuinely new base pose this rig doesn't support well.

**Dropped after rendering (visual QA, not just the `fallback=0`/log check):**
`bridge_pose` (torn/spiky foot geometry + a dark gap at the crotch when
`hips` stays fixed-flat while `spine` arches backward — the supine base
doesn't hold up under that combination) and `frog_rock_kneeling_glute_
mobility_flow` (peak-frame camera framing was badly wrong — the figure was
cropped to an unrecognizable diagonal sliver). Both had clean render logs
(0 fallback muscles) — a reminder that the log alone doesn't prove a render
is usable; every new composition in this batch got its rest/peak PNGs
actually opened and looked at before shipping, which is what caught both of
these plus the two bugs below.

**Deferred (need a new base/dynamic pose, consistent with every prior
batch's policy):** `Left/Right Cossack Squat Stretch`, `Deep Squat Hold`,
`Standing Sumo Squat Hold` (a symmetric deep-knee-bend base would look
visually identical to the ordinary seated-chair pose already used
everywhere else on this rig — no way to distinguish "squatting on your own
feet" from "sitting" without a foot-ground contact concept this rig doesn't
have), `90/90 Hip Switch` (bent-leg internal/external rotation switch risks
the same mitt-webbing failure documented below for large twists on an
already-bent joint), `Sun Salutation Warm-Up` (genuinely a multi-pose flow,
not a single held/oscillating shape).

**Two real bugs caught in review, not just camera/pose mismatches this
time — a Python bug:** the mirrored-side (`_right`) variants of
`runners_lunge_with_rotation`, `shoulder_pendulum_swing`, and
`worlds_greatest_stretch` were generated with `lambda d: r(-d)(N)` inside a
tuple literal, intending "call this negating-then-radians helper with N".
Python parses that as a lambda whose *body* is `r(-d)(N)` — the whole
expression after the colon, including the `(N)` call — not a lambda
immediately invoked with N. So the tuple ended up holding a function object
instead of a number, and Blender's `Euler()` failed with `sequence index 2
expected a number, found 'function' type`. Fixed by regex-substituting
every `lambda d: r(-d)(N)` back to the literal `r(-N)` per-script (the
mirrored angles were static values anyway, so no lambda was actually
needed). Lesson for any future generator script: never build a per-call
lambda through string templating — compute the literal value in Python and
interpolate the number, not the callable.

**One more camera/pose-axis mismatch, the same recurring gotcha:**
`shoulder_pendulum_swing_{left,right}` first rendered with
`CAMERA_AZIMUTH = 0` (front view) for a forward-lean + sagittal-plane arm
swing — both motions live in the plane a front camera views edge-on, i.e.
completely foreshortened away (the render looked like a static, fully
upright figure with arms merely resting out to the sides). Fixed to
`CAMERA_AZIMUTH = 90` (side view), re-rendered, confirmed the lean and
swing are now visible. Same class of bug as the fourth-batch and
62-exercise-batch notes below — worth internalizing as a checklist item
("does this pose's dominant motion happen in the plane this camera views
edge-on?") rather than re-discovering it per batch.

**New reused compositions, no new base needed:** the half-kneeling lunge
base (from the 62-exercise batch) fed 5 more exercises directly —
`left/right_half_kneeling_rear_foot_instep_stretch`, `kneeling_calf_
stretch_on_cushion_left/right`, and (combined with the seated-spinal-
rotation twist axis + an overhead reach) `runners_lunge_with_rotation_
left/right` and `worlds_greatest_stretch_left/right_lead_leg` — the latter
two instructions describe the same underlying lunge-with-rotation shape
under different names, so both reuse one composition rather than inventing
two. `standing_hip_circles` and `shoulder_pendulum_swing` both reused the
lazy 4-keyframe "combine two axes across the loop" trick already proven for
`wrist_circles.py`, applied to the hip and shoulder respectively, kept to
conservative angles since a weight-bearing standing leg (hip circles) and a
scapula-less shoulder (pendulum, no real support prop) are both somewhat
new territory.

**Two exercises wired to an already-rendered asset instead of a new
render:** `Seated Calf Stretch with Towel (Left/Right)` are duplicate-
content entries under a slightly different name from the already-shipped
`Left/Right Seated Calf Stretch with Towel` — same instructions, same
pose — so they point at the existing `left/right_seated_calf_stretch_
with_towel.mp4` rather than re-rendering an identical clip. Flagged NOT
approximate, matching the original entries.

**Verification for this batch:** all 29 newly-rendered exercises checked
programmatically for `skins:1`/`anims:1`/0 fallback muscles, AND had their
rest/peak PNGs actually opened and visually reviewed (not just the log) —
this is what caught the two drops and two fixes above, none of which the
log alone would have surfaced. Full `xcodebuild` unit suite (412 tests)
green throughout. New `ThirtyOneExerciseBatchUITests` (parallel to
`SixtyExerciseBatchUITests`) verifies a 20-exercise sample spanning every
base composition opens live in the app and shows the approximate-animation
disclaimer where expected.

307/372 exercises now animated (was 276). The 65 remaining are
breathing techniques (~44) and jaw/eye/forehead/temple micro-exercises
(~11), both still with no rig precedent, plus the 6 deferred squat/dynamic-
flow exercises named above and `Sun Salutation Warm-Up`. That's very
nearly the entire feasible backlog on this rig.

## 62-exercise batch (2026-08-26, continued past the even-split 40)

## 62-exercise batch (2026-08-26, continued past the even-split 40)

Animated 62 more of the remaining 158 unanimated exercises (214 -> 276 of
372). Every pose was checked against its own exercise's written
instructions before scripting (not just the name), per this session's ask
to double-check exercises actually perform what they're meant to do.

**New base composition, probed before use (high-leverage — feeds 12
exercises): half-kneeling lunge.** Front leg planted (`thigh`=-90/`shin`=+90,
the proven seated-chair fold), rear knee down (`thigh`=+15/`shin`=+100, the
proven quadruped-rest fold), via `run_seated(globals())` with
`SEATED_DROP=0.50`. The drop value was solved numerically with a throwaway
probe (`_lunge_probe*.py`, scratchpad, deleted after use) sweeping
0.40-0.55: no single drop makes BOTH the front foot AND the rear knee touch
the floor exactly (they're driven by different bone chains), so 0.50 was
picked as the value that leaves the smallest visible gap on each (front
foot ~0.04 below floor, rear knee ~0.05 above) rather than a large gap on
either one. Rendered clean (no tearing) across every exercise built on it:
`left/right_kneeling_hip_flexor_lunge`, `left/right_couch_stretch`,
`left/right_kneeling_quad_stretch`, `kneeling_couch_stretch_rear_foot_
elevated_left/right` (same pose as the couch stretch, reused for a third
differently-named entry point), `left/right_low_lunge_anjaneyasana` (same
base + overhead arms + a shallow backbend), and a front-thigh-abduction
variant for `pigeon_pose_left/right_leg_forward` + `left/right_pigeon_pose_
hip_stretch`.

**Content bug found (not fixed — flagged, since it's a SeedData tagging
issue, not an animation one): `Left/Right Pigeon Pose Hip Stretch`'s own
`targetBodyParts` contradicts its own instructions.** Left Pigeon Pose Hip
Stretch is tagged `['Left Glutes', 'Left Hip Flexors']`, but its own
instructions say the stretch is felt "through your left glute and the
front of your RIGHT hip" (the extended-back leg) — anatomically the
tag should read `Right Hip Flexors`, matching `pigeon_pose_left_leg_
forward`'s tag for the identical pose. Looks like a copy/paste bug, the
same class already caught once in `right_levator_scapulae_stretch.py`
(2026-08-22). The animation highlights the anatomically-correct muscle per
the written instructions, not the (likely wrong) tag; the SeedData tag
itself was left alone since fixing it is a content change outside this
batch's scope.

**Two camera/pose-axis mismatches caught in review, both the same gotcha
recurring:** `kneeling_side_lunge_adductor_stretch_on_cushion_left/right`
and `standing_adductor_stretch_with_chair_support_left/right` both first
rendered with a side-on camera (azimuth ~100 / ~90) copied from a
neighboring family without re-deriving it, for a `thigh` local-Z ABDUCTION
motion — the exact "camera azimuth and pose are coupled" mistake the
fourth-batch section of this doc already documents (a side camera views
the sagittal plane; abduction happens in the coronal plane, so it
foreshortens away). Caught by reviewing the rendered contact sheet (the leg
visibly didn't move frame to frame) rather than trusting the log. Fixed to
a front camera (azimuth 0, matching `standing_adductor_rock_side_to_
side.py`'s already-proven convention for this exact axis) for the standing
exercise, and a 3/4-oblique 35 deg for the kneeling one (needs to keep some
lunge depth visible too). Re-rendered, re-encoded, re-verified before
shipping.

**Rig-limitation approximations (21 of the 62, flagged
`animationIsApproximate`):** the no-scapula/clavicle limitation already
implicit in the rig extends to shoulder-blade motions (`Active Shoulder
Shrug & Release`, `Standing Shoulder Blade Squeeze`, `Prone Y-T-W Raise`) —
approximated via small proxy motions on `chest`/`upperarm` rather than
animating a scapula that doesn't exist. The no-independent-ankle/toe-joint
limitation (documented in the tenth batch and the hand/wrist batch)
accounts for the other 18: the whole foot/ankle/shin-mobility family
(`Shin & Ankle Mobiliser`, `Ankle Alphabet`, both `Ankle Circles for
Tibialis Release`, both `Cross-Legged Shin Pull`, both `Seated Assisted
Tibialis Stretch`, both `Seated Shin Stretch with Strap`, `Seated
Foot Flex-and-Point Flow`, `Standing Toe Curl Towel Grip`, `Cross-Legged
Foot Massage & Arch Stretch`, both `Wall-Assisted Toe Extension Stretch`,
both `Kneeling Arch Stretch, Toes Curled Under`) can only show the leg
silhouette + correct highlight, never the actual ankle/toe articulation.
Several of these also came back with `highlight=0` in their render log —
not a bug: "Foot" (like "Temple"/"Jaw"/"Eye"/"Forehead" before it) isn't a
mappable atlas muscle group, matching the tenth batch's Plantar Fascia
finding.

**Verification for this batch:** all 62 rendered with `skins:1`/`anims:1`
and 0 fallback muscles (checked programmatically, not just spot-read).
Visually reviewed via `ffmpeg` 5x2 contact-sheet grids (12-frame stride)
for every new base composition and every bilateral-abduction exercise
before shipping; the two camera bugs above were caught this way. Wired via
the same surgical `"id"`-line regex insert as every prior batch. New
`SixtyExerciseBatchUITests` (parallel to `EvenSplitAnimationBatch40UITests`)
verifies all 62 open via search and the 21 approximate ones show the
disclaimer. Full `xcodebuild` unit suite (413 tests) green throughout.
276/372 exercises now have animations (was 214). 96 remain — mostly
breathing techniques and jaw/eye/forehead micro-exercises (no rig
precedent for either), plus a handful of genuinely dynamic/new-base-pose
exercises deliberately deferred this batch: `Bridge Pose`, `Standing Split
Prep Stretch`, `Dynamic Standing Leg Swings`, `Standing Hip Circles`,
`Runner's Lunge with Rotation` (L/R), `World's Greatest Stretch` (L/R),
`90/90 Hip Switch`, `Deep Squat Hold`, `Standing Sumo Squat Hold`,
`Cossack Squat Stretch` (L/R), `Frog Rock` — each needs its own base-pose
or dynamic-motion probe (deep squat, hip circle, lunge-with-rotation) not
yet attempted on this rig.

## Even-split 40-exercise batch (2026-08-26)

Animated 40 more exercises, an even split (5 each) across 8 thin-coverage
families: quadriceps, calves/tibialis, neck/trapezius, lats, obliques,
abs/backbend, glutes/hip, and adductors. Every pose is a direct clone or a
straightforward composition of an already-proven pose from an earlier batch
(no new bone axes attempted) — see each script's own docstring for exactly
which prior script it derives from. Two new base compositions worth noting
for future sessions:

- **`run_quadruped` + thigh local-Z abduction** (`frog_stretch_kneeling_
  groin_stretch.py`) — first use of the hip-abduction axis (proven seated/
  supine) on the quadruped hands-and-knees base. Worked cleanly.
- **Standing thigh local-Z abduction** (`standing_adductor_rock_side_to_
  side.py`) — first use of that axis while standing (previously only seated/
  supine); kept to a conservative 15deg since it's genuinely new territory
  for a weight-bearing standing leg.

Generator script + full exercise list lived at
`/private/tmp/.../scratchpad/gen_exercises.py` and
`/private/tmp/.../scratchpad/patch_seed_data.py` for this session — not
checked into the repo, just documenting how the 40 scripts were produced in
bulk (adapt the pattern for a future large batch rather than writing each
script by hand).

---

**Previous update:** 2026-07-28
**Goal:** Give the 152 seed exercises 3D-animated demonstrations, authored in
Blender and exported for the app. Started with **"Clasped Hands Behind Back."**
Longer-term vision: an **anatomy figure that performs the stretch while the
worked muscles/joints highlight.**

This file is the context dump so a fresh chat can continue without re-deriving
everything. Read it top-to-bottom once.

---

## TL;DR / current state

- **LATEST (2026-07-28): the muscle-body + skin-head path WORKS.** New script
  `clasped_hands_behind_back_muscleonly.py` builds a **skin-head + muscle-body**
  figure from the app OBJ and animates the full clasp cleanly. Front view is
  presentable (shoulders/chest/biceps highlighted, hands clasp low at the
  midline). See "Muscle-only result" below. Two residual polish items remain:
  upper-arm muscle **stretch/drape** at the extreme elbow fold (visible in
  profile) and **hand-tendon shards** at the wrists. Not blockers.
- **Clean motion is proven** on a generic **A-pose base mesh** — the body
  deforms with no tearing. Script: `clasped_hands_behind_back_basemesh.py`.
  The one remaining issue is **pose authoring** (arms currently lift up/out
  instead of going down-and-behind to clasp) — SOLVED for the muscle-only script
  (see Gotcha #6 for the bone-axis semantics).
- **The anatomy model animates but the SKIN TEARS at the arms** because it's
  modeled arms-down. Script: `clasped_hands_behind_back_bodymap.py`. The
  skinning itself is now correct (was silently broken — see Gotcha #1). The
  muscle-only script sidesteps this entirely by dropping the torso/limb skin.
- **The unified "animate anatomy + highlight muscles" vision is viable** via
  the app's existing `BodySkinMuscle.obj` (skin + 268 named muscle objects),
  NOT via the giant raw merged blend. Muscle groups map cleanly to bones
  (all 41 mapped, 0 fallbacks); **joint-blend weighting** fixes the muscle
  separation. Confirmed this session.

---

## The three scripts (all in `Tools/blender/exercises/`)

Each is a **paste-in Blender script** (run in the *Scripting* tab, fresh file —
they clear the scene) AND runnable headless. Each writes a `.glb` (animated
model), a `.blend` (editable scene), and a `*_log.txt` to
`Tools/blender/generated/exercises/`. They surface success/errors as an
in-Blender popup + the log file (double-clicked Blender has no visible console).

| Script | Model | Status |
|---|---|---|
| `clasped_hands_behind_back.py` | Self-built blocky "segment box" figure | ✅ Works. Pure prototype to prove the rig→keyframe→export pipeline with zero external assets. |
| `clasped_hands_behind_back_bodymap.py` | App's welded anatomy shell (`BodySkinMuscle.obj`) | ⚠️ Animates, but **skin tears at the arms** (arms-down mesh). Skinning fixed via distance weighting. |
| `clasped_hands_behind_back_basemesh.py` | `FinalBaseMesh.obj` (A-pose) | ✅ **Clean deformation, no tearing.** Pose needs re-authoring (arms go up/out, not behind). |
| `clasped_hands_behind_back_muscleonly.py` | App OBJ, **skin clipped to a head cap + 268 muscles** | ✅ **Recommended path.** Per-muscle group→bone bind + joint-blend weighting + muscle highlight + hand/foot mitts. Front view presentable; only faint wrist tendon wisps remain in profile. Writes .glb/.blend/log + 3 PNG renders (rest_front, peak_front, peak_side). |

---

## Muscle-only result (2026-07-28) — how the recommended script works

Figure = **head skin cap + 268 muscle objects** built from the app OBJ; the
full-body skin shell is dropped (that shell is what tore). Pipeline highlights:

1. **Import as separate objects** (not joined-then-welded like the bodymap
   script). Keeps muscles individually bindable + highlightable.
2. **Skin → head cap.** The OBJ's `BodySkin` is a *full-body* shell (Y −0.92→
   +1.0). Auto-detect the neck as the narrowest skin cross-section in the
   0.72–0.93 height band (came out at frac ≈0.864), delete skin below it →
   ~3.2k-vert head cap that never tears (head barely moves in this stretch).
3. **Per-muscle bone bind.** Each muscle's `group` (from
   `skinmuscle_node_names.json`) → a bone via a keyword table (`group_to_bone`).
   All 41 groups map, 0 fallbacks. L/R falls out of the "Left/Right" prefix.
4. **Joint-blend weighting** (the fix for muscle separation): each muscle vertex
   is inverse-distance weighted (power 4, top-2) over the muscle's
   **joint-adjacent bone set only** = primary bone + its parent + its children.
   Mid-muscle verts stay ~rigid; verts near a joint blend to the neighbour, so a
   deltoid stretches across the shoulder instead of detaching. The restricted
   candidate set is what stops the global-nearest-bone "cape tear" (Gotcha #2).
5. **Highlight.** Muscles whose group matches `WORKED_KEYWORDS`
   (shoulder/chest/bicep for this exercise) get an orange material; rest grey;
   head cap gets skin tone. 2 shared muscle materials → 2 slots after join.
6. Join muscles → one skinned "Muscles" mesh; head cap stays separate. Export
   GLB (verified skins:1, anims:1) + blend + renders.

**Works:** no skin-cape tearing, shoulder stays connected, highlight tracks the
muscles, GLB skinning valid. Front view (the app's shipping angle) is presentable.

**Polish pass done (2026-07-28):**
- **Elbow eased** — forearm flexion dropped 50°→36° (see solved pose in Gotcha
  #6). Killed the upper-arm muscle drape; arm now reads as a normal silhouette.
- **Hands + feet → convex-hull mitts.** The atlas hands/feet are dozens of thin
  splayed finger/toe meshes that strand when posed. Each side's `Hand`/`Foot`
  group is joined + `convex_hull_object()`'d into one solid mitt (rigid-ish,
  joint-blend weighted to `forearm`/`shin`). Clean feet wedges + hand mitts.
- **Forearm hull = DEAD END, reverted.** Hulling the forearm (to remove its
  finger-tendon wisps) comes out a flat ugly paddle — a limb segment's convex
  hull bridges its widest points into a slab (merged-with-hand or separate, same
  result). Forearms keep their real geometry + joint-blend instead.

**Residual (minor, profile-only, not blockers):** faint finger-tendon "wisps" at
the wrist — the `flexor/extensor digitorum` tendons are tagged `Forearm` but run
to the fingertips, so they can't be hulled without flattening the forearm. Real
fix if ever wanted: detect + strip just the high-aspect-ratio tendon objects,
keep the forearm belly. Also the two hands slightly overlap where they clasp at
the midline (cosmetic).

---

## Models / assets

| Asset | Path | Notes |
|---|---|---|
| **App anatomy OBJ** | `Breath - Relax & Stretch/Resources/Models3D/BodySkinMuscle.obj` | Welded skin shell + **268 muscles as separate named `o` groups**. Pre-normalized (Y-up, height 2). **Arms-down** → tears when arm-animated. |
| **Muscle tag map** | `Breath - Relax & Stretch/Resources/skinmuscle_node_names.json` | Maps each `o` node → `{layer, group, ...}`. 41 muscle groups. This is what makes muscles **individually highlightable**. |
| **Base mesh** | `Tools/blender/incoming/FinalBaseMesh.obj` | Clean single-manifold male, **A-pose**, 24,461 verts, has normals. User-supplied (extracted from a `.rar`). Great for motion; no anatomy. |
| **Source anatomy blend** | `/Users/jasonlu/Blender/Z-Anatomyskinjointmuscle.blend` | The blend the app OBJ is generated from (via `../export_skin_muscle.py`). |
| **"Merged" anatomy blend** | `/Users/jasonlu/Blender/Z-AnatomyMuscle-Joint-Skin-Merged.blend` | ⚠️ **2.07M verts, 4,372 meshes + 951 curves + 1,660 text labels, NO armature** (76 MB; opened + inventoried 2026-07-28). Full Z-Anatomy atlas. **Its only "skin" (collection `9: Regions of human body`) is HEAD/FACE region patches — `Frontal/Nasal/Buccal region`, `Hairs of head` — NOT a body skin.** Its one genuinely unique asset the app OBJ lacks is **joint geometry** (`3: Joints`, 480 meshes: intervertebral discs, ligaments, membranes). Everything else (skin, muscle) is cleaner in the app OBJ. **Only touch this file if you need joints as highlightable geometry** — then extract just collection 3. |

Collections in the merged blend worth knowing: `1: Skeletal system`,
`3: Joints` (480 meshes), `4: Muscular system` (789), `9: Regions of human
body` (skin, but scattered/unwelded + junk anchor planes + text labels).

---

## Muscle-group → bone mapping (confirmed, enables clean weighting + highlight)

The 41 groups in `skinmuscle_node_names.json` map cleanly onto a simple rig:

| Bone | Muscle groups |
|---|---|
| `upperarm.L/R` | Biceps, Triceps, Shoulder (deltoid) |
| `forearm.L/R` | Forearm, Hand |
| `chest` | Chest, Lats, Trapezius, (upper) Obliques |
| `spine` | Spinal Erectors, Lower Back, Abs |
| `hips` | Glutes, Hip Flexors, Adductors |
| `thigh.L/R` | Quadriceps, Hamstrings |
| `shin.L/R` | Calves, Tibialis, Foot |
| `head` | Head, Front/Back Neck |

**Why this matters:** assigning each *named muscle object* 100% to its bone
avoids the distance-guessing that tears the arms. Highlighting = give target
muscle objects a colored material. (Skin is one welded shell → still needs
distance weighting → may still crease slightly at the shoulder.)

---

## Hard-won gotchas (DO NOT re-learn these the slow way)

### 1. `parent_set(ARMATURE_AUTO)` silently produces ZERO weights on the anatomy mesh
Bone-heat ("Automatic Weights") needs a clean closed manifold. The welded skin
+ overlapping muscle geometry breaks it — but in Blender 5.1.2 it **raises no
error**, just creates empty vertex groups. Result: glTF exports `skins: 0`, the
mesh stays static while only the bones animate ("blocky things move, body
doesn't"). **Fix used:** author weights ourselves — `bind()` in the scripts does
nearest-segment inverse-distance weighting over the TOP_K (=2) nearest bones,
guaranteeing 100% coverage and an exportable skin. Verify with the weight-count
check below.

### 2. Arms-down mesh → arm bones hug the torso → weight bleed → "cape" tearing
On the app anatomy OBJ, torso/waist vertices are Euclidean-close to the arm
bones (arms hang alongside the body), so they get arm weight and drag a sheet of
skin when the arm lifts. **A-pose meshes avoid this** (air between arm and
torso). This is THE reason the base mesh works and the anatomy shell doesn't.
Region-based (per-muscle) weighting sidesteps it for muscles; skin is the
residual problem.

### 3. Pose authoring on A-pose arms is unintuitive (SOLVED for the vertical rig — see #6)
Pose-bone `rotation_euler` is in **bone-local** space. For diagonal A-pose arm
bones, "swing behind the back" is not a clean single-axis rotation. Base-mesh
`POSES` make the arms lift up/out, not down-and-behind. For the muscle-only rig
(arms hang straight down) the axes are clean — see Gotcha #6.

### 4. `~/Downloads` reads HANG from this background session (TCC)
Reading file *contents* under `/Users/jasonlu/Downloads` blocks forever (stat/ls
work). `~/Blender/` and the repo read fine. Always bound Downloads-touching
commands: `perl -e 'alarm 6; exec @ARGV' <cmd>`. To get a file out of Downloads,
have the **user drag it into the repo via Finder** (Finder-osascript automation
is also blocked for the bg process). See memory `icloud-desktop-tcc-gotcha`.

### 5. Rendering headless: TRACK_TO constraint doesn't evaluate; set camera rotation directly
Use `BLENDER_WORKBENCH` engine (solid shading, no materials/lights needed) and
set `cam.rotation_euler` directly (front = `(radians(90),0,0)` looking `-Y`;
side = `(radians(90),0,radians(90))`). Call `bpy.context.view_layer.update()`
before each render. OBJ importer maps file Y-up → Blender Z-up.

### 6. Arm-bone euler axes for the vertical rig (this is how the clasp pose was solved)
The muscle-only rig's arm bones hang **straight down** (local Y = world −Z). For
`upperarm.{L,R}` and `forearm.{L,R}`:
  * **DEPTH DIRECTION (learn from the mistake): −Y is the FRONT/chest side, +Y is
    BEHIND.** The azimuth-0 camera sits at −Y and shows the chest, so front = −Y.
    An earlier diagnostic mislabeled this (+Y=front) and every "extension" swung
    the arms FORWARD — the hands ended up in front of the chest and the
    "behind-the-back" look was faked by filming from behind. Confirm front/back
    before trusting any Y sign.
  * **local X** = world +X → **+X rot swings the arm BACK / behind (+Y)** = shoulder
    extension; **−X = forward**. For the FOREARM, **−X flexes the elbow** to fold
    the hand in behind the spine.
  * **local Z** = world +Y → **+Z = toward the midline for the LEFT arm**
    (adduction); mirror to **−Z for R**.
  * **local Y** = twist.
Don't eyeball depth — solve numerically. `solve_pose.py` (scratchpad) sweeps the
angles and reports the **wrist world position**; target = **behind (y ≈ +0.15..
+0.18, just inside the back surface), midline (|x|≈0), low (z≈0.95)** so the torso
occludes the hands from the front camera. Shipped clasp: upperarm `(+28, 0, ±12)`,
forearm `(−34, 0, ±22)`, rendered at `CAMERA_AZIMUTH = 38`.

---

## Tooling / commands

**Blender CLI:** `/Applications/Blender.app/Contents/MacOS/Blender` (v5.1.2)

Run a script headless (regenerates the .glb/.blend):
```bash
BLENDER=/Applications/Blender.app/Contents/MacOS/Blender
"$BLENDER" -b --python "Tools/blender/exercises/clasped_hands_behind_back_basemesh.py" 2>/dev/null
```

Open a saved scene + run a render/inspect script against it:
```bash
"$BLENDER" -b "Tools/blender/generated/exercises/<name>.blend" --python <script.py>
```

**Verify a .glb actually has a skin + animation** (parse the JSON chunk):
```python
import json, struct
d=open("<file>.glb","rb").read(); clen,_=struct.unpack("<II",d[12:20])
g=json.loads(d[20:20+clen])
print("skins",len(g.get("skins",[])),"anims",len(g.get("animations",[])))
# skins==0 => skinning is broken (see Gotcha #1)
```

**Verify vertex weights exist** (open the .blend headless):
```python
import bpy
b=bpy.data.objects["Body"]
print(sum(1 for v in b.data.vertices if any(g.weight>0 for g in v.groups)),
      "/", len(b.data.vertices), "weighted")
```

**App integration next step:** convert `.glb → .usdz` for SceneKit/RealityKit,
e.g. Reality Converter or `xcrun usdconvert in.glb out.usdz`. Export uses
`export_yup=True` for SceneKit's Y-up. See the app-integration plan:
`docs/superpowers/plans/2026-07-12-exercise-video-animation.md` (proposes an
`Exercise.animationIdentifier` field + a SceneKit card sibling to the existing
`ExerciseMediaCard`/`localVideoURL` video path).

---

## Rig shape (shared by all scripts)

~12-bone humanoid: `hips → spine → chest → head`, `chest → upperarm.{L,R} →
forearm.{L,R}`, `hips → thigh.{L,R} → shin.{L,R}`. The base-mesh and bodymap
scripts **auto-fit** bones to the mesh (measure bounds / detect landmarks like
hands, shoulders, hips, feet) so the rig scales to any model. Animation loop is
0..120 @ 30fps (4s): neutral → clasp → peak → hold → back to neutral.

---

## Where we are now (2026-07-28) + open decisions

**Path 1 (the recommended experiment) is DONE and validated** — see
`clasped_hands_behind_back_muscleonly.py` and "Muscle-only result" above.
Muscle-body + skin-head animates cleanly with joint-blend weighting; the
"show skin at all?" sub-question is answered: **head skin only** (drop the
body skin that tears). Resolved decisions:
- ✅ Source = app `BodySkinMuscle.obj`, NOT the merged blend (its skin is head
  patches only; only joints are unique there).
- ✅ Muscles are bone-mappable (all 41 groups) and don't tear with per-muscle
  bind + joint-blend weighting.
- ✅ Pose authoring solved numerically (Gotcha #6).

**Polish pass DONE** (elbow eased, hand/foot mitts, forearm-hull dead-end
reverted — see "Muscle-only result"). Front view is presentable; only faint
profile wrist wisps remain.

**Next candidate steps:**
1. **App integration — DONE (2026-07-30, Approach A = baked video).** Not usdz/
   SceneKit: the loop renders to a muted mp4 (`render_demo_video()` +
   `Tools/blender/encode_mp4.swift`, since this Blender has no FFMPEG) and routes
   through the app's looping-video slot via `Exercise.animationName` → `demoVideoURL`
   → `ExerciseMediaCard` (portrait 4:5) + an `ExerciseRow` `LoopingVideoThumbnail`.
   Per-exercise angle via `CAMERA_AZIMUTH`. Clasped-Hands shipped (azimuth 38).
   See memory `exercise-animation-app-integration`.
2. **Per-exercise authoring:** this script hard-codes one exercise's pose +
   worked-muscle set. Generalize to author the other 151 (pose library keyed by
   exercise; worked muscles from the exercise's muscle tags).
3. **Joints (later / optional):** app models joints as hitboxes
   (`JointRegion.swift`, `musclegroup_hitboxes.json`), not geometry. Only if
   joint highlighting is wanted → extract collection 3 from the merged blend.

---

## Second batch (2026-08-02): shared lib + 3 more exercises

Generalized the pipeline off `clasped_hands_behind_back_muscleonly.py` (still
kept, unmodified, as a working reference) into **`_lib.py`** — every function
from that script (import/normalize/rig-build/weighting/render/export) minus
the per-exercise config. A new exercise is now a ~50-line script that sets
`EXERCISE`, `VIDEO_NAME`, `CAMERA_AZIMUTH`, `WORKED_KEYWORDS`, `POSES` (and
optionally `ORTHO_SCALE_MULT`), adds `Tools/blender/exercises/` to
`sys.path`, and calls `L.run(globals())`. Still paste-in compatible — the
`sys.path.insert` line works identically pasted into the Scripting tab.

Shipped: `neck_flexion_chin_to_chest.py`, `standing_forward_fold_ragdoll.py`,
`left_standing_side_bend.py`. All three reuse the exact rig/skinning/
highlight machinery — only pose angles, camera azimuth, and worked-muscle
keywords differ per exercise.

### Walkthrough: Neck Flexion Stretch (Chin-to-Chest) — first of this batch

The simplest possible case: **one bone (`head`), one rotation axis.** Chosen
deliberately as the first of the batch to validate the generalized `_lib.py`
against exercise #1's known-good output before attempting anything with more
moving parts.

- **New axis convention needed.** All prior gotchas (esp. #6) were solved for
  the ARM bones, which hang straight down (local Y = world −Z). The vertical
  bones (`head`, `chest`, `spine`) point straight UP (local Y = world +Z) —
  a different bone orientation, so the arm-bone sign conventions do NOT
  transfer. Solved numerically with a throwaway probe script (build the rig,
  apply a lone +20° local-axis rotation to `head`/`chest`/`spine`, print the
  bone tail's world position for each of the 3 axes): **local X pitches a
  vertical bone forward** (+X moves the tail toward −Y, i.e. front, and
  slightly −Z) — the sign is POSITIVE for forward-pitch, opposite of the arm
  bones' "+X = swing back" rule. Local Z bends the bone sideways (toward
  world −X). Local Y is twist, as with the arms.
- **Highlight precision:** the atlas has separate `Back Neck` / `Front Neck`
  muscle objects; `WORKED_KEYWORDS = ("back neck",)` (not the broader
  `"neck"`) highlights only the muscle actually stretched by a chin tuck.
- **Camera:** shot from the side (`CAMERA_AZIMUTH = 90`) — a front camera
  looks straight down the pitch axis, so a nod reads as foreshortening
  instead of visible motion.
- **No new failure modes.** Single rigid bone, no joint-spanning muscle, no
  tearing risk — this one worked first try. Rendered result: clean forward
  nod, `Back Neck` lights up orange, no artifacts.

### The other two — what came up

- **Standing Forward Fold (Ragdoll):** stacks the SAME forward-pitch rotation
  on `spine` + `chest` (children down the `hips -> spine -> chest` chain) so
  the torso hinges at the hips while legs stay planted. Two things that bit:
  (1) **first render clipped the head and left huge dead space** — the fixed
  camera framing (`ortho_scale = height * 1.15`) was tuned for an upright
  rest pose, but the peak fold pushes the silhouette's depth extent (world Y)
  far past the rest-pose bounding box, so the head landed near the frame
  edge. Fixed by adding an `ORTHO_SCALE_MULT` override (`_lib.py`'s
  `setup_render` now takes a multiplier, default 1.15; this exercise ships
  1.7). (2) **arms need to counter-rotate to hang world-vertical** —
  `upperarm.{L,R}` are children of `chest`, so they inherit its pitch; since
  every rotation here is about local X (which stays parallel to world X
  through the whole chain — pitching about X doesn't change what "X" is),
  the chest's total world pitch is just `spine + chest` added up, and giving
  the upperarms that sum negated exactly cancels it. Matches the instruction
  "let your head, neck, and arms hang heavy."
- **Left Standing Side Bend:** local Z instead of local X (sideways instead
  of forward). Almost shipped a sign error here: the rendered peak frame was
  briefly misread as bending the wrong way by eye. Settled it two ways
  instead of trusting the image: (1) numeric — logged the `head` bone's peak
  world position (`x = −0.603`) — and (2) a marker-cube probe rendering a
  red cube at world +X and a blue one at −X through the actual front camera,
  which showed **+X renders on screen-right**. Cross-checked against the
  real mesh: `Left Obliques` centroid is at x=+0.13, `Right Obliques` at
  x=−0.13 (read directly off the imported OBJ, not assumed from the rig's
  own `.L`/`.R` bone-naming convention, which is a separate, arbitrary
  choice made in `build_armature`). Conclusion: positive local-Z bends the
  torso toward the subject's own right (screen-left) — correct for this
  exercise, since "Left Standing Side Bend" means bending right to stretch
  the left flank. **Lesson: don't eyeball left/right off a front-view render
  — a face-on camera mirrors it. Verify with a coordinate probe.**

### Fixed while at it
`show_popup()` now no-ops when `bpy.app.background` is true — calling
`popup_menu` with no window manager (any headless `-b` run) doesn't raise a
Python exception, it **segfaults Blender on exit** (after every file is
already written, so it's harmless but noisy — every headless run of the
original clasped-hands script had this crash too, unnoticed because it
happens post-export).

## Third batch (2026-08-03): 10 more exercises

Generated 10 more exercises reusing `_lib.py` and only already-validated bone-axis
conventions (head/spine/chest pitch ±X, side-bend ±Z, twist ±Y; the clasped-hands
arm-swing angles) — deliberately stayed off the hip/thigh/shin bones, which have
no proven pose-authoring convention yet. Shipped: `neck_extension_look_up`,
`chin_tuck_forward_head_reset`, `right_standing_side_bend`,
`standing_back_extension`, `cobra_stretch_prone_press_up`,
`left_seated_spinal_twist`, `right_seated_spinal_twist`, `reverse_prayer_stretch`,
`left_wall_bicep_stretch`, `right_wall_bicep_stretch`. All 10 exported valid
skinned glTF and rendered clean (no tearing) on first attempt — see
`Tools/blender/generated/exercises/THIRD_BATCH_INSTRUCTIONS.md` for the full
per-exercise writeup and instructions.

**New gotcha:** the twist exercises (first use of local-Y on the *vertical*
bones) exposed a blind spot in the `run()` sanity check — it logs the pose bone's
peak **tail world position**, but a bone twisting about its own long axis barely
moves its tail, so the log reads as a no-op even when the twist is real and
correctly mirrored between the L/R pair. Verified correctness by eyeballing the
rendered PNGs instead (confirmed the L/R pair are genuinely mirrored, not
identical) — don't trust the tail-position log for twist-only poses.

## Rotation audit (2026-08-05/07): Wall Bicep Stretch fix + seated leg pose

Audited all 14 shipped animations against their exercise's actual instructions
(see `docs/superpowers/plans/2026-08-05-rotation-animation-audit.md`). Found
`left_wall_bicep_stretch` / `right_wall_bicep_stretch` never rotated the
torso despite the exercise being "rotate your torso away from the wall" —
fixed by adding a `chest`/`spine` local-Y twist (small, 8-15 deg) alongside
the existing arm pitch, reusing the seated-twist sign convention (believed at
the time to be "positive Y = twist right", matching `left_seated_spinal_twist`).

> **⚠️ That sign was wrong** — and so was the seated twist it copied. `+Y`
> twists toward the subject's own LEFT. Corrected 2026-08-08; see the
> "Twist direction" section below for the probe and the fix.

**New proven convention: a static seated leg pose on `thigh.{L,R}`/
`shin.{L,R}`.** These bones had "no proven pose-authoring convention" as of
the third batch. Probed with a throwaway script
(`Tools/blender/exercises/_seated_probe.py`, deleted after validating —
recreate from this note if needed) applying a *constant* (not per-frame
animated) offset held across the whole clip:

```python
"thigh.L": (r(-90), 0, 0),
"thigh.R": (r(-90), 0, 0),
"shin.L":  (r(90), 0, 0),
"shin.R":  (r(90), 0, 0),
```

Result confirmed by both the tail-position log and eyeballing the render:
thigh tail moved from knee-height to hip-height at world Y = -0.42 (i.e.
swung forward to horizontal — recall azimuth-0's camera sits at world -Y, so
-Y = front, confirming hip *flexion* not extension), and shin tail landed
directly below at floor-adjacent height, i.e. the lower leg hangs straight
down from a forward-bent knee exactly like sitting on a chair/floor edge.
Render showed a convincing seated silhouette with no visible mesh tearing,
though the knee crease geometry is a bit blockier/pinched than the small-
angle poses used elsewhere (largest rotation applied anywhere in the rig
so far) — acceptable at the app's render style/resolution.

**Sign convention (thigh/shin, hip-flexion-and-knee-fold only, NOT yet
validated for anything dynamic like a swing/circle):** thigh and shin hang
down like the arm bones (not vertical like spine/chest/head), and empirically
follow the *same* local-X convention as the arms: thigh -90 = hip flexes
forward to horizontal (mirrors the arm's "-X = forward" for both L/R, no
sign flip needed between sides since this is directly forward, not lateral);
shin's follow-up local-X is relative to the thigh's already-rotated frame,
and needs the *opposite* sign (+90) to fold the lower leg back down rather
than up toward the torso — do not assume shin mirrors thigh's sign.

Applied to `left_seated_spinal_twist.py` / `right_seated_spinal_twist.py`
(previously rendered as a standing torso rotation despite the exercise name
— the docstring said as much: "The rig has no seated pose, so this reads as
a standing torso rotation"). The `_SEATED` leg offset is held constant at
every keyframe (0/30/60/90/120) with the existing twist keyframes layered on
top for spine/chest, same pattern as the probe.

**Still unproven:** anything that moves the legs *dynamically* mid-clip
(a lunge, a hip circle, a leg swing) — this convention only covers a static
held pose. Tier C in the rotation-audit plan (Standing Hip Circles, Runner's
Lunge with Rotation, World's Greatest Stretch, Dynamic Standing Leg Swings,
Cossack Squat) still needs its own probe before authoring.

## Twist direction (2026-08-08): the documented sign was BACKWARDS

**`+Y` on a vertical bone twists toward the subject's own LEFT, not right.**
Everything written before this section that says otherwise is wrong.

How the error survived: the third batch verified its twist exercises by
eyeballing the rendered PNGs and "confirming the L/R pair are genuinely
mirrored, not identical." That proves *symmetry*, not *direction* — a pair
that both twist the wrong way is still perfectly mirrored. The tail-position
log can't help either (a bone twisting about its own long axis barely moves
its tail), so nothing ever actually pinned the sign down.

Settled with `_twist_probe.py` (throwaway, deleted after use — recreate from
this note). The trick is to measure a point that *does* move under a torso
twist: the shoulder, i.e. the head of `upperarm.{L,R}`, which are children of
`chest`. With `chest` local-Y = +45:

```
REST                 upperarm.L head = (+0.230, +0.000, +1.533)
chest local-Y = +45  upperarm.L head = (+0.163, +0.163, +1.533)
```

The left shoulder moved to **y = +0.163**, i.e. BACKWARD (world −Y is the
front). Left shoulder back + right shoulder forward = rotation toward the
subject's own left. Cross-checked against mesh ground truth, not bone naming:
`upperarm.L`'s head sits at x = +0.230, and the real `Left Obliques` centroid
is at x = +0.13, so world +X genuinely is the subject's left.

**Corrected convention: `−Y` = subject's right, `+Y` = subject's left.**

Four shipped animations were rotating backwards and have been fixed:
`left_seated_spinal_twist` ("twist to the right"), `right_seated_spinal_twist`
("twist to the left"), and both wall bicep stretches ("rotate away from the
wall"). `left_seated_spinal_twist`'s camera also moved 45 → 315, since the
old azimuth was framed around the wrong-way rotation.

**Lesson to generalise: mirrored is not correct.** For any bilateral pair,
verify the ABSOLUTE direction of one side against the exercise's written
instructions, then mirror. Checking only that L and R differ will happily
pass two backwards animations.

## Fourth batch (2026-08-08): Tier A of the rotation audit

Shipped 12 new exercises, all on proven axes:
`seated_neck_rotation`, `seated_neck_rolls`,
`left/right_chin_to_shoulder_diagonal_stretch`,
`left/right_scalene_neck_stretch`, `left/right_doorway_bicep_stretch`,
`left/right_wall_corner_pec_stretch`,
`seated_spinal_rotation_overhead_reach_left/right`.
26 of 217 exercises now have animations (was 14).

### New gotchas from this batch

**1. Prefer `local-X` (flexion) over `local-Z` (abduction) on arm bones.**
Gotcha #2 explains why the source mesh tears when arms lift: it's modeled
arms-down, so torso vertices sit Euclidean-close to the arm bones. Lifting an
arm *sideways* drags that neighbouring torso sheet outward into the classic
"cape"; swinging it *forward* moves the arm off the torso surface instead of
across it. Measured in practice: 85° of abduction on `upperarm` stretched the
pec into a flat sheet, and 155° stretched the lat into a huge triangular
cape. Re-authoring the same poses as forward flexion (`−X`, up to −150°)
rendered cleanly. Shoulder flexion is also the anatomically correct path for
an overhead reach, so this is rarely a compromise.

**2. Camera azimuth and pose are coupled — a proven pose can still render as
garbage.** The static seated leg pose only reads from azimuth 45+. The thigh
points along world −Y, so any camera near azimuth 0 looks straight down its
long axis and the leg collapses into an unreadable blob. The neck family is
therefore rendered STANDING (their cameras are chosen for head legibility,
and sitting is incidental to a neck stretch — unlike the seated twists, where
bracing against folded legs is what isolates the spine).

**3. Watch cumulative forward pitch on the head skin cap.** spine 45 + chest
26 + head 20 = 91° drove the head cap down inside the chest mesh. Keep the
total under ~60° or stop pitching the head.

**4. Read the INSTRUCTIONS for direction, never the exercise name.** The
naming convention is not consistent across families. `Left Standing Side Bend`
names the side *stretched* (it bends right), but `Seated Spinal Rotation with
Overhead Reach (Left)` and `Left Standing Reach-Through Twist` say "rotate
your torso to the left" — they name the *direction*. Four exercises in this
batch would have been silently backwards if authored off the name.

### Deferred out of Tier A (the audit plan over-classified these)

The plan listed these as "proven conventions, ready to author now", but each
needs a base body position the rig has never represented:

| Exercise | Blocker |
|---|---|
| Left/Right Thread the Needle | starts **on hands and knees** — no quadruped pose convention. Approximating it as a standing twist would render identically to Standing Reach-Through Twist. |
| Left/Right Supine Chest Opener (Open Book) | **lying** — no supine pose convention |
| Left/Right Standing Reach-Through Twist | scripts authored and kept, but NOT shipped: three passes could not make the cross-body reach read as travelling across the body toward the opposite ankle. Cross-midline adduction collides with the torso (arms-down mesh, no clearance). See the scripts' own docstrings. |

Also note the audit plan's "Tier A batch (10 exercises)" undercounts — it
counted table rows, but most rows are L/R pairs. Tier A was really 18
exercises; 12 shipped, 6 deferred as above.

## Supine pose probe (2026-08-09): base pose + two of three follow-ups solved, 4 exercises shipped

Ran the Tier B "supine / lying pose" experiment the rotation-audit plan
flagged as highest-value (would unblock Supine Chest Opener, Supine Spinal
Twist, and Supine Figure-4, six exercises total). First pass shipped nothing
(three follow-on techniques all failed — see the "NOT solved" writeups
below, kept for the record since the failures themselves are useful data).
**Second pass fixed two of the three** with different techniques and
shipped 4 of the 6 exercises: `right/left_supine_chest_opener.py`
(side-lying, via an object-level roll instead of a second hips pose-bone
rotation) and `right/left_supine_spinal_twist.py` (flat-on-back, via a
direct `thigh` swing instead of a hips-twist-plus-counter-rotation). Only
Supine Figure-4 (L/R) remains blocked — the ankle-cross problem is a
genuinely different failure mode (mesh stretching from bone-distance, not a
rotation-composition or tearing-angle problem) and wasn't revisited.

**Proven: `hips` local-X = −90° (held constant across the whole clip) tips
the ENTIRE rig — spine/chest/head/arms/legs, everything downstream in the
parent chain — from standing to lying flat.** Validated numerically (a
throwaway `_supine_probe.py`, deleted after use — recreate from this note):
at rest, hips/spine/chest/head tails all sit at x=0, climbing z from 1.07 to
1.92. At `hips` local-X = −90, they all land at the SAME z (0.958) with y
climbing from 0 to 0.958 — a flat horizontal line, exactly a lying silhouette.
`+90` produces the mirror (also flat, but the front of the torso ends up
facing the ground instead of the sky — see below).

**Face-up (supine) vs face-down (prone) — the sign that matters:**
`hips` local-X = **−90 → supine (face up)**, confirmed by rendering (below);
`+90 → prone (face down)`. This follows the same "+X = forward pitch"
convention already documented for spine/chest/head (forward = world −Y) —
tipping forward past horizontal lands face-down, tipping backward lands
face-up. Unlike the twist-direction sign (Finding 4), this one was right on
the first guess, but was still verified rather than assumed, per the
handoff's own process.

**Camera: top-down, not the usual azimuth-around-vertical-axis orbit.**
Once the figure is lying flat, an "azimuth" camera (which orbits a vertical
axis at a fixed height, built for a standing figure) has nothing useful to
frame — a lying figure is roughly flat in one plane. A camera positioned
directly above the figure's center, pointed straight down (`rotation_euler =
(0, 0, 0)` — a bare Blender camera's un-rotated view direction is already
−Z, i.e. top-down, which is *why* `camera_for_azimuth` needs `rot=(90,0,th)`
to reach its normal level shots), reads cleanly: head at the top of the
portrait frame, feet at the bottom, matching the app's 4:5 clip aspect
almost exactly. Rendered and eyeballed — full front-of-body muscle detail
visible, face clearly pointing at the camera (confirming face-up), no
tearing. This is the convention to reuse for any future supine exercise.

**First-pass failures (kept for the record — useful negative results):**

1. **Side-lying roll, for Supine Chest Opener.** Read the actual instructions
   before trusting the exercise name: "Supine Chest Opener" instructs *"Lie
   on your right/left side"* — side-lying (lateral), not flat-on-the-back.
   The rotation-audit plan filed this under "the supine pose" without
   checking that; it needed its own, different base pose. First attempt —
   layering a `hips` local-Y rotation on top of the local-X −90 (hypothesis:
   X tips flat, a subsequent Y "rolls" the now-horizontal body over onto its
   side, the same way a person rolls over in bed) — **was wrong.** Rendered
   `hips = (−90, −90, 0)`: the body stayed face-up, just reoriented 90° in
   the horizontal plane. Euler XYZ composition on a bone already at −90 on X
   does not behave like an intrinsic "roll around the new local axis" the
   way the numbers suggested it should.

2. **Coupled thigh/shin tilt ("windshield wipers"), for Supine Spinal
   Twist.** First attempt: twist `hips` local-Y and counter-rotate `spine`
   local-Y by the same amount, hoping the two cancel and leave the upper
   body visually fixed. **They don't cancel** — probed numerically
   (`hips_y=+25, spine_y=−25`) and the spine/chest/head tails moved
   substantially (e.g. spine.x went from 0 to −0.146), proving simple
   sign-negation across a parent/child Euler pair isn't equivalent to
   canceling the parent's rotation once the parent already carries a large
   unrelated rotation (the −90 base pitch). Second attempt: swing
   `thigh.{L,R}` local-Z directly at 25° — kept the torso fixed (never
   touched) but visibly pinched/tore at the hip crease, the same
   "abduction tears geometry" failure mode documented for arm bones
   (Gotcha #1, fourth-batch section above), generalizing to the hip joint.

**Second pass — both fixed with different techniques, not more of the same:**

1. **Side-lying roll — fixed via an OBJECT-level rotation, not a second
   pose-bone rotation.** The failure above was stacking a second Euler
   component onto the `hips` POSE BONE, which composes in the bone's own
   already-rotated local frame — not the world-space "roll" the numbers
   implied. Instead, after posing `hips` local-X = −90 (pose bone, as
   before), rotate the ARMATURE OBJECT ITSELF around world Y (the axis the
   body now lies along, established by the base-pose probe): `arm_obj.
   rotation_euler = (0, r(roll_deg), 0)`. This is a genuinely different
   space — object-level transforms compose in true world space, applied
   after the internal pose — and it worked on the first retry: probed
   numerically (X and Z swap between bones, Y — the length axis — stays
   fixed) and confirmed by rendering, a clean side-lying profile with the
   face correctly visible (confirming face-up-on-the-side, not face-down).
   Sign: `roll_deg = +90` puts the RIGHT side up (lying on the LEFT side),
   `−90` puts the LEFT side up — verified by comparing bone-tail Z, not
   assumed. Landed in `_lib.py` as `apply_supine_base(arm_obj, roll_deg)`
   and `run_supine(cfg)`, a parallel entry point to `run()` for anything
   built on the supine base (recomputes camera bounds from the POSED mesh
   instead of the standing rest pose, and uses a top-down camera instead of
   the azimuth-orbit one `run()` assumes).
   Shipped: `right_supine_chest_opener.py` (`ROLL_DEG=90`, right arm
   sweeps from forward at shoulder height through overhead to behind via
   local-X flexion, `chest` gets a shallow twist alongside) and
   `left_supine_chest_opener.py` (mirror, `ROLL_DEG=-90`).

2. **Windshield-wipers tilt — fixed by using a much smaller angle, not a
   different axis.** The tearing at 25° was real, but re-tested at 10-15°
   and it was clean (this is the same lesson as the arm-abduction gotcha:
   the failure is angle-dependent, not axis-forbidden — smaller flexion-
   adjacent angles are fine, it's specifically *large* abduction-like
   swings that tear). Shipped at 20° at the peak keyframe (12° at the
   quarter-keyframes) — visible without tearing. Also **dropped the
   literal 90° "arms in a T-shape"** the instructions describe: reproduced
   the same known abduction-tearing at that angle (a "cape" forming at both
   armpits), so the shipped version uses 45° instead — a readable
   approximation of "arms out to the sides," not a literal T. Sign for the
   knee-swing and head-turn axes both confirmed by a coordinate probe
   against the written instructions (not eyeballed off the render, which is
   a mirrored top-down view and easy to misread — this is the same trap
   Finding 4 already documents). Shipped: `right_supine_spinal_twist.py`
   (knees fall left via `thigh` local-Z negative, head turns right via
   `head` local-Y negative) and `left_supine_spinal_twist.py` (mirror).

**Third pass (same session) — fixed too, via a pipeline-level rigging fix,
not a per-exercise pose trick:**

3. **Ankle-over-knee cross, for Supine Figure-4.** Swinging one `shin` bone
   across the midline (large local-Z on top of its normal knee-fold) to
   approximate resting an ankle near the opposite knee stretched the foot
   "mitt" (the convex-hulled hand/foot club described in `_lib.py`) into
   thin splayed webbing. This was NOT the same failure as the windshield-
   wipers tearing (that was angle-dependent and fixed by going smaller); an
   ankle cross needs a large swing to actually reach, so "use a smaller
   angle" wasn't available. **Root cause turned out to be generic, not
   specific to this pose:** mitts were weighted with the same joint-blend
   distance function (`blend_weights()`) used for actual stretchy muscle
   geometry — appropriate for a muscle belly that needs to deform across a
   joint, wrong for a mitt, which is a solid convex hull that shouldn't
   deform at all. A large swing left the mitt's far vertices pulled toward
   whichever second-nearest bone the blend picked at the ROTATED pose, and
   a rigid hull pulled by two competing weights is exactly what stretches
   into webbing. **Fix:** added `rigid_weight()` to `_lib.py` — 100% of
   every vertex to the mitt's one owning bone, no distance blending — and
   routed the hull-building loop through it instead of `blend_weights()`.
   Re-rendered the ALREADY-SHIPPED chest-opener/spinal-twist clips first to
   confirm no regression (hands/feet still hold shape at the wrist/ankle
   seam), then retried the same -45 to -60 degree ankle swing that
   produced webbing before: held its shape cleanly through the whole
   range. Getting the swing to not tear was one fix; getting it to read as
   an anatomically clean "figure-4" (ankle resting near, not just crossing
   near, the opposite knee) took several more rendered iterations of
   hand-tuning `thigh`+`shin` together (the crossing leg needs the THIGH
   externally rotated to open the knee out, not just a shin swing — tried
   shin-only first, reads as a kick, not a cross). The shipped values are
   the best rendered result this session, not a numerically-derived pose —
   a reasonable approximation, not precise ankle-on-knee contact. Shipped
   as `right/left_supine_figure_4.py`. Arms are kept in a relaxed forward
   position rather than animating the "reach through and clasp the
   opposite thigh" hand detail, which is out of scope for this pass.

Since the fix is a pipeline-level rigging change (not a pose trick specific
to Figure-4), it should also de-risk any FUTURE exercise needing a large
hand/foot swing to touch another body part — Thread the Needle's under-body
arm reach (Tier B) being the next candidate that would have hit the same
wall.

**Net result: all 6 target exercises shipped** (`right/left_
supine_chest_opener`, `right/left_supine_spinal_twist`,
`right/left_supine_figure_4`), verified in the running app via
`SupineExercisesUITests` (all six open and play in `ExerciseMediaCard` with
correct muscle-target chips), unit tests green.

## Quadruped pose probe (2026-08-09): first hands-and-knees pose, Thread the Needle shipped

Followed up on the "should de-risk Thread the Needle" note above by
actually attempting it — a genuinely new base pose, not a variant of the
supine work, since nothing in the rig had ever been posed on all fours
(originally Tier A in the rotation-audit plan, moved to Tier B 2026-08-08:
"no quadruped pose convention exists").

**First attempt (rotation only) put the pelvis floating in mid-air with the
legs and arms dangling, nowhere near the ground.** Bending `spine` forward
90°+ (reusing the proven "+X = forward pitch" convention) correctly
horizontals the torso, but `hips` — the unparented root bone — doesn't
move in world space under its OWN rotation, and I hadn't rotated it
(deliberately, to keep the legs from tipping the way they did in the
supine work). Result: the pelvis stayed pinned at standing hip height
(~1.07 in these units) with nothing lowering it to a kneeling stance.

**Fix: an OBJECT-level Z translation, `arm_obj.location = (0,0,-drop)`.**
Same category of move as the supine roll being an object-level rotation
rather than a pose-bone one — anything that needs to change the RIG'S
overall position/orientation in world space, rather than a limb's pose
relative to its parent, belongs on the object, not a bone. `drop=0.55`
(found by probe + render, not derived) puts the knee at floor level with
`thigh` left near its standing rest angle. Landed in `_lib.py` as
`apply_quadruped_base()` / `run_quadruped()`, parallel to the supine
entry points — camera is a normal level azimuth shot (reusing
`camera_for_azimuth`) rather than top-down, since a quadruped figure reads
from the side like a standing one, just lower and horizontal.

**Getting the arm to reach the floor took several more iterations and
confirmed the seated-pose lesson generalizes: bounds-driven algebra is
unreliable this far into compound rotations.** The shoulder, after the
spine's forward pitch, is no longer directly above the hand the way it is
standing — an arm pitched by a rough estimate (-15°) left the wrist
44% of body-height off the ground. The angle is very sensitive because it
inherits the torso's already-large pitch: small forearm changes produced
large world-space swings once the upperarm was already near -70°. Settled
by iterating render + tail-position log together (not by computing it):
`upperarm` -68°, `forearm` +25° puts the hand at the floor for a planted
support arm.

**Thread the Needle's reach-under motion is a genuine approximation, not a
literal "hand slides through the gap."** The instructions describe the
arm sliding underneath the torso; three passes on the unrelated Standing
Reach-Through Twist already found that cross-midline arm adduction
collides with this torso mesh (documented earlier in this file), so the
same problem was expected here. What shipped instead: the reaching
`upperarm` swings to -140° (well past the support arm's -68°, deep
flexion) combined with a `chest`/`spine` twist (the already-proven
local-Y convention) so that shoulder visibly lowers and the head turns
down toward it — reads as "shoulder and ear toward the mat," the more
prominent part of the instructions, at the cost of the arm curling up
near the shoulder rather than extending out under the body. Shipped as
`right/left_thread_the_needle.py`, verified via `SupineExercisesUITests`
(renamed to cover 8 exercises now, all pass) — plays correctly in
`ExerciseMediaCard` with correct muscle-target chips.

**All originally-scoped Tier B rotation-audit exercises building on a new
base pose are now shipped**: supine (6) + quadruped (2) = 8.

## Reach-through twist, second attempt (2026-08-09, same day): shipped

The cross-midline arm adduction that blocked Standing Reach-Through Twist
(three failed passes, deferred 2026-08-08 with scripts kept but not
shipped) got a fourth attempt, per the "one more try" ask after the
quadruped work. **Fixed — and the fix was to stop trying to fix the same
axis.** Every prior pass used `upperarm` local-Z (adduction) to swing the
arm across the midline, which is documented elsewhere in this file as the
axis that tears the torso (arms-down source mesh, no clearance for
anything crossing the centerline). The fourth pass drops local-Z from the
reaching arm ENTIRELY — pure local-X flexion, taken deep (-140°, already
proven safe up to -150° for the chest-opener and wall-bicep work) — and
lets the `chest`/`spine` TWIST do the work of carrying the arm across
instead, using a much bigger twist angle (35°+20° cumulative) than the
shallow 8-15° twists used elsewhere. Rendered clean on the first try with
this approach: no tearing, and the reach genuinely reads as travelling
down and across toward the opposite ankle from multiple camera angles
(confirmed with 3 azimuths before committing to the shipped one).

Lesson to generalize: the earlier three-pass failure was diagnosed
correctly ("adduction collides with the torso") but the fix attempted each
time was still local-Z, just at different magnitudes/combinations. The
actual fix was recognizing the SAME visual effect (arm reads as crossing
the body) is reachable via a completely different axis (the torso's own
twist) that doesn't touch the failing one at all — same shape of insight
as the supine chest-opener roll (object-level, not another pose-bone
rotation) and the figure-4 mitt fix (rigid weighting, not a smaller angle).
When an axis is documented as failing, look for a DIFFERENT axis that
produces the same visual result, not a smaller/bigger version of the same
one.

Shipped `right/left_standing_reach_through_twist.py` (overwriting the
NOT-SHIPPED scripts kept from 2026-08-08), verified in the running app via
a new `ReachThroughTwistUITests` (parallel to `SeatedSpinalTwistUITests`) —
both open and play in `ExerciseMediaCard` with correct muscle-target
chips. Full unit suite still green.

**Remaining Tier B/untried items**: arm-bone Y-twist (Sleeper Stretch,
Doorway External Rotation) and `hips` local-Y twist for anything other
than the windshield-wipers workaround remain fully untried.

## Supine Spinal Twist hip-crease tear (2026-08-19)

Reported as "visual glitch/tearing" in the shipped `right/left_
supine_spinal_twist` clips. Not the windshield-wipers swing-angle tearing
already documented above (that was fixed and re-verified 2026-08-09) — this
was a base-pose bug: `thigh.{L,R}` local-X = `-90`, composed on top of the
`-90` base pitch already sitting on `hips`, folded the knees into a tighter
tuck than any other shipped supine exercise. It tore a visible dark gap
between the thighs at the hip crease, seen from the top-down supine
camera — present even at frame 0 (rest), before any windshield-wiper
motion, so `SupineExercisesUITests` (which only checks the clip opens and
plays, not its pixel content) never caught it.

Confirmed by reposing the already-built `.blend` (no rebuild needed — vertex
weights are baked once from the rest pose in `build_figure`/`blend_weights`,
independent of the animated pose) at several `thigh` local-X angles: `-90`
tore, `-75`/`-60`/`-45` were all clean at rest. Picked `-75` (closest to the
original, keeps the "knees bent" read as tucked as possible) and re-checked
it clean at the peak twist pose too. Fix: dropped the constant base fold in
both scripts' `POSES` from `-90` to `-75`, re-ran both scripts headless,
re-encoded both `.mp4`s via `encode_mp4.swift`, replaced the two files in
`Resources/Animations/`.

Lesson for future supine/bent-knee poses: the top-down supine camera looks
straight into the hip crease in a way no azimuth (side) camera ever does —
a fold angle that reads fine from the side (e.g. `apply_seated_base`'s own
`-90` thigh fold) can still tear when viewed top-down. Render and zoom into
the actual crease before shipping a new bent-knee supine pose, don't just
eyeball the full-body thumbnail.

**Follow-up, same day: the tear fix shipped without watching the motion.**
The check above only compared still frames (rest + peak) before and after —
it never played the clip back. Reported again as "the body's legs are
swinging" — watching a 3x3 grid sampled across the full 4s clip (not just
one frame) showed why: the whole leg (thigh+shin, rigid, no independent
knee articulation) swings sideways from the hip like a pendulum, and
untucking the base fold from `-90` to `-75` above made it worse — the same
degrees of `thigh` local-Z now lever a longer, less-foreshortened leg, so
the feet sweep further at the same angle. The swing amplitude itself (peak
20°, quarter 12°) had silently drifted from this script's own docstring,
which always claimed "kept small, 10deg" — apparently changed during the
2026-08-09 tearing fix and never reconciled with the comment. Fix: reduced
to peak 10° / quarter 6°, matching the stale docstring claim, and this time
re-checked the full frame-grid across the whole clip (not just rest/peak
stills) before re-shipping.

**Process lesson, not just a pose lesson:** for any exercise whose defect is
about motion (tearing during a swing, a swing reading as too big/small/
wrong), verifying a `rest_demo`/`peak_demo` still pair is necessary but not
sufficient — sample frames across the whole clip (a `fps=10` extract into a
3x3 grid worked well) and actually look at the motion arc before calling it
fixed.

## Supine Spinal Twist reads as standing, not lying down (2026-08-19, same day)

Reported a third time on this exercise, after the tearing and swing-amplitude
fixes above: the shot itself looked like a standing figure in a T-pose, not
someone lying down. This was a real, previously-unquestioned bug in
`camera_topdown` (the shared camera every ROLL_DEG=0 supine exercise uses) —
an orthographic straight-down camera is mathematically IDENTICAL in
silhouette to a front view of a standing figure. No pose tuning could have
fixed it; every earlier fix on this exercise only ever touched the pose.

## Tenth batch (2026-08-21): 71 -> 131, session target reached

Continued the 130-exercise push across seven reviewed batches (batches
10-16 in this session's numbering), each individually rendered
(skins:1/anims:1, 0 fallback muscles, checked for tearing), visually
reviewed against the exercise's own written instructions before wiring,
and verified against the full test suite before committing.

Shipped, by shape: prop-only pose reuses (towel/wall/strap variants of
already-proven overhead-triceps and doorway-chest poses — no new
mechanics, just different assistive-prop framing in the instructions);
new small-angle conventions (shoulder-height horizontal adduction for
cross-body poses, `thigh` HIP EXTENSION for the first time — standing
tibialis toe-point and step-edge calf drop — verified clean on first
render); new base-pose combinations (chair-sit + thigh abduction for
seated figure-four, asymmetric left/right leg poses in the seated family,
a side-lying deep knee fold reusing sleeper_stretch's `ROLL_DEG`
convention); and the first real use of the PRONE half of the supine-probe
finding (`hips` local-X = +90, Prone Neck Retraction) — previously only
theorized in this doc, never rendered.

**New pipeline limitation surfaced and documented, not fixed:** hand/foot
"mitts" always render in the neutral material
(`mitt.data.materials.append(mat_neutral)` in `build_figure`) regardless
of `WORKED_KEYWORDS` — a `Left Foot`/`Right Hand`-targeted exercise can
never show its target muscle highlighted, only the surrounding limb. Hit
directly on Left/Right Plantar Fascia Stretch (0 highlight objects in the
log, not a bug — confirmed by reading the mitt-coloring code). Flagged
`animationIsApproximate` for those two rather than silently shipping an
unhighlighted clip. Worth a real fix (per-mitt highlight material keyed
off whether the ORIGINAL pre-hull muscles were in the highlight set)
if more foot/hand-targeted exercises come up.

**Approximation classes used this batch, for future reference:**
- Downward-Facing Dog: substituted a very deep standing forward fold for
  the actual raised-hip inverted-V (this rig can't lift the pelvis above
  a straight-leg stance the way `apply_quadruped_base`'s object-level drop
  lifts it for a KNEELING stance).
- Standing IT Band Side Stretch / Standing Crossed-Leg Fold: a small
  constant thigh angle standing in for literal ankle-crossing contact.
- Wrist/ankle-joint motions (wrist circles, toe-point, toe-raise): this
  rig has no independent wrist or ankle joint (rigid mitt on the
  forearm/shin bone), so any exercise whose actual mechanism is at the
  wrist or ankle can only show the limb holding a static/near-static
  position with the target muscle highlighted, never the joint motion
  itself.

131/217 exercises now have animations (was 71 at the start of this
session's push). 86 exercises remain unanimated — mostly breathing
techniques and jaw/eye/face micro-exercises (no rig precedent for either;
see "Related project context" below for the scope discussion), plus a
handful of harder leg poses (kneeling hip-flexor lunges, Bridge Pose,
Cossack Squat) that need their own base-pose probes before attempting.

**Fix: `camera_oblique_supine` in `_lib.py`** — an elevated, pulled-back,
angled-down PERSPECTIVE camera, replacing `camera_topdown` for the flat
ROLL_DEG=0 family specifically (`right/left_supine_spinal_twist`,
`right/left_supine_figure_4` — figure-4 hasn't been re-rendered yet, same fix
applies whenever it's touched next). ROLL_DEG!=0 exercises (chest-opener,
sleeper-stretch) keep `camera_topdown` — the side roll itself already
provides depth cues an orthographic top-down shot lacks, so they don't have
this bug. See `camera_oblique_supine`'s own docstring in `_lib.py` for the
full tuning derivation (why a flat colored floor plane was tried and
rejected, why the azimuth has to stay small or it foreshortens the exercise's
own motion away, the `shift_y` recentering trick).

**Two more defects surfaced by the SAME camera change, each requiring its own
fix — a reminder that changing one axis of a render (camera) can regress
axes that were already correct (pose):**

1. The oblique camera looks into the hip crease from the side, where the
   -75 fold (clean from directly overhead) tore again. Angle sweep re-run
   against the new camera: -45 was the first clean angle from both views.
2. At -45, a NEW defect appeared that was never a tear (confirmed by
   checking a transparent-background render for a literal hole, and by a
   one-off Cycles/EEVEE comparison render) — a solid near-black blob at the
   inner knee/hip. Ruled out lighting config first (FLAT shading, several
   MATCAP presets, `shadow_intensity` at 0 — all still showed it except
   FLAT, which also removes the muscle-definition shading the app needs).
   The EEVEE render showed a fainter version of the same patch, which is
   the tell: a real, deep self-shadow crevice in the geometry at that fold
   angle that Workbench's no-fill-light single directional shading renders
   as flat black instead of a soft gray. Shallower angles reduce the
   crevice itself — swept again, -20 was the first fully clean angle.

Net change from the original shipped version: base thigh fold -90 → -20
(a much shallower "knees bent" than originally authored — every tighter
angle re-tried reintroduced either the tear or the blob), swing peak 20° →
10°, arm angle 45° → 25°, camera top-down → oblique. Re-verified the full
`fps=10` 3x3 frame-grid one more time at each step, specifically re-checking
the hip-crease region (not just eyeballing the whole figure) since that's
where two of these three defects lived.

**If Figure-4 (or any new ROLL_DEG=0 supine exercise) is touched next:**
expect to re-run this same angle-vs-camera sweep rather than assuming
whatever thigh fold Figure-4 currently ships with is still safe — the
tear/blob thresholds are a property of the (pose, camera) pair, not the
pose alone, and Figure-4 was never re-rendered against the new camera.

## Getting closer to a real 90-degree bent knee (2026-08-20, same day)

The -20 fold above was clean but didn't read as an actual bent-knee
position — asked to get closer to a real 90 degrees. Instead of continuing
to trade the angle down (the pattern in every fix above), went at the root:
`blend_weights`'s defaults (`BLEND_TOP_K=2`, `BLEND_POWER=4.0`) were tuned
against ordinary single-joint folds; this hip fold is a compound one
(`thigh` local-X composed on top of the `-90` already on `hips`) that no
other exercise's joints ever attempt, so the default blend was arguably
undertuned for it from the start rather than the angle being the real
problem.

**Method:** vertex weights are baked once in `build_figure`, from the
REST-pose mesh, independent of the animated pose — so testing a different
`BLEND_TOP_K`/`BLEND_POWER` requires a full rebuild from the OBJ each time
(unlike the earlier pose-only sweeps, which could reuse an already-built
`.blend`). Copied `_lib.py` to a scratch location, edited the constants
there, and ran a throwaway script importing the scratch copy — kept the
real `_lib.py` untouched until a setting was proven, so a bad experiment
couldn't corrupt the shared module mid-sweep.

**Result:** `top_k=3, power=1.5` (more candidate bones per vertex, gentler
distance falloff so the blend reaches further) closed nearly all of the
-75 crease that the default `top_k=2, power=4.0` left open, and was also
visibly better than the default at a literal -90. But -90 itself never
fully closed, even pushed to `top_k=4`/`power=1.5` — strong evidence this
is a real geometric limit (very likely a modeling-time seam between the
thigh and hip meshes in the source OBJ, where they were never made to
overlap enough to survive an extreme fold) rather than something a
skinning-weight blend can indefinitely paper over by throwing more blend
at it.

**Shipped:** added `blend_top_k`/`blend_power` as optional parameters on
`build_figure`/`blend_weights`, defaulting to the original module constants
— every other exercise's build is byte-for-byte unaffected. `run_supine`
passes `top_k=3, power=1.5` automatically whenever `ROLL_DEG==0` (see its
docstring in `_lib.py`). Re-tightened the base fold from -20 back to -75
(not all the way to -90) — the same -75 that tore under the OLD default
blend right after the camera fix above, but holds clean-enough under the
new one. A faint crease is still visible on close zoom at -75 (see the
frame-grid zoom used to verify it) — better than every earlier -75 attempt,
not a total elimination.

**For Figure-4 or any future ROLL_DEG=0 exercise:** the wider blend is
already automatic via `run_supine` (nothing extra to opt into), but the
same "-90 never fully closes" ceiling likely applies — expect to sweep the
fold angle again rather than assuming -75 (or any specific number) is
universally safe; it's tuned against this exercise's specific geometry
extent, not derived from a general formula.

## Camera azimuth made the flat lying figure read as diagonal (2026-08-20, same day)

Reported as "rotate the hips so it's flat" — a mismatch between what the
words point at (the `hips` bone, already fixed at exactly -90, perfectly
flat in world space) and what was actually wrong (the CAMERA's azimuth
offset, `camera_oblique_supine`'s `xfrac=0.2`, which rotated the figure's
projected long axis away from vertical in-frame — the figure read as
propped up at a diagonal, like sitting up, not lying flat left-to-right in
the portrait frame). Confirmed the intended meaning with a clarifying
question before touching anything, since "hips" could also have meant the
knee-bend angle (the previous fix) or the pelvis/torso shape itself — each
would have pointed at a different file.

**Fix:** `camera_oblique_supine`'s `xfrac` default dropped from `0.2` to
`0.0` — camera centered directly behind the feet, no azimuth swing. This
was the exact tradeoff the function's own docstring called out when 0.2 was
picked over 0 (see the "reads as standing" fix above): 0 was rejected then
because it views the windshield-wipers knee-swing more head-on, closer to
foreshortening the motion away. Re-checked that concern directly this time
— diffed a rendered rest/peak pair at `xfrac=0` and the swing is still
visibly different frame to frame, just less dramatic than at 0.2. Given the
choice between "motion reads a bit more subtly" and "figure reads as
sitting up instead of lying flat," flat won.

Also re-checked the hip crease and the self-shadow blob at the new camera
angle (yet another camera change, same lesson as before: re-verify both
known failure modes any time the viewing angle changes) — both still clean
at `xfrac=0` with the -75 fold and the wider blend weights from the fix
above.

**Lesson: when a user's wording names a specific part ("the hips"), verify
what they're pointing AT before assuming they mean the part literally** —
here it named the one bone in the whole rig that was already exactly
correct, and the real defect was one layer removed (the camera). A single
clarifying question (three concrete options: camera-diagonal, knees-too-
bent, or pelvis-itself-looks-wrong) settled it in one round trip instead of
guessing and re-rendering.

## Fifth batch (2026-08-20): 5 exercises + a head-twist sign bug found in review

Started the next batch of exercises (target: 30, working through the 177
seed exercises still without an animation). Picked the lowest-risk next 5 —
close analogues of already-shipped families, to validate the batch workflow
before spending render/probe time on riskier poses: `left/
right_levator_scapulae_stretch` (neck pitch+turn, same two axes as
`left/right_chin_to_shoulder_diagonal_stretch`), `left/
right_upper_trapezius_stretch` (neck side-bend only, same axis as the
scalene family), `standing_chest_expansion_stretch` (arms clasped behind
the LOWER back with straight arms — geometrically close to
`clasped_hands_behind_back`/`reverse_prayer_stretch`, just less elbow
flexion). All 5 built clean (skins:1, anims:1, 0 fallback muscles, no
tearing in the rendered frames).

**Bug found while reviewing the new Levator Scapulae scripts against their
own reference pose (chin_to_shoulder_diagonal): the head bone's local-Y
twist sign was backwards in 4 already-shipped exercises.**
`left/right_chin_to_shoulder_diagonal_stretch.py` and `left/
right_scalene_neck_stretch.py` (fourth batch, 2026-08-08) were authored on
the belief that `head` local-Y follows its own convention, independent of
the "Twist direction" fix already documented above for chest/spine
(`+Y = subject's own LEFT`) — that fix's own note only lists 4 corrected
exercises (both seated spinal twists, both wall bicep stretches), and never
re-checked the head bone specifically.

Settled with a throwaway numeric probe (`_head_twist_probe.py`, scratchpad,
recreate from this note if needed — same technique as the original chest
twist probe, adapted to the head): built the figure, posed `head` local-Y
alone at +30, and tracked which side of the head-skin cap moved toward the
front camera (world −Y). The vertex on the subject's own RIGHT side (world
−X, per the already-established "+X = subject's left" fact) moved to −Y
(forward); the LEFT-side vertex moved to +Y (backward). Front-side-forward
on the right = a turn toward the subject's own right happens under
**negative** Y, not positive — the head bone was never actually an
exception, it just never got audited after the chest/spine fix landed.

**Fixed 4 shipped exercises** (`left/right_chin_to_shoulder_diagonal_stretch`,
`left/right_scalene_neck_stretch`) by flipping the sign of `head`'s Y
component only (X pitch and Z side-bend were never in question — this bug
is specific to the twist axis). Re-rendered and re-encoded all 4 clips;
replaced the bundled mp4s. New `left/right_levator_scapulae_stretch.py`
shipped with the corrected sign from the start.

**Lesson to generalize further than the original "Twist direction" section:
a sign convention proven for one bone in a chain is not automatically proven
for every bone in that chain** — even though local-Y = twist is true for
*any* bone regardless of orientation (Gotcha #6), which specific world
direction that twist resolves to for a CHILD bone (head, a child of chest)
still needs its own check, because the probe that established the chest/
spine sign only ever moved a chest-relative landmark (the shoulder). Head
inherited the same sign here, but that was confirmed, not assumed.

45 of 217 exercises now have animations (was 40 before this batch — see the
running total via `python3 -c "import json;
d=json.load(open('Breath - Relax & Stretch/Resources/SeedData.json'));
print(sum(1 for e in d['exercises'] if e.get('animationName')))"`). 25 more
to go to hit this batch's 30-exercise target.

## Sixth batch (2026-08-20, same day): 6 more exercises, two new `_lib.py` capabilities

Continued toward the 30-exercise target: `suboccipital_release_finger_press`
(repeated small nod, reusing the chin-tuck/chin-to-chest axis but with an
oscillating down-up-down keyframe pattern instead of a single hold),
`prayer_stretch_palms_together_lower` (forearm flexion sweep with a
Z-angle that SCALES with how extended the arm is, not a fixed offset — see
below), `left/right_overhead_triceps_stretch` (first pose to combine a deep
overhead upperarm flexion with a large separate forearm fold on top of it),
`left/right_single_leg_supine_knee_to_chest` (first supine exercise where
only one leg moves).

**Two review-driven fixes, both worth generalizing:**

1. **A fixed angular offset doesn't hold two hands together across a
   changing reach length.** `prayer_stretch_palms_together_lower`'s first
   render used the same forearm local-Z angle at both the folded-up (hands
   near chest) and extended-down (hands near waist) keyframes. Hands met at
   the chest but were visibly splayed apart at the waist — the same Z angle
   closes a smaller linear gap on a short lever (folded elbow) than on a
   long one (extended elbow). Fixed by scaling the Z angle up as the
   forearm extends (9 -> 28 deg chest-to-waist) instead of holding it
   constant. Generalizes to any future two-hands-together pose across a
   changing reach.
2. **Straight-line pose composition (Gotcha's "angles add" shortcut) gets
   you the wrong endpoint when the goal is a specific hand position, not
   just a direction.** `left/right_overhead_triceps_stretch`'s first attempt
   (`upperarm -160, forearm -70`, reasoning purely from "both bones rotate
   about the same fixed world-X axis so their angles add") pointed the
   whole arm-plus-forearm line up-and-behind, with the hand reaching skyward
   past the head instead of dropping behind it. The fix wasn't a different
   axis or a smaller angle (the usual fixes elsewhere in this doc) — it was
   recognizing that "hand behind the head" needs the FOREARM SEGMENT's own
   direction (not the whole chain's net direction) to point back-and-down,
   which requires a much bigger forearm fold (-150, not -70) than the
   straight-line intuition suggested. Confirms the doc's standing lesson
   (quadruped arm reach, "bounds-driven algebra is unreliable this far into
   compound rotations") extends to composed-X-axis poses too, not just
   poses with mixed Y/Z components.

**Two `_lib.py` additions, both opt-in / backward compatible:**

- `run_supine`'s `FORCE_TOPDOWN=True` cfg flag lets a ROLL_DEG=0 (flat)
  supine exercise use the plain overhead camera instead of the family's
  usual `camera_oblique_supine`. Needed for the single-leg knee-to-chest
  pair: their working motion (a hip-flexion knee lift) foreshortens to
  near-invisibility from the oblique camera (tuned for the windshield-
  wiper exercises' side-to-side sweep) but reads clearly from directly
  overhead. Every existing ROLL_DEG=0 caller leaves this unset, so their
  behavior is unchanged.
- The single-leg knee-to-chest pair also re-tested (rather than assumed)
  whether the proven -75 hip-flexion ceiling (established for a SYMMETRIC
  two-leg fold — see "Getting closer to a real 90-degree bent knee") holds
  for an ASYMMETRIC single-leg fold: it does not need to stay that shallow.
  -100 on the one working thigh (other leg untouched) rendered clean, no
  hip-crease tear, under the same wider ROLL_DEG=0 blend. Worth re-checking
  again (not assuming -100 either) if a future exercise needs an even
  deeper single-leg fold — the ceiling was pushed once, not derived.

51/217 exercises now have animations (was 45 before this batch).

## Seventh batch (2026-08-20, same day): 6 more exercises, 17 of this session's 30-exercise target so far

Continues this session's 30-exercise push (17 shipped across batches
five-seven, all reviewed and committed individually — see the earlier
batch sections for the first 11; 13 more to go). This batch: `double_knee_to_chest_release`
(symmetric version of the single-leg pair — deliberately kept the peak hip
fold at -85, not the single-leg script's -100, since the -100 ceiling was
only proven for an ASYMMETRIC fold and this is the SYMMETRIC case the
rotation audit already found tears at -90), `pelvic_tilt` (a genuinely
subtle motion — animated via a small oscillating `spine` pitch instead of
the `hips` root bone, since rotating the root would move the whole figure
and read as a much bigger motion than a real pelvic tilt),
`seated_forward_fold` (first `run_seated` exercise with STRAIGHT legs —
`shin` held at 0 instead of the family's usual +90 fold),
`standing_hamstring_stretch` (same shape as
`standing_forward_fold_ragdoll.py`, shallower), `left/
right_standing_side_reach` (side-bend axis from the standing-side-bend
family + an overhead arm reach — the arm needs no adduction of its own
since it inherits the chest's lateral bend as a child bone).

57/217 exercises now have animations (was 51 before this batch).

## Eighth batch (2026-08-20, same day): 6 more exercises, 23 of 30

`sphinx_pose` (reuses cobra_stretch_prone_press_up.py's standing-arch
fallback for prone poses, gentler; flagged `animationIsApproximate` since
substituting standing for prone is a bigger simplification than most
unflagged approximations in this family), `prayer_push_against_wall`
(hands stay apart at forward reach, unlike prayer_stretch's midline clasp),
`left/right_cow_face_arm_stretch` (first exercise to combine two
independently-proven arm poses on opposite arms at once — the overhead
triceps drop-behind-the-head shape on one side, the clasped-hands
behind-the-back reach on the other), `legs_up_the_wall` (first exercise to
raise the legs to fully vertical), `reverse_prayer_shoulder_mobiliser`
(same pose as reverse_prayer_stretch.py, different highlight tags).

**One review-driven camera fix:** `legs_up_the_wall`'s first render used
`CAMERA_AZIMUTH = 0`, copying left_sleeper_stretch.py's "0 views from
directly in front" claim by analogy. That claim only holds for a ROLLED
(side-lying) pose, where the roll has already moved the body's front-facing
direction into the plane `run_supine_side`'s camera orbits (X/Z). This
exercise stays flat (never rolled), so azimuth 0 put the camera on the same
world-Z axis the legs swing toward — foreshortening the whole motion away,
the same failure class `run_supine_side` exists to avoid, just triggered by
copying a sibling's camera number instead of solving for this exercise's
own motion plane. Fixed by solving properly: azimuth 90 views the Y-Z plane
(where the leg swing actually happens) edge-on. Generalizes past this one
script: a camera angle proven for one pose is only proven for THAT pose's
geometry (rolled vs. flat, in this case) — copy the reasoning, re-derive the
number, don't copy the number.

63/217 exercises now have animations (was 57 before this batch). 23 of this
session's 30-exercise target shipped so far; 7 more to go.

## Ninth batch (2026-08-20, same day): 8 more exercises, hits and slightly exceeds the 30-exercise target

`left/right_doorframe_hamstring_stretch` (single-leg version of
legs_up_the_wall.py — one leg to vertical, the other flat), `left/
right_overhead_shoulder_stretch_with_strap` (both arms overhead, tipped
back, one arm "leading" by a few extra degrees rather than a different
axis), `left/right_overhead_reach_lat_stretch_with_strap` (bilateral
version of left/right_standing_side_reach.py — both arms overhead instead
of one, same side-bend), `wrist_flexor_prayer_stretch` (identical
instructions/pose to prayer_stretch_palms_together_lower.py, different
highlight tags) and `wrist_extensor_reverse_prayer_stretch` (the same
pose's keyframes run in reverse — starts low, raises to the chest, instead
of starting high and lowering).

All 8 reused already-proven poses/conventions directly (no new base poses,
no new axis probes needed) — reflects the batch working through the
lowest-risk remaining candidates in the 177-exercise backlog first, per the
project's own stated strategy from the fifth batch. No new gotchas this
batch; every render was clean on the first or second attempt using
existing conventions.

71/217 exercises now have animations (was 63 before this batch). **31 of
this session's 30-exercise target shipped** (five batches, fifth through
ninth), each individually rendered, skin/anim-validated, visually reviewed
for tearing and correct direction, wired into SeedData.json, and verified
against the full SeedDataTests/SeedMigratorTests suite before committing —
plus one real sign-bug fix caught and corrected in 4 pre-existing shipped
exercises (see the fifth batch's writeup) along the way.

## Related project context

- Body Map architecture / SceneKit loading: `Breath - Relax &
  Stretch/Views/BodyMap/BodySceneView.swift`; memory `bodymap-3d-skin-architecture`,
  `anatomy-model-replacement`.
- Blender export pipeline that produces the app OBJ: `Tools/blender/export_skin_muscle.py`
  (welds skin patches, bakes app-space coords, tags muscles). Run `graphify
  query "..."` for codebase questions (see project `CLAUDE.md`).
- Copyright/asset-sourcing: **`ASSET_CREDITS.md` (repo root) is now the
  authoritative record** — Z-Anatomy CC-BY-SA 4.0 over BodyParts3D CC-BY-SA
  2.1 Japan, the full author list, the modifications statement, and the note
  that **the rendered `.mp4` loops are themselves derivative works** carrying
  the same terms. Two things settled there: CC-BY-SA *permits commercial use*
  (the old "share-alike concern for a paid app" framing was misplaced — the
  real obligations are attribution + share-alike on the assets), and none of
  Z-Anatomy's NonCommercial-licensed reference models (inner ear, kidney) are
  in this app's mesh, which was verified against `skinmuscle_node_names.json`
  (269 nodes, layers = skin/muscle only). Broader video-sourcing analysis:
  `docs/superpowers/plans/2026-07-12-exercise-video-animation.md`.

## Full animation-vs-instructions audit (2026-08-21): 2 real bugs found and fixed, most flags were mosaic misreads

Asked to check all 131 shipped animations against their exercise's written
instructions. Ran it as 6 parallel review agents (one per ~22-exercise
slice), each given a low-res 5x4 frame-grid contact sheet per clip (ffmpeg
`select`+`tile`, sampling the whole 4s loop into one image) plus the
exercise's instructions, flagging anything that looked directionally or
anatomically wrong. Got back ~20 flagged exercises, including an apparent
family-wide "Right variant bends the same way as Left instead of
mirroring" bug across the standing side-lean family.

**Before touching any code, re-verified every flag against clean single
full-resolution frames extracted directly from the shipped mp4** (not the
mosaic) — and against the dedicated `_peak_front.png`/`_peak_demo.png`
renders already sitting in `generated/exercises/` where available. This
caught that **the mosaic's 200px-wide tiles are not reliable for left/right
or direction judgments**: of ~20 flags, only 2 were real bugs. False
positives included the "Right Standing Side Bend/Crescent Moon/Side Reach
not mirrored" claim (checked with clean single-frame stills of both
variants side by side — they ARE correctly mirrored, matching their pose
scripts' documented opposite-sign math), "Left/Right Seated Spinal Twist
twisting backward" (the code's signs match the twice-verified `-Y=right,
+Y=left` convention exactly; the visual read was confused by the pair
using genuinely different camera azimuths, 315 vs 45), "Standing
Crossed-Leg Fold shows no motion" (it does — a full forward hinge, just
subtle-looking at mosaic thumbnail res since the legs stay together),
"Left Plantar Fascia crosses the wrong leg" (correctly mirrored on
inspection), and several "missing highlight" claims (Left/Right Upper
Trapezius, Neck Flexion, Right Supine Figure-4) where the highlight is
real but small/partially occluded from that camera angle, not absent.
**Lesson: a low-res contact sheet is fine for triage but not a verdict —
re-check any flagged left/right or highlight-visibility claim against a
full-res single frame (or the dedicated peak renders) before writing a
line of fix code.**

**Bug 1 (confirmed, fixed): `FORCE_TOPDOWN` exercises inherited the exact
"reads as standing, not lying down" defect that `camera_oblique_supine`
was built to fix.** The 2026-08-19 fix (see above) replaced
`camera_topdown` with `camera_oblique_supine` for the ROLL_DEG==0 family
— but only for callers that leave `FORCE_TOPDOWN` unset.
`double_knee_to_chest_release`, `happy_baby_pose`, and
`left/right_single_leg_supine_knee_to_chest` explicitly opt back into
`camera_topdown` (added 2026-08-20, before the "reads as standing" defect
in that exact camera was diagnosed) to keep their hip-flexion knee-lift
legible, since the oblique camera's docstring already warns it foreshortens
that motion. Result: clean single-frame extracts of all 4 showed an
apparently static, standing figure with hands at its sides — because
`camera_topdown` is PURE ORTHOGRAPHIC straight down, which is
pixel-identical in silhouette to a standing front view (the same real
geometric fact documented in `camera_oblique_supine`'s own docstring).
**Fix:** added a third branch in `run_supine` — `ROLL_DEG==0 and
FORCE_TOPDOWN` now calls `camera_oblique_supine(plo, phi, xfrac=0.0,
yfrac=0.15, hfrac=2.6, dist_mult=1.0)`, a steep-but-PERSPECTIVE camera
(much higher/closer than the default oblique shot). Perspective
foreshortening breaks the orthographic "identical to standing" degeneracy
while staying close enough to top-down that the knee-to-chest travel is
still clearly visible frame-to-frame. `camera_topdown` itself is
untouched — still correct and unchanged for the ROLL_DEG!=0 (rolled,
side-lying) family, where the roll already disambiguates lying from
standing. Re-rendered and re-encoded all 4 clips; all now clearly read as
an overhead view of a folded/lying figure, with visible knee travel
between rest and peak. Full `SeedDataTests`/`SeedMigratorTests` suite still
green (asset-only change, no SeedData schema touched).

**Bug 2 (confirmed, fixed): `right_step_edge_calf_drop_stretch`'s highlight
was real but invisible from its own camera.** This exercise's pose has no
leg divergence at all (both legs stay in the same straight standing
position — no independent ankle joint to animate the actual heel-drop, see
the left script's docstring). Viewed in the shared `CAMERA_AZIMUTH = 90`
side profile (copied verbatim from the left script), the two legs project
almost exactly on top of each other, and whichever leg is nearer the camera
fully occludes the far one. The left script happened to ship with its own
target leg (Left Calves) as the near leg; the right script inherited the
same azimuth unmirrored, so the Right Calves highlight — confirmed present
in the render log (`highlight=6`) and visible in the default
`peak_front.png` — ended up on the hidden far leg in the actual demo
camera. Fixed by mirroring `CAMERA_AZIMUTH` to `-90`. Re-rendered,
re-encoded, and re-verified: the right calf highlight is now clearly
visible in the shipped clip. **Lesson for any future single-leg,
same-static-pose exercise: a shared azimuth between L/R variants is only
safe when the working leg is posed distinctly from the resting one (as in
quad stretch, hamstring stretch, etc.); when both legs stay in an identical
pose, the azimuth itself must be mirrored or the near leg will always hide
whichever target happens to be on the far side.**


## Hand-assist neck family: arm-to-head FK fix (2026-08-22)

Followed up on the "documented, deliberate limitation" note from the audit
above: 8 exercises (`left/right_isometric_neck_side_press`, `left/
right_levator_scapulae_stretch`, `left/right_chin_to_shoulder_diagonal_stretch`,
`left/right_scalene_neck_stretch`) never moved the assist arm, per each
script's own comment ("no hand-target IK"). Asked to actually solve it
rather than leave it. The rig genuinely has no IK — no bone-target solver,
no constraint stack — so the fix is **numeric forward-kinematics fitting**:
sweep candidate `upperarm`/`forearm` local-X/Z pairs and keep whichever
minimizes the forearm-tail (mitt) distance to a hand-picked target point,
the same throwaway-probe pattern already used elsewhere in this doc (the
quadruped floor reach, the twist-direction probes) — just automated as a
grid search instead of a few manual tries, since a 4-angle search space is
too big to hand-tune by eyeballing renders.

**Tool:** `_arm_to_head_probe.py` (deleted after use, recreate from this
note if needed) — builds ONLY the armature (skips muscle/skin, ~90ms) via
`L.import_obj` + `L.normalize_orientation` + `L.build_armature`, poses the
head exactly as the target exercise's peak frame does, then for a grid of
`(upperarm_x, upperarm_z, forearm_x, forearm_z)` candidates sets the pose,
calls `bpy.context.view_layer.update()`, and logs `forearm.<side>`'s world
tail position vs. a target point. No rendering needed for the numeric
search — only for the final visual confirmation once a close candidate is
found.

**Three genuinely different reach targets, not one shared pose:**

1. **Own-side hand to own-side head, above the ear** (isometric neck side
   press — "place your palm flat against the side of your head"). Target:
   a point offset sideways (+0.11, own-side direction) from a point 55%
   up the posed head bone. Best fit: `upperarm=(-115,0,10)`,
   `forearm=(-150,0,-30)`, dist 0.035.
2. **Opposite-side hand to top of head** (levator scapulae + chin-to-
   shoulder-diagonal — "rest your [other] hand on top of your head").
   Target: the head bone's own tail (already tilted/twisted by that
   exercise's own head pose). Levator: `upperarm=(-130,0,30)`,
   `forearm=(-100,0,-30)`, dist 0.048. Chin-to-shoulder (backed off
   slightly from an initial 0.026-dist fit that visually clipped into the
   hair, see below): `upperarm=(-100,0,25)`, `forearm=(-95,0,-25)`.
3. **Own-side hand to own-side collarbone** (scalene — "place your hand
   flat just below your collarbone"). A much closer, lower target (0.55x
   the shoulder's own X offset, 0.12 in front of the torso, 0.10 below
   shoulder height) — this one doesn't reach the head at all. Best fit:
   `upperarm=(0,0,-10)`, `forearm=(-150,0,-30)`, dist 0.059 — a
   near-vertical upper arm with a deep elbow fold, the forearm alone
   swinging up across the chest.

Each category needed its own grid — early narrow sweeps kept landing at
the search range's own edge (the true optimum outside the tried range),
so every category went through 2-3 widen-and-resweep passes before the
distance dropped under ~0.06 (the head cap / mitt are roughly 0.1-0.15
across, so anything under that reads as contact, not floating).

**Mirroring:** verified numerically, not assumed — probed the opposite
side/head-pose combination directly and confirmed the same distance
(0.048 both ways for the levator case) rather than just flipping the sign
and trusting it, per this doc's own standing "mirrored is not correct,
verify the absolute direction" lesson (this time applied to a reach
target, not a rotation direction). Convention: swap bone side, negate
local-Z, keep local-X unchanged.

**Bug found while fixing (unrelated to the arm reach):
`right_levator_scapulae_stretch.py`'s own docstring said the head turn
should be `+Y` (turn left), but its `POSES` dict shipped with the SAME
`-Y` values as the left script — a copy-paste-and-never-updated bug, not a
wrong sign belief. Caught by literally diffing the two scripts' `POSES`
while adding the arm fix. Fixed alongside the arm reach.**

**Camera bug surfaced by the arm reach, not caused by it:**
`right_chin_to_shoulder_diagonal_stretch.py` shared `CAMERA_AZIMUTH = 45`
with the left script (unmirrored — never revisited, unlike
`left_seated_spinal_twist`'s camera, which WAS mirrored to 315 when its
own rotation bug was fixed). With no arm animated this didn't matter much;
once the hand rose near the head, the unmirrored angle looked straight
into a tangle of hair strands and fingers (confirmed by comparing against
the same exercise's clean `rest_demo.png`, where the hair renders normally
with no arm nearby — ruling out a hair-modeling defect). Fixed by mirroring
the azimuth to -45, same fix class as the seated-spinal-twist precedent:
**a camera angle proven for one variant is only proven for that variant's
own geometry — when new geometry (an animated arm) enters the shot, an
unmirrored "shared" camera angle is worth re-checking, not assumed safe
just because it rendered fine before.**

All 8 re-rendered, re-encoded, and visually confirmed (no tearing, hand
reads as contacting its target, correct L/R mirroring). Full
`SeedDataTests`/`SeedMigratorTests` suite green throughout (asset + pose
data only, no schema changes).

## Hand/wrist batch, 8 exercises (2026-08-25)

Animated the 8 exercises from the "deepen hands/feet/core/glutes" content
batch that a real forearm-level motion can honestly represent: Assisted
Wrist Flexion/Extension Stretch (L/R) — direct reuse of the already-shipped
`left/right_wrist_flexor_stretch.py`/`_extensor_stretch.py` pattern (forward
arm extension + forearm local-Y twist, no hand-target IK) since they're the
same exercise concept under a different name; Wrist & Forearm Release —
a single representative arm cycling through both twist directions in one
loop, since the exercise's own `isBilateral: false` already implies a
"switch sides" cue and trying to show two arms x two directions at once
would be unreadable; Overhead Finger Interlace Stretch — both arms to the
overhead ceiling (`upperarm` local-X toward -155, the proven range) with
`forearm` local-Z scaled up to bring the mitts together at the top, the
same "close the gap as the reach deepens" technique
`prayer_stretch_palms_together_lower.py` uses low, applied overhead instead
(first pass under-rotated — mitts read as still shoulder-width apart at
frame 60; doubled the local-Z magnitudes on both `upperarm` and `forearm`
and re-rendered before shipping); Table-Supported Wrist Extensor Stretch —
seated base + backward spine lean (same axis
`seated_thoracic_extension_over_chair_back.py` uses) with both arms forward
and forearms pronated; Hook Fist Tendon Glide — the honest limit of this
whole approximation strategy: the rig cannot show ANY finger motion at all
(no finger bones), so this one only shows the arm position the exercise's
setup describes (hands up in front, elbows bent) with a small oscillating
forearm twist so the loop reads as active rather than frozen, not a
literal demonstration of the hook motion.

**Explicit rig-limitation finding, worth restating for future hand/finger
content:** every hand is a rigid convex-hulled "mitt" 100% weighted to its
forearm bone (`rigid_weight`, see the mitt-building note above) — there is
no wrist bone and no finger geometry to move independently, ever, on this
rig. Any exercise whose entire visible motion is finger articulation
(spreading, curling, individual finger pulls) has NOTHING to animate
honestly; the flexor/extensor family works only because the exercise's own
setup includes a real arm/forearm position to show. Content review for a
future hand-focused batch should sort candidates by this test before
scripting starts, not after.

All 8 flagged `animationIsApproximate`. Live-verified via
`HandWristAnimationVerificationUITests` (all 8 searchable, each detail
screen shows the approximate-animation disclaimer — proof
`exercise.demoVideoURL` actually resolved the bundled mp4, not just that
`animationName` is set in SeedData.json). Full `xcodebuild` unit suite
(412 tests) green; SeedData.json patched surgically (regex-insert after
each `"id"` line, not a full re-dump) to keep the diff to the 8 new fields.

## 20-exercise thin-coverage batch (2026-08-26)

Animated 20 more of the still-unanimated 172 (biceps/forearm, lats, hand,
foot, calves, neck, temple/head families), continuing the lowest-risk-first
strategy: every pose is a direct or lightly-adapted reuse of an already-proven
convention, no new base poses or axis probes needed. Shipped: `table_edge_
bicep_stretch_left/right` (direct reuse of `left/right_wall_bicep_stretch`'s
straight-arm-back + torso-twist shape, different prop name only),
`left/right_kneeling_lat_stretch_hands_on_chair` (`kneeling_chest_stretch_
on_chair`'s kneeling base + a torso side-bend layered on top, using `left/
right_overhead_reach_lat_stretch_with_strap`'s proven "+Z bends toward the
subject's own right, stretches the LEFT lat" sign), `thumb_extension_
stretch_left/right` + `fist_to_fan_tendon_gliding_flow` (hand family, same
honest "no finger geometry" approximation as `hook_fist_tendon_glide`),
`left/right_toe_spread_stretch` + `towel_scrunch_toe_flexor_stretch` +
`big_toe_extension_stretch_left/right` + `seated_toe_to_shin_stretch_left/
right` (foot family, same crossed-ankle or seated-chair approximation as
`left_plantar_fascia_stretch_toe_raise`), `left/right_seated_calf_stretch_
with_towel` (floor-sitting straight-leg base from `seated_forward_fold`),
`neck_isometric_front_and_back_press` (alternating forward/backward head
pitch, same isometric-oscillation precedent as `left_isometric_neck_side_
press`), `seated_neck_half_circles_ear_to_shoulder_arc` (near-identical
reuse of `seated_neck_rolls`' front-hemisphere arc), and `circular_temple_
self_massage` + `full_scalp_massage_tension_release` (both arms reaching to
the head at once, mirroring `left_isometric_neck_side_press`'s solved
arm-to-head FK target onto both sides simultaneously — new territory in that
no prior exercise animated BOTH assist arms at once, but the underlying
per-arm target was already solved, so no new probe was needed).

All 20 rendered clean on the first attempt (skins:1/anims:1, 0 fallback
muscles each, verified via `muscles: ... fallback=0` in each `_log.txt`) —
expected, given every pose reused an already-derived convention rather than
attempting new mechanics. Visually reviewed via `ffmpeg` 5×2 contact-sheet
grids (12-frame stride across the 120-frame loop) for tearing and correct
L/R mirroring before wiring into SeedData.json; none found.

**Flagging:** `animationIsApproximate: true` on the 15 exercises where the
rig genuinely can't show the real mechanism (no finger/toe/ankle geometry,
or an isometric press with no true hand-target IK) — same test the hand/
wrist batch's own "sort candidates by this test" note recommends. Left
unflagged: the 2 bicep-stretch, 2 kneeling-lat, and 1 neck-half-circle
exercises, whose animated motion (torso twist, side-bend, head arc) is the
actual real mechanism, matching their reused source scripts' own flags.

`Left/Right Temple` and `Forehead`/`Head` confirm the muscle-group table's
existing note: only `Head` (not Temple/Jaw/Eye/Forehead) is a mappable atlas
group, so `circular_temple_self_massage` ships with 0 highlighted muscles by
design (arm-to-head reach only) while `full_scalp_massage_tension_release`
gets a real Head highlight.

Live-verified via a new `ThinCoverageAnimationBatchUITests` (parallel to
`HandWristAnimationVerificationUITests`) — all 20 exercises' detail screens
open via search, and the 15 approximate ones show the disclaimer note,
proving `exercise.demoVideoURL` resolved a real bundled mp4 for every one of
them. Full `xcodebuild` unit suite (412 tests) green throughout. SeedData.json
patched surgically (regex-insert after each `"id"` line) to keep the diff to
the 20 new fields. 174/372 exercises now have animations (was 154).
