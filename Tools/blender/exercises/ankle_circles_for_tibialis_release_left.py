"""Ankle Circles for Tibialis Release (Left) — muscle-body + skin-head animation.

60-exercise batch. Seated, leg extended and lifted, a small circular `shin` local-X/Z sweep standing in for the ankle circle.

Highlight: Left Tibialis.

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
EXERCISE = "ankle_circles_for_tibialis_release_left"
VIDEO_NAME = "ankle_circles_for_tibialis_release_left.mp4"

WORKED_KEYWORDS = ("left tibialis",)

CAMERA_AZIMUTH = 90
CENTER_ON_POSE = True
ORTHO_SCALE_MULT = 1.6

_LEGS = {
    "thigh.L": (r(-100), 0, 0),
    "shin.L": (0, 0, 0),
    "thigh.R": (r(-90), 0, 0),
    "shin.R": (0, 0, 0),
}

POSES = {
    0: {**_LEGS, "foot.L": (r(-20), 0, 0)},
    15: {**_LEGS, "foot.L": (r(-14.1), 0, r(-14.1))},
    30: {**_LEGS, "foot.L": (0, 0, r(-20))},
    45: {**_LEGS, "foot.L": (r(14.1), 0, r(-14.1))},
    60: {**_LEGS, "foot.L": (r(20), 0, 0)},
    75: {**_LEGS, "foot.L": (r(14.1), 0, r(14.1))},
    90: {**_LEGS, "foot.L": (0, 0, r(20))},
    105: {**_LEGS, "foot.L": (r(-14.1), 0, r(14.1))},
    120: {**_LEGS, "foot.L": (r(-20), 0, 0)},
}

L.run_seated(globals())
