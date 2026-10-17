"""Ankle Alphabet — muscle-body + skin-head animation.

60-exercise batch. Same pose/motion as shin_and_ankle_mobiliser.py -- an identically-described exercise under a different name.

Highlight: Left Foot, Right Foot.

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
EXERCISE = "ankle_alphabet"
VIDEO_NAME = "ankle_alphabet.mp4"

WORKED_KEYWORDS = ("foot",)

CAMERA_AZIMUTH = 90
ORTHO_SCALE_MULT = 1.4

_LEGS = {
    "thigh.L": (r(-75), 0, 0),
    "shin.L": (r(90), 0, 0),
    "thigh.R": (r(-80), 0, 0),
    "shin.R": (r(45), 0, 0),
}

POSES = {
    0: {**_LEGS, "foot.R": (r(-18), 0, 0)},
    15: {**_LEGS, "foot.R": (r(-12.7), 0, r(12.7))},
    30: {**_LEGS, "foot.R": (0, 0, r(18))},
    45: {**_LEGS, "foot.R": (r(12.7), 0, r(12.7))},
    60: {**_LEGS, "foot.R": (r(18), 0, 0)},
    75: {**_LEGS, "foot.R": (r(12.7), 0, r(-12.7))},
    90: {**_LEGS, "foot.R": (0, 0, r(-18))},
    105: {**_LEGS, "foot.R": (r(-12.7), 0, r(-12.7))},
    120: {**_LEGS, "foot.R": (r(-18), 0, 0)},
}

L.run_seated(globals())
