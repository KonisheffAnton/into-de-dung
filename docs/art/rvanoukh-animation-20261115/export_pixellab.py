"""Экспортирует завершённые PixelLab кадры без изменения байтов PNG."""
from pathlib import Path
import base64
import hashlib
import io
import json

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent
JOBS = Path("D:/Codex/home/generated_images/rvanoukh-animation-20261115/pixellab")
CANVAS = (256, 256)


def sha(data: bytes) -> str:
	return hashlib.sha256(data).hexdigest()


def read_json(path: Path) -> dict | list:
	return json.loads(path.read_text(encoding="utf-8-sig"))


def decode_png(container: dict) -> bytes:
	encoded = container.get("base64")
	if not isinstance(encoded, str):
		raise SystemExit("PixelLab frame is missing base64 PNG data")
	if encoded.startswith("data:"):
		encoded = encoded.split(",", 1)[1]
	return base64.b64decode(encoded, validate=True)


def alpha_bbox(image: Image.Image, threshold: int = 1) -> list[int] | None:
	mask = image.getchannel("A")
	if threshold != 1:
		mask = mask.point(lambda value: 255 if value >= threshold else 0)
	box = mask.getbbox()
	return list(box) if box else None


def compare_to_input(frame: Image.Image, initial: Image.Image) -> dict:
	a, b = np.asarray(frame), np.asarray(initial)
	alpha_diff = a[:, :, 3] != b[:, :, 3]
	visible = (a[:, :, 3] > 0) | (b[:, :, 3] > 0)
	rgba_diff = np.any(a != b, axis=2)
	visible_diff = rgba_diff & visible
	return {"alpha_equal": not bool(alpha_diff.any()), "alpha_differing_pixels": int(np.count_nonzero(alpha_diff)),
		"visible_rgba_equal": not bool(visible_diff.any()), "visible_rgba_differing_pixels": int(np.count_nonzero(visible_diff)),
		"all_rgba_equal": not bool(rgba_diff.any()), "all_rgba_differing_pixels": int(np.count_nonzero(rgba_diff)),
		"transparent_rgb_differing_pixels": int(np.count_nonzero(rgba_diff & ~visible))}


def durations_for(row: dict, count: int) -> list[int]:
	if row["kind"] == "idle":
		return [90] * count
	if row["kind"] == "ability":
		return [60] * (count - 1) + [350]
	if row["kind"] == "death":
		return [70] * (count - 1) + [1500]
	raise SystemExit(f"Unknown animation kind: {row['kind']}")


def build_sheet(frames: list[Image.Image]) -> Image.Image:
	columns, rows = 8, (len(frames) + 7) // 8
	sheet = Image.new("RGBA", (columns * 256, rows * 256), (0, 0, 0, 0))
	for index, image in enumerate(frames):
		sheet.paste(image, ((index % columns) * 256, (index // columns) * 256))
	return sheet


def main() -> None:
	rows = read_json(ROOT / "requests.json")
	if not isinstance(rows, list) or len(rows) != 9:
		raise SystemExit("requests.json must contain nine clips")
	model_input = ROOT / "model/input-256.png"
	input_manifest = read_json(ROOT / "model/input-manifest.json")
	input_bytes = model_input.read_bytes()
	input_sha = sha(input_bytes)
	if input_sha != input_manifest.get("input_sha256"):
		raise SystemExit("Prepared model input SHA mismatch")
	with Image.open(model_input) as image:
		if image.size != CANVAS or image.mode != "RGBA":
			raise SystemExit("Animation input must be 256x256 RGBA")
		initial = image.copy()
	results = []
	for row in rows:
		if row.get("input") != "model/input-256.png" or row.get("input_sha256") != input_sha or row.get("endpoint") != "animate-pixminimax" or row.get("expected_frames") != 33 or row.get("frame_count") != 32:
			raise SystemExit(f"Request manifest/source mismatch: {row.get('key')}")
		folder = JOBS / row["key"]
		job_path, admission_path, request_path = folder / "job-latest.json", folder / "admission.json", folder / "request.json"
		if not job_path.is_file() or not admission_path.is_file() or not request_path.is_file():
			continue
		job, admission, actual = read_json(job_path), read_json(admission_path), read_json(request_path)
		if job.get("status") != "completed":
			continue
		job_id = job.get("id")
		if not job_id or job_id != admission.get("background_job_id"):
			raise SystemExit(f"Job/admission ID mismatch: {row['key']}")
		if actual.get("description") != row.get("prompt") or actual.get("seed") != row.get("seed") or actual.get("frame_count") != row.get("frame_count") or actual.get("no_background") is not True or actual.get("enhance_prompt") is not False:
			raise SystemExit(f"Submitted request fields differ from manifest: {row['key']}")
		for caption_key, caption_value in row.get("captions", {}).items():
			if actual.get(caption_key) != caption_value:
				raise SystemExit(f"Submitted caption {caption_key} differs from manifest: {row['key']}")
		if decode_png(actual.get("first_frame", {})) != input_bytes:
			raise SystemExit(f"Submitted first frame differs from prepared input: {row['key']}")
		should_return = bool(row.get("return_to_first"))
		if should_return:
			if decode_png(actual.get("last_frame", {})) != input_bytes:
				raise SystemExit(f"Submitted last frame differs from prepared input: {row['key']}")
		elif "last_frame" in actual:
			raise SystemExit(f"Unexpected last_frame in request: {row['key']}")
		response = job.get("last_response") or {}
		items = response.get("images", [])
		if len(items) != row["expected_frames"]:
			raise SystemExit(f"Expected 33 raw frames for {row['key']}, got {len(items)}")
		out = ROOT / "pixellab" / row["key"]
		frames_dir = out / "frames"
		frames_dir.mkdir(parents=True, exist_ok=True)
		frames: list[Image.Image] = []
		frame_records = []
		for index, item in enumerate(items):
			raw = decode_png(item)
			try:
				with Image.open(io.BytesIO(raw)) as decoded:
					decoded.load()
					if decoded.format != "PNG" or decoded.size != CANVAS or decoded.mode != "RGBA":
						raise SystemExit(f"Frame must be 256x256 RGBA PNG: {row['key']}:{index}")
					image = decoded.copy()
			except OSError as error:
				raise SystemExit(f"Invalid PNG response for {row['key']}:{index}") from error
			frame_path = frames_dir / f"frame-{index:02d}.png"
			if frame_path.exists() and frame_path.read_bytes() != raw:
				raise SystemExit(f"Existing raw frame bytes differ: {frame_path}")
			frame_path.write_bytes(raw)
			frames.append(image)
			alpha_box = alpha_bbox(image)
			visible_box = alpha_bbox(image, 8)
			edge_alpha = bool(alpha_box and (alpha_box[0] < 8 or alpha_box[1] < 8 or alpha_box[2] > 248 or alpha_box[3] > 248))
			frame_records.append({"index": index, "file": frame_path.relative_to(ROOT).as_posix(),
				"sha256": sha(raw), "canvas": list(CANVAS), "format": "PNG", "mode": "RGBA",
				"alpha_extrema": list(image.getchannel("A").getextrema()), "alpha_bbox": alpha_box,
				"visible_bbox_alpha_ge_8": visible_box, "alpha_margin_violation": edge_alpha})
		first_cmp, last_cmp = compare_to_input(frames[0], initial), compare_to_input(frames[-1], initial)
		frame_durations = durations_for(row, len(frames))
		out.mkdir(parents=True, exist_ok=True)
		sheet = build_sheet(frames)
		sheet_path = out / "spritesheet.png"
		if sheet_path.exists():
			with Image.open(sheet_path) as old:
				if old.tobytes() != sheet.tobytes():
					raise SystemExit(f"Existing sheet pixels differ: {sheet_path}")
		sheet.save(sheet_path)
		preview_frames = []
		for image in frames:
			background = Image.new("RGBA", CANVAS, "#182131")
			background.alpha_composite(image)
			preview_frames.append(background.convert("RGB").resize((512, 512), Image.Resampling.NEAREST))
		gif_path = out / "preview.gif"
		preview_frames[0].save(gif_path, save_all=True, append_images=preview_frames[1:], duration=frame_durations, loop=0, disposal=2)
		gif_durations = []
		with Image.open(gif_path) as gif:
			for frame_index in range(gif.n_frames):
				gif.seek(frame_index)
				gif_durations.append(gif.info.get("duration", 0))
		if sum(gif_durations) != sum(frame_durations):
			raise SystemExit(f"GIF total duration differs: {row['key']}")
		filmstrip = Image.new("RGBA", (256 * 5, 256), (24, 33, 49, 255))
		for column, frame_index in enumerate((0, 8, 16, 24, 32)):
			filmstrip.alpha_composite(frames[frame_index], (column * 256, 0))
		filmstrip.save(out / "filmstrip.png")
		clip = {**row, "provider": "PixelLab animate-pixminimax", "job_id": job_id,
			"input_sha256_verified": input_sha, "request_sha256": sha(json.dumps(actual, sort_keys=True, separators=(",", ":")).encode()),
			"actual_frames": len(frames), "canvas": list(CANVAS), "anchor": [128, 200], "usage": response.get("billing_usage") or response.get("usage") or job.get("usage"),
			"durations_ms": frame_durations, "total_duration_ms": sum(frame_durations),
			"timing_origin": "Preview timing authored by exporter; provider returns poses only",
			"first_frame_consistency": first_cmp, "last_frame_consistency": last_cmp,
			"first_frame_png_byte_equal_input": frame_records[0]["sha256"] == input_sha,
			"return_to_first_requested": should_return, "last_frame_returns_to_input_rgba": last_cmp["all_rgba_equal"],
			"raw_alpha_edge_frames": [f["index"] for f in frame_records if f["alpha_margin_violation"]],
			"unique_rgba_frames": len({sha(frame.tobytes()) for frame in frames}),
			"unique_png_frames": len({f["sha256"] for f in frame_records}), "frame_records": frame_records,
			"spritesheet": {"file": sheet_path.relative_to(ROOT).as_posix(), "sha256": sha(sheet_path.read_bytes()), "size": list(sheet.size)},
			"preview_gif": {"file": gif_path.relative_to(ROOT).as_posix(), "sha256": sha(gif_path.read_bytes()),
				"frames": len(gif_durations), "durations_ms": gif_durations, "total_duration_ms": sum(gif_durations)},
			"filmstrip": {"file": (out / "filmstrip.png").relative_to(ROOT).as_posix(), "sha256": sha((out / "filmstrip.png").read_bytes())},
			"integration": False}
		(out / "clip.json").write_text(json.dumps(clip, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
		results.append(clip)
	validation = {"expected": 9, "completed": len(results), "complete": len(results) == 9,
		"input_sha256": input_sha, "model_transform_sha256": input_manifest["transform_sha256"],
		"first_last_consistency_policy": "Record exact alpha and visible RGBA equality; drift is diagnostic and does not rewrite frames",
		"raw_frames_unchanged": True, "integration": False, "clips": results}
	(ROOT / "pixellab-validation.json").write_text(json.dumps(validation, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
	print(json.dumps({"expected": 9, "exported": len(results), "complete": len(results) == 9,
		"clips": [{"key": c["key"], "frames": c["actual_frames"], "edges": c["raw_alpha_edge_frames"],
			"first_alpha_drift": c["first_frame_consistency"]["alpha_differing_pixels"],
			"first_visible_rgba_drift": c["first_frame_consistency"]["visible_rgba_differing_pixels"],
			"last_rgba_equal": c["last_frame_consistency"]["all_rgba_equal"]} for c in results]}, ensure_ascii=False))


if __name__ == "__main__":
	main()
