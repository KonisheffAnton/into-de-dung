"""Только кадрирование и nearest-масштабирование, без перерисовки исходника."""
from pathlib import Path
import hashlib
import json

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / "model" / "source-full.png"
OUTPUT = ROOT / "model" / "input-256.png"


def digest(path: Path) -> str:
	return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
	if not SOURCE.is_file():
		raise SystemExit(f"Missing confirmed source: {SOURCE}")
	original = Image.open(SOURCE).convert("RGBA")
	alpha = original.getchannel("A")
	if alpha.getextrema() != (0, 255):
		raise SystemExit("Source must preserve transparent pixels")
	solid = alpha.point(lambda value: 255 if value >= 128 else 0).getbbox()
	if solid is None:
		raise SystemExit("Source has no solid figure")
	bbox = (max(0, solid[0] - 2), max(0, solid[1] - 2),
			min(original.width, solid[2] + 2), min(original.height, solid[3] + 2))
	crop = original.crop(bbox)
	scale = min(152 / crop.height, 180 / crop.width)
	width, height = round(crop.width * scale), round(crop.height * scale)
	if width <= 0 or height <= 0:
		raise SystemExit("Source crop cannot fit the requested 180x152 footprint")
	sprite = crop.resize((width, height), Image.Resampling.NEAREST)
	array = np.asarray(sprite)
	# Тёплая коричневая нижняя область даёт устойчивую точку между сапогами.
	brown = ((array[:, :, 0] > array[:, :, 2] * 1.35)
			& (array[:, :, 0] > array[:, :, 1] * 1.1)
			& (array[:, :, 3] > 128))
	brown[:int(height * .88)] = False
	ys, xs = np.where(brown)
	foot_x = (int(xs.min()) + int(xs.max())) / 2 if len(xs) else width / 2
	foot_y = int(ys.max()) + 1 if len(ys) else height
	offset = (round(128 - foot_x), 200 - foot_y)
	canvas = Image.new("RGBA", (256, 256))
	canvas.paste(sprite, offset)
	input_bbox = canvas.getchannel("A").getbbox()
	if input_bbox is None or min(input_bbox[:2]) <= 0 or max(input_bbox[2:]) >= 256:
		raise SystemExit("Prepared mage touches canvas boundary")
	OUTPUT.parent.mkdir(parents=True, exist_ok=True)
	canvas.save(OUTPUT)
	metadata = {
		"source": SOURCE.relative_to(ROOT).as_posix(), "source_sha256": digest(SOURCE),
		"source_size": original.size, "alpha_solid_bbox": solid, "crop_bbox": bbox,
		"resampling": "nearest", "scale_from_crop": scale, "resized_size": [width, height],
		"foot_estimate_in_resized_crop": [foot_x, foot_y], "offset": offset,
		"canvas": [256, 256], "anchor": [128, 200], "input_bbox": input_bbox,
		"input_sha256": digest(OUTPUT), "integration": False,
	}
	(ROOT / "model" / "transform.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8")
	print(json.dumps(metadata, ensure_ascii=False))


if __name__ == "__main__":
	main()
