"""Проверяет packaged PNG и собирает ростовой лист из пяти Костяшей и Воина."""
from pathlib import Path
import hashlib
import json

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
BG = (24, 33, 49, 255)
ALPHA_THRESHOLD = 8
HERO_HEIGHT = 456
GOBLIN_HEIGHT = 304


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
	alpha = image.getchannel("A")
	full, visible = alpha.getbbox(), alpha.point(lambda a: 255 if a >= ALPHA_THRESHOLD else 0).getbbox()
	return ([*full] if full else None, [*visible] if visible else None)


def fit(image: Image.Image, target: int) -> tuple[Image.Image, list[int], int]:
	_, body = boxes(image)
	if body is None:
		raise ValueError("no visible body at alpha>=8")
	padded = (max(0, body[0] - 4), max(0, body[1] - 4), min(image.width, body[2] + 4), min(image.height, body[3] + 4))
	crop = image.crop(padded)
	native_h = body[3] - body[1]
	preferred = round(crop.height * target / native_h)
	for h in sorted(range(max(1, preferred - 3), preferred + 4), key=lambda v: (abs(v - preferred), v)):
		w = max(1, round(crop.width * h / crop.height))
		candidate = crop.resize((w, h), Image.Resampling.NEAREST)
		_, visible = boxes(candidate)
		if visible and visible[3] - visible[1] == target:
			return candidate, visible, native_h
	raise ValueError(f"unable to fit visible body to {target}px within search ±3")


def open_png(path: Path) -> Image.Image:
	with Image.open(path) as image:
		image.load()
		if image.format != "PNG" or image.mode != "RGBA":
			raise SystemExit(f"Expected packaged RGBA PNG: {path}")
		return image.copy()


def place(sheet: Image.Image, draw: ImageDraw.ImageDraw, file: str, name: str,
		cell: int, baseline: int, target: int, label_y: int, label_font, detail_font,
		records: list[dict]) -> None:
	path = ROOT / file
	before = sha(path.read_bytes())
	image = open_png(path)
	alpha_box, visible = boxes(image)
	if visible is None:
		raise SystemExit(f"No visible body: {file}")
	margins = [visible[0], visible[1], image.width - visible[2], image.height - visible[3]]
	flags = ["visible_margin_under_8px"] if min(margins) < 8 else []
	try:
		presentation, rendered, native = fit(image, target)
	except ValueError as exc:
		raise SystemExit(f"Could not fit {file}: {exc}") from exc
	visible_w = rendered[2] - rendered[0]
	left = cell * 440 + (440 - visible_w) // 2
	image_x = left - rendered[0]
	image_y = baseline - rendered[3]
	if left < cell * 440 or left + visible_w > (cell + 1) * 440 or image_y + rendered[1] < (0 if baseline == 550 else 640):
		raise SystemExit(f"Silhouette does not fit its cell: {file}")
	sheet.alpha_composite(presentation, (image_x, image_y))
	draw.text((cell * 440 + 220, label_y), name, font=label_font, fill="#f4d18e", anchor="mt")
	draw.text((cell * 440 + 220, label_y + 24), "⅔ высоты Воина" if target == GOBLIN_HEIGHT else "Эталон масштаба",
		font=detail_font, fill="#ffb6a6" if flags else "#c8d2dd", anchor="mt")
	if sha(path.read_bytes()) != before:
		raise SystemExit(f"Source PNG changed while composing: {file}")
	records.append({"file": file, "name": name, "sha256": before, "native_size": list(image.size),
		"alpha_bbox": alpha_box, "visible_bbox_alpha_ge_8": visible, "visible_native_height": native,
		"visible_margins_ltrb": margins, "flags": flags, "display_visible_height": target,
		"display_bottom": baseline, "presentation_scale": target / native, "raw_sha_unchanged": True})


def main() -> None:
	manifest_path = ROOT / "generations.json"
	manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
	variants = manifest.get("variants")
	if manifest.get("complete") is not True or manifest.get("expected") != 5 or not isinstance(variants, list) or [v.get("id") for v in variants] != list(range(1, 6)):
		raise SystemExit("generations.json must be complete with variant IDs 1 through 5")
	briefs_path = ROOT / "briefs.json"
	briefs = json.loads(briefs_path.read_text(encoding="utf-8-sig"))
	brief_map = {v["id"]: v for v in briefs.get("variants", [])}
	if len(brief_map) != 5:
		raise SystemExit("briefs.json must contain five variants")
	refs_path = ROOT / "references.json"
	refs = json.loads(refs_path.read_text(encoding="utf-8-sig"))
	ref_map = {v["file"]: v for v in refs}
	required_refs = ("references/crooked-fang.png", "references/heavy-brow.png", "references/warrior11.png")
	ref_info = {}
	for file in required_refs:
		if file not in ref_map:
			raise SystemExit(f"Missing packaged reference {file}")
		path = ROOT / file
		if sha(path.read_bytes()) != ref_map[file].get("sha256"):
			raise SystemExit(f"Reference SHA mismatch: {file}")
		image = open_png(path)
		alpha, visible = boxes(image)
		if alpha is None or visible is None:
			raise SystemExit(f"Reference has empty silhouette: {file}")
		ref_info[file] = {"sha256": ref_map[file]["sha256"], "size": list(image.size), "alpha_bbox": alpha,
			"visible_bbox_alpha_ge_8": visible}
	if len({v.get("sha256") for v in variants}) != 5:
		raise SystemExit("Generated variant PNG SHAs must be unique")
	for row in variants:
		brief = brief_map.get(row["id"])
		if not brief or any(row.get(k) != brief.get(k) for k in ("name", "focus", "file", "prompt_file")):
			raise SystemExit(f"Generation record differs from brief: {row.get('id')}")
		path = ROOT / row["file"]
		if sha(path.read_bytes()) != row.get("sha256"):
			raise SystemExit(f"Variant PNG SHA mismatch: {path}")
		image = open_png(path)
		alpha, visible = boxes(image)
		if alpha is None or visible is None or row.get("alpha_bbox") != alpha or row.get("visible_bbox") != visible or list(image.getchannel("A").getextrema()) != row.get("alpha_extrema"):
			raise SystemExit(f"Variant alpha metadata mismatch: {path}")
		if list(image.size) != row.get("size") or image.mode != row.get("mode"):
			raise SystemExit(f"Variant dimensions/mode mismatch: {path}")
		if canonical_sha(ROOT / row["prompt_file"]) != row.get("prompt_sha256"):
			raise SystemExit(f"Canonical prompt SHA mismatch: {row['prompt_file']}")

	comparison = Image.new("RGBA", (1320, 1280), BG)
	draw = ImageDraw.Draw(comparison)
	draw.line((18, 550, 1302, 550), fill="#4e6179", width=2)
	draw.line((18, 1190, 1302, 1190), fill="#4e6179", width=2)
	records = []
	warrior = "references/warrior11.png"
	row1 = [(0, variants[0]["file"], "01 · " + variants[0]["name"]), (1, warrior, "Воин 11"), (2, variants[1]["file"], "02 · " + variants[1]["name"])]
	row2 = [(0, variants[2]["file"], "03 · " + variants[2]["name"]), (1, variants[3]["file"], "04 · " + variants[3]["name"]), (2, variants[4]["file"], "05 · " + variants[4]["name"])]
	for row_num, entries in enumerate((row1, row2)):
		baseline = 550 if row_num == 0 else 1190
		top = row_num * 640
		for col, file, name in entries:
			target = HERO_HEIGHT if file == warrior else GOBLIN_HEIGHT
			place(comparison, draw, file, name, col, baseline, target, top + 25,
				font(21), font(14), records)
	draw.text((22, 1242), "Пять развитий новой прорисовки · Костяши — ⅔ роста воина", font=font(23), fill="#f4d18e")
	comparison.convert("RGB").save(ROOT / "comparison.png")
	for record in records:
		if record["display_visible_height"] != (HERO_HEIGHT if record["file"] == warrior else GOBLIN_HEIGHT):
			raise SystemExit("Visible height does not match the requested 3:2 scale")
	result = {"complete": True, "generation_manifest_sha256": canonical_sha(manifest_path),
		"briefs_sha256": canonical_sha(briefs_path), "references_manifest_sha256": canonical_sha(refs_path),
		"prompt_canonical_sha256": {str(v["id"]): v["prompt_sha256"] for v in variants},
		"reference_checks": ref_info, "alpha_threshold": ALPHA_THRESHOLD,
		"nearest_neighbor_presentation_only": True, "comparison_size": [1320, 1280],
		"row_baselines": [550, 1190], "hero_display_height": HERO_HEIGHT,
		"kostyash_display_height": GOBLIN_HEIGHT, "hero_to_kostyash_ratio": HERO_HEIGHT / GOBLIN_HEIGHT,
		"records": records, "visible_edge_flags": [r["file"] for r in records if r["flags"]],
		"all_source_pngs_unchanged": True, "raw_variant_shas_unique": True,
		"scope": "Presentation-only nearest-neighbor scale fit; alpha>=8 determines visible body. It does not change packaged pixels or assert runtime dimensions."}
	(ROOT / "validation.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
	print(json.dumps({"complete": True, "variants": 5, "comparison": [1320, 1280],
		"visible_heights": [r["visible_native_height"] for r in records if r["file"] != warrior],
		"baselines": [550, 1190], "ratio": HERO_HEIGHT / GOBLIN_HEIGHT}, ensure_ascii=False))


if __name__ == "__main__":
	main()
