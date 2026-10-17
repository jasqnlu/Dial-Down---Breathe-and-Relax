"""Standing Bilateral Calf Stretch on Incline Board — muscle-body + skin-head animation.

New batch (2026-08-27). "Both feet on an incline board, toes up the
slope, heels down, knees straight, lean slightly forward from the
ankles." No independent ankle joint to show the incline-driven
dorsiflexion, so approximated with a small forward torso lean (spine)
while the legs stay straight and planted — the closest available proxy.
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
EXERCISE = "standing_bilateral_calf_stretch_on_incline_board"
VIDEO_NAME = "standing_bilateral_calf_stretch_on_incline_board.mp4"

CAMERA_AZIMUTH = 90
WORKED_KEYWORDS = (['calve'])

POSES = {
    0:   {"foot.L": (r(-15), 0, 0), "foot.R": (r(-15), 0, 0), },
    30:  {"foot.L": (r(-15), 0, 0), "foot.R": (r(-15), 0, 0), "spine": (r(6), 0, 0)},
    60:  {"foot.L": (r(-15), 0, 0), "foot.R": (r(-15), 0, 0), "spine": (r(10), 0, 0)},
    90:  {"foot.L": (r(-15), 0, 0), "foot.R": (r(-15), 0, 0), "spine": (r(10), 0, 0)},
    120: {"foot.L": (r(-15), 0, 0), "foot.R": (r(-15), 0, 0), },
}

L.run(globals())
