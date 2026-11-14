"""Проверяет исходные PNG, геометрию пяти вариантов и автономную галерею."""
from pathlib import Path
import base64
import hashlib
import json
import re

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[2]


def sha(data: bytes) -> str:
	return hashlib.sha256(data).hexdigest()


def image_bbox(image: Image.Image) -> list[int] | None:
	box = image.getchannel("A").getbbox()
	return list(box) if box else None


def expected_flags(image: Image.Image) -> list[str]:
	box = image_bbox(image)
	if box is None:
		return ["empty_alpha"]
	height = box[3] - box[1]
	flags = []
	if not 130 <= height <= 140:
		flags.append("height_outside_130_140")
	if height >= 152:
		flags.append("not_shorter_than_warrior")
	if min(box[0], box[1], 256 - box[2], 256 - box[3]) < 8:
		flags.append("margin_under_8px")
	if not np.any(np.asarray(image.getchannel("A")) == 0):
		flags.append("no_transparency")
	return flags


def main() -> None:
	requests_path = ROOT / "requests.json"
	requests = json.loads(requests_path.read_text(encoding="utf-8-sig"))
	rows = requests.get("variants", [])
	input_source_path = ROOT / "input-source.json"
	input_source_sha = sha(input_source_path.read_text(encoding="utf-8-sig").encode("utf-8"))
	manifest = json.loads((ROOT / "sources.json").read_text(encoding="utf-8-sig"))
	if not manifest.get("complete") or len(rows) != 5 or len(manifest.get("variants", [])) != 5:
		raise SystemExit("Expected five completed variants")
	if [row.get("id") for row in rows] != list(range(1, 6)):
		raise SystemExit("Request IDs must be numbered 1 through 5")
	if manifest.get("request_manifest_sha256") != sha(requests_path.read_text(encoding="utf-8-sig").encode("utf-8")):
		raise SystemExit("Canonical LF request manifest SHA mismatch")
	if manifest.get("input_source_manifest_sha256") != input_source_sha:
		raise SystemExit("Canonical LF input-source manifest SHA mismatch")
	input_source = manifest["input_source"]
	source_path, warrior_path = ROOT / input_source["file"], ROOT / input_source["warrior_file"]
	if sha(source_path.read_bytes()) != input_source.get("sha256") or sha(warrior_path.read_bytes()) != input_source.get("warrior_sha256"):
		raise SystemExit("Source or Warrior SHA mismatch")
	previous_source = REPO / input_source["source_package"]
	if not previous_source.is_file() or previous_source.read_bytes() != source_path.read_bytes():
		raise SystemExit("Kostyash input differs from the prior selected source")
	with Image.open(source_path) as source_image, Image.open(warrior_path) as warrior_image:
		if source_image.size != (256, 256) or source_image.mode != "RGBA":
			raise SystemExit("Source Kostyash must be 256x256 RGBA")
		if warrior_image.size != (256, 256) or warrior_image.mode != "RGBA":
			raise SystemExit("Warrior reference must be 256x256 RGBA")
		source_box = image_bbox(source_image)
		if source_box != input_source.get("bbox") or source_box is None or source_box[3] - source_box[1] != input_source.get("height"):
			raise SystemExit("Source alpha bbox mismatch")
		if image_bbox(warrior_image) is None or image_bbox(warrior_image)[3] - image_bbox(warrior_image)[1] != input_source.get("warrior_height"):
			raise SystemExit("Warrior alpha-height mismatch")
	variants = manifest["variants"]
	if [item.get("id") for item in variants] != list(range(1, 6)):
		raise SystemExit("Expected variants numbered 1 through 5")
	for item, row in zip(variants, rows):
		if item.get("name") != row.get("name") or item.get("focus") != row.get("focus"):
			raise SystemExit(f"Variant identity differs from requests.json: {row.get('id')}")
		path = ROOT / item["file"]
		data = path.read_bytes()
		if sha(data) != item.get("sha256"):
			raise SystemExit(f"Variant SHA mismatch: {path}")
		with Image.open(path) as image:
			if image.size != (256, 256) or image.mode != "RGBA":
				raise SystemExit(f"Variant must remain original 256x256 RGBA: {path}")
			box = image_bbox(image)
			height = box[3] - box[1] if box else None
			flags = expected_flags(image)
		if item.get("bbox") != box or item.get("native_height") != height:
			raise SystemExit(f"Variant geometry metadata mismatch: {path}")
		if item.get("geometry_flags") != flags or item.get("geometry_pass") != (not flags) or item.get("needs_review") != bool(flags):
			raise SystemExit(f"Variant geometry status mismatch: {path}")
	sheets = {
		"contact-sheet.png": (1280, 290),
		"before-after-sheet.png": (2560, 286), "development-compare.png": (768, 572),
		"reference-strip.png": (1792, 290),
	}
	for name, size in sheets.items():
		with Image.open(ROOT / name) as sheet:
			if sheet.size != size or sheet.mode != "RGB":
				raise SystemExit(f"Unexpected sheet dimensions or mode: {name}")
	html_path = ROOT / "gallery.html"
	if not html_path.is_file():
		raise SystemExit("Missing gallery.html; run build_gallery.py")
	html = html_path.read_text(encoding="utf-8")
	assets_match = re.search(r"const ASSETS=(\{.*?\}),CARDS=", html, re.S)
	cards_match = re.search(r"CARDS=(\[.*?\]);let showVariant", html, re.S)
	if not assets_match or not cards_match:
		raise SystemExit("Could not read gallery asset/card manifests")
	assets, cards = json.loads(assets_match.group(1)), json.loads(cards_match.group(1))
	if len(assets) != 7 or len(cards) != 5:
		raise SystemExit(f"Expected five variants, source, and Warrior; got {len(cards)} cards / {len(assets)} images")
	expected_files = [input_source["file"], input_source["warrior_file"], *[item["file"] for item in variants]]
	if set(assets) != set(expected_files):
		raise SystemExit("Gallery embeds missing or unexpected source images")
	for name in expected_files:
		match = re.fullmatch(r"data:image/png;base64,([A-Za-z0-9+/=]+)", assets[name])
		if not match or base64.b64decode(match.group(1), validate=True) != (ROOT / name).read_bytes():
			raise SystemExit(f"Embedded source differs: {name}")
	if [card.get("id") for card in cards] != list(range(1, 6)):
		raise SystemExit("Gallery must have five numbered variant cards")
	for card, item in zip(cards, variants):
		if (card.get("name"), card.get("focus"), card.get("native_height"), card.get("needs_review")) != (
				item["name"], item["focus"], item["native_height"], item["needs_review"]):
			raise SystemExit(f"Gallery card metadata mismatch: {card.get('id')}")
	for name in sheets:
		data_url = "data:image/png;base64," + base64.b64encode((ROOT / name).read_bytes()).decode("ascii")
		if data_url not in html:
			raise SystemExit(f"Gallery does not embed {name}")
	if "width:min(70vh,80vw,768px)" not in html or "object-fit:cover" in html:
		raise SystemExit("Gallery modal must preserve square image aspect without cropping")
	result = {"complete": True, "variants": 5, "embedded_source_images": len(assets),
		"input_source_sha256": input_source["sha256"], "warrior_reference_sha256": input_source["warrior_sha256"],
		"geometry": [{"id": item["id"], "height": item["native_height"], "geometry_pass": item["geometry_pass"],
			"needs_review": item["needs_review"], "flags": item["geometry_flags"]} for item in variants],
		"sheets": {name: list(size) for name, size in sheets.items()},
		"scope": "Source and geometry integrity only; visual style acceptance remains human review"}
	(ROOT / "validation.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
	print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
	main()
