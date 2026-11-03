"""Экспортирует ответы без перекодирования исходных PNG PixelLab."""
from pathlib import Path
import base64
import hashlib
import io
import json

from PIL import Image
import numpy as np

ROOT = Path(__file__).resolve().parent
JOBS = Path("C:/Users/Aston/.codex/generated_images/archer14-04-animation-20261103")


def sha(data: bytes) -> str:
	return hashlib.sha256(data).hexdigest()


def load_json(path: Path) -> dict:
	return json.loads(path.read_text(encoding="utf-8-sig"))


def main() -> None:
	rows = load_json(ROOT / "requests.json")
	results = []
	for row in rows:
		folder = JOBS / "pixellab" / row["key"]
		job_file = folder / "job-latest.json"
		if not job_file.exists():
			continue
		job = load_json(job_file)
		if job.get("status") != "completed":
			continue
		admission = load_json(folder / "admission.json")
		if job.get("id") != admission.get("background_job_id"):
			raise SystemExit(f"Job/admission ID mismatch for {row['key']}")
		response = job["last_response"]
		images = response.get("images", [])
		if len(images) != row["expected_frames"]:
			raise SystemExit(f"Expected {row['expected_frames']} raw frames for {row['key']}, got {len(images)}")
		out = ROOT / "pixellab" / row["key"]
		frames_dir = out / "frames"
		frames_dir.mkdir(parents=True, exist_ok=True)
		frames, raw_bytes, frame_hashes, solid_boxes, raw_boxes = [], [], [], [], []
		for index, item in enumerate(images):
			encoded = item["base64"]
			if encoded.startswith("data:"):
				encoded = encoded.split(",", 1)[1]
			raw = base64.b64decode(encoded, validate=True)
			image = Image.open(io.BytesIO(raw)).convert("RGBA")
			if image.size != (256, 256):
				raise SystemExit(f"Unexpected frame size {image.size} in {row['key']}:{index}")
			frame_path = frames_dir / f"frame-{index:02d}.png"
			if frame_path.exists() and frame_path.read_bytes() != raw:
				raise SystemExit(f"Existing raw frame differs: {frame_path}")
			frame_path.write_bytes(raw)
			frames.append(image)
			raw_bytes.append(raw)
			frame_hashes.append(sha(raw))
			solid_boxes.append(image.getchannel("A").point(lambda alpha: 255 if alpha >= 128 else 0).getbbox())
			raw_boxes.append(image.getchannel("A").getbbox())
		original = Image.open(ROOT / row["input"]).convert("RGBA")
		original_array = np.asarray(original)
		first_array = np.asarray(frames[0])
		first_rgba_diff_mask = np.any(first_array != original_array, axis=2)
		first_alpha_diff_mask = first_array[:, :, 3] != original_array[:, :, 3]
		first_visible_mask = (first_array[:, :, 3] > 0) | (original_array[:, :, 3] > 0)
		first_rgba_differing_pixels = int(np.count_nonzero(first_rgba_diff_mask))
		first_alpha_differing_pixels = int(np.count_nonzero(first_alpha_diff_mask))
		first_visible_differing_pixels = int(np.count_nonzero(first_rgba_diff_mask & first_visible_mask))
		first_transparent_rgb_differing_pixels = first_rgba_differing_pixels - first_visible_differing_pixels
		first_alpha_equal = first_alpha_differing_pixels == 0
		durations = [90] * len(frames) if row["kind"] == "idle" else [70] * len(frames)
		if row["kind"] == "death":
			durations[-1] = 1500
		elif row["kind"] == "ability":
			durations[-1] = 700
		sheet = Image.new("RGBA", (256 * 8, 256 * ((len(frames) + 7) // 8)))
		for index, image in enumerate(frames):
			sheet.paste(image, ((index % 8) * 256, (index // 8) * 256))
		sheet.save(out / "spritesheet.png")
		preview_frames = []
		for image in frames:
			background = Image.new("RGBA", (256, 256), "#182131")
			background.alpha_composite(image)
			preview_frames.append(background.convert("RGB").resize((512, 512), Image.Resampling.NEAREST))
		preview_frames[0].save(out / "preview.gif", save_all=True, append_images=preview_frames[1:], duration=durations, loop=0, disposal=2)
		gif_durations = []
		with Image.open(out / "preview.gif") as gif:
			for index in range(gif.n_frames):
				gif.seek(index)
				gif_durations.append(gif.info.get("duration", 0))
		if sum(gif_durations) != sum(durations):
			raise SystemExit(f"GIF timing changed for {row['key']}")
		filmstrip = Image.new("RGB", (256 * 5, 256), "#182131")
		for column, index in enumerate([0, len(frames) // 4, len(frames) // 2, 3 * len(frames) // 4, len(frames) - 1]):
			filmstrip.paste(frames[index], (column * 256, 0), frames[index])
		filmstrip.save(out / "filmstrip.png")
		first_png_byte_equal = raw_bytes[0] == (ROOT / row["input"]).read_bytes()
		result = {
			**row, "provider": "PixelLab PixMiniMax", "job_id": job["id"],
			"actual_frames": len(frames), "usage": response.get("billing_usage") or response.get("usage") or job.get("usage"),
			"canvas": [256, 256], "anchor": [128, 200], "durations_ms": durations,
			"timing_origin": "Preview timing authored in export script; provider supplies poses only",
			"gif_replay": True, "death_replay_note": "Gallery holds death and ability; GIF repeats for comparison",
			"first_frame_rgba_equal": first_rgba_differing_pixels == 0,
			"first_frame_rgba_differing_pixels": first_rgba_differing_pixels,
			"first_frame_alpha_equal": first_alpha_equal,
			"first_frame_alpha_differing_pixels": first_alpha_differing_pixels,
			"first_frame_visible_differing_pixels": first_visible_differing_pixels,
			"first_frame_transparent_rgb_differing_pixels": first_transparent_rgb_differing_pixels,
			"first_frame_png_byte_equal": first_png_byte_equal,
			"last_frame_rgba_equal": frames[-1].tobytes() == original.tobytes(),
			"edge_frames": [index for index, box in enumerate(solid_boxes) if box and (box[0] == 0 or box[1] == 0 or box[2] == 256 or box[3] == 256)],
			"rgba_unique": len({sha(image.tobytes()) for image in frames}),
			"frame_sha256": frame_hashes, "bboxes": solid_boxes, "raw_alpha_bboxes": raw_boxes,
			"gif_actual_durations_ms": gif_durations,
			"margin_violation_frames": [index for index, box in enumerate(raw_boxes) if box and (box[0] < 8 or box[1] < 8 or box[2] > 248 or box[3] > 248)],
			"strong_margin_violation_frames": [index for index, box in enumerate(solid_boxes) if box and (box[0] < 8 or box[1] < 8 or box[2] > 248 or box[3] > 248)],
			"integration": False,
		}
		(out / "clip.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
		results.append(result)
	transparent_rgb_only = [result["key"] for result in results
		if result["first_frame_alpha_equal"] and result["first_frame_visible_differing_pixels"] == 0
		and result["first_frame_rgba_differing_pixels"] > 0]
	(ROOT / "pixellab-validation.json").write_text(json.dumps({
		"expected": len(rows), "completed": len(results), "complete": len(results) == len(rows),
		"first_frame_policy": "Alpha must match exactly; visible RGBA must match. RGB-only differences where both alpha values are zero are diagnostic only.",
		"first_frame_counts": {
			"alpha_differing_pixels": sum(result["first_frame_alpha_differing_pixels"] for result in results),
			"visible_differing_pixels": sum(result["first_frame_visible_differing_pixels"] for result in results),
			"rgba_differing_pixels": sum(result["first_frame_rgba_differing_pixels"] for result in results),
			"transparent_rgb_differing_pixels": sum(result["first_frame_transparent_rgb_differing_pixels"] for result in results),
			"transparent_rgb_only_clips": transparent_rgb_only,
		},
		"complete_meaning": "Count only; not artistic acceptance or runtime validation", "clips": results,
	}, ensure_ascii=False, indent=2), encoding="utf-8")
	print(json.dumps({
		"expected": len(rows), "exported": len(results),
		"edge_clips": [result["key"] for result in results if result["edge_frames"]],
		"first_frame_png_byte_mismatches": [result["key"] for result in results if not result["first_frame_png_byte_equal"]],
		"first_frame_transparent_rgb_only": transparent_rgb_only,
		"usage": [result["usage"] for result in results],
	}, ensure_ascii=False))


if __name__ == "__main__":
	main()
