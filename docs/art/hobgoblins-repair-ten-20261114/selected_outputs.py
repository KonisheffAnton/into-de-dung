"""Разрешает выборочную замену результата отдельной reference-правкой."""
from pathlib import Path
import hashlib
import json

import numpy as np
from PIL import Image


def _sha(path: Path) -> str:
	return hashlib.sha256(path.read_bytes()).hexdigest()


def _box(image: Image.Image) -> list[int] | None:
	box = image.getchannel("A").getbbox()
	return list(box) if box else None


def resolve_selected(manifest: dict, rootpath: Path) -> list[dict]:
	"""Возвращает copy-on-write список: базовые источники остаются нетронутыми."""
	root = Path(rootpath)
	selection_path = root / "selection.json"
	if not selection_path.is_file():
		raise SystemExit("Missing selection.json")
	selection = json.loads(selection_path.read_text(encoding="utf-8-sig"))
	overrides = selection.get("overrides", [])
	if len(overrides) != 1 or overrides[0].get("id") != 8:
		raise SystemExit("selection.json must contain exactly one override for variant 8")
	base_items = manifest.get("variants", [])
	if len(base_items) != 10 or [item.get("id") for item in base_items] != list(range(1, 11)):
		raise SystemExit("Base sources manifest must contain variants 1 through 10")
	resolved = [dict(item) for item in base_items]
	base8, base3 = resolved[7], resolved[2]
	entry = overrides[0]
	if (entry.get("endpoint"), entry.get("method"), entry.get("no_mask_guarantee")) != ("/edit-images-v2", "edit_with_reference", True):
		raise SystemExit("Variant 8 override must be an explicit unmasked reference edit")
	for key in ("file", "sha256", "job_id", "input_sha256", "reference_sha256", "final_bbox", "final_height"):
		if entry.get(key) in (None, ""):
			raise SystemExit(f"Selection override is missing {key}")
	input_path = root / entry.get("source_input", "")
	ref_path = root / entry.get("reference", "")
	output_path = root / entry["file"]
	base8_path = root / base8["file"]
	base3_path = root / base3["file"]
	if not all(path.is_file() for path in (input_path, ref_path, output_path, base8_path, base3_path)):
		raise SystemExit("Selection override input/reference/output/base files must exist")
	if _sha(input_path) != entry["input_sha256"] or input_path.read_bytes() != base8_path.read_bytes():
		raise SystemExit("Selection style input must match base variant 8 exactly")
	if _sha(ref_path) != entry["reference_sha256"] or ref_path.read_bytes() != base3_path.read_bytes():
		raise SystemExit("Selection reference must match base variant 3 exactly")
	if _sha(output_path) != entry["sha256"]:
		raise SystemExit("Selection output SHA mismatch")
	with Image.open(input_path) as source_image, Image.open(output_path) as output_image:
		source = source_image.convert("RGBA")
		output = output_image.copy()
		if output.size != (256, 256) or output.mode != "RGBA":
			raise SystemExit("Selected override must be 256x256 RGBA")
		alpha = np.asarray(output.getchannel("A"))
		if not np.any(alpha > 0) or not np.any(alpha == 0):
			raise SystemExit("Selected override must contain visible pixels and transparency")
		box = _box(output)
		if box is None or box != entry["final_bbox"]:
			raise SystemExit("Selection final_bbox differs from output alpha bounds")
		height = box[3] - box[1]
		source_box = _box(source)
		if source_box is None:
			raise SystemExit("Base variant 8 source is empty")
		style_input_height = source_box[3] - source_box[1]
		if style_input_height != base8["final_height"]:
			raise SystemExit("Style input height differs from base masked output")
		source_height = base8["source_height"]
		if height != entry["final_height"] or height >= 152 or not source_height - 8 <= height <= source_height + 9:
			raise SystemExit(f"Selected variant 8 height outside source tolerance: {source_height}->{height}")
		if min(box[0], box[1], 256 - box[2], 256 - box[3]) < 8:
			raise SystemExit("Selected variant 8 must keep at least 8px canvas margin")
	selected = dict(base8)
	for obsolete in ("outside_white_mask_exact", "changed_pixels_top_repair_zone", "changed_pixels_bottom_repair_zone", "whole_figure_style_mask"):
		selected.pop(obsolete, None)
	selected.update({
		"base_file": base8["file"], "base_sha256": base8["sha256"],
		"base_final_bbox": base8["final_bbox"], "base_final_height": base8["final_height"],
		"input_file": base8["input_file"], "file": entry["file"], "sha256": entry["sha256"],
		"final_bbox": entry["final_bbox"], "final_height": entry["final_height"],
		"height_delta": entry["final_height"] - base8["source_height"],
		"job_id": entry["job_id"], "usage": entry.get("usage"),
		"additional_style_pass": True, "selection_method": entry["method"],
		"no_mask_guarantee": True,
	})
	resolved[7] = selected
	return resolved
