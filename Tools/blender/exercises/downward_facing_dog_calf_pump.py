"""Downward-Facing Dog Calf Pump — muscle-body + skin-head animation.

New batch (2026-08-27). "From downward-facing dog, bend one knee at a
time, pressing the opposite heel toward the floor, alternate pedaling."
Same rig limitation as downward_facing_dog.py (no independent pelvis
lift — see that script's docstring for the full derivation): reuses its
deep-standing-fold approximation of the inverted-V shape verbatim, adding
an alternating small shin bend on each leg in turn as the "pedal" motion.
Flagged `animationIsApproximate`.

Highlight: both Calves.

2026-10-17: re-authored on the new `foot.{L,R}` ankle bone (see ANIMATION_HANDOFF.md "Ankle joint") -- the foot itself now moves.
"""
import sys
import os

REPO = "/Users/jasonlu/Desktop/X-Code Projects/Breath - Relax & Stretch"
sys.path.insert(0, os.path.join(REPO, "Tools/blender/exercises"))
import _lib as L  # noqa: E402

r = L.r

APP_OBJ = os.path.join(REPO, "Breath - Relax & Stretch/Resources/Models3D/BodySkinMuscle.obj")
NODE_MAP = os.path.join(REPO, "Breath - Relax & Stretch/Resources/skinmuscle_node_names.json")
OUT_DIR = os.path.join(REPO, "Tools/blender/generated/exercises")
EXERCISE = "downward_facing_dog_calf_pump"
VIDEO_NAME = "downward_facing_dog_calf_pump.mp4"

CAMERA_AZIMUTH = 90
ORTHO_SCALE_MULT = 1.5
WORKED_KEYWORDS = (['calve'])

POSES = {
    0:   {"spine": (r(55), 0, 0), "chest": (r(40), 0, 0), "head": (r(10), 0, 0),
          "upperarm.L": (r(-95), 0, 0), "upperarm.R": (r(-95), 0, 0)},
    30:  {"foot.L": (r(20), 0, 0), "foot.R": (r(-12), 0, 0), "spine": (r(55), 0, 0), "chest": (r(40), 0, 0), "head": (r(10), 0, 0),
          "upperarm.L": (r(-95), 0, 0), "upperarm.R": (r(-95), 0, 0),
          "shin.L": (r(-16), 0, 0)},
    60:  {"spine": (r(55), 0, 0), "chest": (r(40), 0, 0), "head": (r(10), 0, 0),
          "upperarm.L": (r(-95), 0, 0), "upperarm.R": (r(-95), 0, 0)},
    90:  {"foot.R": (r(20), 0, 0), "foot.L": (r(-12), 0, 0), "spine": (r(55), 0, 0), "chest": (r(40), 0, 0), "head": (r(10), 0, 0),
          "upperarm.L": (r(-95), 0, 0), "upperarm.R": (r(-95), 0, 0),
          "shin.R": (r(-16), 0, 0)},
    120: {"spine": (r(55), 0, 0), "chest": (r(40), 0, 0), "head": (r(10), 0, 0),
          "upperarm.L": (r(-95), 0, 0), "upperarm.R": (r(-95), 0, 0)},
}

L.run(globals())
