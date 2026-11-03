"""Проверяет транспорт, исходные PNG и экспорт клипов; не оценивает рисунок."""
from pathlib import Path
import hashlib
import json
import re

from PIL import Image
import numpy as np

ROOT = Path(__file__).resolve().parent


def read(path: Path):
	return json.loads(path.read_text(encoding="utf-8-sig"))


def digest(path: Path) -> str:
	return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
	errors = []
	requests = read(ROOT / "requests.json")
	exported = read(ROOT / "pixellab-validation.json")
	transform = read(ROOT / "model" / "transform.json")
	expected = len(requests)
	keys = [row["key"] for row in requests]
	if expected != 15 or len(set(keys)) != expected:
		errors.append("15 unique request rows")
	if not exported.get("complete") or exported.get("completed") != expected or exported.get("expected") != expected:
		errors.append("all request rows exported")
	if digest(ROOT / "model" / "source-full.png") != transform["source_sha256"]:
		errors.append("full source hash")
	if digest(ROOT / "model" / "input-256.png") != transform["input_sha256"]:
		errors.append("prepared input hash")
	if transform.get("canvas") != [256, 256] or transform.get("anchor") != [128, 200] or transform.get("resampling") != "nearest":
		errors.append("technical input canvas, anchor or resampling")
	resized = transform.get("resized_size", [0, 0])
	if resized[0] > 180 or resized[1] > 152:
		errors.append("prepared source footprint exceeds 180x152")
	counts = {kind: sum(row["kind"] == kind for row in requests) for kind in ("idle", "death", "ability")}
	if counts != {"idle": 5, "death": 5, "ability": 5}:
		errors.append("five requests per clip kind")
	input_rgba = np.asarray(Image.open(ROOT / "model" / "input-256.png").convert("RGBA"))
	exported_clips = exported.get("clips", [])
	if not isinstance(exported_clips, list):
		exported_clips = []
		errors.append("export clips must be a list")
	metadata = {clip["key"]: clip for clip in exported_clips
		if isinstance(clip, dict) and isinstance(clip.get("key"), str)}
	if len(exported_clips) != expected or set(metadata) != set(keys):
		errors.append("one export metadata record for every request key")
	if sorted(row.get("seed", -1) for row in requests) != list(range(2026110351, 2026110351 + expected)):
		errors.append("unique consecutive request seeds")
	for row in requests:
		if row.get("frame_count") != 32 or row.get("expected_frames") != 33:
			errors.append(f"32 generated plus input frame {row.get('key')}")
		if row.get("loop") != (row.get("kind") == "idle") or row.get("return_to_first") != (row.get("kind") != "death"):
			errors.append(f"clip loop and endpoint rules {row.get('key')}")
	diagnostics = []
	total_frames = total_cells = total_gifs = 0
	for row in requests:
		key = row["key"]
		folder = ROOT / "pixellab" / key
		meta_path = folder / "clip.json"
		if not meta_path.is_file():
			errors.append(f"missing clip metadata {key}")
			continue
		meta = read(meta_path)
		count = int(row["expected_frames"])
		frame_paths = sorted((folder / "frames").glob("frame-*.png"))
		if count != 33 or meta.get("actual_frames") != count or len(frame_paths) != count:
			errors.append(f"33 exported frames {key}")
		if meta.get("kind") != row["kind"] or meta.get("loop") != (row["kind"] == "idle"):
			errors.append(f"clip metadata {key}")
		if len(meta.get("durations_ms", [])) != count:
			errors.append(f"timing count {key}")
		frame_hashes = meta.get("frame_sha256")
		if not isinstance(frame_hashes, list) or len(frame_hashes) != count:
			errors.append(f"exact frame hash count {key}")
			hashes_for_export = []
		else:
			hashes_for_export = frame_hashes
		clip_export = metadata.get(key)
		if clip_export is None:
			errors.append(f"missing export metadata {key}")
			export_hashes = []
		else:
			export_hashes = clip_export.get("frame_sha256")
			if not isinstance(export_hashes, list) or len(export_hashes) != count:
				errors.append(f"exact export metadata frame hash count {key}")
				export_hashes = []
			elif any(not isinstance(value, str) or re.fullmatch(r"[0-9a-fA-F]{64}", value) is None
					for value in export_hashes):
				errors.append(f"invalid export metadata frame hash {key}")
			elif export_hashes != hashes_for_export:
				errors.append(f"clip/export frame hashes differ {key}")
		sheet_path = folder / "spritesheet.png"
		gif_path = folder / "preview.gif"
		if not sheet_path.is_file() or not gif_path.is_file():
			errors.append(f"missing sheet/GIF {key}")
			continue
		sheet = Image.open(sheet_path).convert("RGBA")
		if sheet.size != (2048, 256 * ((count + 7) // 8)):
			errors.append(f"sheet dimensions {key}")
		frames = []
		for index, frame_path in enumerate(frame_paths):
			raw = frame_path.read_bytes()
			expected_hash = frame_hashes[index] if isinstance(frame_hashes, list) and index < len(frame_hashes) else None
			if (not isinstance(expected_hash, str) or re.fullmatch(r"[0-9a-fA-F]{64}", expected_hash) is None
					or digest(frame_path) != expected_hash.lower()):
				errors.append(f"raw PNG hash {key}:{index}")
			image = Image.open(frame_path).convert("RGBA")
			if image.size != (256, 256):
				errors.append(f"frame dimensions {key}:{index}")
			if not np.any(np.asarray(image)[:, :, 3]):
				errors.append(f"empty alpha {key}:{index}")
			cell = sheet.crop(((index % 8) * 256, (index // 8) * 256,
				(index % 8 + 1) * 256, (index // 8 + 1) * 256))
			if not np.array_equal(np.asarray(image), np.asarray(cell)):
				errors.append(f"sheet cell {key}:{index}")
			frames.append(np.asarray(image))
			total_frames += 1
			total_cells += 1
		with Image.open(gif_path) as gif:
			gif_timing = []
			for index in range(gif.n_frames):
				gif.seek(index)
				gif_timing.append(gif.info.get("duration", 0))
			if not (1 <= len(gif_timing) <= count) or sum(gif_timing) != sum(meta.get("durations_ms", [])):
				errors.append(f"GIF timing {key}")
			total_gifs += 1
		first = frames[0] if frames else np.empty((0,))
		last = frames[-1] if frames else np.empty((0,))
		first_same_shape = first.shape == input_rgba.shape
		first_rgba_diff_mask = np.any(first != input_rgba, axis=2) if first_same_shape else np.ones(input_rgba.shape[:2], dtype=bool)
		first_alpha_diff_mask = first[:, :, 3] != input_rgba[:, :, 3] if first_same_shape else np.ones(input_rgba.shape[:2], dtype=bool)
		first_visible_mask = (first[:, :, 3] > 0) | (input_rgba[:, :, 3] > 0) if first_same_shape else np.ones(input_rgba.shape[:2], dtype=bool)
		first_rgba_diff_pixels = int(np.count_nonzero(first_rgba_diff_mask))
		first_alpha_diff_pixels = int(np.count_nonzero(first_alpha_diff_mask))
		first_visible_diff_pixels = int(np.count_nonzero(first_rgba_diff_mask & first_visible_mask))
		first_transparent_rgb_diff_pixels = first_rgba_diff_pixels - first_visible_diff_pixels
		first_rgba_equal = first_same_shape and first_rgba_diff_pixels == 0
		first_alpha_equal = first_same_shape and first_alpha_diff_pixels == 0
		first_pixel_bytes_equal = bool((folder / "frames" / "frame-00.png").read_bytes() == (ROOT / row["input"]).read_bytes()) if frames else False
		last_rgba_equal = bool(last.shape == input_rgba.shape and np.array_equal(last, input_rgba))
		if not first_alpha_equal or first_visible_diff_pixels > 0:
			errors.append(f"API input frame alpha or visible pixels changed {key}")
		unique = len({hashlib.sha256(frame.tobytes()).hexdigest() for frame in frames})
		if unique < 2:
			errors.append(f"no frame variation {key}")
		diagnostics.append({
			"key": key, "kind": row["kind"], "frames": len(frames), "unique_rgba_frames": unique,
			"gif_frames": len(gif_timing), "first_frame_rgba_equal": first_rgba_equal,
			"first_frame_rgba_differing_pixels": first_rgba_diff_pixels,
			"first_frame_alpha_equal": first_alpha_equal,
			"first_frame_alpha_differing_pixels": first_alpha_diff_pixels,
			"first_frame_visible_differing_pixels": first_visible_diff_pixels,
			"first_frame_transparent_rgb_differing_pixels": first_transparent_rgb_diff_pixels,
			"first_frame_png_bytes_equal": first_pixel_bytes_equal,
			"last_frame_equal_to_input": last_rgba_equal,
			"last_frame_differs_from_first": bool(frames and not np.array_equal(last, first)),
			"edge_frames": meta.get("edge_frames", []),
			"margin_violation_frames": meta.get("margin_violation_frames", []),
			"preview_endpoint_review_needed": row["kind"] in ("idle", "ability") and not last_rgba_equal,
			"export_metadata_present": clip_export is not None,
		})
	result = {
		"pass": not errors,
		"meaning": "Raw-source/export structure only; no motion, art or runtime acceptance",
		"first_frame_policy": "Alpha must match exactly; RGBA must match wherever either pixel has nonzero alpha. RGB-only differences where both alpha values are zero are diagnostics, not failures.",
		"first_frame_counts": {
			"alpha_differing_pixels": sum(item["first_frame_alpha_differing_pixels"] for item in diagnostics),
			"visible_differing_pixels": sum(item["first_frame_visible_differing_pixels"] for item in diagnostics),
			"rgba_differing_pixels": sum(item["first_frame_rgba_differing_pixels"] for item in diagnostics),
			"transparent_rgb_differing_pixels": sum(item["first_frame_transparent_rgb_differing_pixels"] for item in diagnostics),
			"transparent_rgb_only_clips": [item["key"] for item in diagnostics
				if item["first_frame_alpha_equal"] and item["first_frame_visible_differing_pixels"] == 0
				and item["first_frame_rgba_differing_pixels"] > 0],
		},
		"requests": expected, "clips": len(diagnostics), "kind_counts": counts,
		"checked_png_frames": total_frames, "checked_sheet_cells": total_cells,
		"checked_gifs": total_gifs, "diagnostics": diagnostics, "errors": errors,
		"integration": False, "art_acceptance": False, "runtime_validation": False,
	}
	(ROOT / "validation.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
	print(json.dumps({key: value for key, value in result.items() if key != "diagnostics"}, ensure_ascii=False))
	if errors:
		raise SystemExit(1)


if __name__ == "__main__":
	main()
