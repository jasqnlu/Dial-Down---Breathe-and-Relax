"""Standing Calf Stretch on Stair Edge (Left) — muscle-body + skin-head animation.

40-exercise thin-coverage batch (session 2026-08-26). Same near-static standing hold as left_step_edge_calf_drop_stretch.py — the ankle-drop itself is an ankle-joint motion this rig has no bone for, so it reads via a small body-weight sway. Flagged animationIsApproximate.

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
EXERCISE = "standing_calf_stretch_on_stair_edge_left"
VIDEO_NAME = "standing_calf_stretch_on_stair_edge_left.mp4"

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
