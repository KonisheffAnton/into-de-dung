"""Extract original PNGs from a saved completed PixelLab job; no API calls."""
import base64
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
TARGET = ROOT / "pixellab"
job = json.loads((TARGET / "job-status.json").read_text(encoding="utf-8-sig"))
assert job["status"] == "completed", "The existing job has not completed yet. Do not resubmit."
result = job["last_response"]
images = result["images"]
assert len(images) == 16, len(images)
files = []
for index, entry in enumerate(images):
    encoded = entry["base64"]
    if encoded.startswith("data:"):
        encoded = encoded.split(",", 1)[1]
    image = base64.b64decode(encoded, validate=True)
    assert image.startswith(b"\x89PNG\r\n\x1a\n"), "Unexpected response image format"
    filename = f"frame-{index + 1:02}.png"
    (TARGET / filename).write_bytes(image)
    files.append({"file": filename, "sha256": hashlib.sha256(image).hexdigest()})
metadata = {key: value for key, value in result.items() if key not in ["images", "image"]}
metadata.update({"job_id": job["id"], "status": job["status"], "frame_count": len(images), "files": files})
(TARGET / "result.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"status": job["status"], "frame_count": len(images), "billing_usage": metadata.get("billing_usage")}))
