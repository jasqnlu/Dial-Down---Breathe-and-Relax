"""Seated Toe-to-Shin Stretch (Left) — muscle-body + skin-head animation.

20-exercise thin-coverage batch, foot family. "Sit toward the edge of a
chair, extend your left leg with your heel on the floor, pull the ball of
your foot and toes back toward your shin." Asymmetric seated leg pose —
the working leg extends straight (thigh -90, shin 0, the same straight-leg
convention left_seated_hamstring_stretch.py/seated_forward_fold.py use),
the other leg stays in the standard seated-in-chair fold. No independent
ankle joint to show the actual toe-pull, same rig limit as the rest of the
foot family — reads through the extended-leg silhouette and the foot
highlight.

Highlight: Left Foot, matching the exercise's tag. Flagged
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
EXERCISE = "seated_toe_to_shin_stretch_left"
VIDEO_NAME = "seated_toe_to_shin_stretch_left.mp4"

CAMERA_AZIMUTH = 90
CENTER_ON_POSE = True
ORTHO_SCALE_MULT = 1.4

WORKED_KEYWORDS = ("left foot",)

_LEGS = {
    "thigh.L": (r(-90), 0, 0), "shin.L": (0, 0, 0),
    "thigh.R": (r(-90), 0, 0), "shin.R": (r(90), 0, 0),
}

POSES = {
    0:   {**_LEGS},
    30:  {"foot.L": (r(-12.5), 0, 0), **_LEGS, "spine": (r(8), 0, 0),
          "upperarm.L": (r(-30), 0, 0), "upperarm.R": (r(-15), 0, 0)},
    60:  {"foot.L": (r(-25), 0, 0), **_LEGS, "spine": (r(15), 0, 0),
          "upperarm.L": (r(-45), 0, 0), "upperarm.R": (r(-20), 0, 0)},
    90:  {"foot.L": (r(-25), 0, 0), **_LEGS, "spine": (r(15), 0, 0),
          "upperarm.L": (r(-45), 0, 0), "upperarm.R": (r(-20), 0, 0)},
    120: {**_LEGS},
}

L.run_seated(globals())
