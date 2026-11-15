"""Независимо проверяет анимационные PNG, preview timing и автономную галерею."""
from pathlib import Path
import base64
import hashlib
import json
import re

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[2]
CANVAS = (256, 256)
KINDS = {"idle", "ability", "death"}


def sha(data: bytes) -> str:
	return hashlib.sha256(data).hexdigest()


def canonical_sha(path: Path) -> str:
	return sha(path.read_text(encoding="utf-8-sig").encode("utf-8"))


def bbox(image: Image.Image, threshold: int = 1) -> list[int] | None:
	alpha = image.getchannel("A")
	if threshold != 1:
		alpha = alpha.point(lambda a: 255 if a >= threshold else 0)
	box = alpha.getbbox()
	return list(box) if box else None


def compare(image: Image.Image, initial: Image.Image) -> dict:
	a, b = np.asarray(image), np.asarray(initial)
	alpha_diff = a[:, :, 3] != b[:, :, 3]
	rgba_diff = np.any(a != b, axis=2)
	visible = (a[:, :, 3] > 0) | (b[:, :, 3] > 0)
	return {"alpha_equal": not bool(alpha_diff.any()), "alpha_differing_pixels": int(alpha_diff.sum()),
		"visible_rgba_equal": not bool((rgba_diff & visible).any()),
		"visible_rgba_differing_pixels": int((rgba_diff & visible).sum()),
		"all_rgba_equal": not bool(rgba_diff.any()), "all_rgba_differing_pixels": int(rgba_diff.sum()),
		"transparent_rgb_differing_pixels": int((rgba_diff & ~visible).sum())}


def expected_durations(kind: str) -> list[int]:
	if kind == "idle":
		return [90] * 33
	if kind == "ability":
		return [60] * 32 + [350]
	return [70] * 32 + [1500]


def load_rgba(path: Path) -> Image.Image:
	with Image.open(path) as image:
		image.load()
		if image.format != "PNG" or image.mode != "RGBA":
			raise SystemExit(f"Expected RGBA PNG: {path}")
		return image.copy()


def main() -> None:
	requests_path = ROOT / "requests.json"
	requests = json.loads(requests_path.read_text(encoding="utf-8-sig"))
	if not isinstance(requests, list) or len(requests) != 9 or len({row.get("key") for row in requests}) != 9:
		raise SystemExit("Expected nine unique clip requests")
	if {row.get("kind") for row in requests} != KINDS or {row.get("variant") for row in requests} != {1, 2, 3}:
		raise SystemExit("Request kinds/variants do not form idle/ability/death × 1..3")
	input_manifest_path = ROOT / "model/input-manifest.json"
	input_manifest = json.loads(input_manifest_path.read_text(encoding="utf-8-sig"))
	input_path = ROOT / "model/input-256.png"
	input_raw = input_path.read_bytes()
	if sha(input_raw) != input_manifest.get("input_sha256"):
		raise SystemExit("Prepared input SHA mismatch")
	transform_hash = sha(json.dumps(input_manifest["transform"], sort_keys=True, separators=(",", ":")).encode("utf-8"))
	if transform_hash != input_manifest.get("transform_sha256"):
		raise SystemExit("Prepared input transform SHA mismatch")
	with Image.open(input_path) as im:
		if im.size != CANVAS or im.mode != "RGBA" or bbox(im, 8) != [73, 99, 184, 200]:
			raise SystemExit("Prepared input canvas/ground anchor geometry mismatch")
		initial = im.copy()
	source_copy = ROOT / "model/source-full.png"
	if sha(source_copy.read_bytes()) != input_manifest.get("source_copy_sha256") or source_copy.read_bytes() != (REPO / input_manifest["source"]).read_bytes():
		raise SystemExit("Original source copy SHA/bytes mismatch")
	warrior_path = REPO / "assets/art_presets/approved/character_skins_v1/red_bastion/still.png"
	warrior_runtime = warrior_path
	warrior = load_rgba(warrior_path)
	if warrior.size != CANVAS or (bbox(warrior, 8)[3] - bbox(warrior, 8)[1]) != 152:
		raise SystemExit("Warrior reference must stay 256x256 with 152px visible height")
	pixellab_path = ROOT / "pixellab-validation.json"
	pixellab = json.loads(pixellab_path.read_text(encoding="utf-8-sig"))
	if pixellab.get("expected") != 9 or pixellab.get("completed") != len(pixellab.get("clips", [])) or pixellab.get("completed", 0) > 9:
		raise SystemExit("PixelLab export completion counts are inconsistent")
	clip_meta = {c["key"]: c for c in pixellab.get("clips", [])}
	if not set(clip_meta).issubset({r["key"] for r in requests}):
		raise SystemExit("Exported clip keys are not a subset of requests")
	clips_report = []
	quality_issues = []
	for row in requests:
		key, kind = row["key"], row["kind"]
		if key not in clip_meta:
			continue
		meta = clip_meta[key]
		if meta.get("actual_frames") != 33 or meta.get("input_sha256_verified") != input_manifest["input_sha256"] or meta.get("loop") != row["loop"] or meta.get("canvas") != [256, 256] or meta.get("anchor") != [128, 200]:
			raise SystemExit(f"Clip count/source/loop metadata mismatch: {key}")
		if meta.get("durations_ms") != expected_durations(kind) or sum(meta["durations_ms"]) != meta.get("total_duration_ms"):
			raise SystemExit(f"Unexpected timing policy: {key}")
		frame_records = meta.get("frame_records", [])
		if len(frame_records) != 33:
			raise SystemExit(f"Clip must list 33 raw frame records: {key}")
		frames = []
		computed_edge_frames = []
		for index, record in enumerate(frame_records):
			if record.get("index") != index or record.get("canvas") != [256, 256] or record.get("format") != "PNG" or record.get("mode") != "RGBA":
				raise SystemExit(f"Raw PNG header/ordering mismatch: {key}:{index}")
			path = ROOT / record["file"]
			raw = path.read_bytes()
			if sha(raw) != record.get("sha256"):
				raise SystemExit(f"Raw frame SHA mismatch: {key}:{index}")
			image = load_rgba(path)
			if image.size != CANVAS or list(image.getchannel("A").getextrema()) != record.get("alpha_extrema") or bbox(image) != record.get("alpha_bbox") or bbox(image, 8) != record.get("visible_bbox_alpha_ge_8"):
				raise SystemExit(f"Raw frame alpha metadata mismatch: {key}:{index}")
			box = bbox(image)
			if box is None:
				raise SystemExit(f"Raw frame has empty alpha: {key}:{index}")
			margins = (box[0], box[1], 256 - box[2], 256 - box[3])
			edge_violation = min(margins) < 8
			if edge_violation != record.get("alpha_margin_violation"):
				raise SystemExit(f"Frame edge flag differs from raw alpha bbox: {key}:{index}")
			if edge_violation:
				computed_edge_frames.append(index)
			frames.append(image)
		if meta.get("raw_alpha_edge_frames") != computed_edge_frames:
			raise SystemExit(f"Clip edge frame list differs from raw alpha bboxes: {key}")
		if computed_edge_frames:
			quality_issues.append({"key": key, "reason": "alpha_bbox_within_8px_edge_margin", "frames": computed_edge_frames})
		unique_rgba = len({sha(frame.tobytes()) for frame in frames})
		unique_png = len({record["sha256"] for record in frame_records})
		if meta.get("unique_rgba_frames") != unique_rgba or meta.get("unique_png_frames") != unique_png:
			raise SystemExit(f"Unique frame counts mismatch: {key}")
		first_check, last_check = compare(frames[0], initial), compare(frames[-1], initial)
		if first_check != meta.get("first_frame_consistency") or last_check != meta.get("last_frame_consistency"):
			raise SystemExit(f"First/last alpha/visible RGBA consistency mismatch: {key}")
		if meta.get("first_frame_png_byte_equal_input") != (frame_records[0]["sha256"] == input_manifest["input_sha256"]):
			raise SystemExit(f"First frame byte equality diagnostic mismatch: {key}")
		for field, size in (("spritesheet", [2048, 1280]), ("filmstrip", [1280, 256])):
			file = ROOT / meta[field]["file"]
			if sha(file.read_bytes()) != meta[field]["sha256"]:
				raise SystemExit(f"{field} SHA mismatch: {key}")
			with Image.open(file) as sheet:
				if list(sheet.size) != size or sheet.mode != "RGBA":
					raise SystemExit(f"{field} canvas/mode mismatch: {key}")
				if field == "spritesheet":
					for index, frame in enumerate(frames):
						crop = sheet.crop(((index % 8) * 256, (index // 8) * 256, (index % 8 + 1) * 256, (index // 8 + 1) * 256))
						if crop.tobytes() != frame.tobytes():
							raise SystemExit(f"Sprite sheet pixels differ from raw frame: {key}:{index}")
					if np.any(np.asarray(sheet.getchannel("A"))[4 * 256:, 256:] != 0):
						raise SystemExit(f"Unused final sprite sheet cells are not transparent: {key}")
		gif_file = ROOT / meta["preview_gif"]["file"]
		if sha(gif_file.read_bytes()) != meta["preview_gif"]["sha256"]:
			raise SystemExit(f"Preview GIF SHA mismatch: {key}")
		with Image.open(gif_file) as gif:
			gif_durations = []
			for i in range(gif.n_frames):
				gif.seek(i)
				gif_durations.append(gif.info.get("duration", 0))
		if sum(gif_durations) != meta["total_duration_ms"] or gif_durations != meta["preview_gif"].get("durations_ms") or len(gif_durations) != meta["preview_gif"].get("frames"):
			raise SystemExit(f"GIF encoded durations mismatch: {key}")
		clips_report.append({"key": key, "frames": 33, "unique_rgba_frames": unique_rgba,
			"unique_png_frames": unique_png, "total_duration_ms": meta["total_duration_ms"],
			"first_alpha_equal": first_check["alpha_equal"], "first_visible_rgba_equal": first_check["visible_rgba_equal"],
			"last_alpha_equal": last_check["alpha_equal"], "last_visible_rgba_equal": last_check["visible_rgba_equal"],
			"raw_alpha_edges": len(computed_edge_frames), "raw_alpha_edge_frames": computed_edge_frames,
			"quality_quarantined": bool(computed_edge_frames), "loop": row["loop"]})
	overview_path = ROOT / "overview.png"
	with Image.open(overview_path) as overview:
		if overview.size != (1536, 540) or overview.mode != "RGB":
			raise SystemExit("Static overview dimensions/mode mismatch")
	gallery_data_path = ROOT / "gallery-data.json"
	gallery_data = json.loads(gallery_data_path.read_text(encoding="utf-8-sig"))
	completed_count = len(clip_meta)
	expected_asset_count = 4 + 2 * completed_count
	if gallery_data.get("embedded_asset_count") != expected_asset_count or gallery_data.get("completed_clips") != completed_count or len(gallery_data.get("clips", [])) != 9:
		raise SystemExit("Gallery data asset/clip counts mismatch")
	html_path = ROOT / "gallery.html"
	html = html_path.read_text(encoding="utf-8")
	assets_match = re.search(r"const ASSETS=(\{.*?\}),CLIPS=", html, re.S)
	clips_match = re.search(r"CLIPS=(\[.*?\]);let players", html, re.S)
	if not assets_match or not clips_match:
		raise SystemExit("Could not parse gallery asset/clip data")
	assets = json.loads(assets_match.group(1))
	gallery_clips = json.loads(clips_match.group(1))
	if len(assets) != expected_asset_count or len(gallery_clips) != 9 or set(assets) != set(gallery_data["assets"]):
		raise SystemExit("Gallery embedded asset/clip count mismatch")
	for name, url in assets.items():
		match = re.fullmatch(r"data:image/(png|gif);base64,([A-Za-z0-9+/=]+)", url)
		asset_path = warrior_runtime if name == "runtime/red_bastion/still.png" else ROOT / name
		if not match or base64.b64decode(match.group(2), validate=True) != asset_path.read_bytes():
			raise SystemExit(f"Embedded gallery asset differs from packaged bytes: {name}")
	if "Воин 11" not in html or "видимая высота 152px" not in html or "видимая высота 101px" not in html:
		raise SystemExit("Native-size static Warrior/model comparison missing")
	if "Способность" in html or "Падение" in html or "ability:'Атака'" not in html or "death:'Смерть'" not in html:
		raise SystemExit("Russian animation kind labels differ from the reviewed wording")
	if "return_to_first" not in html and "hold" not in html:
		# Player behavior is verified via the actual terminal hold branch below.
		if "else{p.elapsed=0;break}" not in html:
			raise SystemExit("Non-loop clips do not hold the last frame")
	export_complete = len(clip_meta) == 9 and pixellab.get("complete") is True
	quality_pass = not quality_issues
	result = {"complete": export_complete, "export_complete": export_complete,
		"structural_pass": True, "byte_integrity_pass": True, "quality_pass": quality_pass,
		"status": "PASS" if export_complete and quality_pass else ("QUALITY_FAIL" if export_complete else "PARTIAL"),
		"request_manifest_sha256": canonical_sha(requests_path),
		"input_sha256": input_manifest["input_sha256"], "transform_sha256": input_manifest["transform_sha256"],
		"warrior_reference_sha256": sha(warrior_path.read_bytes()), "frame_canvas": [256, 256],
		"expected_frames_each": 33, "durations_ms_by_kind": {k: expected_durations(k) for k in sorted(KINDS)},
		"frame_edge_policy": "Every alpha-nonzero bbox must have >=8px margin on all four canvas edges",
		"clips": clips_report, "quality_issues": quality_issues,
		"overview_size": [1536, 540], "embedded_gallery_assets": len(assets),
		"runtime_integration": False,
		"scope": "PNG provenance/frame counts/alpha margins/timings and offline gallery integrity only; artistic and runtime acceptance remain separate."}
	(ROOT / "validation.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
	print(json.dumps({"export_complete": export_complete, "structural_pass": True, "byte_integrity_pass": True,
		"quality_pass": quality_pass, "clips_exported": len(clips_report), "frames": sum(x["frames"] for x in clips_report),
		"embedded_gallery_assets": len(assets), "quality_issues": quality_issues,
		"model_input_sha256": input_manifest["input_sha256"]}, ensure_ascii=False))


if __name__ == "__main__":
	main()
