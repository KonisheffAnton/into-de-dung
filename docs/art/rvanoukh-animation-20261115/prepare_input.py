"""Подготавливает input PNG nearest-neighbor без перерисовки или обрезки тела."""
from pathlib import Path
import hashlib
import json

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent
SOURCE = Path("docs/art/kostyash-rvanoukh-rags-20261115/rvanoukh-torn-cloth.png")
CANVAS = (256, 256)
VISIBLE_ALPHA_THRESHOLD = 8
TARGET_VISIBLE_HEIGHT = 101
GROUND_ANCHOR = (128, 200)
BODY_PADDING = 4


def sha(data: bytes) -> str:
	return hashlib.sha256(data).hexdigest()


def bbox_at_alpha(image: Image.Image, threshold: int) -> list[int]:
	mask = image.getchannel("A").point(lambda alpha: 255 if alpha >= threshold else 0)
	box = mask.getbbox()
	if box is None:
		raise SystemExit(f"Source has no pixels at alpha>={threshold}")
	return list(box)


def main() -> None:
	source_path = ROOT.parent.parent.parent / SOURCE
	if not source_path.is_file():
		raise SystemExit(f"Missing selected source: {source_path}")
	source_raw = source_path.read_bytes()
	with Image.open(source_path) as opened:
		opened.load()
		if opened.format != "PNG":
			raise SystemExit("Selected source must be PNG")
		source = opened.convert("RGBA")
	visible_box = bbox_at_alpha(source, VISIBLE_ALPHA_THRESHOLD)
	left = max(0, visible_box[0] - BODY_PADDING)
	top = max(0, visible_box[1] - BODY_PADDING)
	right = min(source.width, visible_box[2] + BODY_PADDING)
	bottom = min(source.height, visible_box[3] + BODY_PADDING)
	crop = source.crop((left, top, right, bottom))
	preferred_height = round(crop.height * TARGET_VISIBLE_HEIGHT / (visible_box[3] - visible_box[1]))
	transformed = None
	transform_box = None
	for output_height in sorted(range(max(1, preferred_height - 3), preferred_height + 4), key=lambda value: (abs(value - preferred_height), value)):
		output_width = max(1, round(crop.width * output_height / crop.height))
		candidate = crop.resize((output_width, output_height), Image.Resampling.NEAREST)
		box = bbox_at_alpha(candidate, VISIBLE_ALPHA_THRESHOLD)
		if box[3] - box[1] == TARGET_VISIBLE_HEIGHT:
			transformed, transform_box = candidate, box
			break
	if transformed is None or transform_box is None:
		raise SystemExit("Could not reach 101px visible height with nearest-neighbor resize ±3")
	anchor_x, anchor_y = GROUND_ANCHOR
	place_x = anchor_x - (transform_box[0] + transform_box[2]) // 2
	place_y = anchor_y - transform_box[3]
	if place_x < 0 or place_y < 0 or place_x + transformed.width > CANVAS[0] or place_y + transformed.height > CANVAS[1]:
		raise SystemExit("Fitted image including full crop does not fit the 256x256 canvas")
	canvas = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
	canvas.paste(transformed, (place_x, place_y))
	output_box = bbox_at_alpha(canvas, VISIBLE_ALPHA_THRESHOLD)
	if output_box[3] - output_box[1] != TARGET_VISIBLE_HEIGHT:
		raise SystemExit("Final visible silhouette does not match target height")
	if (output_box[0] + output_box[2]) // 2 != anchor_x or output_box[3] != anchor_y:
		raise SystemExit("Final visible body does not match requested center-ground anchor")
	model_dir = ROOT / "model"
	model_dir.mkdir(parents=True, exist_ok=True)
	source_copy = model_dir / "source-full.png"
	input_path = model_dir / "input-256.png"
	if source_copy.exists() and source_copy.read_bytes() != source_raw:
		raise SystemExit("Existing source copy differs from selected source bytes")
	source_copy.write_bytes(source_raw)
	canvas.save(input_path, format="PNG")
	transform = {"crop_bbox": [left, top, right, bottom], "source_visible_bbox_alpha_ge_8": visible_box,
		"source_visible_height": visible_box[3] - visible_box[1], "crop_padding_source_pixels": BODY_PADDING,
		"nearest_neighbor_only": True, "target_visible_height": TARGET_VISIBLE_HEIGHT,
		"canvas": list(CANVAS), "ground_anchor": list(GROUND_ANCHOR),
		"transformed_size": list(transformed.size), "transformed_bbox_alpha_ge_8": transform_box,
		"placement_xy": [place_x, place_y], "output_visible_bbox_alpha_ge_8": output_box}
	transform_hash = sha(json.dumps(transform, sort_keys=True, separators=(",", ":")).encode("utf-8"))
	manifest = {"source": SOURCE.as_posix(), "source_sha256": sha(source_raw), "source_copy": "model/source-full.png",
		"source_copy_sha256": sha(source_copy.read_bytes()), "input": "model/input-256.png",
		"input_sha256": sha(input_path.read_bytes()), "transform": transform,
		"transform_sha256": transform_hash, "alpha_extrema": list(canvas.getchannel("A").getextrema()),
		"alpha_bbox": bbox_at_alpha(canvas, 1), "visible_bbox_alpha_ge_8": output_box,
		"method": "bbox(alpha>=8)+4px crop, nearest-neighbor search, centered by visible silhouette, ground anchored; no repaint",
		"runtime_integration": False}
	(model_dir / "input-manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
	print(json.dumps({"source_visible_bbox_alpha_ge_8": visible_box,
		"source_visible_height": visible_box[3] - visible_box[1],
		"input_canvas": list(CANVAS), "input_visible_bbox_alpha_ge_8": output_box,
		"input_visible_height": output_box[3] - output_box[1], "ground_anchor": [anchor_x, anchor_y],
		"placement_xy": [place_x, place_y], "transform_sha256": transform_hash}, ensure_ascii=False))


if __name__ == "__main__":
	main()
