"""Prepare one stronger, defiant PixelLab shield taunt; does not submit it."""
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
    "Aggressive defiant COME AT ME taunt. This same helmeted defender forcefully bangs his sword "
    "against his OWN shield EXACTLY TWICE. 1-3: lean chest forward, thrust shield toward the enemy, "
    "draw sword well back on screen-left. 4: sharp first blade contact on shield front at screen-right. "
    "5-7: recoil and pull sword far away, visibly separating blade from shield. 8: sharp second hard contact. "
    "9-12: sword rebounds away; hold shield forward, chin raised, chest proud in a bold threatening challenge. "
    "13-16: return to reference stance. Two strong separate swings, two brief contacts, no prolonged rubbing. "
    "Shield recoils at each hit; power shown by poses and timing only. Feet stay planted, no steps or spins. "
    "Preserve camera, scale, armor, olive palette, sword and shield shapes, simple broad pixel clusters. "
    "No white flashes, stars, sparks, impact symbols, glow, trails, particles, text, extra details or background."
)
assert len(action) <= 1000, len(action)
request = {"first_frame": image, "last_frame": image, "action": action,
           "frame_count": 16, "seed": 20261012, "no_background": True, "enhance_prompt": False}
(TARGET / "request.json").write_text(json.dumps(request, indent=2) + "\n", encoding="utf-8")
manifest = {"endpoint": "https://api.pixellab.ai/v2/animate-with-text-v3",
            "reference": str(SOURCE.relative_to(ROOT.parent)).replace("\\", "/"),
            "reference_sha256": hashlib.sha256(source).hexdigest(),
            "frame_count": 16, "first_last_same_reference": True,
            "action": action, "seed": request["seed"], "no_background": True,
            "enhance_prompt": False,
            "note": "One user-requested more aggressive, challenging candidate. Preserve previous trial. No runtime integration."}
(ROOT / "request-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"frame_count": 16, "action_chars": len(action), "reference_sha256": manifest["reference_sha256"]}))
