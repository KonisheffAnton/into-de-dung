"""Extract original PNGs from a saved completed PixelLab job; no API calls."""
import base64
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
TARGET = ROOT / "pixellab"
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("job_response", type=Path, help="Saved raw completed job JSON, including last_response.images")
job_path = parser.parse_args().job_response
job = json.loads(job_path.read_text(encoding="utf-8-sig"))
accepted_path = TARGET / "response.json"
assert accepted_path.exists(), "No accepted job ID saved. Do not guess a job or resubmit automatically."
accepted = json.loads(accepted_path.read_text(encoding="utf-8-sig"))
assert accepted.get("background_job_id") and job.get("id") == accepted["background_job_id"], "Response belongs to another job"
assert job["status"] == "completed", "The existing job has not completed yet. Do not resubmit."
result = job["last_response"]
images = result["images"]
# API может включать исходную позу сверх запрошенных кадров: сохраняем весь ответ.
assert images, "Completed job contains no images"
requested = json.loads((TARGET / "request.json").read_text(encoding="utf-8-sig"))["frame_count"]
files = []
decoded = []
for index, entry in enumerate(images):
    encoded = entry["base64"]
    if encoded.startswith("data:"):
        encoded = encoded.split(",", 1)[1]
    image = base64.b64decode(encoded, validate=True)
    assert image.startswith(b"\x89PNG\r\n\x1a\n"), "Unexpected response image format"
    filename = f"frame-{index + 1:02}.png"
    decoded.append((filename, image))
    files.append({"file": filename, "sha256": hashlib.sha256(image).hexdigest()})
# Проверяем весь пакет до записи: чужой ответ не должен подменить сохранённую пробу.
expected_names = {filename for filename, _ in decoded}
assert not {path.name for path in TARGET.glob("frame-*.png")} - expected_names, "Existing candidate has extra frames"
for filename, image in decoded:
    path = TARGET / filename
    assert not path.exists() or path.read_bytes() == image, "Existing candidate differs; refusing overwrite: " + filename
for filename, image in decoded:
    path = TARGET / filename
    if not path.exists():
        path.write_bytes(image)
metadata = {key: value for key, value in result.items() if key not in ["images", "image"]}
metadata.update({"job_id": job["id"], "status": job["status"], "requested_frame_count": requested,
                 "frame_count": len(images), "files": files})
(TARGET / "result.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
summary = {key: value for key, value in job.items() if key != "last_response"}
summary["last_response"] = {key: value for key, value in metadata.items() if key != "files"}
(TARGET / "job-status.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"status": job["status"], "frame_count": len(images), "billing_usage": metadata.get("billing_usage")}))
