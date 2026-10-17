"""Left Plantar Fascia Stretch (Toe Raise) — muscle-body + skin-head animation.

Batch 16. "Sit in a chair, cross your left ankle over your opposite knee,
pull your toes back toward your shin." Reuses left_seated_figure_four_
stretch.py's chair-sit + thigh-abduction shape (the same "cross the
ankle over the opposite knee" approximation) as a static hold — the
toe-pull itself can't be shown (no independent toe/ankle joint on this
rig), so the stretch reads through the crossed-leg silhouette and the
foot highlight.

Highlight: Left Foot, matching the exercise's tag.

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
EXERCISE = "left_plantar_fascia_stretch_toe_raise"
VIDEO_NAME = "left_plantar_fascia_stretch_toe_raise.mp4"

CAMERA_AZIMUTH = 20
ORTHO_SCALE_MULT = 1.3

WORKED_KEYWORDS = ("left foot",)

_LEGS = {
    "thigh.L": (r(-75), 0, r(-38)),
    "shin.L": (r(90), 0, 0),
    "thigh.R": (r(-75), 0, 0),
    "shin.R": (r(90), 0, 0),
}

POSES = {
    0: {**_LEGS, "foot.L": (0, 0, 0)},
    30: {**_LEGS, "upperarm.L": (r(-30), 0, 0), "foot.L": (r(-12.5), 0, 0)},
    60: {**_LEGS, "upperarm.L": (r(-55), 0, 0), "spine": (r(8), 0, 0), "foot.L": (r(-25), 0, 0)},
    90: {**_LEGS, "upperarm.L": (r(-55), 0, 0), "spine": (r(8), 0, 0), "foot.L": (r(-25), 0, 0)},
    120: {**_LEGS, "foot.L": (0, 0, 0)},
}

L.run_seated(globals())
