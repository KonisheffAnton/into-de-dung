"""Строит два nearest-neighbor листа и проверяет packaged PNG/манифесты."""
from pathlib import Path
import hashlib
import json

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
BG = (24, 33, 49, 255)
THRESHOLD = 8
GOBLIN_HEIGHT = 304
HERO_HEIGHT = 456


def sha(data: bytes) -> str:
	return hashlib.sha256(data).hexdigest()


def canonical_sha(path: Path) -> str:
	return sha(path.read_text(encoding="utf-8-sig").encode("utf-8"))


def font(size: int):
	for path in (Path("C:/Windows/Fonts/arial.ttf"), Path("C:/Windows/Fonts/segoeui.ttf")):
		if path.is_file():
			return ImageFont.truetype(str(path), size=size)
	return ImageFont.load_default()


def bounds(image: Image.Image) -> tuple[list[int] | None, list[int] | None]:
	alpha = image.getchannel("A")
	full = alpha.getbbox()
	visible = alpha.point(lambda a: 255 if a >= THRESHOLD else 0).getbbox()
	return ([*full] if full else None, [*visible] if visible else None)


def fit(image: Image.Image, target_height: int) -> tuple[Image.Image, list[int], int]:
	_, body = bounds(image)
	if body is None:
		raise ValueError("no visible body at alpha >= 8")
	padded = (max(0, body[0] - 4), max(0, body[1] - 4), min(image.width, body[2] + 4), min(image.height, body[3] + 4))
	crop = image.crop(padded)
	native_height = body[3] - body[1]
	preferred = round(crop.height * target_height / native_height)
	for height in sorted(range(max(1, preferred - 3), preferred + 4), key=lambda h: (abs(h - preferred), h)):
		width = max(1, round(crop.width * height / crop.height))
		candidate = crop.resize((width, height), Image.Resampling.NEAREST)
		_, body_out = bounds(candidate)
		if body_out and body_out[3] - body_out[1] == target_height:
			return candidate, body_out, native_height
	raise ValueError(f"unable to fit visible height {target_height} within search ±3")


def load_png(path: Path) -> Image.Image:
	with Image.open(path) as image:
		image.load()
		if image.format != "PNG" or image.mode != "RGBA":
			raise SystemExit(f"Expected RGBA PNG: {path}")
		return image.copy()


def place(sheet: Image.Image, draw: ImageDraw.ImageDraw, file: str, name: str, label: str,
		cell_left: int, cell_top: int, cell_width: int, baseline: int, height: int,
		label_y: int, label_font, detail_font, records: list[dict]) -> None:
	path = ROOT / file
	before = sha(path.read_bytes())
	image = load_png(path)
	alpha_box, visible_box = bounds(image)
	if visible_box is None:
		raise SystemExit(f"Empty visible silhouette: {file}")
	margins = [visible_box[0], visible_box[1], image.width - visible_box[2], image.height - visible_box[3]]
	flags = ["visible_margin_under_8px"] if min(margins) < 8 else []
	try:
		presentation, body_out, native_height = fit(image, height)
	except ValueError as exc:
		raise SystemExit(f"Could not fit {file}: {exc}") from exc
	visible_width = body_out[2] - body_out[0]
	left = cell_left + (cell_width - visible_width) // 2
	image_x = left - body_out[0]
	image_y = baseline - body_out[3]
	if left < cell_left or left + visible_width > cell_left + cell_width or image_y + body_out[1] < cell_top:
		raise SystemExit(f"Rendered silhouette exceeds cell: {file}")
	sheet.alpha_composite(presentation, (image_x, image_y))
	draw.text((cell_left + cell_width // 2, label_y), label, font=label_font, fill="#f4d18e", anchor="mt")
	caption = ("Эталон героя" if height == HERO_HEIGHT else "⅔ роста воина") + (" · проверить край" if flags else "")
	draw.text((cell_left + cell_width // 2, label_y + 24), caption, font=detail_font,
		fill="#ffb6a6" if flags else "#c8d2dd", anchor="mt")
	if sha(path.read_bytes()) != before:
		raise SystemExit(f"Packaged PNG changed while composing: {file}")
	records.append({"file": file, "name": name, "png_sha256": before,
		"native_size": [image.width, image.height], "alpha_bbox": alpha_box,
		"visible_bbox_alpha_ge_8": visible_box, "visible_native_height": native_height,
		"visible_margins_ltrb": margins, "flags": flags,
		"display_visible_height": height, "display_bottom": baseline,
		"presentation_scale": height / native_height, "raw_sha_unchanged": True})


def main() -> None:
	root_path = ROOT / "generations.json"
	manifest = json.loads(root_path.read_text(encoding="utf-8-sig"))
	variants = manifest.get("variants")
	if manifest.get("complete") is not True or manifest.get("expected") != 2 or not isinstance(variants, list) or [v.get("id") for v in variants] != [5, 1]:
		raise SystemExit("generations.json must be complete and ordered [5, 1]")
	briefs_path = ROOT / "briefs.json"
	briefs = json.loads(briefs_path.read_text(encoding="utf-8-sig"))
	brief_by_id = {v["id"]: v for v in briefs.get("variants", [])}
	refs_path = ROOT / "references.json"
	refs = json.loads(refs_path.read_text(encoding="utf-8-sig"))
	ref_by_file = {v["file"]: v for v in refs}
	required_refs = {"references/original-05.png", "references/original-01.png", "references/warrior11.png"}
	if not required_refs.issubset(ref_by_file):
		raise SystemExit("references.json lacks one or more required PNGs")
	ref_records = {}
	for filename in sorted(required_refs):
		path = ROOT / filename
		if sha(path.read_bytes()) != ref_by_file[filename].get("sha256"):
			raise SystemExit(f"Reference SHA mismatch: {filename}")
		image = load_png(path)
		alpha_box, visible_box = bounds(image)
		if alpha_box is None or visible_box is None:
			raise SystemExit(f"Reference silhouette empty: {filename}")
		ref_records[filename] = {"sha256": ref_by_file[filename]["sha256"], "size": list(image.size),
			"alpha_bbox": alpha_box, "visible_bbox_alpha_ge_8": visible_box}
	if len({v.get("sha256") for v in variants}) != 2:
		raise SystemExit("Generated PNG SHA values must be unique")
	for row in variants:
		brief = brief_by_id.get(row["id"])
		if not brief or any(row.get(k) != brief.get(k) for k in ("name", "focus", "file", "prompt_file")):
			raise SystemExit(f"Generation record differs from brief: {row.get('id')}")
		path = ROOT / row["file"]
		if sha(path.read_bytes()) != row.get("sha256"):
			raise SystemExit(f"Generated PNG SHA mismatch: {path}")
		image = load_png(path)
		alpha_box, visible_box = bounds(image)
		if alpha_box is None or visible_box is None or row.get("alpha_bbox") != alpha_box or row.get("visible_bbox") != visible_box or list(image.getchannel("A").getextrema()) != row.get("alpha_extrema"):
			raise SystemExit(f"Generated alpha metadata mismatch: {path}")
		if list(image.size) != row.get("size") or row.get("mode") != image.mode:
			raise SystemExit(f"Generated dimensions/mode mismatch: {path}")
		if canonical_sha(ROOT / row["prompt_file"]) != row.get("prompt_sha256"):
			raise SystemExit(f"Canonical prompt SHA mismatch: {row['prompt_file']}")
	manifest_sha = canonical_sha(root_path)
	briefs_sha = canonical_sha(briefs_path)
	refs_sha = canonical_sha(refs_path)
	font_title, font_label, font_detail = font(23), font(19), font(14)

	comparison = Image.new("RGBA", (1320, 640), BG)
	draw = ImageDraw.Draw(comparison)
	draw.line((18, 550, 1302, 550), fill="#4e6179", width=2)
	comparison_records = []
	entries = [
		(variants[0], "variants/crooked-fang.png", "Кривозуб №5"),
		(None, "references/warrior11.png", "Воин 11"),
		(variants[1], "variants/heavy-brow.png", "Тяжёлый лоб №1"),
	]
	for col, (row, file, name) in enumerate(entries):
		place(comparison, draw, file, name, name, col * 440, 0, 440, 550,
			HERO_HEIGHT if row is None else GOBLIN_HEIGHT, 26, font_label, font_detail, comparison_records)
	draw.text((30, 596), "Новая прорисовка · Костяши — ⅔ роста воина", font=font_title, fill="#f4d18e")
	comparison.convert("RGB").save(ROOT / "comparison.png")

	before_after = Image.new("RGBA", (1760, 450), BG)
	draw = ImageDraw.Draw(before_after)
	draw.line((18, 385, 1742, 385), fill="#4e6179", width=2)
	paired = [
		("references/original-05.png", "Кривозуб №5 · раньше"),
		("variants/crooked-fang.png", "Кривозуб №5 · теперь"),
		("references/original-01.png", "Тяжёлый лоб №1 · раньше"),
		("variants/heavy-brow.png", "Тяжёлый лоб №1 · теперь"),
	]
	pair_records = []
	for col, (file, name) in enumerate(paired):
		place(before_after, draw, file, name, name, col * 440, 0, 440, 385,
			GOBLIN_HEIGHT, 18, font_label, font_detail, pair_records)
	before_after.convert("RGB").save(ROOT / "before-after.png")
	for record in comparison_records + pair_records:
		expected_height = HERO_HEIGHT if record["file"] == "references/warrior11.png" else GOBLIN_HEIGHT
		if record["display_visible_height"] != expected_height:
			raise SystemExit("Rendered silhouette height mismatch")
	if any(r["display_bottom"] != 550 for r in comparison_records) or any(r["display_bottom"] != 385 for r in pair_records):
		raise SystemExit("Silhouette baseline mismatch")
	result = {"complete": True, "generations_sha256": manifest_sha, "briefs_sha256": briefs_sha,
		"references_manifest_sha256": refs_sha, "prompt_canonical_sha256": {str(v["id"]): v["prompt_sha256"] for v in variants},
		"alpha_threshold": THRESHOLD, "nearest_neighbor_presentation_only": True,
		"comparison_size": [1320, 640], "comparison_bottom_y": 550,
		"before_after_size": [1760, 450], "before_after_bottom_y": 385,
		"hero_display_height": HERO_HEIGHT, "goblin_display_height": GOBLIN_HEIGHT,
		"hero_to_goblin_ratio": HERO_HEIGHT / GOBLIN_HEIGHT,
		"comparison_records": comparison_records, "before_after_records": pair_records,
		"references": ref_records,
		"visible_edge_flags": sorted({r["file"] for r in comparison_records + pair_records if r["flags"]}),
		"raw_variant_shas_unique": True, "all_source_pngs_unchanged": True,
		"scope": "Presentation-only NN scale fit; alpha>=8 defines visible height. No runtime/integration or art-quality claim."}
	(ROOT / "validation.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
	print(json.dumps({"complete": True, "variant_ids": [v["id"] for v in variants],
		"comparison": [1320, 640], "before_after": [1760, 450],
		"crooked_fang_height": comparison_records[0]["visible_native_height"],
		"heavy_brow_height": comparison_records[2]["visible_native_height"]}, ensure_ascii=False))


if __name__ == "__main__":
	main()
