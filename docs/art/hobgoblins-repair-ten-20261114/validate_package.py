"""Проверяет provenance ремонта, mask-only pixels и автономную галерею."""
from pathlib import Path
import base64
import hashlib
import json
import re

import numpy as np
from PIL import Image
from selected_outputs import resolve_selected

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[2]


def sha(data: bytes) -> str:
	return hashlib.sha256(data).hexdigest()


def load_rgba(path: Path) -> Image.Image:
	with Image.open(path) as image:
		if image.size != (256, 256) or image.mode != "RGBA":
			raise SystemExit(f"Expected 256x256 RGBA image: {path}")
		return image.copy()


def bbox(alpha: np.ndarray) -> list[int] | None:
	points = np.argwhere(alpha > 0)
	if not len(points):
		return None
	return [int(points[:, 1].min()), int(points[:, 0].min()), int(points[:, 1].max()) + 1, int(points[:, 0].max()) + 1]


def main() -> None:
	requests_path, owner_path = ROOT / "requests.json", ROOT / "input-sources.json"
	rows = json.loads(requests_path.read_text(encoding="utf-8-sig"))
	owner = json.loads(owner_path.read_text(encoding="utf-8-sig"))
	manifest_path = ROOT / "sources.json"
	if not manifest_path.is_file():
		raise SystemExit("Missing sources.json; run exporter after all jobs complete")
	manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
	canonical_requests_sha = sha(requests_path.read_text(encoding="utf-8-sig").encode("utf-8"))
	canonical_owner_sha = sha(owner_path.read_text(encoding="utf-8-sig").encode("utf-8"))
	if manifest.get("request_manifest_sha256") != canonical_requests_sha or manifest.get("input_sources_manifest_sha256") != canonical_owner_sha:
		raise SystemExit("Canonical LF manifest SHA mismatch")
	if not manifest.get("complete") or len(rows) != 10 or len(manifest.get("variants", [])) != 10:
		raise SystemExit("Expected exactly ten completed repairs")
	if manifest.get("whole_figure_mask_exception") != {"id": 8, "enabled": True}:
		raise SystemExit("Variant 8 whole-figure mask exception is missing or changed")
	owner_by_id = {item["id"]: item for item in owner.get("inputs", [])}
	if set(owner_by_id) != set(range(1, 11)):
		raise SystemExit("Input source manifest must cover IDs 1 through 10")
	variants = manifest["variants"]
	if [item.get("id") for item in variants] != list(range(1, 11)):
		raise SystemExit("Expected outputs numbered 1 through 10")
	for item, row in zip(variants, rows):
		owner_item = owner_by_id[row["id"]]
		if item.get("name") != row.get("name") or item.get("request_sha256") == "":
			raise SystemExit(f"Variant/request metadata mismatch: {row['id']}")
		if item.get("whole_figure_style_mask") is not (row["id"] == 8):
			raise SystemExit(f"Whole-figure-mask exception must apply to variant 8 only: {row['id']}")
		input_path, mask_path, context_path = ROOT / row["input"], ROOT / row["mask"], ROOT / row["context"]
		input_raw, mask_raw, context_raw = input_path.read_bytes(), mask_path.read_bytes(), context_path.read_bytes()
		if sha(input_raw) != owner_item.get("input_sha256") or sha(mask_raw) != owner_item.get("mask_sha256") or sha(context_raw) != owner_item.get("context_sha256"):
			raise SystemExit(f"Input/mask/context hash differs from source owner: {row['id']}")
		previous_source = REPO / owner_item["source"]
		if not previous_source.is_file() or previous_source.read_bytes() != input_raw:
			raise SystemExit(f"Repair input differs from the previous source image: {row['id']}")
		with Image.open(context_path) as context_image:
			if context_image.size != (768, 256) or context_image.mode != "RGBA":
				raise SystemExit(f"Context must be 768x256 RGBA: {row['id']}")
		with Image.open(mask_path) as mask_image:
			if mask_image.size != (256, 256) or mask_image.mode != "RGB":
				raise SystemExit(f"Mask must be 256x256 RGB: {row['id']}")
			mask_rgb = np.asarray(mask_image)
		if not np.all(mask_rgb == mask_rgb[:, :, :1]) or not np.isin(mask_rgb[:, :, 0], (0, 255)).all():
			raise SystemExit(f"Mask must contain pure black/white RGB only: {row['id']}")
		mask_white = mask_rgb[:, :, 0] == 255
		if int(np.count_nonzero(mask_white)) != owner_item.get("white_mask_pixels"):
			raise SystemExit(f"Mask white-pixel count mismatch: {row['id']}")
		source, final = load_rgba(input_path), load_rgba(ROOT / item["file"])
		source_array, final_array = np.asarray(source), np.asarray(final)
		changed = np.any(final_array != source_array, axis=2)
		if np.any(changed & ~mask_white):
			raise SystemExit(f"RGBA pixels changed outside white mask: {row['id']}")
		source_box = bbox(source_array[:, :, 3])
		final_box = bbox(final_array[:, :, 3])
		if source_box != owner_item.get("source_bbox") or source_box != item.get("source_bbox") or final_box != item.get("final_bbox"):
			raise SystemExit(f"Source/final alpha bounds mismatch: {row['id']}")
		if final_box is None:
			raise SystemExit(f"Final output has no visible pixels: {row['id']}")
		source_height = source_box[3] - source_box[1]
		final_height = final_box[3] - final_box[1]
		if final_height >= 152 or final_height > source_height + 9:
			raise SystemExit(f"Final height exceeds preserved compact silhouette: {row['id']} {source_height}->{final_height}")
		if final_height < source_height - 8 or not item.get("height_within_repair_allowance"):
			raise SystemExit(f"Final silhouette shrank by more than 8px: {row['id']} {source_height}->{final_height}")
		if min(final_box[0], final_box[1], 256 - final_box[2], 256 - final_box[3]) < 8:
			raise SystemExit(f"Final output lacks 8px canvas margin: {row['id']} {final_box}")
		if item.get("source_height") != source_height or item.get("final_height") != final_height:
			raise SystemExit(f"Height metadata mismatch: {row['id']}")
		if item.get("sha256") != sha((ROOT / item["file"]).read_bytes()):
			raise SystemExit(f"Final output SHA mismatch: {row['id']}")
		if item.get("input_sha256") != sha(input_raw) or item.get("mask_sha256") != sha(mask_raw) or item.get("context_sha256") != sha(context_raw):
			raise SystemExit(f"Per-variant provenance SHA mismatch: {row['id']}")
		if not item.get("outside_white_mask_exact"):
			raise SystemExit(f"Per-variant outside-mask assertion missing: {row['id']}")
		# Счётчики показывают, сколько уже видимых пикселей изменено в зонах ремонта.
		top_limit = max(source_box[1], final_box[1]) + 1
		bottom_start = max(0, min(source_box[3], final_box[3]) - 1)
		top_count = int(np.count_nonzero(changed[:top_limit] & mask_white[:top_limit]))
		bottom_count = int(np.count_nonzero(changed[bottom_start:] & mask_white[bottom_start:]))
		if item.get("changed_pixels_top_repair_zone") != top_count or item.get("changed_pixels_bottom_repair_zone") != bottom_count:
			raise SystemExit(f"Top/bottom repair-zone change diagnostics mismatch: {row['id']}")
		if item.get("edge_contact") != (final_box[0] == 0 or final_box[1] == 0 or final_box[2] == 256 or final_box[3] == 256):
			raise SystemExit(f"Edge diagnostic mismatch: {row['id']}")
	selected_variants = resolve_selected(manifest, ROOT)
	selected8 = selected_variants[7]
	if selected8.get("additional_style_pass") is not True or "outside_white_mask_exact" in selected8:
		raise SystemExit("Selected variant 8 must be an unmasked style pass without inherited mask-exact claim")
	sheets = {
		"contact-sheet.png": (2560, 1192), "contact-sheet-small.png": (1280, 596),
		"style-compare.png": (1024, 858), "before-after-sheet.png": (2560, 572),
	}
	for name, expected_size in sheets.items():
		with Image.open(ROOT / name) as sheet:
			if sheet.mode != "RGB" or sheet.size != expected_size:
				raise SystemExit(f"Unexpected sheet dimensions/mode: {name} {sheet.size}/{sheet.mode}")
	html_path = ROOT / "gallery.html"
	if not html_path.is_file():
		raise SystemExit("Missing gallery.html; run build_gallery.py")
	html = html_path.read_text(encoding="utf-8")
	asset_match = re.search(r"const ASSETS=(\{.*?\}),CARDS=", html, re.S)
	card_match = re.search(r"CARDS=(\[.*?\]);let showAfter", html, re.S)
	if not asset_match or not card_match:
		raise SystemExit("Could not parse embedded gallery data")
	assets, cards = json.loads(asset_match.group(1)), json.loads(card_match.group(1))
	if len(assets) != 21 or len(cards) != 10:
		raise SystemExit(f"Expected 10 before + 10 selected after + reference; got {len(assets)} images and {len(cards)} cards")
	for item in selected_variants:
		before_path = item["input_file"]
		for path in (before_path, item["file"]):
			match = re.fullmatch(r"data:image/png;base64,([A-Za-z0-9+/=]+)", assets.get(path, ""))
			if not match or base64.b64decode(match.group(1), validate=True) != (ROOT / path).read_bytes():
				raise SystemExit(f"Gallery embedded PNG differs from original: {path}")
	ref_key = "references/warrior11.png"
	ref_match = re.fullmatch(r"data:image/png;base64,([A-Za-z0-9+/=]+)", assets.get(ref_key, ""))
	if not ref_match or base64.b64decode(ref_match.group(1), validate=True) != (ROOT / ref_key).read_bytes():
		raise SystemExit("Gallery embedded Warrior reference differs")
	if [card.get("id") for card in cards] != list(range(1, 11)):
		raise SystemExit("Gallery cards must include all ten numbered variants")
	for card, item in zip(cards, selected_variants):
		before_height = item["source_height"]
		if (card.get("source_height"), card.get("final_height")) != (before_height, item["final_height"]):
			raise SystemExit(f"Gallery source/final height labels mismatch: {card['id']}")
		if card.get("before") != (item["input_file"]):
			raise SystemExit(f"Gallery before image source mismatch: {card['id']}")
		if card.get("after") != item["file"] or card.get("additional_style_pass", False) != item.get("additional_style_pass", False):
			raise SystemExit(f"Gallery selected after image mismatch: {card['id']}")
	for name in sheets:
		data_url = "data:image/png;base64," + base64.b64encode((ROOT / name).read_bytes()).decode("ascii")
		if data_url not in html:
			raise SystemExit(f"Gallery does not embed {name}")
	if "width:min(70vh,80vw,768px)" not in html or "object-fit:cover" in html:
		raise SystemExit("Gallery modal must retain image aspect ratio without crop")
	result = {"complete": True, "variants": 10, "inpaint_outside_mask_exact": True,
		"full_reference_edit_id8": {"job_id": selected8["job_id"], "sha256": selected8["sha256"],
			"final_bbox": selected8["final_bbox"], "final_height": selected8["final_height"],
			"outside_mask_exact": "not_applicable_no_mask_guarantee"},
		"native_heights": [{"id": item["id"], "before": (item["source_height"]), "after": item["final_height"]} for item in selected_variants],
		"embedded_source_images": len(assets), "sheets": {name: list(size) for name, size in sheets.items()},
		"scope": "Pixel and artifact integrity only; visual face, feet, and blister acceptance remains human review"}
	(ROOT / "validation.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
	print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
	main()
