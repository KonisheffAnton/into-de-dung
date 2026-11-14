"""Экспортирует completed inpaint PNG и сверяет их с точной маской ремонта."""
from pathlib import Path
import base64
import hashlib
import json
import shutil

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[2]
JOBS = Path("C:/Users/Aston/.codex/generated_images/hobgoblins-repair-ten-20261114/items")
SIZE = (256, 256)


def read_json(path: Path) -> dict | list:
	return json.loads(path.read_text(encoding="utf-8-sig"))


def sha(data: bytes) -> str:
	return hashlib.sha256(data).hexdigest()


def canonical_sha(value: object) -> str:
	return sha(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8"))


def decode_image(container: dict, field: str, label: str) -> bytes:
	value = container.get(field)
	if not isinstance(value, dict) or not isinstance(value.get("base64"), str):
		raise SystemExit(f"Missing submitted {label} bytes")
	encoded = value["base64"]
	if encoded.startswith("data:"):
		encoded = encoded.split(",", 1)[1]
	return base64.b64decode(encoded, validate=True)


def validate_request(row: dict, external: Path) -> str:
	stored = read_json(external / "request.json")
	if stored.get("endpoint") != row.get("endpoint") or not isinstance(stored.get("body"), dict):
		raise SystemExit(f"Submitted request endpoint/body mismatch: {row['id']}")
	body = stored["body"]
	for key in ("description", "bounding_box", "no_background", "output_method", "crop_to_mask", "seed"):
		if body.get(key) != row.get(key):
			raise SystemExit(f"Submitted {key} differs from public request for item {row['id']}")
	for field, row_key in (("image", "input"), ("mask_image", "mask"), ("context_image", "context")):
		if decode_image(body, field, field) != (ROOT / row[row_key]).read_bytes():
			raise SystemExit(f"Submitted {field} bytes differ from package for item {row['id']}")
	return canonical_sha(stored)


def load_rgba(path: Path) -> Image.Image:
	with Image.open(path) as image:
		if image.size != SIZE or image.mode != "RGBA":
			raise SystemExit(f"Expected 256x256 RGBA: {path}")
		return image.copy()


def load_binary_mask(path: Path) -> np.ndarray:
	with Image.open(path) as image:
		if image.size != SIZE or image.mode != "RGB":
			raise SystemExit(f"Mask must be 256x256 RGB: {path}")
		mask = np.asarray(image)
	if not np.all(mask == mask[:, :, :1]) or not np.isin(mask[:, :, 0], (0, 255)).all():
		raise SystemExit(f"Mask must contain pure black/white RGB pixels only: {path}")
	return mask[:, :, 0] == 255


def bbox(alpha: np.ndarray) -> list[int] | None:
	points = np.argwhere(alpha > 0)
	if not len(points):
		return None
	return [int(points[:, 1].min()), int(points[:, 0].min()), int(points[:, 1].max()) + 1, int(points[:, 0].max()) + 1]


def main() -> None:
	requests_path = ROOT / "requests.json"
	rows = read_json(requests_path)
	if not isinstance(rows, list) or len(rows) != 10 or [row.get("id") for row in rows] != list(range(1, 11)):
		raise SystemExit("Expected exactly ten repair requests")
	owner = read_json(ROOT / "input-sources.json")
	if len(owner.get("inputs", [])) != 10:
		raise SystemExit("input-sources.json must cover all ten originals")
	owner_by_id = {item["id"]: item for item in owner["inputs"]}
	request_sha = sha(requests_path.read_text(encoding="utf-8-sig").encode("utf-8"))
	owner_sha = sha((ROOT / "input-sources.json").read_text(encoding="utf-8-sig").encode("utf-8"))
	results = []
	for row in rows:
		if row.get("endpoint") != "/inpaint-image-pro-flash" or row.get("expected_size") != [256, 256]:
			raise SystemExit(f"Unexpected repair request contract for item {row.get('id')}")
		owner_item = owner_by_id.get(row["id"])
		if owner_item is None or owner_item.get("whole_figure_style_mask") != (row["id"] == 8):
			raise SystemExit(f"Input source/mask exception metadata mismatch for item {row['id']}")
		input_path, mask_path = ROOT / row["input"], ROOT / row["mask"]
		input_bytes = input_path.read_bytes()
		if sha(input_bytes) != owner_item.get("input_sha256") or sha(mask_path.read_bytes()) != owner_item.get("mask_sha256"):
			raise SystemExit(f"Input or mask source SHA differs from owner manifest: {row['id']}")
		previous_source = REPO / owner_item["source"]
		if not previous_source.is_file() or previous_source.read_bytes() != input_bytes:
			raise SystemExit(f"Repair input differs from previous package source: {row['id']}")
		mask_white = load_binary_mask(mask_path)
		with Image.open(ROOT / row["context"]) as context_image:
			if context_image.size != (768, 256) or context_image.mode != "RGBA":
				raise SystemExit(f"Context must be 768x256 RGBA for item {row['id']}")
		if int(np.count_nonzero(mask_white)) != owner_item.get("white_mask_pixels"):
			raise SystemExit(f"Mask white-pixel count differs from owner manifest: {row['id']}")
		source = load_rgba(input_path)
		source_alpha = np.asarray(source.getchannel("A"))
		source_box = bbox(source_alpha)
		if source_box != owner_item.get("source_bbox"):
			raise SystemExit(f"Source bbox differs from owner manifest: {row['id']}")
		external = JOBS / f"{row['id']:03d}"
		result_path, job_path, submitted_path = external / "result.json", external / "job-latest.json", external / "submitted.json"
		if not result_path.is_file() or not job_path.is_file() or not submitted_path.is_file():
			continue
		result, job, submitted = read_json(result_path), read_json(job_path), read_json(submitted_path)
		if result.get("status") != "completed" or job.get("status") != "completed":
			continue
		job_id = result.get("job_id")
		if not job_id or job.get("id") != job_id or submitted.get("background_job_id") != job_id:
			raise SystemExit(f"Result/job/admission ID mismatch for item {row['id']}")
		request_hash = validate_request(row, external)
		outputs = result.get("outputs", [])
		if len(outputs) != 1:
			raise SystemExit(f"Expected one final PNG for item {row['id']}")
		output = outputs[0]
		source_output = external / Path(output.get("path", "")).name
		if source_output.name != "original.png" or not source_output.is_file():
			raise SystemExit(f"Missing downloaded final original.png for item {row['id']}")
		raw = source_output.read_bytes()
		if sha(raw) != output.get("sha256"):
			raise SystemExit(f"Final provider output SHA mismatch for item {row['id']}")
		final = load_rgba(source_output)
		final_array, input_array = np.asarray(final), np.asarray(source)
		changed = np.any(final_array != input_array, axis=2)
		if np.any(changed & ~mask_white):
			raise SystemExit(f"Provider modified RGBA pixels outside the white mask: item {row['id']}")
		final_box = bbox(final_array[:, :, 3])
		if final_box is None or np.all(final_array[:, :, 3] == 0) or not np.any(final_array[:, :, 3] == 0):
			raise SystemExit(f"Final sprite must contain visible and transparent pixels: {row['id']}")
		final_height = final_box[3] - final_box[1]
		source_height = int(owner_item["source_height"])
		if final_height >= 152 or final_height > source_height + 9:
			raise SystemExit(f"Final silhouette grew outside allowed bounds for item {row['id']}: {source_height}->{final_height}")
		if final_height < source_height - 8:
			raise SystemExit(f"Final silhouette shrank by more than 8px for item {row['id']}: {source_height}->{final_height}")
		alpha = final.getchannel("A")
		if final_box[0] < 8 or final_box[1] < 8 or final_box[2] > 248 or final_box[3] > 248:
			raise SystemExit(f"Final silhouette lacks 8px canvas margin: item {row['id']} bbox={final_box}")
		if owner_item.get("whole_figure_style_mask") and row["id"] != 8:
			raise SystemExit("Whole-figure mask exception is only allowed for variant 8")
		before_top, before_bottom = source_box[1], source_box[3]
		after_top, after_bottom = final_box[1], final_box[3]
		top_zone = np.zeros(mask_white.shape, dtype=bool)
		top_zone[:max(before_top, after_top) + 1, :] = mask_white[:max(before_top, after_top) + 1, :]
		bottom_start = min(before_bottom, after_bottom) - 1
		bottom_zone = np.zeros(mask_white.shape, dtype=bool)
		bottom_zone[max(0, bottom_start):, :] = mask_white[max(0, bottom_start):, :]
		top_changes = int(np.count_nonzero(changed & top_zone))
		bottom_changes = int(np.count_nonzero(changed & bottom_zone))
		variant_dir = ROOT / "variants"
		variant_dir.mkdir(parents=True, exist_ok=True)
		destination = variant_dir / f"hobgoblin-{row['id']:02d}.png"
		if destination.exists() and destination.read_bytes() != raw:
			raise SystemExit(f"Existing final variant bytes differ: {destination}")
		shutil.copyfile(source_output, destination)
		results.append({
			"id": row["id"], "name": row["name"], "file": destination.relative_to(ROOT).as_posix(),
			"sha256": sha(raw), "job_id": job_id, "usage": result.get("usage"), "request_sha256": request_hash,
			"input_file": row["input"], "input_sha256": sha(input_bytes), "mask_file": row["mask"],
			"mask_sha256": sha(mask_path.read_bytes()), "context_file": row["context"],
			"context_sha256": sha((ROOT / row["context"]).read_bytes()), "whole_figure_style_mask": owner_item["whole_figure_style_mask"],
			"source_bbox": source_box, "final_bbox": final_box, "source_height": source_height,
			"final_height": final_height, "height_delta": final_height - source_height,
			"height_within_repair_allowance": final_height >= source_height - 8, "outside_white_mask_exact": True,
			"changed_pixels_top_repair_zone": top_changes, "changed_pixels_bottom_repair_zone": bottom_changes,
			"edge_contact": final_box[0] == 0 or final_box[1] == 0 or final_box[2] == 256 or final_box[3] == 256,
		})
	sources = {"expected": 10, "completed": len(results), "complete": len(results) == 10,
		"request_manifest_sha256": request_sha, "request_manifest_hash_policy": "UTF-8 without BOM, LF newlines",
		"input_sources_manifest_sha256": owner_sha, "input_sources_hash_policy": "UTF-8 without BOM, LF newlines",
		"whole_figure_mask_exception": {"id": 8, "enabled": True},
		"boundary_note": "Changed-pixel counts in top/bottom repair zones are diagnostics; outside-white-mask equality is mandatory.",
		"style_and_blister_appearance": "Visual review required; not automatically accepted.", "integration": False, "variants": results}
	(ROOT / "sources.json").write_text(json.dumps(sources, ensure_ascii=False, indent=2), encoding="utf-8")
	print(json.dumps({"expected": 10, "exported": len(results), "complete": len(results) == 10,
		"height_deltas": {str(item["id"]): item["height_delta"] for item in results}}, ensure_ascii=False))


if __name__ == "__main__":
	main()
