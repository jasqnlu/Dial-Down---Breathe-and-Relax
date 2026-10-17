"""Standing Ankle Dorsiflexion Stretch (Left) — muscle-body + skin-head animation.

New batch (2026-08-27). "Face a wall, left foot planted flat behind you,
heel down, bend the left knee forward toward the wall." No independent
ankle joint on this rig, so the actual dorsiflexion angle at the ankle
can't be shown; approximated via the front (right) leg bending forward
(a wall-lean proxy) while the working (left) leg stays planted with only
a small forward thigh tip. Same honest-limit class as the ankle/shin
family in ANIMATION_HANDOFF.md's tenth-batch note. Flagged
`animationIsApproximate`.

Highlight: Left Tibialis + Left Calves.

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
EXERCISE = "standing_ankle_dorsiflexion_stretch_left"
VIDEO_NAME = "standing_ankle_dorsiflexion_stretch_left.mp4"

CAMERA_AZIMUTH = 90
ORTHO_SCALE_MULT = 1.3
WORKED_KEYWORDS = (['left tibialis', 'left calve'])

POSES = {
    0: {},
    30: {"thigh.L": (r(-9), 0, 0), "shin.L": (r(18), 0, 0), "foot.L": (r(-9), 0, 0), "thigh.R": (r(-12), 0, 0), "shin.R": (r(12), 0, 0), "upperarm.L": (r(-27), 0, 0), "upperarm.R": (r(-27), 0, 0)},
    60: {"thigh.L": (r(-15), 0, 0), "shin.L": (r(30), 0, 0), "foot.L": (r(-15), 0, 0), "thigh.R": (r(-20), 0, 0), "shin.R": (r(20), 0, 0), "upperarm.L": (r(-45), 0, 0), "upperarm.R": (r(-45), 0, 0)},
    90: {"thigh.L": (r(-15), 0, 0), "shin.L": (r(30), 0, 0), "foot.L": (r(-15), 0, 0), "thigh.R": (r(-20), 0, 0), "shin.R": (r(20), 0, 0), "upperarm.L": (r(-45), 0, 0), "upperarm.R": (r(-45), 0, 0)},
    120: {},
}

L.run(globals())
