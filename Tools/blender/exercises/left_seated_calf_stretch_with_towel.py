"""Left Seated Calf Stretch with Towel — muscle-body + skin-head animation.

20-exercise thin-coverage batch. "Sit on the floor, left leg extended, loop
a towel around the ball of your foot, keeping your knee straight gently pull
the towel to draw your toes back." Floor-sitting base (apply_seated_base,
same as seated_forward_fold.py) with BOTH legs straight (thigh -90, shin 0)
— the exercise doesn't fold the other leg in, unlike the asymmetric hamstring
family. Arms reach forward and down as if holding towel ends; no ankle joint
to show the actual toe-pull (same rig limit as the rest of the foot/calf
family this batch).

Highlight: Left Calves, matching the exercise's tag. Flagged
`animationIsApproximate`.

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
EXERCISE = "left_seated_calf_stretch_with_towel"
VIDEO_NAME = "left_seated_calf_stretch_with_towel.mp4"

CAMERA_AZIMUTH = 90
CENTER_ON_POSE = True
ORTHO_SCALE_MULT = 1.6

WORKED_KEYWORDS = ("left calf",)

_LEGS = {
    "thigh.L": (r(-90), 0, 0), "shin.L": (0, 0, 0),
    "thigh.R": (r(-90), 0, 0), "shin.R": (0, 0, 0),
}

POSES = {
    0:   {**_LEGS},
    30:  {"foot.L": (r(-12.5), 0, 0), **_LEGS,
          "upperarm.L": (r(-25), 0, 0), "upperarm.R": (r(-25), 0, 0)},
    60:  {"foot.L": (r(-25), 0, 0), **_LEGS,
          "upperarm.L": (r(-45), 0, 0), "upperarm.R": (r(-45), 0, 0),
          "forearm.L": (r(-30), 0, 0), "forearm.R": (r(-30), 0, 0)},
    90:  {"foot.L": (r(-25), 0, 0), **_LEGS,
          "upperarm.L": (r(-45), 0, 0), "upperarm.R": (r(-45), 0, 0),
          "forearm.L": (r(-30), 0, 0), "forearm.R": (r(-30), 0, 0)},
    120: {**_LEGS},
}

L.run_seated(globals())
