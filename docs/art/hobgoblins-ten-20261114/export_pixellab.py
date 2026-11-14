"""Экспортирует только завершённые PixelLab-концепты, сохраняя PNG побайтно."""
from pathlib import Path
import base64
import hashlib
import json
import shutil

from PIL import Image

ROOT = Path(__file__).resolve().parent
JOBS = Path("C:/Users/Aston/.codex/generated_images/hobgoblins-ten-20261114")
RUNTIME_REFERENCE = ROOT.parents[2] / "assets/art_presets/approved/character_skins_v1/red_bastion/still.png"


def read_json(path: Path) -> dict | list:
	return json.loads(path.read_text(encoding="utf-8-sig"))


def sha(data: bytes) -> str:
	return hashlib.sha256(data).hexdigest()


def canonical_sha(value: object) -> str:
	return sha(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8"))


def check_request_provenance(row: dict, external: Path) -> str:
	request_path = external / "request.json"
	if not request_path.is_file():
		raise SystemExit(f"Missing stored submitted request for item {row['id']}")
	stored = read_json(request_path)
	if stored.get("endpoint") != row.get("endpoint"):
		raise SystemExit(f"Endpoint differs from local plan for item {row['id']}")
	body = stored.get("body")
	if not isinstance(body, dict):
		raise SystemExit(f"Stored request body is invalid for item {row['id']}")
	for key in ("description", "image_size", "no_background", "seed", "style_options"):
		if body.get(key) != row.get(key):
			raise SystemExit(f"Submitted request {key} differs from plan for item {row['id']}")
	style = body.get("style_image")
	if not isinstance(style, dict) or style.get("usage_description") != row.get("style_usage"):
		raise SystemExit(f"Submitted style reference policy differs for item {row['id']}")
	image_data = style.get("image", {}).get("base64", "")
	if not isinstance(image_data, str):
		raise SystemExit(f"Stored style reference image is missing for item {row['id']}")
	if image_data.startswith("data:"):
		image_data = image_data.split(",", 1)[1]
	if base64.b64decode(image_data, validate=True) != (ROOT / row["style_image"]).read_bytes():
		raise SystemExit(f"Submitted style PNG differs from plan for item {row['id']}")
	return canonical_sha(stored)


def main() -> None:
	requests_path = ROOT / "requests.json"
	rows = read_json(requests_path)
	if not isinstance(rows, list) or len(rows) != 10 or [row.get("id") for row in rows] != list(range(1, 11)):
		raise SystemExit("Expected exactly ten requests numbered 1 through 10")
	reference_path = ROOT / "references/warrior11.png"
	reference_bytes = reference_path.read_bytes()
	if reference_bytes != RUNTIME_REFERENCE.read_bytes():
		raise SystemExit("warrior11.png must be byte-identical to runtime red_bastion/still.png")
	reference_sha = sha(reference_bytes)
	# Git хранит LF; Windows может создать CRLF. Хешируем одинаковое представление текста.
	request_sha = sha(requests_path.read_text(encoding="utf-8-sig").encode("utf-8"))
	outputs = []
	for row in rows:
		if row.get("endpoint") != "/generate-image-v2" or row.get("style_image") != "references/warrior11.png":
			raise SystemExit(f"Unexpected request contract for item {row['id']}")
		external = JOBS / "items" / f"{row['id']:03d}"
		result_path = external / "result.json"
		job_path = external / "job-latest.json"
		submitted_path = external / "submitted.json"
		if not result_path.is_file() or not job_path.is_file() or not submitted_path.is_file():
			continue
		result, job, submitted = read_json(result_path), read_json(job_path), read_json(submitted_path)
		if result.get("status") != "completed" or job.get("status") != "completed":
			continue
		job_id = result.get("job_id")
		if not job_id or job.get("id") != job_id or submitted.get("background_job_id") != job_id:
			raise SystemExit(f"Job/result/submission ID mismatch for item {row['id']}")
		if submitted.get("status") not in ("submitted", "processing", "completed", None):
			raise SystemExit(f"Unexpected submission status for item {row['id']}")
		request_sha_actual = check_request_provenance(row, external)
		items = result.get("outputs", [])
		if len(items) != 1:
			raise SystemExit(f"Expected exactly one PNG output for item {row['id']}, got {len(items)}")
		item = items[0]
		# Корень папки с локальными результатами отделён от логов и полных ответов провайдера.
		source_path = external / Path(item.get("path", "")).name
		if source_path.name != "original.png" or not source_path.is_file():
			raise SystemExit(f"Missing provider original PNG for item {row['id']}")
		raw = source_path.read_bytes()
		if sha(raw) != item.get("sha256"):
			raise SystemExit(f"Provider PNG SHA mismatch for item {row['id']}")
		with Image.open(source_path) as image:
			image.load()
			if image.size != (256, 256) or image.mode != "RGBA":
				raise SystemExit(f"Expected one 256x256 RGBA output for item {row['id']}")
			if item.get("width") != 256 or item.get("height") != 256 or item.get("mode") != "RGBA":
				raise SystemExit(f"Result metadata dimensions/mode mismatch for item {row['id']}")
			if list(image.getchannel("A").getextrema()) != item.get("alpha_extrema"):
				raise SystemExit(f"Alpha metadata mismatch for item {row['id']}")
			rgba = image.copy()
		alpha = rgba.getchannel("A")
		if not alpha.getbbox() or alpha.getextrema()[0] == 255:
			raise SystemExit(f"Output must have visible and transparent pixels for item {row['id']}")
		bbox = alpha.getbbox()
		out_dir = ROOT / "variants"
		out_dir.mkdir(parents=True, exist_ok=True)
		out_path = out_dir / f"hobgoblin-{row['id']:02d}.png"
		if out_path.exists() and out_path.read_bytes() != raw:
			raise SystemExit(f"Existing exported bytes differ: {out_path}")
		shutil.copyfile(source_path, out_path)
		outputs.append({
			"id": row["id"], "name": row["name"], "file": out_path.relative_to(ROOT).as_posix(),
			"sha256": sha(raw), "job_id": job_id, "usage": result.get("usage"),
			"width": 256, "height": 256, "mode": "RGBA",
			"alpha_extrema": list(alpha.getextrema()), "alpha_bbox": list(bbox),
			"edge_contact": bbox[0] == 0 or bbox[1] == 0 or bbox[2] == 256 or bbox[3] == 256,
			"request_sha256": request_sha_actual,
		})
	sources = {
		"expected": 10, "completed": len(outputs), "complete": len(outputs) == 10,
		"request_manifest_sha256": request_sha, "request_manifest_hash_policy": "UTF-8 without BOM, LF newlines",
		"style_reference": "references/warrior11.png",
		"style_reference_sha256": reference_sha,
		"runtime_reference_sha256": sha(RUNTIME_REFERENCE.read_bytes()),
		"transformation": "PNG provider originals copied byte-for-byte; no repaint or resize",
		"integration": False, "variants": outputs,
	}
	(ROOT / "sources.json").write_text(json.dumps(sources, ensure_ascii=False, indent=2), encoding="utf-8")
	print(json.dumps({"expected": 10, "exported": len(outputs), "complete": len(outputs) == 10,
		"edge_contact": [item["id"] for item in outputs if item["edge_contact"]]}, ensure_ascii=False))


if __name__ == "__main__":
	main()
