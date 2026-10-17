"""Left Step-Edge Calf Drop Stretch — muscle-body + skin-head animation.

Batch 16. "Ball of the foot on a step edge, heel hanging off, let the heel
drop below step level, knee nearly straight." The actual heel-drop is an
ankle-joint motion this rig can't articulate (no independent ankle/foot
bone), and the standing leg itself barely changes shape (knee stays
straight throughout) — so this is animated as a small forward `hips`... no
independent hip motion is called for either. Kept as a near-static hold
(a subtle body-weight sway via a small `spine` lean, the same device
suboccipital_release_finger_press.py uses to keep an otherwise-static hold
from reading as a frozen frame) with the calf highlighted. Flagged
`animationIsApproximate` — the actual stretch mechanism (ankle
dorsiflexion) isn't shown.

Highlight: Left Calves.

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
EXERCISE = "left_step_edge_calf_drop_stretch"
VIDEO_NAME = "left_step_edge_calf_drop_stretch.mp4"

CAMERA_AZIMUTH = 90

WORKED_KEYWORDS = ("left calve",)

POSES = {
    0: {"foot.L": (0, 0, 0)},
    30: {"spine": (r(3), 0, 0), "foot.L": (r(-12), 0, 0)},
    60: {"spine": (r(6), 0, 0), "foot.L": (r(-24), 0, 0)},
    90: {"spine": (r(3), 0, 0), "foot.L": (r(-12), 0, 0)},
    120: {"foot.L": (0, 0, 0)},
}

L.run(globals())
