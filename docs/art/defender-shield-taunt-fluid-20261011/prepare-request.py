"""Prepare one continuous 32-frame PixelLab taunt, without submitting it."""
import base64
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT.parent / "defender-idle-vertical-20261010/pixellab/reference-128.png"
TARGET = ROOT / "pixellab"
TARGET.mkdir(parents=True, exist_ok=True)
source = SOURCE.read_bytes()
(TARGET / "reference-128.png").write_bytes(source)
image = {"type":"base64", "base64":base64.b64encode(source).decode("ascii"), "format":"png"}
motion = (
    "One continuous aggressive COME AT ME challenge with EXACTLY TWO sword knocks on his OWN shield. "
    "First straighten the chest, lift the chin slightly and offer the shield forward toward the enemy. "
    "Draw the sword arm back, then swing the flat of the blade inward in a clear smooth arc to the shield "
    "front: first sharp contact and a small shield recoil. Immediately draw the blade fully away with a "
    "visible gap, then a second forceful inward arc, second brief contact and recoil. The blade must leave "
    "the shield between the TWO contacts. Lower the sword outward, hold the forward shield and lifted chin "
    "in a bold daring stare, then smoothly return to the initial stance. Natural connected shoulder, elbow "
    "and wrist motion, readable anticipation and follow-through, no pose jumps. Both feet stay planted. "
    "Bare matte shield and sword throughout: no flashes, stars, sparks, glows, trails, particles or text. "
    "No steps, turns, extra strikes or camera motion."
)
assert len(motion) <= 1000, len(motion)
request = {"first_frame":image, "last_frame":image, "description":motion,
           "frame_count":32, "seed":20261013, "no_background":True, "enhance_prompt":False,
           "direction":"south-east", "view":"high top-down",
           "subject_description":"A compact helmeted human defender in simple steel armor and olive cloth, holding a short sword in his right hand on screen-left and a large olive shield in his left hand on screen-right; broad quiet pixel clusters, no added details.",
           "initial_pose":"Standing in a wide braced stance with bent knees, sword lowered diagonally toward screen-left, shield raised in front on screen-right, leaning slightly forward, looking toward the lower-right."}
for field in ["subject_description", "initial_pose"]:
    assert len(request[field]) <= 300
(TARGET / "request.json").write_text(json.dumps(request, indent=2) + "\n", encoding="utf-8")
manifest = {key:value for key,value in request.items() if key not in ["first_frame", "last_frame"]}
manifest.update({"endpoint":"https://api.pixellab.ai/v2/animate-pixminimax",
                 "reference":str(SOURCE.relative_to(ROOT.parent)).replace("\\", "/"),
                 "reference_sha256":hashlib.sha256(source).hexdigest(),
                 "first_last_same_reference":True,
                 "reason":"User requests stronger challenge and smoother motion. Continuous 32 frames instead of repeated contact montage.",
                 "scope":"One offline candidate, retain previous trials; no game integration."})
(ROOT / "request-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"frame_count":32, "motion_chars":len(motion), "reference_sha256":manifest["reference_sha256"]}))
