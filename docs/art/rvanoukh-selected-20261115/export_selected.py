"""Assemble the selected death edit from PixelLab mask pixels only."""
from pathlib import Path
import base64
import hashlib
import io
import json
import sys

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[2]
SOURCE_PACKAGE = REPO / "docs/art/rvanoukh-animation-20261115"
JOBS = Path("D:/Codex/home/generated_images/rvanoukh-selected-20261115/pixellab/edit-1")
CANVAS = (256, 256)


def sha(data: bytes) -> str:
	return hashlib.sha256(data).hexdigest()


def read_json(path: Path) -> dict:
	return json.loads(path.read_text(encoding="utf-8-sig"))


def json_sha(path: Path) -> str:
	# JSON provenance must survive the repository's LF checkout policy.
	return sha(json.dumps(read_json(path), sort_keys=True, separators=(",", ":")).encode("utf-8"))


def decode_image(payload: dict) -> bytes:
	encoded = payload.get("image", {}).get("base64")
	if not isinstance(encoded, str):
		raise SystemExit("PixelLab response is missing base64 image bytes")
	return base64.b64decode(encoded, validate=True)


def source_frame(frame_index: int) -> tuple[Path, bytes, Image.Image]:
	path = SOURCE_PACKAGE / "pixellab/death-1/frames" / f"frame-{frame_index:02d}.png"
	raw = path.read_bytes()
	with Image.open(io.BytesIO(raw)) as image:
		image.load()
		if image.format != "PNG" or image.size != CANVAS or image.mode != "RGBA":
			raise SystemExit(f"Base frame must be 256x256 RGBA: {path}")
		return path, raw, image.copy()


def box_from_manifest(quadrant: dict, kind: str) -> list[int]:
	return quadrant["corner_box_xyxy"] if kind == "corner" else None


def paste_atlas_patch(canvas: Image.Image, atlas: Image.Image, quadrant: dict, box: list[int]) -> None:
	offset_x, offset_y = quadrant["offset"]
	x0, y0, x1, y1 = box
	patch = atlas.crop((offset_x + x0, offset_y + y0, offset_x + x1, offset_y + y1))
	canvas.paste(patch, (x0, y0))


def make_sheet(frames: list[Image.Image]) -> Image.Image:
	sheet = Image.new("RGBA", (2048, 1280), (0, 0, 0, 0))
	for i, frame in enumerate(frames):
		sheet.paste(frame, ((i % 8) * 256, (i // 8) * 256))
	return sheet


def main() -> None:
	manifest = read_json(ROOT / "edit-manifest.json")
	if manifest.get("endpoint") != "inpaint-v3" or len(manifest.get("quadrants", [])) != 4:
		raise SystemExit("Unexpected PixelLab edit manifest")
	request_file, admission_file = JOBS / "request.json", JOBS / "admission.json"
	job_file = JOBS / "job-latest.json"
	if not all(path.is_file() for path in (request_file, admission_file, job_file)):
		raise SystemExit("PixelLab job is not ready: request/admission/job result missing")
	actual, admission, job = read_json(request_file), read_json(admission_file), read_json(job_file)
	input_path, mask_path = ROOT / manifest["input"], ROOT / manifest["mask"]
	input_raw, mask_raw = input_path.read_bytes(), mask_path.read_bytes()
	if sha(input_raw) != manifest["input_sha256"] or sha(mask_raw) != manifest["mask_sha256"]:
		raise SystemExit("Inpainting input or mask SHA mismatch")
	if actual.get("description") != (ROOT / "prompt.txt").read_text(encoding="utf-8"):
		raise SystemExit("Submitted inpaint description differs from prompt")
	for field, raw in (("inpainting_image", input_raw), ("mask_image", mask_raw)):
		if decode_image(actual.get(field, {})) != raw:
			raise SystemExit(f"Submitted {field} bytes differ from packaged PNG")
		if actual[field].get("size") != {"width": 512, "height": 512}:
			raise SystemExit(f"Submitted {field} dimensions mismatch")
	if actual.get("seed") != manifest["seed"] or actual.get("no_background") is not True or actual.get("crop_to_mask") is not True:
		raise SystemExit("Submitted PixelLab options differ from manifest")
	if job.get("status") != "completed":
		raise SystemExit(f"PixelLab job not complete: {job.get('status')}")
	job_id = job.get("background_job_id") or job.get("id")
	if not job_id or job_id != admission.get("background_job_id"):
		raise SystemExit("PixelLab job/admission ID mismatch")
	response = job.get("last_response") or {}
	output = response.get("image")
	if not isinstance(output, dict):
		raise SystemExit("Expected one provider atlas in PixelLab response.image")
	atlas_bytes = base64.b64decode(output["base64"], validate=True)
	with Image.open(io.BytesIO(atlas_bytes)) as decoded:
		decoded.load()
		if decoded.format != "PNG" or decoded.size != (512, 512) or decoded.mode != "RGBA" or output.get("width") != 512 or output.get("height") != 512:
			raise SystemExit("PixelLab response must be a 512x512 RGBA PNG atlas")
		atlas = decoded.copy()
	provider_dir = ROOT / "provider"
	provider_dir.mkdir(parents=True, exist_ok=True)
	(provider_dir / "raw-atlas.png").write_bytes(atlas_bytes)
	(provider_dir / "provenance.json").write_text(json.dumps({
		"endpoint": "inpaint-v3", "job_id": job_id, "usage": response.get("billing_usage") or response.get("usage") or job.get("usage"),
		"atlas_sha256": sha(atlas_bytes), "atlas_size": [512, 512], "atlas_mode": "RGBA",
		"request_sha256": sha(json.dumps(actual, sort_keys=True, separators=(",", ":")).encode("utf-8")),
		"input_sha256": manifest["input_sha256"], "mask_sha256": manifest["mask_sha256"]}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
	if "--extract-only" in sys.argv:
		print(json.dumps({"status": "atlas_extracted", "path": "provider/raw-atlas.png", "job_id": job_id,
			"atlas_sha256": sha(atlas_bytes), "usage": response.get("billing_usage") or response.get("usage") or job.get("usage")}, ensure_ascii=False))
		return
	quadrants = {int(q["source_frame"]): q for q in manifest["quadrants"]}
	map_rows = manifest["frame_mapping"]
	frames_dir = ROOT / "death-1-closed-eyes/frames"
	frames_dir.mkdir(parents=True, exist_ok=True)
	frame_images, records = [], []
	for index in range(33):
		_, original_raw, original = source_frame(index)
		mapping = map_rows[str(index)]
		if index == 0:
			final_raw = original_raw
			final = original.copy()
		else:
			final = original.copy()
			corner_quad = quadrants[mapping["corner_from"]]
			paste_atlas_patch(final, atlas, corner_quad, corner_quad["corner_box_xyxy"])
			eye_source = mapping["eyes_from"]
			if eye_source is not None:
				eye_quad = quadrants[eye_source]
				for box in eye_quad["eye_boxes_xyxy"]:
					paste_atlas_patch(final, atlas, eye_quad, box)
			buffer = io.BytesIO()
			final.save(buffer, format="PNG")
			final_raw = buffer.getvalue()
		path = frames_dir / f"frame-{index:02d}.png"
		path.write_bytes(final_raw)
		frame_images.append(final)
		records.append({"index": index, "file": path.relative_to(ROOT).as_posix(), "sha256": sha(final_raw),
			"source_file": (SOURCE_PACKAGE / "pixellab/death-1/frames" / f"frame-{index:02d}.png").relative_to(REPO).as_posix(),
			"source_sha256": sha(original_raw), "provider_patch_sources": mapping,
			"byte_equal_source": final_raw == original_raw, "canvas": [256, 256], "mode": "RGBA"})
		if index == 0 and final_raw != original_raw:
			raise SystemExit("Death frame 0 must remain a byte-exact copy")
		# PNG sheet and previews are downstream presentation derivatives; source patches stay untouched.
	sheet = make_sheet(frame_images)
	sheet_path = ROOT / "death-1-closed-eyes/spritesheet.png"
	sheet.save(sheet_path)
	filmstrip = Image.new("RGBA", (1280, 256), (24, 33, 49, 255))
	for column, frame_index in enumerate((0, 8, 16, 24, 32)):
		filmstrip.alpha_composite(frame_images[frame_index], (column * 256, 0))
	filmstrip.save(ROOT / "death-1-closed-eyes/filmstrip.png")
	base_clip = read_json(SOURCE_PACKAGE / "pixellab/death-1/clip.json")
	meta = {"kind": "death", "variant": 1, "name": "Рухнул вперёд — закрытые глаза", "key": "death-1-closed-eyes",
		"source_clip": "../rvanoukh-animation-20261115/pixellab/death-1", "source_clip_sha256": json_sha(SOURCE_PACKAGE / "pixellab/death-1/clip.json"),
		"json_hash_policy": "Parsed JSON, sorted keys, compact separators, ensure_ascii=True, UTF-8 without BOM; binary PNG hashes remain raw",
		"anchor": base_clip["anchor"], "canvas": [256, 256], "actual_frames": 33, "loop": False,
		"durations_ms": base_clip["durations_ms"], "total_duration_ms": base_clip["total_duration_ms"],
		"provider": {"file": "provider/raw-atlas.png", "sha256": sha(atlas_bytes), "job_id": job_id,
			"usage": response.get("billing_usage") or response.get("usage") or job.get("usage"), "atlas_size": [512, 512]},
		"edit_manifest_sha256": sha(json.dumps(manifest, sort_keys=True, separators=(",", ":")).encode("utf-8")),
		"assembly_policy": manifest["assembly_policy"], "frames": records,
		"spritesheet": {"file": sheet_path.relative_to(ROOT).as_posix(), "sha256": sha(sheet_path.read_bytes()), "size": list(sheet.size)},
		"filmstrip": {"file": "death-1-closed-eyes/filmstrip.png", "sha256": sha((ROOT / "death-1-closed-eyes/filmstrip.png").read_bytes())},
		"runtime_integration": False}
	(ROOT / "death-1-closed-eyes/clip.json").write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
	print(json.dumps({"status": "assembled", "job_id": job_id, "atlas_sha256": sha(atlas_bytes), "frames": 33,
		"source_frame0_byte_equal": records[0]["byte_equal_source"], "usage": meta["provider"]["usage"]}, ensure_ascii=False))


if __name__ == "__main__":
	main()
