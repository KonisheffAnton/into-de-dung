"""Проверяет целостность пяти исходных атак и автономной HTML-галереи."""
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
	issues: list[str] = []
	if len(rows) != 5 or [row.get("key") for row in rows] != [f"attack-{i}" for i in range(1, 6)]:
		raise SystemExit("Expected exactly attack-1 through attack-5")
	input_path = ROOT / "model/input-256.png"
	if not input_path.is_file() or not RUNTIME_INPUT.is_file():
		raise SystemExit("Missing model input or runtime red_bastion still.png")
	input_image = Image.open(input_path).convert("RGBA")
	runtime_image = Image.open(RUNTIME_INPUT).convert("RGBA")
	input_bytes_match_runtime = input_path.read_bytes() == RUNTIME_INPUT.read_bytes()
	input_matches_runtime = input_image.size == runtime_image.size and input_image.tobytes() == runtime_image.tobytes()
	if not input_matches_runtime or not input_bytes_match_runtime:
		raise SystemExit("model/input-256.png does not pixel-match runtime red_bastion/still.png")
	clip_results = []
	all_raw_count = 0
	for row in rows:
		folder = ROOT / "pixellab" / row["key"]
		meta_path = folder / "clip.json"
		if not meta_path.is_file():
			raise SystemExit(f"Missing clip manifest: {row['key']}")
		meta = json.loads(meta_path.read_text(encoding="utf-8-sig"))
		frames = []
		for index in range(33):
			path = folder / "frames" / f"frame-{index:02d}.png"
			if not path.is_file():
				raise SystemExit(f"Missing raw frame: {path}")
			raw = path.read_bytes()
			with Image.open(path) as image:
				if image.size != (256, 256) or image.mode != "RGBA":
					raise SystemExit(f"Raw frame must be 256x256 RGBA: {path}")
				alpha = np.asarray(image.getchannel("A"))
				if not np.any(alpha == 0) or not np.any(alpha > 0):
					raise SystemExit(f"Frame must be nonempty with transparency: {path}")
				frames.append(image.copy())
			if meta.get("frame_sha256", [])[index] != sha(raw):
				raise SystemExit(f"Raw frame hash mismatch: {path}")
		all_raw_count += 1
		if meta.get("actual_frames") != 33 or meta.get("kind") != "attack" or meta.get("key") != row["key"]:
			raise SystemExit(f"Clip contract mismatch: {row['key']}")
		if meta.get("durations_ms") != [50] * 32 + [700]:
			raise SystemExit(f"Preview timing mismatch: {row['key']}")
		sheet_path = folder / "spritesheet.png"
		with Image.open(sheet_path) as sheet:
			if sheet.size != (2048, 1280) or sheet.mode != "RGBA":
				raise SystemExit(f"Expected 8x5 RGBA sheet: {sheet_path}")
			for index, frame in enumerate(frames):
				cell = sheet.crop(((index % 8) * 256, (index // 8) * 256, (index % 8 + 1) * 256, (index // 8 + 1) * 256))
				if cell.tobytes() != frame.tobytes():
					raise SystemExit(f"Sprite sheet cell differs from raw frame {index}: {row['key']}")
			for index in range(33, 40):
				cell = sheet.crop(((index % 8) * 256, (index // 8) * 256, (index % 8 + 1) * 256, (index // 8 + 1) * 256))
				if cell.getbbox():
					raise SystemExit(f"Unexpected non-empty padding cell {index}: {row['key']}")
		with Image.open(folder / "preview.gif") as gif:
			if not 1 <= gif.n_frames <= 33:
				raise SystemExit(f"GIF frame count mismatch: {row['key']}")
			gif_durations = []
			for index in range(gif.n_frames):
				gif.seek(index)
				gif_durations.append(gif.info.get("duration", 0))
				if gif.size != (512, 512):
					raise SystemExit(f"Unexpected GIF canvas: {row['key']}")
		# GIF объединяет одинаковые соседние позы; длительность всей цепочки сохраняется.
		if sum(gif_durations) != 2300 or any(d <= 0 for d in gif_durations) or gif_durations != meta["gif_actual_durations_ms"]:
			raise SystemExit(f"GIF timing mismatch: {row['key']}: {gif_durations}")
		first = np.asarray(frames[0])
		initial = np.asarray(input_image)
		pixel_diff = np.any(first != initial, axis=2)
		alpha_diff = first[:, :, 3] != initial[:, :, 3]
		visible = (first[:, :, 3] > 0) | (initial[:, :, 3] > 0)
		alpha_count = int(np.count_nonzero(alpha_diff))
		visible_count = int(np.count_nonzero(pixel_diff & visible))
		if alpha_count or visible_count:
			raise SystemExit(f"Original first-frame alpha/visible RGBA mismatch: {row['key']} ({alpha_count}, {visible_count})")
		alpha_union = np.asarray(frames[0].getchannel("A"))
		bbox = frames[0].getchannel("A").getbbox()
		transparent = int(np.count_nonzero(alpha_union == 0))
		if transparent == 0 or bbox is None:
			raise SystemExit(f"Expected a non-empty transparent sprite: {row['key']}")
		if meta.get("edge_frames"):
			issues.append(f"{row['key']}: edge contact frames {meta['edge_frames']}")
		if meta.get("margin_violation_frames"):
			issues.append(f"{row['key']}: under-8px margins {meta['margin_violation_frames']}")
		if not meta.get("last_frame_rgba_equal"):
			issues.append(f"{row['key']}: final frame differs from starting pose")
		clip_results.append({"key": row["key"], "raw_frames": len(frames), "sheet_cells_equal": True,
			"gif_durations_ms": gif_durations, "first_alpha_visible_match": True,
			"edge_frames": meta.get("edge_frames", []), "margin_violation_frames": meta.get("margin_violation_frames", []),
			"last_frame_rgba_equal": meta.get("last_frame_rgba_equal")})
	if all_raw_count != 5:
		raise SystemExit(f"Expected 165 raw frames, checked {all_raw_count * 33}")
	html_path = ROOT / "gallery.html"
	if not html_path.is_file():
		raise SystemExit("Missing gallery.html; run build_gallery.py first")
	html = html_path.read_text(encoding="utf-8")
	asset_match = re.search(r"const ASSETS=(\{.*?\}),CLIPS=", html, re.S)
	if not asset_match:
		raise SystemExit("Could not parse embedded gallery asset table")
	assets = json.loads(asset_match.group(1))
	if len(assets) != 10:
		raise SystemExit(f"Expected 10 embedded assets, got {len(assets)}")
	for relative, data_url in assets.items():
		match = re.fullmatch(r"data:image/(png|gif);base64,([A-Za-z0-9+/=]+)", data_url)
		if not match:
			raise SystemExit(f"Malformed embedded asset {relative}")
		decoded = base64.b64decode(match.group(2), validate=True)
		if decoded != (ROOT / relative).read_bytes():
			raise SystemExit(f"Embedded asset mismatch: {relative}")
	clip_match = re.search(r"CLIPS=(\[.*?\]);let players=", html, re.S)
	if not clip_match:
		raise SystemExit("Missing embedded clip manifest")
	gallery_clips = json.loads(clip_match.group(1))
	if [c["key"] for c in gallery_clips] != [row["key"] for row in rows]:
		raise SystemExit("Gallery does not contain exactly the five expected clips")
	for c, result in zip(gallery_clips, clip_results):
		if c["last_match"] != result["last_frame_rgba_equal"]:
			raise SystemExit("Gallery end-pose diagnostic mismatch")
	if "id=\"toggle\"" not in html or "id=\"replay\"" not in html or "type=\"range\"" not in html:
		raise SystemExit("Gallery is missing cards or playback/scrub controls")
	if "Игровой 0,4×" not in html or "Шахматный фон" not in html:
		raise SystemExit("Gallery lacks game-size or backdrop controls")
	result = {"complete": True, "expected_variants": 5, "raw_frames": 165,
		"input_matches_runtime_red_bastion_still": True, "input_bytes_match_runtime": input_bytes_match_runtime, "embedded_assets": len(assets),
		"diagnostics": issues, "clips": clip_results,
		"scope": "Artifact integrity only; no artistic or game integration acceptance"}
	(ROOT / "package-validation.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
	print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
	main()
