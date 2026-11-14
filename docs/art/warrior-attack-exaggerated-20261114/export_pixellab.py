"""Сохраняет подтверждённые PNG PixelLab и строит файлы только для просмотра."""
from pathlib import Path
import base64
import hashlib
import io
import json

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent
JOBS = Path("C:/Users/Aston/.codex/generated_images/warrior-attack-exaggerated-20261114")


def load_json(path: Path) -> dict | list:
	return json.loads(path.read_text(encoding="utf-8-sig"))


def sha(data: bytes) -> str:
	return hashlib.sha256(data).hexdigest()


def main() -> None:
	rows = load_json(ROOT / "requests.json")
	if not isinstance(rows, list) or len(rows) != 5:
		raise SystemExit("requests.json must contain exactly five attack variants")
	results = []
	for row in rows:
		if row.get("kind") != "attack" or row.get("frame_count") != 32 or row.get("expected_frames") != 33:
			raise SystemExit(f"Invalid attack request contract: {row.get('key')}")
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
		images = job.get("last_response", {}).get("images", [])
		if len(images) != row["expected_frames"]:
			raise SystemExit(f"Expected 33 raw frames for {row['key']}, got {len(images)}")
		out = ROOT / "pixellab" / row["key"]
		frames_dir = out / "frames"
		frames_dir.mkdir(parents=True, exist_ok=True)
		frames: list[Image.Image] = []
		raw_list: list[bytes] = []
		for index, item in enumerate(images):
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
			raw_list.append(raw)
		original_path = ROOT / row["input"]
		original = Image.open(original_path).convert("RGBA")
		if original.size != (256, 256):
			raise SystemExit(f"Input must be 256x256: {original_path}")
		first = np.asarray(frames[0])
		initial = np.asarray(original)
		diff = np.any(first != initial, axis=2)
		alpha_diff = first[:, :, 3] != initial[:, :, 3]
		visible = (first[:, :, 3] > 0) | (initial[:, :, 3] > 0)
		alpha_count = int(np.count_nonzero(alpha_diff))
		visible_count = int(np.count_nonzero(diff & visible))
		durations = [50] * len(frames)
		durations[-1] = 700
		sheet = Image.new("RGBA", (256 * 8, 256 * ((len(frames) + 7) // 8)))
		for index, image in enumerate(frames):
			sheet.paste(image, ((index % 8) * 256, (index // 8) * 256))
		sheet.save(out / "spritesheet.png")
		preview = []
		for image in frames:
			bg = Image.new("RGBA", (256, 256), "#182131")
			bg.alpha_composite(image)
			preview.append(bg.convert("RGB").resize((512, 512), Image.Resampling.NEAREST))
		preview[0].save(out / "preview.gif", save_all=True, append_images=preview[1:], duration=durations, loop=0, disposal=2)
		filmstrip = Image.new("RGB", (256 * 5, 256), "#182131")
		for column, index in enumerate([0, 8, 16, 24, 32]):
			filmstrip.paste(frames[index], (column * 256, 0), frames[index])
		filmstrip.save(out / "filmstrip.png")
		gif_durations = []
		with Image.open(out / "preview.gif") as gif:
			for index in range(gif.n_frames):
				gif.seek(index)
				gif_durations.append(gif.info.get("duration", 0))
		boxes = [image.getchannel("A").getbbox() for image in frames]
		solid_boxes = [image.getchannel("A").point(lambda value: 255 if value >= 128 else 0).getbbox() for image in frames]
		result = {
			**row, "provider": "PixelLab PixMiniMax", "job_id": job["id"],
			"usage": job["last_response"].get("billing_usage") or job["last_response"].get("usage") or job.get("usage"),
			"actual_frames": len(frames), "canvas": [256, 256], "durations_ms": durations,
			"timing_origin": "Preview timing authored locally; provider supplies poses only",
			"gif_actual_durations_ms": gif_durations, "gif_total_duration_ms": sum(gif_durations),
			"first_frame_alpha_equal": alpha_count == 0, "first_frame_alpha_differing_pixels": alpha_count,
			"first_frame_visible_differing_pixels": visible_count,
			"first_frame_rgba_differing_pixels": int(np.count_nonzero(diff)),
			"first_frame_transparent_rgb_differing_pixels": int(np.count_nonzero(diff)) - visible_count,
			"first_frame_png_byte_equal": raw_list[0] == original_path.read_bytes(),
			"last_frame_rgba_equal": frames[-1].tobytes() == original.tobytes(),
			"edge_frames": [i for i, box in enumerate(solid_boxes) if box and (box[0] == 0 or box[1] == 0 or box[2] == 256 or box[3] == 256)],
			"margin_violation_frames": [i for i, box in enumerate(boxes) if box and (box[0] < 8 or box[1] < 8 or box[2] > 248 or box[3] > 248)],
			"frame_sha256": [sha(data) for data in raw_list], "bboxes": solid_boxes,
			"raw_alpha_bboxes": boxes, "integration": False,
		}
		(out / "clip.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
		results.append(result)
	complete = len(results) == len(rows)
	(ROOT / "pixellab-validation.json").write_text(json.dumps({
		"expected": 5, "completed": len(results), "complete": complete,
		"first_frame_policy": "Exact alpha and visible RGBA are checked; transparent RGB-only differences are diagnostic.",
		"complete_meaning": "Count only; not artistic acceptance or runtime validation", "clips": results,
	}, ensure_ascii=False, indent=2), encoding="utf-8")
	print(json.dumps({"expected": 5, "exported": len(results), "complete": complete,
		"edge_clips": [r["key"] for r in results if r["edge_frames"]],
		"first_frame_alpha_mismatch": [r["key"] for r in results if not r["first_frame_alpha_equal"]],
		"first_frame_visible_mismatch": [r["key"] for r in results if r["first_frame_visible_differing_pixels"]]}, ensure_ascii=False))


if __name__ == "__main__":
	main()
