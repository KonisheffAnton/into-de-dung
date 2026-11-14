"""Проверяет provenance, исходные PNG, контактные листы и встроенную галерею."""
from pathlib import Path
import base64
import hashlib
import json
import re

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[2]
RUNTIME_REFERENCE = REPO / "assets/art_presets/approved/character_skins_v1/red_bastion/still.png"


def sha(data: bytes) -> str:
	return hashlib.sha256(data).hexdigest()


def main() -> None:
	requests_path = ROOT / "requests.json"
	rows = json.loads(requests_path.read_text(encoding="utf-8-sig"))
	manifest_path = ROOT / "sources.json"
	if not manifest_path.is_file():
		raise SystemExit("Missing sources.json; run export_pixellab.py")
	manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
	if not manifest.get("complete") or manifest.get("expected") != 10 or len(manifest.get("variants", [])) != 10:
		raise SystemExit("Expected ten completed admitted PixelLab originals")
	if manifest.get("request_manifest_sha256") != sha(requests_path.read_text(encoding="utf-8-sig").encode("utf-8")):
		raise SystemExit("requests.json provenance SHA mismatch")
	ref_path = ROOT / manifest["style_reference"]
	ref_raw = ref_path.read_bytes()
	if sha(ref_raw) != manifest.get("style_reference_sha256") or ref_raw != RUNTIME_REFERENCE.read_bytes():
		raise SystemExit("Style reference SHA/runtime identity mismatch")
	with Image.open(ref_path) as ref_image:
		if ref_image.size != (256, 256) or ref_image.mode != "RGBA":
			raise SystemExit("Style reference must be 256x256 RGBA")
	variants = manifest["variants"]
	if [item.get("id") for item in variants] != list(range(1, 11)):
		raise SystemExit("Expected variants numbered 1 through 10")
	for item, row in zip(variants, rows):
		if item.get("name") != row.get("name"):
			raise SystemExit(f"Name differs from requests.json for variant {item.get('id')}")
		path = ROOT / item["file"]
		raw = path.read_bytes()
		if sha(raw) != item.get("sha256"):
			raise SystemExit(f"Exported PNG SHA mismatch: {path}")
		with Image.open(path) as image:
			if image.size != (256, 256) or image.mode != "RGBA":
				raise SystemExit(f"Expected 256x256 RGBA source PNG: {path}")
			alpha = np.asarray(image.getchannel("A"))
			bbox = image.getchannel("A").getbbox()
			if not np.any(alpha == 0) or not np.any(alpha > 0) or bbox is None:
				raise SystemExit(f"Source PNG must have transparent margin and visible subject: {path}")
			if list(image.getchannel("A").getextrema()) != item.get("alpha_extrema"):
				raise SystemExit(f"Alpha extrema mismatch: {path}")
			if list(bbox) != item.get("alpha_bbox"):
				raise SystemExit(f"Alpha bbox mismatch: {path}")
		if item.get("width") != 256 or item.get("height") != 256 or item.get("mode") != "RGBA":
			raise SystemExit(f"Manifest size/mode mismatch: {path}")
	if len(variants) != 10:
		raise SystemExit("Expected exactly ten concept PNGs")
	sheets = (("contact-sheet.png", (2560, 1200)),
		("contact-sheet-small.png", (1280, 600)), ("style-compare.png", (1024, 858)))
	for filename, expected_size in sheets:
		with Image.open(ROOT / filename) as image:
			if image.size != expected_size or image.mode != "RGB":
				raise SystemExit(f"Unexpected sheet size/mode: {filename}: {image.size}/{image.mode}")
	html_path = ROOT / "gallery.html"
	if not html_path.is_file():
		raise SystemExit("Missing gallery.html; run build_gallery.py")
	html = html_path.read_text(encoding="utf-8")
	assets_match = re.search(r"const ASSETS=(\{.*?\}),CARDS=", html, re.S)
	cards_match = re.search(r"CARDS=(\[.*?\]);const grid", html, re.S)
	if not assets_match or not cards_match:
		raise SystemExit("Could not parse embedded gallery assets/cards")
	assets = json.loads(assets_match.group(1))
	cards = json.loads(cards_match.group(1))
	if len(assets) != 11 or len(cards) != 10:
		raise SystemExit(f"Expected 10 concepts and their style reference, got {len(cards)} cards / {len(assets)} assets")
	for item in [*variants, {"file": manifest["style_reference"], "sha256": manifest["style_reference_sha256"]}]:
		data_url = assets.get(item["file"])
		match = re.fullmatch(r"data:image/png;base64,([A-Za-z0-9+/=]+)", data_url or "")
		if not match or base64.b64decode(match.group(1), validate=True) != (ROOT / item["file"]).read_bytes():
			raise SystemExit(f"Gallery embedded PNG differs from source: {item['file']}")
	if [card.get("id") for card in cards] != list(range(1, 11)) or [card.get("name") for card in cards] != [row["name"] for row in rows]:
		raise SystemExit("Gallery cards do not preserve all ten requested names/order")
	for sheetname in ("contact-sheet.png", "style-compare.png"):
		needle = "data:image/png;base64," + base64.b64encode((ROOT / sheetname).read_bytes()).decode("ascii")
		if needle not in html:
			raise SystemExit(f"Gallery does not embed {sheetname}")
	if "no-repeat" in html or "object-fit:cover" in html:
		raise SystemExit("Gallery must preserve source aspect ratio without cropping")
	result = {"complete": True, "concepts": 10, "source_pngs_verified": 10,
		"reference_matches_runtime": True, "embedded_images": len(assets),
		"contact_sheets": {name: list(size) for name, size in sheets},
		"scope": "Source and artifact integrity only; no art acceptance or game integration"}
	(ROOT / "validation.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
	print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
	main()
