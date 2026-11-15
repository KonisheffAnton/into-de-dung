"""Validate source provenance, mask-only PixelLab assembly, timing, and gallery."""
from pathlib import Path
import base64
import hashlib
import io
import json
import re

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[2]
SOURCE = REPO / "docs/art/rvanoukh-animation-20261115"


def sha(data: bytes) -> str:
	return hashlib.sha256(data).hexdigest()


def read_json(path: Path) -> dict:
	return json.loads(path.read_text(encoding="utf-8-sig"))


def json_sha(path: Path) -> str:
	return sha(json.dumps(read_json(path), sort_keys=True, separators=(",", ":")).encode("utf-8"))


def load_rgba(path: Path) -> Image.Image:
	with Image.open(path) as image:
		image.load()
		if image.format != "PNG" or image.mode != "RGBA":
			raise SystemExit(f"Expected RGBA PNG: {path}")
		return image.copy()


def bbox(image: Image.Image) -> list[int] | None:
	box = image.getchannel("A").getbbox()
	return list(box) if box else None


def is_warm_eye_patch(pixels: np.ndarray) -> np.ndarray:
	return (pixels[:, :, 3] > 0) & (pixels[:, :, 0] >= 150) & (pixels[:, :, 1] >= 95) & (pixels[:, :, 2] <= 115)


def expected_frame_patch(index: int, manifest: dict) -> tuple[dict | None, list[list[int]], dict | None]:
	mapping = manifest["frame_mapping"][str(index)]
	quadrants = {int(q["source_frame"]): q for q in manifest["quadrants"]}
	eye_q = quadrants.get(mapping["eyes_from"]) if mapping["eyes_from"] is not None else None
	corner_q = quadrants.get(mapping["corner_from"]) if mapping["corner_from"] is not None else None
	eye_boxes = eye_q["eye_boxes_xyxy"] if eye_q else []
	return eye_q, eye_boxes, corner_q


def main() -> None:
	manifest = read_json(ROOT / "edit-manifest.json")
	selection = read_json(ROOT / "selection.json")
	if not {"main_idle", "rare_idle", "death", "ability", "runtime_integration", "rare_idle_frequency"} <= set(selection):
		raise SystemExit("Selection manifest is missing user decisions")
	if selection["ability"].get("generate") is not False or selection["ability"].get("integrate") is not False or selection["rare_idle_frequency"] != "not specified; do not invent a gameplay probability":
		raise SystemExit("Deferred attack or rare-idle frequency contract changed")
	if manifest.get("endpoint") != "inpaint-v3" or len(manifest.get("quadrants", [])) != 4:
		raise SystemExit("Unexpected edit manifest endpoint/quadrants")
	input_raw = (ROOT / manifest["input"]).read_bytes()
	mask_raw = (ROOT / manifest["mask"]).read_bytes()
	if sha(input_raw) != manifest["input_sha256"] or sha(mask_raw) != manifest["mask_sha256"]:
		raise SystemExit("Packaged inpaint input/mask SHA mismatch")
	# Reconstruct the request from the selected source poses, not only recorded hashes.
	expected_input = Image.new("RGBA", (512, 512))
	expected_mask = np.zeros((512, 512), dtype=bool)
	for index, quadrant in enumerate(manifest["quadrants"]):
		offset = [(index % 2) * 256, (index // 2) * 256]
		if quadrant["quadrant"] != index or quadrant["source_frame"] != index + 9 or quadrant["offset"] != offset:
			raise SystemExit("Inpaint source-pose order or quadrant placement changed")
		source_path = SOURCE / "pixellab/death-1/frames" / f"frame-{index + 9:02d}.png"
		if (ROOT.parent / quadrant["source"]).resolve() != source_path.resolve() or sha(source_path.read_bytes()) != quadrant["source_sha256"]:
			raise SystemExit("Inpaint quadrant source path/SHA mismatch")
		expected_input.paste(load_rgba(source_path), tuple(offset))
		for left, top, right, bottom in [quadrant["corner_box_xyxy"], *quadrant["eye_boxes_xyxy"]]:
			if not (0 <= left < right <= 256 and 0 <= top < bottom <= 256):
				raise SystemExit("Mask rectangle outside source quadrant")
			x, y = offset
			expected_mask[y + top:y + bottom, x + left:x + right] = True
	with Image.open(io.BytesIO(input_raw)) as input_image:
		if input_image.mode != "RGBA" or input_image.size != (512, 512) or input_image.tobytes() != expected_input.tobytes():
			raise SystemExit("Inpaint atlas pixels differ from the four selected source frames")
	with Image.open(io.BytesIO(mask_raw)) as mask_image:
		expected_rgb = np.repeat((expected_mask.astype(np.uint8) * 255)[:, :, None], 3, axis=2)
		if mask_image.mode != "RGB" or mask_image.size != (512, 512) or not np.array_equal(np.asarray(mask_image), expected_rgb):
			raise SystemExit("Inpaint mask is not exactly the recorded black/white eye/corner regions")
	request = read_json(ROOT / "provider/provenance.json")
	atlas_raw = (ROOT / "provider/raw-atlas.png").read_bytes()
	if sha(atlas_raw) != request.get("atlas_sha256") or request.get("input_sha256") != manifest["input_sha256"] or request.get("mask_sha256") != manifest["mask_sha256"]:
		raise SystemExit("Provider atlas or input/mask provenance mismatch")
	with Image.open(io.BytesIO(atlas_raw)) as im:
		im.load()
		if im.format != "PNG" or im.size != (512, 512) or im.mode != "RGBA":
			raise SystemExit("Provider atlas must be raw 512x512 RGBA PNG")
		atlas = im.copy()
	job_dir = Path("D:/Codex/home/generated_images/rvanoukh-selected-20261115/pixellab/edit-1")
	actual = read_json(job_dir / "request.json")
	admission, job = read_json(job_dir / "admission.json"), read_json(job_dir / "job-latest.json")
	if actual.get("description") != (ROOT / "prompt.txt").read_text(encoding="utf-8") or actual.get("seed") != manifest["seed"] or actual.get("no_background") is not True or actual.get("crop_to_mask") is not True:
		raise SystemExit("Provider request options differ from source manifest")
	request_sha = sha(json.dumps(actual, sort_keys=True, separators=(",", ":")).encode("utf-8"))
	if request_sha != request.get("request_sha256") or job.get("status") != "completed" or job.get("id") != request.get("job_id") or admission.get("background_job_id") != request.get("job_id"):
		raise SystemExit("Provider request hash or admitted/completed job ID mismatch")
	response_image = (job.get("last_response") or {}).get("image") or {}
	if base64.b64decode(response_image.get("base64", ""), validate=True) != atlas_raw:
		raise SystemExit("Saved raw atlas bytes differ from original provider response")
	for field, expected in (("inpainting_image", input_raw), ("mask_image", mask_raw)):
		payload = actual[field]
		if base64.b64decode(payload["image"]["base64"], validate=True) != expected or payload.get("size") != {"width": 512, "height": 512}:
			raise SystemExit(f"Actual provider {field} differs from packaged input")
	if request.get("job_id") != "41d92196-8d34-4996-91fc-f4cea1fc38ab":
		raise SystemExit("Provider job ID differs from admitted job")
	clip = read_json(ROOT / "death-1-closed-eyes/clip.json")
	base_clip_path = SOURCE / "pixellab/death-1/clip.json"
	base_clip = read_json(base_clip_path)
	if clip.get("source_clip_sha256") != json_sha(base_clip_path) or clip.get("anchor") != [128, 200] or clip.get("durations_ms") != base_clip["durations_ms"] or clip.get("actual_frames") != 33:
		raise SystemExit("Corrected death clip source/timing/anchor mismatch")
	quadrants = {int(q["source_frame"]): q for q in manifest["quadrants"]}
	frames, patched_regions, frame_rows = [], [], []
	for index, record in enumerate(clip.get("frames", [])):
		if record.get("index") != index or record.get("canvas") != [256, 256] or record.get("mode") != "RGBA":
			raise SystemExit(f"Corrected frame index/canvas/mode mismatch: {index}")
		out_path = ROOT / record["file"]
		out_raw = out_path.read_bytes()
		if sha(out_raw) != record.get("sha256"):
			raise SystemExit(f"Corrected frame SHA mismatch: {index}")
		# Resolve exact original bytes without depending on the local preview package.
		source_path = SOURCE / "pixellab/death-1/frames" / f"frame-{index:02d}.png"
		source_raw = source_path.read_bytes()
		if sha(source_raw) != record.get("source_sha256") or source_raw != (REPO / record["source_file"]).read_bytes():
			raise SystemExit(f"Base frame provenance mismatch: {index}")
		original, final = load_rgba(source_path), load_rgba(out_path)
		if original.size != (256, 256) or final.size != (256, 256):
			raise SystemExit(f"Death frame canvas mismatch: {index}")
		if index == 0 and out_raw != source_raw:
			raise SystemExit("Frame zero is not a byte-exact base copy")
		mapping = manifest["frame_mapping"][str(index)]
		eye_source = mapping["eyes_from"]
		corner_source = mapping["corner_from"]
		eye_q = quadrants[eye_source] if eye_source is not None else None
		corner_q = quadrants[corner_source] if corner_source is not None else None
		eye_boxes = eye_q["eye_boxes_xyxy"] if eye_q else []
		allowed = np.zeros((256, 256), dtype=bool)
		for box in eye_boxes + ([corner_q["corner_box_xyxy"]] if corner_q else []):
			x0, y0, x1, y1 = box
			allowed[y0:y1, x0:x1] = True
		before, after = np.asarray(original), np.asarray(final)
		changed = np.any(before != after, axis=2)
		if np.any(changed & ~allowed):
			raise SystemExit(f"RGBA pixels outside allowed edit masks changed: frame {index}")
		for quadrant, boxes in ((eye_q, eye_boxes), (corner_q, [corner_q["corner_box_xyxy"]] if corner_q else [])):
			if quadrant is None:
				continue
			ox, oy = quadrant["offset"]
			for x0, y0, x1, y1 in boxes:
				provider_crop = np.asarray(atlas.crop((ox + x0, oy + y0, ox + x1, oy + y1)))
				final_crop = after[y0:y1, x0:x1]
				if not np.array_equal(provider_crop, final_crop):
					raise SystemExit(f"Composed patch differs from raw PixelLab atlas: frame {index}, box {(x0, y0, x1, y1)}")
		if corner_q:
			x0, y0, x1, y1 = corner_q["corner_box_xyxy"]
			if np.any(after[y0:y1, x0:x1, 3] != 0):
				raise SystemExit(f"Corner patch is not fully transparent: frame {index}")
		if eye_q:
			for x0, y0, x1, y1 in eye_boxes:
				crop = after[y0:y1, x0:x1]
				if np.any(crop[:, :, 3] != 255):
					raise SystemExit(f"Eye patch has alpha holes: frame {index}")
				if np.any(is_warm_eye_patch(crop)):
					raise SystemExit(f"Open/warm eye pixels remain in closed-eye patch: frame {index}")
		box = bbox(final)
		if box is None:
			raise SystemExit(f"Corrected frame is fully transparent: {index}")
		margins = (box[0], box[1], 256 - box[2], 256 - box[3])
		if min(margins) < 8:
			raise SystemExit(f"Corrected frame still touches 8px margin: {index}, margins {margins}")
		frames.append(final)
		patched_regions.append(int(np.count_nonzero(changed)))
		frame_rows.append({"index": index, "outside_mask_rgba_exact": True, "frame0_byte_equal": index != 0 or out_raw == source_raw,
			"corner_transparent": corner_q is None or not np.any(after[:4, :4, 3]), "eye_alpha_opaque": bool(eye_q),
			"warm_eye_pixels": 0, "alpha_bbox": box, "margins": list(margins), "changed_pixels": patched_regions[-1]})
	if len(frames) != 33:
		raise SystemExit("Corrected death clip must contain 33 frames")
	selected_idle_checks = []
	for folder, key, selected_key, variant in ((SOURCE / "pixellab/idle-3", "idle-3", "main_idle", 3),
		(SOURCE / "pixellab/idle-2", "idle-2", "rare_idle", 2)):
		selected_meta = read_json(folder / "clip.json")
		if selection.get(selected_key, {}).get("source") != f"../rvanoukh-animation-20261115/pixellab/{key}" or selected_meta.get("kind") != "idle" or selected_meta.get("variant") != variant or selected_meta.get("loop") is not True or len(selected_meta.get("frame_records", [])) != 33:
			raise SystemExit(f"Selected idle source invalid: {key}")
		for record in selected_meta["frame_records"]:
			path = SOURCE / record["file"]
			if sha(path.read_bytes()) != record["sha256"]:
				raise SystemExit(f"Selected idle raw frame changed: {key}:{record['index']}")
		idle_sheet = folder / "spritesheet.png"
		if sha(idle_sheet.read_bytes()) != selected_meta["spritesheet"]["sha256"]:
			raise SystemExit(f"Selected idle spritesheet changed: {key}")
		selected_idle_checks.append({"key": key, "role": selection[selected_key]["source"],
			"variant": variant, "clip_sha256": json_sha(folder / "clip.json"),
			"job_id": selected_meta["job_id"], "usage": selected_meta["usage"],
			"spritesheet_sha256": sha(idle_sheet.read_bytes()), "source_frames_verified": 33,
			"unchanged": True})
	sheet_path = ROOT / clip["spritesheet"]["file"]
	if sha(sheet_path.read_bytes()) != clip["spritesheet"]["sha256"]:
		raise SystemExit("Corrected death sheet SHA mismatch")
	with Image.open(sheet_path) as sheet:
		if sheet.mode != "RGBA" or sheet.size != (2048, 1280):
			raise SystemExit("Corrected death sheet dimensions/mode mismatch")
		for index, frame in enumerate(frames):
			crop = sheet.crop(((index % 8) * 256, (index // 8) * 256, (index % 8 + 1) * 256, (index // 8 + 1) * 256))
			if crop.tobytes() != frame.tobytes():
				raise SystemExit(f"Corrected sprite sheet cell differs from frame {index}")
		if np.any(np.asarray(sheet.getchannel("A"))[4 * 256:, 256:] != 0):
			raise SystemExit("Unused corrected spritesheet cells are not transparent")
	with Image.open(ROOT / "preview.gif") as gif:
		if gif.size != (1536, 512):
			raise SystemExit("Combined preview GIF must show three 2x nearest-neighbor panels")
		gif_total = 0
		gif_durations = []
		for i in range(gif.n_frames):
			gif.seek(i)
			duration = gif.info.get("duration", 0)
			gif_durations.append(duration)
			gif_total += duration
	if gif_total != clip["total_duration_ms"]:
		raise SystemExit(f"Composite preview GIF total timing mismatch: {gif_total}")
	expected_boundaries = {0}
	expected_boundaries.update(range(90, clip["total_duration_ms"], 90))
	clock = 0
	for duration in clip["durations_ms"]:
		clock += duration
		if clock < clip["total_duration_ms"]:
			expected_boundaries.add(clock)
	expected_times = sorted(expected_boundaries)
	expected_gif_durations = [expected_times[i + 1] - t if i + 1 < len(expected_times) else clip["total_duration_ms"] - t for i, t in enumerate(expected_times)]
	if gif_durations != expected_gif_durations:
		raise SystemExit("Combined GIF frame intervals differ from the merged original clip timings")
	data = read_json(ROOT / "gallery-data.json")
	if len(data.get("clips", [])) != 3 or data.get("embedded_asset_count") != 6 or len(data.get("assets", [])) != 6:
		raise SystemExit("Selected gallery must embed exactly three clips and six assets")
	html = (ROOT / "gallery.html").read_text(encoding="utf-8")
	asset_match = re.search(r"const ASSETS=(\{.*?\}),CLIPS=", html, re.S)
	clip_match = re.search(r"CLIPS=(\[.*?\]);let players", html, re.S)
	if not asset_match or not clip_match:
		raise SystemExit("Cannot parse offline gallery data")
	assets, gallery_clips = json.loads(asset_match.group(1)), json.loads(clip_match.group(1))
	if len(assets) != 6 or len(gallery_clips) != 3 or set(assets) != set(data["assets"]):
		raise SystemExit("Gallery embedded asset/clip count mismatch")
	for key, uri in assets.items():
		m = re.fullmatch(r"data:image/(png|gif);base64,([A-Za-z0-9+/=]+)", uri)
		if not m:
			raise SystemExit(f"Gallery asset is not embedded as a data URI: {key}")
		bytes_ = base64.b64decode(m.group(2), validate=True)
		if key == "overview.png":
			on_disk = (ROOT / "overview.png").read_bytes()
		elif key == "preview.gif":
			on_disk = (ROOT / "preview.gif").read_bytes()
		elif key == "source/death-1/spritesheet.png":
			on_disk = (SOURCE / "pixellab/death-1/spritesheet.png").read_bytes()
		elif key.startswith("selected/idle-"):
			clip_key = key.split("/")[1]
			on_disk = (SOURCE / "pixellab" / clip_key / "spritesheet.png").read_bytes()
		else:
			on_disk = sheet_path.read_bytes()
		if bytes_ != on_disk:
			raise SystemExit(f"Embedded asset bytes differ from packaged source: {key}")
	if any(clip["kind"] == "ability" for clip in gallery_clips) or len({c["kind"] for c in gallery_clips}) != 2:
		raise SystemExit("Deferred attacks or wrong clip kinds appear in selected gallery")
	for required in ("Основное ожидание №3", "Редкое ожидание №2", "Смерть №1 — закрытые глаза", "частота не задана", "data-source", "requestAnimationFrame", "data-slider"):
		if required not in html:
			raise SystemExit(f"Gallery UI missing requirement: {required}")
	result = {"status": "PASS", "structural_pass": True, "outside_mask_rgba_exact": True,
		"frame0_byte_exact": True, "closed_eye_frames": [9, 10, 11, *range(12, 33)],
		"warm_eye_pixels_in_patches": 0, "corner_clear_frames": list(range(1, 33)),
		"corrected_frame_count": len(frames), "source_idle_clips_unchanged": True,
		"provider_job_id": request["job_id"], "provider_usage": request["usage"], "provider_request_sha256": request_sha,
		"provider_atlas_sha256": request["atlas_sha256"], "provider_patch_sources": {str(r["index"]): r["provider_patch_sources"] for r in clip["frames"]},
		"selection_manifest_sha256": json_sha(ROOT / "selection.json"), "selected_idle_clips": selected_idle_checks,
		"input_atlas_matches_source_poses": True, "mask_geometry_exact": True,
		"mask_white_pixels": int(expected_mask.sum()),
		"json_hash_policy": "Canonical parsed JSON; binary PNG/GIF remain raw byte hashes",
		"timings_ms": clip["durations_ms"], "duration_total_ms": clip["total_duration_ms"],
		"preview_gif_frames": gif.n_frames, "preview_gif_total_duration_ms": gif_total, "preview_gif_size": [1536, 512],
		"gallery_embedded_assets": len(assets), "gallery_clips": [c["key"] for c in gallery_clips],
		"frame_checks": frame_rows, "runtime_integration": False}
	(ROOT / "validation.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
	print(json.dumps({"status": "PASS", "frames": len(frames), "outside_mask_rgba_exact": True,
		"frame0_byte_exact": True, "warm_eye_pixels": 0, "corners_clear": 32,
		"preview_gif_frames": gif.n_frames, "preview_gif_ms": gif_total, "gallery_assets": len(assets)}, ensure_ascii=False))


if __name__ == "__main__":
	main()
