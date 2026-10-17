"""Seated Foot Flex-and-Point Flow — muscle-body + skin-head animation.

60-exercise batch. Seated, legs extended, a small alternating `shin` local-X sway both feet together standing in for flex/point.

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
EXERCISE = "seated_foot_flex_and_point_flow"
VIDEO_NAME = "seated_foot_flex_and_point_flow.mp4"

WORKED_KEYWORDS = ("foot",)

CAMERA_AZIMUTH = 90
CENTER_ON_POSE = True
ORTHO_SCALE_MULT = 1.6

_LEGS = {
    "thigh.L": (r(-90), 0, 0),
    "thigh.R": (r(-90), 0, 0),
    "shin.L": (0, 0, 0),
    "shin.R": (0, 0, 0),
}

POSES = {
    0: {**_LEGS, "foot.L": (0, 0, 0), "foot.R": (0, 0, 0)},
    30: {**_LEGS, "foot.L": (r(-25), 0, 0), "foot.R": (r(-25), 0, 0)},
    60: {**_LEGS, "foot.L": (r(30), 0, 0), "foot.R": (r(30), 0, 0)},
    90: {**_LEGS, "foot.L": (r(-25), 0, 0), "foot.R": (r(-25), 0, 0)},
    120: {**_LEGS, "foot.L": (0, 0, 0), "foot.R": (0, 0, 0)},
}

L.run_seated(globals())
