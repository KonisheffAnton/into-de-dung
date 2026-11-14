"""Экспортирует пять PixelLab edit_with_text PNG без изменения исходных пикселей."""
from pathlib import Path
import base64
import hashlib
import json
import shutil

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[2]
JOBS = Path("C:/Users/Aston/.codex/generated_images/kostyash-development-five-20261114/items")
SIZE = (256, 256)


def read_json(path: Path) -> dict | list:
	return json.loads(path.read_text(encoding="utf-8-sig"))


def sha(data: bytes) -> str:
	return hashlib.sha256(data).hexdigest()


def canonical_sha(value: object) -> str:
	return sha(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8"))


def decode_image(container: dict) -> bytes:
	image = container.get("image")
	if not isinstance(image, dict) or not isinstance(image.get("base64"), str):
		raise SystemExit("Submitted request has no input image bytes")
	data = image["base64"]
	if data.startswith("data:"):
		data = data.split(",", 1)[1]
	return base64.b64decode(data, validate=True)


def validate_request(row: dict, external: Path) -> str:
	stored = read_json(external / "request.json")
	if stored.get("endpoint") != row.get("endpoint") or not isinstance(stored.get("body"), dict):
		raise SystemExit(f"Request endpoint/body mismatch: variant {row['id']}")
	body = stored["body"]
	if "reference" in body or "reference_image" in body:
		raise SystemExit(f"edit_with_text request must not include a reference image: variant {row['id']}")
	method = stored.get("method", body.get("method", body.get("edit_method")))
	if method != row.get("method"):
		raise SystemExit(f"Request method mismatch: variant {row['id']}")
	for key in ("description", "seed", "no_background"):
		if body.get(key) != row.get(key):
			raise SystemExit(f"Submitted {key} differs from public request: variant {row['id']}")
	if body.get("image_size") != row.get("image_size"):
		raise SystemExit(f"Submitted image_size differs from public request: variant {row['id']}")
	edit_images = body.get("edit_images")
	if not isinstance(edit_images, list) or len(edit_images) != 1:
		raise SystemExit(f"Expected one edit_images input: variant {row['id']}")
	entry = edit_images[0]
	if (entry.get("width"), entry.get("height")) != SIZE:
		raise SystemExit(f"Unexpected edit input dimensions: variant {row['id']}")
	if decode_image(entry) != (ROOT / row["input"]).read_bytes():
		raise SystemExit(f"Submitted input PNG differs from source: variant {row['id']}")
	return canonical_sha(stored)


def alpha_bbox(image: Image.Image) -> list[int] | None:
	box = image.getchannel("A").getbbox()
	return list(box) if box else None


def geometry_flags(image: Image.Image) -> list[str]:
	box = alpha_bbox(image)
	if box is None:
		return ["empty_alpha"]
	height = box[3] - box[1]
	flags = []
	if not 130 <= height <= 140:
		flags.append("height_outside_130_140")
	if height >= 152:
		flags.append("not_shorter_than_warrior")
	if min(box[0], box[1], 256 - box[2], 256 - box[3]) < 8:
		flags.append("margin_under_8px")
	alpha = np.asarray(image.getchannel("A"))
	if not np.any(alpha == 0):
		flags.append("no_transparency")
	return flags


def main() -> None:
	requests = read_json(ROOT / "requests.json")
	rows = requests.get("variants") if isinstance(requests, dict) else None
	if not isinstance(rows, list) or len(rows) != 5 or [row.get("id") for row in rows] != list(range(1, 6)):
		raise SystemExit("requests.json must contain five variants numbered 1 through 5")
	input_source = read_json(ROOT / "input-source.json")
	source_path = ROOT / input_source["file"]
	warrior_path = ROOT / input_source["warrior_file"]
	if sha(source_path.read_bytes()) != input_source.get("sha256") or sha(warrior_path.read_bytes()) != input_source.get("warrior_sha256"):
		raise SystemExit("Input-source or Warrior reference SHA mismatch")
	previous_source = REPO / input_source["source_package"]
	if not previous_source.is_file() or previous_source.read_bytes() != source_path.read_bytes():
		raise SystemExit("Kostyash source differs from the selected prior output")
	with Image.open(source_path) as source_image, Image.open(warrior_path) as warrior_image:
		source = source_image.convert("RGBA")
		warrior = warrior_image.convert("RGBA")
		if source.size != SIZE or warrior.size != SIZE or source_image.mode != "RGBA" or warrior_image.mode != "RGBA":
			raise SystemExit("Source Kostyash and Warrior reference must be 256x256 RGBA")
		source_box = alpha_bbox(source)
		warrior_box = alpha_bbox(warrior)
		if source_box != input_source.get("bbox") or source_box[3] - source_box[1] != input_source.get("height"):
			raise SystemExit("Source Kostyash bbox/height differs from input-source.json")
		if warrior_box is None or warrior_box[3] - warrior_box[1] != input_source.get("warrior_height"):
			raise SystemExit("Warrior alpha height differs from input-source.json")
	request_sha = sha((ROOT / "requests.json").read_text(encoding="utf-8-sig").encode("utf-8"))
	input_source_sha = sha((ROOT / "input-source.json").read_text(encoding="utf-8-sig").encode("utf-8"))
	results = []
	for row in rows:
		if (row.get("endpoint") != "/edit-images-v2" or row.get("method") != "edit_with_text"
				or row.get("input") != input_source["file"] or row.get("image_size") != {"width": 256, "height": 256}):
			raise SystemExit(f"Unexpected edit request contract: {row.get('id')}")
		external = JOBS / f"{row['id']:03d}"
		result_path, job_path, submitted_path = external / "result.json", external / "job-latest.json", external / "submitted.json"
		if not result_path.is_file() or not job_path.is_file() or not submitted_path.is_file():
			continue
		result, job, submitted = read_json(result_path), read_json(job_path), read_json(submitted_path)
		if result.get("status") != "completed" or job.get("status") != "completed":
			continue
		job_id = result.get("job_id")
		if not job_id or job.get("id") != job_id or submitted.get("background_job_id") != job_id:
			raise SystemExit(f"Result/job/admission ID mismatch: variant {row['id']}")
		request_hash = validate_request(row, external)
		outputs = result.get("outputs", [])
		if len(outputs) != 1:
			raise SystemExit(f"Expected one image output: variant {row['id']}")
		output = outputs[0]
		source_output = external / Path(output.get("path", "")).name
		if source_output.name != "original.png" or not source_output.is_file():
			raise SystemExit(f"Missing provider original.png: variant {row['id']}")
		raw = source_output.read_bytes()
		if sha(raw) != output.get("sha256"):
			raise SystemExit(f"Provider SHA mismatch: variant {row['id']}")
		with Image.open(source_output) as image:
			image.load()
			if image.size != SIZE or image.mode != "RGBA":
				raise SystemExit(f"Provider output must be 256x256 RGBA: variant {row['id']}")
			if (output.get("width"), output.get("height"), output.get("mode")) != (256, 256, "RGBA"):
				raise SystemExit(f"Output metadata size/mode mismatch: variant {row['id']}")
			if list(image.getchannel("A").getextrema()) != output.get("alpha_extrema"):
				raise SystemExit(f"Output alpha metadata mismatch: variant {row['id']}")
			final = image.copy()
		box = alpha_bbox(final)
		flags = geometry_flags(final)
		variants_dir = ROOT / "variants"
		variants_dir.mkdir(parents=True, exist_ok=True)
		destination = variants_dir / f"kostyash-{row['id']:02d}.png"
		if destination.exists() and destination.read_bytes() != raw:
			raise SystemExit(f"Existing raw variant bytes differ: {destination}")
		shutil.copyfile(source_output, destination)
		results.append({
			"id": row["id"], "name": row["name"], "focus": row.get("focus", ""),
			"file": destination.relative_to(ROOT).as_posix(), "sha256": sha(raw), "job_id": job_id,
			"usage": result.get("usage"), "request_sha256": request_hash,
			"width": 256, "height": 256, "mode": "RGBA", "bbox": box,
			"native_height": box[3] - box[1] if box else None, "geometry_pass": not flags,
			"needs_review": bool(flags), "geometry_flags": flags,
		})
	sources = {
		"expected": 5, "completed": len(results), "complete": len(results) == 5,
		"request_manifest_sha256": request_sha, "request_manifest_hash_policy": "UTF-8 without BOM, LF newlines",
		"input_source_manifest_sha256": input_source_sha, "input_source_hash_policy": "UTF-8 without BOM, LF newlines",
		"input_source": input_source, "geometry_policy": "130-140px native alpha height, shorter than Warrior, at least 8px canvas margin",
		"raw_images_unmodified": True, "integration": False, "variants": results,
	}
	(ROOT / "sources.json").write_text(json.dumps(sources, ensure_ascii=False, indent=2), encoding="utf-8")
	print(json.dumps({"expected": 5, "exported": len(results), "complete": len(results) == 5,
		"needs_review": [item["id"] for item in results if item["needs_review"]]}, ensure_ascii=False))


if __name__ == "__main__":
	main()
