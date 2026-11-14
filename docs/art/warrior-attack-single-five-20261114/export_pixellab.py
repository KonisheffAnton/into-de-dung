"""Экспортирует завершённые PixelLab PNG без изменения исходных байтов."""
from pathlib import Path
import base64
import hashlib
import io
import json

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent
JOBS = Path("C:/Users/Aston/.codex/generated_images/warrior-attack-single-five-20261114")


def load_json(path: Path) -> dict | list:
	return json.loads(path.read_text(encoding="utf-8-sig"))


def sha(data: bytes) -> str:
	return hashlib.sha256(data).hexdigest()


def main() -> None:
	rows = load_json(ROOT / "requests.json")
	if not isinstance(rows, list) or len(rows) != 5:
		raise SystemExit("requests.json must contain exactly five attacks")
	results = []
	for expected, row in enumerate(rows, start=1):
		if row.get("key") != f"attack-{expected}" or row.get("kind") != "attack" or row.get("frame_count") != 16 or row.get("expected_frames") != 17:
			raise SystemExit(f"Invalid 16-frame attack contract: {row.get('key')}")
		folder = JOBS / "pixellab" / row["key"]
		job_file = folder / "job-latest.json"
		if not job_file.is_file():
			continue
		job = load_json(job_file)
		if job.get("status") != "completed":
			continue
		admission = load_json(folder / "admission.json")
		if job.get("id") != admission.get("background_job_id"):
			raise SystemExit(f"Job/admission ID mismatch for {row['key']}")
		response = job.get("last_response", {})
		items = response.get("images", [])
		if len(items) != 17:
			raise SystemExit(f"Expected 17 raw frames for {row['key']}, got {len(items)}")
		out = ROOT / "pixellab" / row["key"]
		frames_dir = out / "frames"
		frames_dir.mkdir(parents=True, exist_ok=True)
		frames: list[Image.Image] = []
		raw_frames: list[bytes] = []
		for index, item in enumerate(items):
			encoded = item["base64"]
			if encoded.startswith("data:"):
				encoded = encoded.split(",", 1)[1]
			raw = base64.b64decode(encoded, validate=True)
			image = Image.open(io.BytesIO(raw)).convert("RGBA")
			if image.size != (256, 256):
				raise SystemExit(f"Unexpected frame size in {row['key']}:{index}: {image.size}")
			path = frames_dir / f"frame-{index:02d}.png"
			if path.exists() and path.read_bytes() != raw:
				raise SystemExit(f"Existing raw frame differs: {path}")
			path.write_bytes(raw)
			frames.append(image)
			raw_frames.append(raw)
		input_path = ROOT / row["input"]
		original = Image.open(input_path).convert("RGBA")
		if original.size != (256, 256):
			raise SystemExit(f"Input must be 256x256: {input_path}")
		first = np.asarray(frames[0])
		initial = np.asarray(original)
		diff = np.any(first != initial, axis=2)
		alpha_diff = first[:, :, 3] != initial[:, :, 3]
		visible = (first[:, :, 3] > 0) | (initial[:, :, 3] > 0)
		alpha_count = int(np.count_nonzero(alpha_diff))
		visible_count = int(np.count_nonzero(diff & visible))
		durations = [40] * 16 + [700]
		sheet = Image.new("RGBA", (2048, 768))
		for index, image in enumerate(frames):
			sheet.paste(image, ((index % 8) * 256, (index // 8) * 256))
		sheet.save(out / "spritesheet.png")
		gif_frames = []
		for image in frames:
			background = Image.new("RGBA", (256, 256), "#182131")
			background.alpha_composite(image)
			gif_frames.append(background.convert("RGB").resize((512, 512), Image.Resampling.NEAREST))
		gif_frames[0].save(out / "preview.gif", save_all=True, append_images=gif_frames[1:], duration=durations, loop=0, disposal=2)
		filmstrip = Image.new("RGB", (1280, 256), "#182131")
		for column, index in enumerate([0, 4, 8, 12, 16]):
			filmstrip.paste(frames[index], (column * 256, 0), frames[index])
		filmstrip.save(out / "filmstrip.png")
		gif_durations = []
		with Image.open(out / "preview.gif") as gif:
			for index in range(gif.n_frames):
				gif.seek(index)
				gif_durations.append(gif.info.get("duration", 0))
		boxes = [frame.getchannel("A").getbbox() for frame in frames]
		solid_boxes = [frame.getchannel("A").point(lambda alpha: 255 if alpha >= 128 else 0).getbbox() for frame in frames]
		result = {
			**row, "provider": "PixelLab PixMiniMax", "job_id": job["id"],
			"usage": response.get("billing_usage") or response.get("usage") or job.get("usage"),
			"actual_frames": 17, "canvas": [256, 256], "durations_ms": durations,
			"timing_origin": "Preview timing authored locally; provider supplies poses only",
			"gif_actual_durations_ms": gif_durations, "gif_total_duration_ms": sum(gif_durations),
			"first_frame_alpha_equal": alpha_count == 0, "first_frame_alpha_differing_pixels": alpha_count,
			"first_frame_visible_differing_pixels": visible_count,
			"first_frame_rgba_differing_pixels": int(np.count_nonzero(diff)),
			"first_frame_transparent_rgb_differing_pixels": int(np.count_nonzero(diff)) - visible_count,
			"first_frame_png_byte_equal": raw_frames[0] == input_path.read_bytes(),
			"last_frame_rgba_equal": frames[-1].tobytes() == original.tobytes(),
			"edge_frames": [i for i, box in enumerate(solid_boxes) if box and (box[0] == 0 or box[1] == 0 or box[2] == 256 or box[3] == 256)],
			"margin_violation_frames": [i for i, box in enumerate(boxes) if box and (box[0] < 8 or box[1] < 8 or box[2] > 248 or box[3] > 248)],
			"frame_sha256": [sha(data) for data in raw_frames], "bboxes": solid_boxes,
			"raw_alpha_bboxes": boxes, "integration": False,
		}
		(out / "clip.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
		results.append(result)
	complete = len(results) == 5
	(ROOT / "pixellab-validation.json").write_text(json.dumps({
		"expected": 5, "completed": len(results), "complete": complete,
		"first_frame_policy": "Alpha and visible RGBA must match exactly; transparent RGB-only differences are diagnostic.",
		"complete_meaning": "Count only; not artistic acceptance or runtime validation", "clips": results,
	}, ensure_ascii=False, indent=2), encoding="utf-8")
	print(json.dumps({"expected": 5, "exported": len(results), "complete": complete,
		"edge_clips": [r["key"] for r in results if r["edge_frames"]],
		"first_frame_alpha_mismatch": [r["key"] for r in results if not r["first_frame_alpha_equal"]],
		"first_frame_visible_mismatch": [r["key"] for r in results if r["first_frame_visible_differing_pixels"]],
		"usage": [r["usage"] for r in results]}, ensure_ascii=False))


if __name__ == "__main__":
	main()
