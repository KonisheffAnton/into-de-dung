"""Проверяет пять 17-кадровых PixelLab-атак, PNG-листы, GIF и HTML-встраивание."""
from pathlib import Path
import base64
import hashlib
import json
import re

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent
RUNTIME_INPUT = ROOT.parents[2] / "assets/art_presets/approved/character_skins_v1/red_bastion/still.png"


def sha(data: bytes) -> str:
	return hashlib.sha256(data).hexdigest()


def main() -> None:
	rows = json.loads((ROOT / "requests.json").read_text(encoding="utf-8-sig"))
	if len(rows) != 5 or [row.get("key") for row in rows] != [f"attack-{i}" for i in range(1, 6)]:
		raise SystemExit("Expected exactly attack-1 through attack-5")
	input_path = ROOT / "model/input-256.png"
	if not input_path.is_file() or not RUNTIME_INPUT.is_file():
		raise SystemExit("Missing model input or runtime red_bastion still.png")
	input_raw = input_path.read_bytes()
	runtime_raw = RUNTIME_INPUT.read_bytes()
	if input_raw != runtime_raw:
		raise SystemExit("model/input-256.png must be byte-identical to runtime red_bastion/still.png")
	with Image.open(input_path) as source_image:
		original = source_image.convert("RGBA")
		if original.size != (256, 256):
			raise SystemExit("Runtime input must be 256x256")
	clips = []
	for row in rows:
		folder = ROOT / "pixellab" / row["key"]
		meta_path = folder / "clip.json"
		if not meta_path.is_file():
			raise SystemExit(f"Missing clip manifest: {row['key']}")
		meta = json.loads(meta_path.read_text(encoding="utf-8-sig"))
		if meta.get("actual_frames") != 17 or meta.get("kind") != "attack" or meta.get("key") != row["key"]:
			raise SystemExit(f"Clip contract mismatch: {row['key']}")
		if meta.get("durations_ms") != [40] * 16 + [700]:
			raise SystemExit(f"Preview timing mismatch: {row['key']}")
		frames = []
		for index in range(17):
			path = folder / "frames" / f"frame-{index:02d}.png"
			if not path.is_file():
				raise SystemExit(f"Missing raw frame: {path}")
			raw = path.read_bytes()
			with Image.open(path) as image:
				if image.size != (256, 256) or image.mode != "RGBA":
					raise SystemExit(f"Raw frame must be 256x256 RGBA: {path}")
				alpha = np.asarray(image.getchannel("A"))
				if not np.any(alpha == 0) or not np.any(alpha > 0):
					raise SystemExit(f"Frame must contain visible and transparent pixels: {path}")
				frames.append(image.copy())
			if meta.get("frame_sha256", [])[index] != sha(raw):
				raise SystemExit(f"Raw frame SHA mismatch: {path}")
		sheet_path = folder / "spritesheet.png"
		with Image.open(sheet_path) as sheet:
			if sheet.mode != "RGBA" or sheet.size != (2048, 768):
				raise SystemExit(f"Expected 8x3 RGBA sheet: {sheet_path}")
			for index, frame in enumerate(frames):
				cell = sheet.crop(((index % 8) * 256, (index // 8) * 256,
					(index % 8 + 1) * 256, (index // 8 + 1) * 256))
				if cell.tobytes() != frame.tobytes():
					raise SystemExit(f"Sprite sheet cell differs from raw frame {index}: {row['key']}")
			for index in range(17, 24):
				cell = sheet.crop(((index % 8) * 256, (index // 8) * 256,
					(index % 8 + 1) * 256, (index // 8 + 1) * 256))
				if cell.getbbox():
					raise SystemExit(f"Unexpected non-empty sheet padding cell {index}: {row['key']}")
		with Image.open(folder / "preview.gif") as gif:
			if not 1 <= gif.n_frames <= 17:
				raise SystemExit(f"Unexpected GIF frame count: {row['key']}")
			gif_durations = []
			for index in range(gif.n_frames):
				gif.seek(index)
				gif_durations.append(gif.info.get("duration", 0))
				if gif.size != (512, 512):
					raise SystemExit(f"Unexpected GIF canvas: {row['key']}")
		if sum(gif_durations) != 1340 or any(duration <= 0 for duration in gif_durations):
			raise SystemExit(f"GIF total duration mismatch: {row['key']} ({sum(gif_durations)}ms)")
		first = np.asarray(frames[0])
		initial = np.asarray(original)
		diff = np.any(first != initial, axis=2)
		alpha_diff = first[:, :, 3] != initial[:, :, 3]
		visible = (first[:, :, 3] > 0) | (initial[:, :, 3] > 0)
		alpha_count = int(np.count_nonzero(alpha_diff))
		visible_count = int(np.count_nonzero(diff & visible))
		if alpha_count or visible_count:
			raise SystemExit(f"First frame differs in alpha/visible pixels: {row['key']} ({alpha_count}, {visible_count})")
		clips.append({"key": row["key"], "raw_frames": len(frames), "sheet_cells_equal": True,
			"gif_actual_durations_ms": gif_durations, "gif_total_duration_ms": sum(gif_durations),
			"first_frame_alpha_equal": True, "first_frame_visible_equal": True,
			"first_frame_png_byte_equal": (folder / "frames/frame-00.png").read_bytes() == input_raw,
			"edge_frames": meta.get("edge_frames", []),
			"margin_violation_frames": meta.get("margin_violation_frames", []),
			"last_frame_rgba_equal": meta.get("last_frame_rgba_equal")})
	if sum(clip["raw_frames"] for clip in clips) != 85:
		raise SystemExit("Expected 85 original raw frames in total")
	html_path = ROOT / "gallery.html"
	if not html_path.is_file():
		raise SystemExit("Missing gallery.html; run build_gallery.py first")
	html = html_path.read_text(encoding="utf-8")
	asset_match = re.search(r"const ASSETS=(\{.*?\}),CLIPS=", html, re.S)
	clip_match = re.search(r"CLIPS=(\[.*?\]);let players=", html, re.S)
	if not asset_match or not clip_match:
		raise SystemExit("Could not parse embedded gallery tables")
	assets = json.loads(asset_match.group(1))
	gallery_clips = json.loads(clip_match.group(1))
	if len(assets) != 15:
		raise SystemExit(f"Expected 15 embedded assets, got {len(assets)}")
	for relative, data_url in assets.items():
		match = re.fullmatch(r"data:image/(png|gif);base64,([A-Za-z0-9+/=]+)", data_url)
		if not match or base64.b64decode(match.group(2), validate=True) != (ROOT / relative).read_bytes():
			raise SystemExit(f"Malformed or mismatching embedded asset: {relative}")
	if [clip.get("key") for clip in gallery_clips] != [row["key"] for row in rows]:
		raise SystemExit("Gallery does not contain all five expected attacks")
	edits = json.loads((ROOT / "single-edits.json").read_text(encoding="utf-8"))["edits"]
	if [e["key"] for e in edits] != [row["key"] for row in rows]:
		raise SystemExit("Single edits do not match requests")
	for edit, gallery_clip in zip(edits, gallery_clips):
		indices, durations = edit["source_indices"], edit["durations_ms"]
		folder = ROOT / "single" / edit["key"]
		meta = json.loads((folder / "clip.json").read_text(encoding="utf-8"))
		if meta["source_indices"] != indices or meta["durations_ms"] != durations:
			raise SystemExit("Single metadata differs from edit")
		if gallery_clip["count"] != len(indices) or gallery_clip["timing"] != durations:
			raise SystemExit("Gallery timing/count differs from edit")
		with Image.open(folder / "spritesheet.png") as sheet:
			if sheet.size != (2048, 512) or sheet.mode != "RGBA":
				raise SystemExit("Single sheet canvas mismatch")
			for i, source_index in enumerate(indices):
				path = ROOT / "pixellab" / edit["key"] / "frames" / f"frame-{source_index:02d}.png"
				with Image.open(path) as raw:
					x, y = i % 8 * 256, i // 8 * 256
					if sheet.crop((x, y, x + 256, y + 256)).tobytes() != raw.tobytes():
						raise SystemExit("Single sheet pixels differ from raw")
				if meta["source_frame_sha256"][i] != sha(path.read_bytes()):
					raise SystemExit("Single provenance SHA mismatch")
		with Image.open(folder / "preview.gif") as gif:
			actual_durations = []
			for i in range(gif.n_frames):
				gif.seek(i)
				actual_durations.append(gif.info["duration"])
			if sum(actual_durations) != sum(durations) or actual_durations != meta["gif_actual_durations_ms"]:
				raise SystemExit("Single GIF timing mismatch")
	if "max=\"${c.count-1}\"" not in html or "Игровой 0,4×" not in html or "id=\"toggle\"" not in html or "id=\"replay\"" not in html:
		raise SystemExit("Gallery lacks variable slider or playback/scale controls")
	if "max=\"32\"" in html or re.search(r"\b33\s+кадр", html, re.I):
		raise SystemExit("Stale 33-frame assumptions remain in gallery HTML")
	result = {"complete": True, "expected_variants": 5, "raw_frames": 85,
		"input_byte_identical_to_runtime_red_bastion_still": True, "embedded_assets": 15,
		"single_previews": 5, "single_selected_cells_equal_to_raw": True,
		"clips": clips, "scope": "Artifact integrity; no artistic or game integration acceptance"}
	(ROOT / "package-validation.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
	print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
	main()
