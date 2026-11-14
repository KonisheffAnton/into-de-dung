"""Один удар из каждой новой генерации; исходные PNG не изменяются."""
from pathlib import Path
import hashlib
import json
import math

from PIL import Image

ROOT = Path(__file__).resolve().parent


def main() -> None:
	edits = json.loads((ROOT / "single-edits.json").read_text(encoding="utf-8"))["edits"]
	if [edit["key"] for edit in edits] != [f"attack-{i}" for i in range(1, 6)]:
		raise SystemExit("Expected five edits in order")
	results = []
	for edit in edits:
		folder = ROOT / "pixellab" / edit["key"]
		source = json.loads((folder / "clip.json").read_text(encoding="utf-8"))
		indices = edit["source_indices"]
		durations = edit["durations_ms"]
		if sorted(set(indices)) != indices or indices[0] != 0 or indices[-1] != 16:
			raise SystemExit("Edits must preserve order and first/last raw frames")
		if len(indices) != len(durations) or any(ms <= 0 or ms % 10 for ms in durations):
			raise SystemExit("Invalid GIF timing")
		frames = []
		for index in indices:
			path = folder / "frames" / f"frame-{index:02d}.png"
			if hashlib.sha256(path.read_bytes()).hexdigest() != source["frame_sha256"][index]:
				raise SystemExit(f"Raw SHA mismatch: {path}")
			with Image.open(path) as image:
				frames.append(image.convert("RGBA"))
		out = ROOT / "single" / edit["key"]
		out.mkdir(parents=True, exist_ok=True)
		sheet = Image.new("RGBA", (2048, 256 * math.ceil(len(frames) / 8)))
		for index, frame in enumerate(frames):
			sheet.paste(frame, ((index % 8) * 256, (index // 8) * 256))
		sheet.save(out / "spritesheet.png")
		gif_frames = []
		for frame in frames:
			background = Image.new("RGBA", (256, 256), "#182131")
			background.alpha_composite(frame)
			gif_frames.append(background.convert("RGB").resize((512, 512), Image.Resampling.NEAREST))
		gif_frames[0].save(out / "preview.gif", save_all=True, append_images=gif_frames[1:],
			duration=durations, loop=0, disposal=2)
		with Image.open(out / "spritesheet.png") as saved:
			for index, frame in enumerate(frames):
				x, y = index % 8 * 256, index // 8 * 256
				if saved.crop((x, y, x + 256, y + 256)).tobytes() != frame.tobytes():
					raise SystemExit("Single sheet differs from selected raw pixels")
		with Image.open(out / "preview.gif") as gif:
			gif_durations = []
			for index in range(gif.n_frames):
				gif.seek(index)
				gif_durations.append(gif.info["duration"])
			if sum(gif_durations) != sum(durations):
				raise SystemExit("GIF duration mismatch")
		meta = {**edit, "actual_frames": len(frames), "total_ms": sum(durations),
			"active_ms": sum(durations[:-1]), "source_job_id": source["job_id"],
			"gif_actual_durations_ms": gif_durations, "integration": False,
			"source_frame_sha256": [source["frame_sha256"][i] for i in indices],
			"sheet_cells_equal_to_raw": True, "limitation": "Recovery cuts and last-to-first seam need visual acceptance"}
		(out / "clip.json").write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8")
		results.append(meta)
	result = {"complete": True, "new_pixel_lab_generations": 5, "clips": results,
		"scope": "Selected poses are exact raw RGBA; no redraw; no runtime or user acceptance"}
	(ROOT / "single-validation.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
	print(json.dumps({"clips": len(results), "selected_frames": sum(r["actual_frames"] for r in results),
		"active_ms": [r["active_ms"] for r in results]}))


if __name__ == "__main__":
	main()
