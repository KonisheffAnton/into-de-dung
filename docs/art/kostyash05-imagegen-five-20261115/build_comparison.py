"""Проверяет упакованные PNG и собирает презентационные сравнения масштаба."""
from pathlib import Path
import hashlib
import json

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
BG = (24, 33, 49, 255)
HERO_HEIGHT = 456
KOSTYASH_HEIGHT = 304
THRESHOLD = 8


def sha(data: bytes) -> str:
	return hashlib.sha256(data).hexdigest()


def canonical_sha(path: Path) -> str:
	return sha(path.read_text(encoding="utf-8-sig").encode("utf-8"))


def font(size: int):
	for path in (Path("C:/Windows/Fonts/arial.ttf"), Path("C:/Windows/Fonts/segoeui.ttf")):
		if path.is_file():
			return ImageFont.truetype(str(path), size=size)
	return ImageFont.load_default()


def boxes(image: Image.Image) -> tuple[list[int] | None, list[int] | None]:
	a = image.getchannel("A")
	alpha = a.getbbox()
	visible = a.point(lambda value: 255 if value >= THRESHOLD else 0).getbbox()
	return (list(alpha) if alpha else None, list(visible) if visible else None)


def prepare(image: Image.Image, target_height: int) -> tuple[Image.Image, list[int], int]:
	_, body = boxes(image)
	if body is None:
		raise ValueError("PNG has no alpha>=8 visible body")
	padded = (max(0, body[0] - 4), max(0, body[1] - 4), min(image.width, body[2] + 4), min(image.height, body[3] + 4))
	crop = image.crop(padded)
	native_h = body[3] - body[1]
	preferred = round(crop.height * target_height / native_h)
	for height in sorted(range(max(1, preferred - 3), preferred + 4), key=lambda value: (abs(value - preferred), value)):
		width = max(1, round(crop.width * height / crop.height))
		candidate = crop.resize((width, height), Image.Resampling.NEAREST)
		_, rendered_body = boxes(candidate)
		if rendered_body and rendered_body[3] - rendered_body[1] == target_height:
			return candidate, rendered_body, native_h
	raise ValueError(f"Could not fit visible height {target_height}px within nearest-neighbor search ±3")


def image_for(path: Path) -> Image.Image:
	with Image.open(path) as image:
		image.load()
		if image.format != "PNG" or image.mode != "RGBA":
			raise SystemExit(f"Expected packaged RGBA PNG: {path}")
		return image.copy()


def draw_cell(sheet: Image.Image, draw: ImageDraw.ImageDraw, entry: dict, x: int, cell_top: int,
		cell_width: int, baseline: int, target_height: int, label: str, header_y: int,
		label_font, detail_font, all_records: list[dict]) -> None:
	path = ROOT / entry["file"]
	image = image_for(path)
	before = sha(path.read_bytes())
	alpha_bbox, visible_bbox = boxes(image)
	if visible_bbox is None:
		raise SystemExit(f"No visible body at alpha threshold {THRESHOLD}: {path}")
	margins = [visible_bbox[0], visible_bbox[1], image.width - visible_bbox[2], image.height - visible_bbox[3]]
	flags = ["visible_margin_under_8px"] if min(margins) < 8 else []
	try:
		presentation, rendered, native_h = prepare(image, target_height)
	except ValueError as error:
		raise SystemExit(f"Cannot present {path}: {error}") from error
	display_w = rendered[2] - rendered[0]
	display_left = x + (cell_width - display_w) // 2
	display_x = display_left - rendered[0]
	display_y = baseline - rendered[3]
	if display_left < x or display_left + display_w > x + cell_width or display_y + rendered[1] < cell_top:
		raise SystemExit(f"Fitted body does not fit cell: {path}")
	sheet.alpha_composite(presentation, (display_x, display_y))
	draw.text((x + cell_width // 2, header_y), label, font=label_font, fill="#f4d18e", anchor="mt")
	logical = ("Эталон героя · 152 px" if target_height == HERO_HEIGHT else "⅔ героя · ≈101 px в масштабе эталона") + (" · проверить край" if flags else "")
	draw.text((x + cell_width // 2, header_y + 27), logical, font=detail_font, fill="#ffb6a6" if flags else "#c8d2dd", anchor="mt")
	if sha(path.read_bytes()) != before:
		raise SystemExit(f"Packaged source PNG changed while composing: {path}")
	all_records.append({"file": entry["file"], "name": entry["name"], "source_sha256": before,
		"native_canvas": [image.width, image.height], "alpha_bbox": alpha_bbox, "visible_bbox_alpha_ge_8": visible_bbox,
		"visible_native_height": native_h, "visible_margin_ltrb": margins, "flags": flags,
		"display_bbox": [display_left, baseline - target_height, display_left + display_w, baseline],
		"display_visible_height": target_height, "display_baseline": baseline,
		"scale_from_visible_height": target_height / native_h, "raw_sha_unchanged": True})


def main() -> None:
	manifest_path = ROOT / "generations.json"
	manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
	variants = manifest.get("variants")
	if manifest.get("complete") is not True or not isinstance(variants, list) or len(variants) != 5 or [v.get("id") for v in variants] != list(range(1, 6)):
		raise SystemExit("generations.json must be complete with five ordered variants")
	briefs = json.loads((ROOT / "briefs.json").read_text(encoding="utf-8-sig"))
	if len(briefs.get("variants", [])) != 5:
		raise SystemExit("briefs.json must contain five variants")
	refs_path = ROOT / "references.json"
	refs = json.loads(refs_path.read_text(encoding="utf-8-sig"))
	ref_by_file = {item["file"]: item for item in refs}
	for required in ("references/kostyash05.png", "references/warrior11.png", "references/mage02.png"):
		if required not in ref_by_file:
			raise SystemExit(f"Missing packaged reference {required}")
		path = ROOT / required
		if sha(path.read_bytes()) != ref_by_file[required].get("sha256"):
			raise SystemExit(f"Reference SHA mismatch: {required}")
		image = image_for(path)
		if not boxes(image)[1]:
			raise SystemExit(f"Reference has no visible body: {required}")
	if len({v.get("sha256") for v in variants}) != 5:
		raise SystemExit("All five variant PNG SHA values must be unique")
	if len({ref_by_file[x]["sha256"] for x in ("references/warrior11.png", "references/mage02.png")}) != 2:
		raise SystemExit("Hero reference SHA values must be distinct")
	for row, brief in zip(variants, briefs["variants"]):
		if row.get("id") != brief.get("id") or row.get("name") != brief.get("name") or row.get("focus") != brief.get("focus") or row.get("file") != brief.get("file"):
			raise SystemExit(f"Generated record differs from brief: {row.get('id')}")
		path = ROOT / row["file"]
		if sha(path.read_bytes()) != row.get("sha256"):
			raise SystemExit(f"Variant SHA mismatch: {path}")
		image = image_for(path)
		if list(image.size) != row.get("size") or image.mode != row.get("mode") or canonical_sha(ROOT / row["prompt_file"]) != row.get("prompt_sha256"):
			raise SystemExit(f"Variant dimensions/mode/prompt mismatch: {path}")
		alpha, visible = boxes(image)
		if alpha is None or visible is None or list(image.getchannel("A").getextrema()) != row.get("alpha_extrema"):
			raise SystemExit(f"Variant alpha metadata mismatch: {path}")
		if row.get("alpha_bbox") != alpha or row.get("visible_bbox") != visible:
			raise SystemExit(f"Variant bbox metadata mismatch: {path}")
	manifest_sha = canonical_sha(manifest_path)
	refs_sha = canonical_sha(refs_path)
	briefs_sha = canonical_sha(ROOT / "briefs.json")
	font_title, font_label, font_detail = font(24), font(18), font(14)
	showcase = Image.new("RGBA", (1320, 860), BG)
	draw = ImageDraw.Draw(showcase)
	draw.text((22, 828), "Костяш · пять вариантов · рост ⅔ от героев", font=font_title, fill="#f4d18e")
	draw.line((18, 380, 1302, 380), fill="#4e6179", width=2)
	draw.line((18, 810, 1302, 810), fill="#4e6179", width=2)
	cell_entries = [{"id": v["id"], "name": v["name"], "file": v["file"]} for v in variants] + [{"id": 0, "name": "Костяш №5 · исходник", "file": "references/kostyash05.png"}]
	showcase_records = []
	for index, entry in enumerate(cell_entries):
		row, col = divmod(index, 3)
		x, top = col * 440, row * 430
		draw_cell(showcase, draw, entry, x, top, 440, 380 if row == 0 else 810,
			KOSTYASH_HEIGHT, f"{entry['id']:02d} · {entry['name']}", top + 17, font_label, font_detail, showcase_records)
	showcase.convert("RGB").save(ROOT / "showcase.png")

	comparison = Image.new("RGBA", (1680, 1280), BG)
	draw = ImageDraw.Draw(comparison)
	draw.text((22, 1240), "Герой : Костяш = 3 : 2 · общая линия земли в каждом ряду", font=font_title, fill="#f4d18e")
	draw.line((14, 544, 1666, 544), fill="#4e6179", width=2)
	draw.line((14, 1184, 1666, 1184), fill="#4e6179", width=2)
	warrior = {"id": "W", "name": "Воин 11", "file": "references/warrior11.png"}
	mage = {"id": "M", "name": "Маг 02", "file": "references/mage02.png"}
	comparison_entries = [warrior, *cell_entries[:3], mage, *cell_entries[3:]]
	comparison_records = []
	for index, entry in enumerate(comparison_entries):
		row, col = divmod(index, 4)
		target = HERO_HEIGHT if entry["id"] in ("W", "M") else KOSTYASH_HEIGHT
		top, baseline = row * 640, 544 if row == 0 else 1184
		entry_id = entry["id"] if isinstance(entry["id"], str) else f"{entry['id']:02d}"
		draw_cell(comparison, draw, entry, col * 420, top, 420, baseline, target,
			f"{entry_id} · {entry['name']}", top + 32,
			font_label, font_detail, comparison_records)
	comparison.convert("RGB").save(ROOT / "hero-scale-comparison.png")
	for record in showcase_records + comparison_records:
		if record["display_visible_height"] != (HERO_HEIGHT if record["file"] in ("references/warrior11.png", "references/mage02.png") else KOSTYASH_HEIGHT):
			raise SystemExit("Rendered visible-body target-height mismatch")
	result = {"complete": True, "generation_manifest_sha256": manifest_sha, "briefs_sha256": briefs_sha,
		"references_manifest_sha256": refs_sha, "threshold_alpha_ge_8": THRESHOLD,
		"nearest_neighbor_presentation_only": True, "hero_display_height": HERO_HEIGHT,
		"kostyash_display_height": KOSTYASH_HEIGHT, "hero_to_kostyash_display_ratio": HERO_HEIGHT / KOSTYASH_HEIGHT,
		"showcase_size": [1320, 860], "hero_scale_comparison_size": [1680, 1280],
		"showcase_records": showcase_records, "hero_scale_records": comparison_records,
		"flags": {"visible_alpha_margin_under_8px": [r["file"] for r in showcase_records + comparison_records if r["flags"]]},
		"raw_variant_shas_unique": True, "reference_shas_verified": True,
		"scope": "Presentation-only nearest-neighbor scale fit; alpha>=8 determines visible height. Original packaged PNGs remain unchanged; this does not assert runtime dimensions or art acceptance."}
	(ROOT / "validation.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
	print(json.dumps({"complete": True, "variants": len(variants), "showcase": [1320, 860],
		"hero_scale_comparison": [1680, 1280], "variant_visible_heights": [r["visible_native_height"] for r in showcase_records[:5]]}, ensure_ascii=False))


if __name__ == "__main__":
	main()
