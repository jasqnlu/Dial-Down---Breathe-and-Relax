"""Seated Shin Stretch with Strap (Right) — muscle-body + skin-head animation.

60-exercise batch. Floor-sitting base with the working leg extended straight and the other bent in (asymmetric leg pose, reusing left_seated_hamstring_stretch.py's proven asymmetric convention), both arms reaching forward toward the extended foot.

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
EXERCISE = "seated_shin_stretch_with_strap_right"
VIDEO_NAME = "seated_shin_stretch_with_strap_right.mp4"

WORKED_KEYWORDS = ("right tibialis",)

CAMERA_AZIMUTH = 90
CENTER_ON_POSE = True
ORTHO_SCALE_MULT = 1.4

_LEGS = {
    "thigh.R": (r(-90), 0, 0), "shin.R": (0, 0, 0),
    "thigh.L": (r(-60), 0, -r(30)), "shin.L": (r(90), 0, 0),
}

POSES = {
    0:   {**_LEGS},
    30:  {"foot.R": (r(17.5), 0, 0), **_LEGS, "spine": (r(15), 0, 0), "upperarm.L": (r(-25), 0, 0), "upperarm.R": (r(-25), 0, 0)},
    60:  {"foot.R": (r(35), 0, 0), **_LEGS, "spine": (r(28), 0, 0), "upperarm.L": (r(-45), 0, 0), "upperarm.R": (r(-45), 0, 0)},
    90:  {"foot.R": (r(35), 0, 0), **_LEGS, "spine": (r(28), 0, 0), "upperarm.L": (r(-45), 0, 0), "upperarm.R": (r(-45), 0, 0)},
    120: {**_LEGS},
}

L.run_seated(globals())
