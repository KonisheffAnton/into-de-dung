"""Экспортирует admitted PixelLab PNG и создаёт отдельный вид с padding без resize."""
from pathlib import Path
import base64
import hashlib
import json
import shutil

from PIL import Image

ROOT = Path(__file__).resolve().parent
JOBS = Path("C:/Users/Aston/.codex/generated_images/hobgoblins-hunched-ten-20261114/final192x128")
RUNTIME_REFERENCE = ROOT.parents[2] / "assets/art_presets/approved/character_skins_v1/red_bastion/still.png"
RAW_SIZE = (192, 128)
DISPLAY_SIZE = (256, 256)
GROUNDLINE_Y = 200
WARRIOR_HEIGHT = 152


def read_json(path: Path) -> dict | list:
	return json.loads(path.read_text(encoding="utf-8-sig"))


def sha(data: bytes) -> str:
	return hashlib.sha256(data).hexdigest()


def canonical_sha(value: object) -> str:
	return sha(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8"))


def check_request_provenance(row: dict, external: Path) -> str:
	path = external / "request.json"
	if not path.is_file():
		raise SystemExit(f"Missing submitted request for item {row['id']}")
	stored = read_json(path)
	if stored.get("endpoint") != row.get("endpoint"):
		raise SystemExit(f"Endpoint differs from local request for item {row['id']}")
	body = stored.get("body")
	for key in ("description", "image_size", "seed", "no_background", "style_options"):
		if not isinstance(body, dict) or body.get(key) != row.get(key):
			raise SystemExit(f"Submitted {key} differs from plan for item {row['id']}")
	style = body.get("style_image")
	if not isinstance(style, dict) or style.get("usage_description") != row.get("style_usage"):
		raise SystemExit(f"Style reference policy differs for item {row['id']}")
	encoded = style.get("image", {}).get("base64", "")
	if not isinstance(encoded, str):
		raise SystemExit(f"Submitted reference image is missing for item {row['id']}")
	if encoded.startswith("data:"):
		encoded = encoded.split(",", 1)[1]
	if base64.b64decode(encoded, validate=True) != (ROOT / row["style_image"]).read_bytes():
		raise SystemExit(f"Submitted reference bytes differ for item {row['id']}")
	return canonical_sha(stored)


def main() -> None:
	requests_path = ROOT / "requests.json"
	rows = read_json(requests_path)
	if not isinstance(rows, list) or len(rows) != 10 or [row.get("id") for row in rows] != list(range(1, 11)):
		raise SystemExit("Expected ten requests numbered 1 through 10")
	reference_path = ROOT / "references/warrior11.png"
	reference_bytes = reference_path.read_bytes()
	if reference_bytes != RUNTIME_REFERENCE.read_bytes():
		raise SystemExit("warrior11.png must match runtime red_bastion/still.png byte-for-byte")
	with Image.open(reference_path) as reference:
		ref_bbox = reference.convert("RGBA").getchannel("A").getbbox()
		if reference.size != DISPLAY_SIZE or reference.mode != "RGBA" or ref_bbox is None:
			raise SystemExit("Warrior style reference must be a nonempty 256x256 RGBA PNG")
		reference_height = ref_bbox[3] - ref_bbox[1]
	if reference_height != WARRIOR_HEIGHT:
		raise SystemExit(f"Expected Warrior native silhouette height {WARRIOR_HEIGHT}px, got {reference_height}px")
	request_sha = sha(requests_path.read_text(encoding="utf-8-sig").encode("utf-8"))
	outputs = []
	for row in rows:
		if row.get("endpoint") != "/generate-image-v2" or row.get("style_image") != "references/warrior11.png" or row.get("image_size") != {"width": 192, "height": 128}:
			raise SystemExit(f"Unexpected 192x128 request contract for item {row['id']}")
		external = JOBS / "items" / f"{row['id']:03d}"
		result_path, job_path, submitted_path = external / "result.json", external / "job-latest.json", external / "submitted.json"
		if not result_path.is_file() or not job_path.is_file() or not submitted_path.is_file():
			continue
		result, job, submitted = read_json(result_path), read_json(job_path), read_json(submitted_path)
		if result.get("status") != "completed" or job.get("status") != "completed":
			continue
		job_id = result.get("job_id")
		if not job_id or job.get("id") != job_id or submitted.get("background_job_id") != job_id:
			raise SystemExit(f"Job/result/submission admission ID mismatch for item {row['id']}")
		check_request_provenance(row, external)
		provider_outputs = result.get("outputs", [])
		if len(provider_outputs) != 1:
			raise SystemExit(f"Expected one original PNG for item {row['id']}")
		provider = provider_outputs[0]
		source_path = external / Path(provider.get("path", "")).name
		if source_path.name != "original.png" or not source_path.is_file():
			raise SystemExit(f"Missing original provider PNG for item {row['id']}")
		raw = source_path.read_bytes()
		if sha(raw) != provider.get("sha256"):
			raise SystemExit(f"Provider original SHA mismatch for item {row['id']}")
		with Image.open(source_path) as image:
			image.load()
			if image.size != RAW_SIZE or image.mode != "RGBA":
				raise SystemExit(f"Expected 192x128 RGBA output for item {row['id']}, got {image.size}/{image.mode}")
			if (provider.get("width"), provider.get("height"), provider.get("mode")) != (192, 128, "RGBA"):
				raise SystemExit(f"Provider dimensions/mode metadata mismatch for item {row['id']}")
			alpha = image.getchannel("A")
			if list(alpha.getextrema()) != provider.get("alpha_extrema"):
				raise SystemExit(f"Alpha extrema metadata mismatch for item {row['id']}")
			rgba = image.copy()
		alpha = rgba.getchannel("A")
		bbox = alpha.getbbox()
		if bbox is None or alpha.getextrema()[0] != 0 or alpha.getextrema()[1] == 0:
			raise SystemExit(f"Output must contain transparent margins and a visible subject for item {row['id']}")
		native_height = bbox[3] - bbox[1]
		if native_height >= WARRIOR_HEIGHT:
			raise SystemExit(f"Item {row['id']} is not shorter than Warrior: {native_height}px >= {WARRIOR_HEIGHT}px")
		x_offset, y_offset = 32, GROUNDLINE_Y - bbox[3]
		display = Image.new("RGBA", DISPLAY_SIZE, (0, 0, 0, 0))
		# Пэддинг переносит неизменённый растр к общей линии земли; масштаб не меняется.
		display.paste(rgba, (x_offset, y_offset))
		variant_dir, display_dir = ROOT / "variants", ROOT / "display"
		variant_dir.mkdir(parents=True, exist_ok=True)
		display_dir.mkdir(parents=True, exist_ok=True)
		raw_path = variant_dir / f"hobgoblin-{row['id']:02d}.png"
		display_path = display_dir / f"hobgoblin-{row['id']:02d}-256.png"
		if raw_path.exists() and raw_path.read_bytes() != raw:
			raise SystemExit(f"Existing raw export differs: {raw_path}")
		shutil.copyfile(source_path, raw_path)
		display.save(display_path)
		outputs.append({
			"id": row["id"], "name": row["name"], "file": raw_path.relative_to(ROOT).as_posix(),
			"display_file": display_path.relative_to(ROOT).as_posix(), "sha256": sha(raw),
			"original_sha256": sha(raw), "display_sha256": sha(display_path.read_bytes()),
			"job_id": job_id, "usage": result.get("usage"), "width": 192, "height": 128, "mode": "RGBA",
			"alpha_extrema": list(alpha.getextrema()), "alpha_bbox": list(bbox),
			"native_alpha_height": native_height, "shorter_than_warrior": True,
			"edge_sides": [side for side, touched in (("left", bbox[0] == 0), ("top", bbox[1] == 0), ("right", bbox[2] == RAW_SIZE[0]), ("bottom", bbox[3] == RAW_SIZE[1])) if touched],
			"margin_violation": bbox[0] < 8 or bbox[1] < 8 or bbox[2] > RAW_SIZE[0] - 8 or bbox[3] > RAW_SIZE[1] - 8,
			"paste_offset": [x_offset, y_offset], "groundline_y": GROUNDLINE_Y,
			"request_sha256": canonical_sha(read_json(external / "request.json")),
		})
	sources = {
		"expected": 10, "completed": len(outputs), "complete": len(outputs) == 10,
		"request_manifest_sha256": request_sha, "request_manifest_hash_policy": "UTF-8 without BOM, LF newlines",
		"style_reference": "references/warrior11.png", "style_reference_sha256": sha(reference_bytes),
		"runtime_reference_sha256": sha(RUNTIME_REFERENCE.read_bytes()), "reference_native_alpha_height": reference_height,
		"raw_size": [192, 128], "display_size": [256, 256], "groundline_y": GROUNDLINE_Y,
		"transformation": "Raw provider PNGs copied byte-for-byte. Display images add transparent padding only; no scaling or recoloring.",
		"edge_policy": "Raw edge contact and narrow margins are retained as visible diagnostics; padded preview is checked for clipping separately.",
		"integration": False, "variants": outputs,
	}
	(ROOT / "sources.json").write_text(json.dumps(sources, ensure_ascii=False, indent=2), encoding="utf-8")
	print(json.dumps({"expected": 10, "exported": len(outputs), "complete": len(outputs) == 10,
		"native_heights": [item["native_alpha_height"] for item in outputs],
		"edge_contact": [item["id"] for item in outputs if item["edge_sides"]]}, ensure_ascii=False))


if __name__ == "__main__":
	main()
