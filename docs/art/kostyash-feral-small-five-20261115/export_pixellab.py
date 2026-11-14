"""Проверяет происхождение и экспортирует исходные PNG пяти вариантов."""
from pathlib import Path
import base64
import hashlib
import json
import shutil

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[2]
JOBS = Path("C:/Users/Aston/.codex/generated_images/kostyash-feral-small-five-20261115/feral-generation/items")
SIZE = (256, 256)
OUTPUT_SIZE = (160, 128)
PREVIEW_WIDTH_OFFSET = 48


def read_json(path: Path):
	return json.loads(path.read_text(encoding="utf-8-sig"))


def sha(data: bytes) -> str:
	return hashlib.sha256(data).hexdigest()


def canonical_sha(value: object) -> str:
	return sha(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8"))


def manifest_sha(path: Path) -> str:
	return sha(path.read_text(encoding="utf-8-sig").encode("utf-8"))


def decode_image(entry: dict) -> bytes:
	image = entry if isinstance(entry.get("base64"), str) else entry.get("image")
	data = image.get("base64") if isinstance(image, dict) else None
	if not isinstance(data, str):
		raise SystemExit("Submitted image has no base64 bytes")
	if data.startswith("data:"):
		data = data.split(",", 1)[1]
	return base64.b64decode(data, validate=True)


def bbox(image: Image.Image) -> list[int] | None:
	box = image.getchannel("A").getbbox()
	return list(box) if box else None


def validate_request(row: dict, source: dict, external: Path) -> str:
	request = read_json(external / "request.json")
	if request.get("endpoint") != row["endpoint"] or not isinstance(request.get("body"), dict):
		raise SystemExit(f"Request endpoint/body mismatch: {row['id']}")
	body = request["body"]
	if "method" in body or row.get("method") != "generate_with_references":
		raise SystemExit(f"Unexpected request method contract: {row['id']}")
	for key in ("description", "seed", "image_size", "no_background", "style_options"):
		if body.get(key) != row.get(key):
			raise SystemExit(f"Submitted {key} differs from requests.json: {row['id']}")
	if body.get("image_size") != {"width": 160, "height": 128} or body["style_options"] != {"color_palette": False, "outline": True, "detail": True, "shading": True}:
		raise SystemExit(f"Unexpected image size or style options: {row['id']}")
	images, style = body.get("reference_images"), body.get("style_image")
	if not isinstance(images, list) or len(images) != 1 or not isinstance(style, dict):
		raise SystemExit(f"Expected one character reference and one style reference: {row['id']}")
	input_path = ROOT / row["input"]
	if decode_image(images[0]) != input_path.read_bytes() or input_path.read_bytes() != (ROOT / source["file"]).read_bytes():
		raise SystemExit(f"Submitted input does not match its prior variant: {row['id']}")
	if images[0].get("size") != {"width": 256, "height": 256} or images[0].get("usage_description") != row.get("reference_usage_description"):
		raise SystemExit(f"Character reference dimensions/usage mismatch: {row['id']}")
	warrior_path = ROOT / row["style_image"]
	if style.get("size") != {"width": 256, "height": 256} or style.get("usage_description") != row.get("style_usage_description") or decode_image(style) != warrior_path.read_bytes():
		raise SystemExit(f"Style reference dimensions/usage/bytes mismatch: {row['id']}")
	return canonical_sha(request)


def geometry(image: Image.Image, prior_height: int, warrior_height: int) -> tuple[list[str], list[int] | None, int | None, int | None]:
	box = bbox(image)
	if box is None:
		return ["empty_alpha"], None, None, None
	height = box[3] - box[1]
	margin = min(box[0], box[1], OUTPUT_SIZE[0] - box[2], OUTPUT_SIZE[1] - box[3])
	flags = []
	if not 90 <= height <= 110:
		flags.append("height_outside_target_90_110")
	if not 80 <= height <= 112:
		flags.append("height_outside_technical_80_112")
	if height >= prior_height:
		flags.append("not_shorter_than_prior")
	if height >= warrior_height:
		flags.append("not_shorter_than_warrior")
	if margin < 8:
		flags.append("margin_under_8px")
	if not np.any(np.asarray(image.getchannel("A")) == 0):
		flags.append("no_transparency")
	return flags, box, height, margin


def load_cleanup(row_id: int, generated: bytes, generated_path: Path) -> tuple[bytes, dict | None]:
	cleanup_path = ROOT / "cleanup.json"
	if not cleanup_path.is_file():
		return generated, None
	entries = read_json(cleanup_path).get("variants", [])
	selected = [item for item in entries if item.get("id") == row_id]
	if not selected:
		return generated, None
	if len(selected) != 1:
		raise SystemExit(f"Expected at most one cleanup record for {row_id}")
	entry = selected[0]
	if entry.get("input_file") != generated_path.relative_to(ROOT).as_posix() or entry.get("input_sha256") != sha(generated):
		raise SystemExit(f"Cleanup input provenance mismatch: {row_id}")
	external = Path(entry["external_dir"])
	request = read_json(external / "request.json")
	if request.get("endpoint") != entry.get("endpoint") or entry.get("endpoint") != "/remove-background" or not isinstance(request.get("body"), dict):
		raise SystemExit(f"Cleanup endpoint mismatch: {row_id}")
	body = request["body"]
	declared = entry.get("request", {})
	if set(body) != set(declared) or body.get("image_size") != {"width": 160, "height": 128}:
		raise SystemExit(f"Cleanup body fields/size differ from manifest: {row_id}")
	for key, value in declared.items():
		if key == "image":
			if decode_image(body[key]) != generated or value.get("sha256") != sha(generated):
				raise SystemExit(f"Cleanup submitted image bytes mismatch: {row_id}")
		elif body.get(key) != value:
			raise SystemExit(f"Cleanup request field differs from manifest ({key}): {row_id}")
	result = read_json(external / "result.json")
	if result.get("status") != "completed" or result.get("job_id") is not None or result.get("usage") != entry.get("usage"):
		raise SystemExit(f"Synchronous cleanup result status/usage mismatch: {row_id}")
	outputs = result.get("outputs", [])
	if len(outputs) != 1:
		raise SystemExit(f"Cleanup must return exactly one image: {row_id}")
	output = outputs[0]
	path = external / Path(output.get("path", "")).name
	data = path.read_bytes()
	if path.name != "original.png" or sha(data) != output.get("sha256") or sha(data) != entry.get("output_sha256"):
		raise SystemExit(f"Cleanup output SHA/path mismatch: {row_id}")
	with Image.open(path) as image:
		if image.size != OUTPUT_SIZE or image.mode != "RGBA" or (output.get("width"), output.get("height"), output.get("mode")) != (160, 128, "RGBA") or list(image.getchannel("A").getextrema()) != output.get("alpha_extrema"):
			raise SystemExit(f"Cleanup output image metadata mismatch: {row_id}")
	return data, {"endpoint": entry["endpoint"], "request_sha256": canonical_sha(request), "input_sha256": sha(generated), "output_sha256": sha(data), "usage": entry.get("usage"), "job_id": None}


def main() -> None:
	requests = read_json(ROOT / "requests.json")
	rows = requests.get("variants") if isinstance(requests, dict) else None
	if not isinstance(rows, list) or len(rows) != 5 or [row.get("id") for row in rows] != list(range(1, 6)):
		raise SystemExit("requests.json must contain IDs 1 through 5")
	manifest = read_json(ROOT / "input-source.json")
	sources = manifest.get("sources")
	if not isinstance(sources, list) or len(sources) != 5 or [s.get("id") for s in sources] != list(range(1, 6)):
		raise SystemExit("input-source.json must contain five source records")
	if sha((ROOT / manifest["warrior_file"]).read_bytes()) != manifest.get("warrior_sha256"):
		raise SystemExit("Warrior reference SHA mismatch")
	with Image.open(ROOT / manifest["warrior_file"]) as warrior_image:
		if warrior_image.size != SIZE or warrior_image.mode != "RGBA":
			raise SystemExit("Warrior reference must be 256x256 RGBA")
		warrior_box = bbox(warrior_image)
		if not warrior_box or warrior_box[3] - warrior_box[1] != manifest.get("warrior_height"):
			raise SystemExit("Warrior reference height mismatch")
	request_sha = manifest_sha(ROOT / "requests.json")
	input_sha = manifest_sha(ROOT / "input-source.json")
	selection_path = ROOT / "selection.json"
	selection_manifest = read_json(selection_path)
	selections = selection_manifest.get("variants", [])
	if len(selections) != 5 or [x.get("id") for x in selections] != list(range(1, 6)) or selection_manifest.get("returned_per_job") != 4:
		raise SystemExit("selection.json must select one of four returned candidates for each variant")
	selection_sha = manifest_sha(selection_path)
	results = []
	for row, source, selection in zip(rows, sources, selections):
		if row.get("endpoint") != "/generate-image-v2" or row.get("method") != "generate_with_references" or row.get("input") != source.get("file") or row.get("style_image") != manifest["warrior_file"] or row.get("image_size") != {"width": 160, "height": 128}:
			raise SystemExit(f"Unexpected public request contract: {row['id']}")
		input_path, previous_path = ROOT / source["file"], REPO / source["source_package"]
		if sha(input_path.read_bytes()) != source.get("sha256") or not previous_path.is_file() or previous_path.read_bytes() != input_path.read_bytes():
			raise SystemExit(f"Prior source bytes/hash mismatch: {row['id']}")
		with Image.open(input_path) as src:
			if src.size != SIZE or src.mode != "RGBA" or bbox(src) != source.get("bbox") or bbox(src)[3] - bbox(src)[1] != source.get("height"):
				raise SystemExit(f"Prior source geometry mismatch: {row['id']}")
		external = JOBS / f"{row['id']:03d}"
		paths = [external / n for n in ("result.json", "job-latest.json", "submitted.json")]
		if not all(p.is_file() for p in paths):
			continue
		result, job, submitted = map(read_json, paths)
		if result.get("status") != "completed" or job.get("status") != "completed":
			continue
		job_id = result.get("job_id")
		if not job_id or job.get("id") != job_id or submitted.get("background_job_id") != job_id:
			raise SystemExit(f"Job/admission ID mismatch: {row['id']}")
		rq_sha = validate_request(row, source, external)
		outputs = result.get("outputs", [])
		if not outputs:
			raise SystemExit(f"Generation returned no outputs: {row['id']}")
		if len(outputs) != 4:
			raise SystemExit(f"Expected four generated candidates: {row['id']}")
		checked_outputs = []
		provider_files = []
		for index, output in enumerate(outputs):
			provider = external / Path(output.get("path", "")).name
			if not provider.is_file() or sha(provider.read_bytes()) != output.get("sha256"):
				raise SystemExit(f"Provider output SHA/path mismatch: {row['id']}")
			with Image.open(provider) as image:
				image.load()
				if image.size != OUTPUT_SIZE or image.mode != "RGBA" or (output.get("width"), output.get("height"), output.get("mode")) != (160, 128, "RGBA") or list(image.getchannel("A").getextrema()) != output.get("alpha_extrema"):
					raise SystemExit(f"Provider output metadata mismatch (expected 160x128 RGBA): {row['id']}")
			candidate_path = ROOT / "candidates" / f"{row['id']:02d}" / f"{index+1:02d}.png"
			if not candidate_path.is_file() or candidate_path.read_bytes() != provider.read_bytes():
				raise SystemExit(f"Preserved candidate differs from provider bytes: {row['id']}/{index+1}")
			provider_files.append(provider)
			checked_outputs.append({"index": index, "file": provider.name, "sha256": output["sha256"],
				"candidate_file": candidate_path.relative_to(ROOT).as_posix()})
		chosen_index = selection.get("output_index")
		if not isinstance(chosen_index, int) or not 0 <= chosen_index < len(outputs):
			raise SystemExit(f"Invalid selected generation output index: {row['id']}")
		selected_provider = provider_files[chosen_index]
		selected_output = outputs[chosen_index]
		selected_candidate = ROOT / selection.get("candidate_file", "")
		if selected_provider.name != selection.get("output_name") or sha(selected_provider.read_bytes()) != selection.get("sha256") or selected_output.get("sha256") != selection.get("sha256") or selected_candidate != ROOT / "candidates" / f"{row['id']:02d}" / f"{chosen_index+1:02d}.png" or selected_candidate.read_bytes() != selected_provider.read_bytes():
			raise SystemExit(f"Selection manifest does not match chosen provider candidate: {row['id']}")
		generated_raw = selected_provider.read_bytes()
		generated_path = ROOT / "generated" / f"kostyash-{row['id']:02d}.png"
		generated_path.parent.mkdir(parents=True, exist_ok=True)
		if generated_path.exists() and generated_path.read_bytes() != generated_raw:
			raise SystemExit(f"Existing generated raw bytes differ: {generated_path}")
		shutil.copyfile(selected_provider, generated_path)
		final_raw, cleanup_record = load_cleanup(row["id"], generated_raw, generated_path)
		final_path = ROOT / "variants" / f"kostyash-{row['id']:02d}.png"
		final_path.parent.mkdir(parents=True, exist_ok=True)
		if cleanup_record is None:
			if final_path.exists() and final_path.read_bytes() != generated_raw:
				raise SystemExit(f"Existing final bytes differ: {final_path}")
			shutil.copyfile(selected_provider, final_path)
		else:
			clean_entries = [x for x in read_json(ROOT / "cleanup.json")["variants"] if x["id"] == row["id"]]
			external_clean = Path(clean_entries[0]["external_dir"])
			clean_file = external_clean / "original.png"
			if final_path.exists() and final_path.read_bytes() != final_raw:
				raise SystemExit(f"Existing final bytes differ: {final_path}")
			shutil.copyfile(clean_file, final_path)
		with Image.open(final_path) as image:
			image.load()
			flags, box, height, margin = geometry(image, source["height"], manifest["warrior_height"])
			raw_image = image.copy()
		preview_offset = (PREVIEW_WIDTH_OFFSET, source["bbox"][3] - box[3])
		if preview_offset[1] < 0 or preview_offset[0] < 0 or preview_offset[0] + OUTPUT_SIZE[0] > SIZE[0] or preview_offset[1] + OUTPUT_SIZE[1] > SIZE[1]:
			raise SystemExit(f"Raw image does not fit preview canvas at feet-aligned offset: {row['id']}")
		preview = Image.new("RGBA", SIZE, (0, 0, 0, 0))
		preview.paste(raw_image, preview_offset)
		preview_path = ROOT / "previews" / final_path.name
		preview_path.parent.mkdir(parents=True, exist_ok=True)
		preview.save(preview_path, format="PNG")
		results.append({"id": row["id"], "name": row["name"], "focus": row.get("focus", ""),
			"file": final_path.relative_to(ROOT).as_posix(), "sha256": sha(final_raw), "generated_file": generated_path.relative_to(ROOT).as_posix(),
			"generated_sha256": sha(generated_raw), "selected_output_index": chosen_index, "selected_output_name": selected_provider.name,
			"generation_outputs": checked_outputs, "cleanup": cleanup_record, "job_id": job_id,
			"raw_width": 160, "raw_height": 128, "raw_mode": "RGBA", "usage": result.get("usage"), "request_sha256": rq_sha,
			"preview_file": preview_path.relative_to(ROOT).as_posix(), "preview_sha256": sha(preview_path.read_bytes()),
			"preview_width": 256, "preview_height": 256, "preview_mode": "RGBA", "preview_offset": list(preview_offset),
			"source_file": source["file"], "source_package": source["source_package"], "source_sha256": source["sha256"],
			"source_height": source["height"], "source_bbox": source["bbox"], "bbox": box, "native_height": height,
			"height_delta": height - source["height"], "shrink_percent": round((source["height"] - height) * 100 / source["height"], 2),
			"min_margin": margin, "geometry_pass": not flags, "needs_review": bool(flags), "geometry_flags": flags})
	output_manifest = {"expected": 5, "completed": len(results), "complete": len(results) == 5,
		"request_manifest_sha256": request_sha, "request_manifest_hash_policy": "UTF-8 without BOM, LF newlines",
		"selection_manifest_sha256": selection_sha, "selection_manifest_hash_policy": "UTF-8 without BOM, LF newlines",
		"input_source_manifest_sha256": input_sha, "input_source_hash_policy": "UTF-8 without BOM, LF newlines",
		"input_sources": manifest, "geometry_policy": "raw 160x128; target 90-110px and technical range 80-112px; at least 8px raw-canvas margin; shorter than prior source and Warrior; previews align raw feet to source feet without scaling",
		"raw_images_unmodified": True, "integration": False, "variants": results}
	(ROOT / "sources.json").write_text(json.dumps(output_manifest, ensure_ascii=False, indent=2), encoding="utf-8")
	print(json.dumps({"expected": 5, "exported": len(results), "complete": len(results) == 5,
		"needs_review": [x["id"] for x in results if x["needs_review"]]}, ensure_ascii=False))


if __name__ == "__main__":
	main()
