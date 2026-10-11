"""Build one PixelLab animation request from the existing padded Defender reference."""
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
image = {"type": "base64", "base64": base64.b64encode(source).decode("ascii"), "format": "png"}
action = (
    "The same helmeted defender performs a defiant taunt, striking his OWN shield with his sword EXACTLY TWICE. "
    "Start in the reference stance. Lift the sword in his right hand from screen-left, bring the blade across "
    "his chest to visibly tap the outer front of the shield on screen-right. First crisp contact, pull the "
    "sword away with a clear gap, second crisp contact, then lower the sword back to the exact initial stance. "
    "Two distinct small swings and two readable blade-to-shield contacts, no extra strikes. The shield stays "
    "braced in his left hand and recoils only slightly at each tap. Confident challenging gesture, compact "
    "motion of arms and weapons only. Feet, legs, pelvis and head stay fixed. Preserve the same three-quarter "
    "top-down camera, silhouette, size, steel armor, olive colors, sword and shield shapes. Simple clean pixel "
    "clusters. No steps, turns, body twisting, drift, new details, sparks, trails, text, scenery or camera motion."
)
assert len(action) <= 1000
request = {"first_frame": image, "last_frame": image, "action": action,
           "frame_count": 16, "seed": 20261011, "no_background": True, "enhance_prompt": False}
(TARGET / "request.json").write_text(json.dumps(request, indent=2) + "\n", encoding="utf-8")
manifest = {"endpoint": "https://api.pixellab.ai/v2/animate-with-text-v3",
            "reference": str(SOURCE.relative_to(ROOT.parent)).replace("\\", "/"),
            "reference_sha256": hashlib.sha256(source).hexdigest(),
            "frame_count": 16, "first_last_same_reference": True,
            "action": action, "seed": 20261011, "no_background": True,
            "note": "Single candidate; no runtime integration or changes to original frames."}
(ROOT / "request-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"frame_count": 16, "action_chars": len(action), "reference_sha256": manifest["reference_sha256"]}))
