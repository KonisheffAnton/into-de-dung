"""Сохраняет PNG завершённой PixelLab-задачи без изменений и без API-вызовов."""
import argparse
import base64
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
TARGET = ROOT / "pixellab"
EXPECTED_JOB_ID = "4811a2d7-cf5e-4aa6-bd62-51f892bdae1d"

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("job_response", type=Path, help="Сохранённый JSON завершённой задачи")
job_path = parser.parse_args().job_response
job = json.loads(job_path.read_text(encoding="utf-8-sig"))
accepted_path = TARGET / "response.json"
assert accepted_path.exists(), "Не найден сохранённый ID принятой задачи"
accepted = json.loads(accepted_path.read_text(encoding="utf-8-sig"))
assert accepted.get("background_job_id") == EXPECTED_JOB_ID, "ID в манифесте принятия отличается от пакета"
assert job.get("id") == EXPECTED_JOB_ID, "Ответ относится к другой задаче"
assert job.get("status") == "completed", "Задача ещё не завершена; повторно не отправлять"
result = job["last_response"]
images = result["images"]
assert images, "Завершённый ответ не содержит кадров"
requested = json.loads((TARGET / "request.json").read_text(encoding="utf-8-sig"))["frame_count"]

decoded = []
files = []
for index, entry in enumerate(images):
    encoded = entry["base64"]
    if encoded.startswith("data:"):
        encoded = encoded.split(",", 1)[1]
    image = base64.b64decode(encoded, validate=True)
    assert image.startswith(b"\x89PNG\r\n\x1a\n"), "Формат изображения не PNG"
    filename = f"frame-{index + 1:02}.png"
    decoded.append((filename, image))
    files.append({"file": filename, "sha256": hashlib.sha256(image).hexdigest()})

names = {filename for filename, _ in decoded}
assert not {path.name for path in TARGET.glob("frame-*.png")} - names, "В каталоге есть лишние кадры"
for filename, image in decoded:
    path = TARGET / filename
    assert not path.exists() or path.read_bytes() == image, "Отказываюсь перезаписать отличающийся файл: " + filename
for filename, image in decoded:
    path = TARGET / filename
    if not path.exists():
        path.write_bytes(image)

metadata = {key: value for key, value in result.items() if key not in ("images", "image")}
metadata.update({"job_id": job["id"], "status": job["status"], "requested_frame_count": requested,
                 "frame_count": len(images), "files": files})
(TARGET / "result.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
summary = {key: value for key, value in job.items() if key != "last_response"}
summary["last_response"] = {key: value for key, value in metadata.items() if key != "files"}
(TARGET / "job-status.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"status": job["status"], "frame_count": len(images),
                  "billing_usage": metadata.get("billing_usage")}))
