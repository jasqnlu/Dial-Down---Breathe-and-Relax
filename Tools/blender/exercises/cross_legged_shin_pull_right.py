"""Cross-Legged Shin Pull (Right) — muscle-body + skin-head animation.

60-exercise batch. Seated cross-legged (`thigh` local-Z abduction crossing the ankle over the opposite knee, reusing seated_cross_ankle_glute_stretch's proven cross-leg shape) plus a forward hand reach toward the foot.

Highlight: Right Tibialis.

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
EXERCISE = "cross_legged_shin_pull_right"
VIDEO_NAME = "cross_legged_shin_pull_right.mp4"

WORKED_KEYWORDS = ("right tibialis",)

CAMERA_AZIMUTH = 20
ORTHO_SCALE_MULT = 1.3

_LEGS = {
    "thigh.R": (r(-75), 0, r(30)),
    "shin.R": (r(90), 0, 0),
    "thigh.L": (r(-75), 0, 0),
    "shin.L": (r(90), 0, 0),
}

POSES = {
    0: {**_LEGS, "foot.R": (0, 0, 0)},
    30: {**_LEGS, "upperarm.R": (r(-30), 0, 0), "foot.R": (r(-12.5), 0, 0)},
    60: {**_LEGS, "upperarm.R": (r(-55), 0, 0), "spine": (r(8), 0, 0), "foot.R": (r(-25), 0, 0)},
    90: {**_LEGS, "upperarm.R": (r(-55), 0, 0), "spine": (r(8), 0, 0), "foot.R": (r(-25), 0, 0)},
    120: {**_LEGS, "foot.R": (0, 0, 0)},
}

L.run_seated(globals())
