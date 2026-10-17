"""Right Step-Edge Calf Drop Stretch — mirror of the left version.

See left_step_edge_calf_drop_stretch.py's docstring. Flagged
`animationIsApproximate` in SeedData.

**Camera fix (2026-08-21, animation-vs-instructions audit):** this pose has
no leg divergence at all (both legs stay in the same straight standing
position — see the left script's own docstring on why: no independent
ankle joint, so the actual heel-drop can't be animated, only held). Viewed
in a true side profile (azimuth 90, copied from the left script unchanged),
the two legs project on top of each other, and whichever leg is nearer the
camera fully occludes the far one. The left script happened to ship with
its own (Left Calves) target leg as the near one; this script inherited the
same azimuth verbatim, so the RIGHT calf highlight ended up on the far,
hidden leg instead — confirmed by comparing rendered peak_demo frames
side-by-side (right variant: no visible highlight; peak_front render at the
default front camera: highlight present, so this was a camera-angle bug,
not a missing/mis-tagged highlight). Fixed by mirroring the azimuth to -90
so the right leg becomes the near, visible one — same fix class as any
other single-leg exercise where the target leg must face the camera.

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
EXERCISE = "right_step_edge_calf_drop_stretch"
VIDEO_NAME = "right_step_edge_calf_drop_stretch.mp4"

CAMERA_AZIMUTH = -90

WORKED_KEYWORDS = ("right calve",)

POSES = {
    0: {"foot.R": (0, 0, 0)},
    30: {"spine": (r(3), 0, 0), "foot.R": (r(-12), 0, 0)},
    60: {"spine": (r(6), 0, 0), "foot.R": (r(-24), 0, 0)},
    90: {"spine": (r(3), 0, 0), "foot.R": (r(-12), 0, 0)},
    120: {"foot.R": (0, 0, 0)},
}

L.run(globals())
