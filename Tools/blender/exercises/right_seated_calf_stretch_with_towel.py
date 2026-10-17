"""Right Seated Calf Stretch with Towel — muscle-body + skin-head animation.

Mirror of left_seated_calf_stretch_with_towel.py. Both legs stay straight
(symmetric leg pose), so nothing in this script actually needs mirroring
beyond the highlight tag and exercise metadata.

Highlight: Right Calves. Flagged `animationIsApproximate`.

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
EXERCISE = "right_seated_calf_stretch_with_towel"
VIDEO_NAME = "right_seated_calf_stretch_with_towel.mp4"

CAMERA_AZIMUTH = -90
CENTER_ON_POSE = True
ORTHO_SCALE_MULT = 1.6

WORKED_KEYWORDS = ("right calf",)

_LEGS = {
    "thigh.L": (r(-90), 0, 0), "shin.L": (0, 0, 0),
    "thigh.R": (r(-90), 0, 0), "shin.R": (0, 0, 0),
}

POSES = {
    0:   {**_LEGS},
    30:  {"foot.R": (r(-12.5), 0, 0), **_LEGS,
          "upperarm.L": (r(-25), 0, 0), "upperarm.R": (r(-25), 0, 0)},
    60:  {"foot.R": (r(-25), 0, 0), **_LEGS,
          "upperarm.L": (r(-45), 0, 0), "upperarm.R": (r(-45), 0, 0),
          "forearm.L": (r(-30), 0, 0), "forearm.R": (r(-30), 0, 0)},
    90:  {"foot.R": (r(-25), 0, 0), **_LEGS,
          "upperarm.L": (r(-45), 0, 0), "upperarm.R": (r(-45), 0, 0),
          "forearm.L": (r(-30), 0, 0), "forearm.R": (r(-30), 0, 0)},
    120: {**_LEGS},
}

L.run_seated(globals())
