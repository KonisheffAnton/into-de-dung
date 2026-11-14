"""Проверяет PNG-провенанс, ground-line padding и автономную галерею."""
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
	manifest = json.loads((ROOT / "sources.json").read_text(encoding="utf-8-sig"))
	if not manifest.get("complete") or manifest.get("expected") != 10 or len(manifest.get("variants", [])) != 10:
		raise SystemExit("Expected ten completed final 192x128 concepts")
	canonical_manifest_sha = sha(requests_path.read_text(encoding="utf-8-sig").encode("utf-8"))
	if manifest.get("request_manifest_sha256") != canonical_manifest_sha:
		raise SystemExit("Canonical LF requests manifest SHA mismatch")
	if manifest.get("raw_size") != [192, 128] or manifest.get("display_size") != [256, 256] or manifest.get("groundline_y") != 200:
		raise SystemExit("Unexpected raw/display canvas contract")
	ref_path = ROOT / manifest["style_reference"]
	ref_raw = ref_path.read_bytes()
	if sha(ref_raw) != manifest.get("style_reference_sha256") or ref_raw != RUNTIME_REFERENCE.read_bytes():
		raise SystemExit("Style reference does not match runtime Warrior PNG")
	with Image.open(ref_path) as ref:
		if ref.size != (256, 256) or ref.mode != "RGBA":
			raise SystemExit("Reference must be 256x256 RGBA")
		ref_bbox = ref.getchannel("A").getbbox()
		if ref_bbox is None or ref_bbox[3] - ref_bbox[1] != 152:
			raise SystemExit("Warrior native alpha silhouette must measure 152px")
	variants = manifest["variants"]
	if [item.get("id") for item in variants] != list(range(1, 11)) or len(rows) != 10:
		raise SystemExit("Expected ten variants numbered 1 through 10")
	for item, row in zip(variants, rows):
		if (item.get("name") != row.get("name") or item.get("request_sha256") == ""
				or row.get("image_size") != {"width": 192, "height": 128}):
			raise SystemExit(f"Request/source metadata mismatch for variant {item.get('id')}")
		raw_path, display_path = ROOT / item["file"], ROOT / item["display_file"]
		raw_bytes = raw_path.read_bytes()
		if sha(raw_bytes) != item.get("sha256") or item.get("sha256") != item.get("original_sha256"):
			raise SystemExit(f"Original source PNG SHA mismatch: {raw_path}")
		with Image.open(raw_path) as source:
			if source.size != (192, 128) or source.mode != "RGBA":
				raise SystemExit(f"Raw source must be 192x128 RGBA: {raw_path}")
			raw = source.copy()
		alpha = raw.getchannel("A")
		bbox = alpha.getbbox()
		alpha_values = np.asarray(alpha)
		if bbox is None or not np.any(alpha_values == 0) or not np.any(alpha_values > 0):
			raise SystemExit(f"Raw source must have transparent margin and visible pixels: {raw_path}")
		height = bbox[3] - bbox[1]
		if height > 128 or height >= 152 or not item.get("shorter_than_warrior"):
			raise SystemExit(f"Silhouette is not within the shorter-than-Warrior contract: {raw_path} ({height}px)")
		edge_sides = [side for side, touched in (("left", bbox[0] == 0), ("top", bbox[1] == 0),
			("right", bbox[2] == 192), ("bottom", bbox[3] == 128)) if touched]
		margin_violation = bbox[0] < 8 or bbox[1] < 8 or bbox[2] > 184 or bbox[3] > 120
		if item.get("edge_sides") != edge_sides or item.get("margin_violation") != margin_violation:
			raise SystemExit(f"Raw edge/margin diagnostic mismatch: {raw_path}")
		if item.get("native_alpha_height") != height or item.get("alpha_bbox") != list(bbox):
			raise SystemExit(f"Native silhouette metadata mismatch: {raw_path}")
		if list(alpha.getextrema()) != item.get("alpha_extrema"):
			raise SystemExit(f"Raw alpha extrema mismatch: {raw_path}")
		offset = item.get("paste_offset")
		if offset != [32, 200 - bbox[3]] or item.get("groundline_y") != 200:
			raise SystemExit(f"Display paste offset does not align the baseline: {item['id']}")
		with Image.open(display_path) as padded:
			if padded.size != (256, 256) or padded.mode != "RGBA":
				raise SystemExit(f"Display image must be 256x256 RGBA: {display_path}")
			if sha(display_path.read_bytes()) != item.get("display_sha256"):
				raise SystemExit(f"Display PNG SHA mismatch: {display_path}")
			expected = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
			expected.paste(raw, tuple(offset))
			if padded.tobytes() != expected.tobytes():
				raise SystemExit(f"Display differs from unscaled raw padding: {display_path}")
			crop = padded.crop((offset[0], offset[1], offset[0] + 192, offset[1] + 128))
			if crop.tobytes() != raw.tobytes():
				raise SystemExit(f"Raw crop does not exactly match padded display: {display_path}")
			outside_alpha = np.asarray(padded.getchannel("A")).copy()
			outside_alpha[offset[1]:offset[1] + 128, offset[0]:offset[0] + 192] = 0
			if np.any(outside_alpha):
				raise SystemExit(f"Visible pixels appear outside the padded source rectangle: {display_path}")
	sheets = {"contact-sheet.png": (2560, 1200), "contact-sheet-small.png": (1280, 600), "style-compare.png": (1024, 918)}
	for name, size in sheets.items():
		with Image.open(ROOT / name) as sheet:
			if sheet.size != size or sheet.mode != "RGB":
				raise SystemExit(f"Unexpected sheet format: {name} {sheet.size}/{sheet.mode}")
	html_path = ROOT / "gallery.html"
	if not html_path.is_file():
		raise SystemExit("Missing gallery.html; run build_gallery.py")
	html = html_path.read_text(encoding="utf-8")
	assets_match = re.search(r"const ASSETS=(\{.*?\}),CARDS=", html, re.S)
	cards_match = re.search(r"CARDS=(\[.*?\]);const grid", html, re.S)
	if not assets_match or not cards_match:
		raise SystemExit("Could not parse embedded gallery asset/card manifests")
	assets, cards = json.loads(assets_match.group(1)), json.loads(cards_match.group(1))
	if len(assets) != 21 or len(cards) != 10:
		raise SystemExit(f"Expected 20 raw/padded concepts plus reference; got {len(assets)} assets, {len(cards)} cards")
	for item in [*variants, {"file": manifest["style_reference"], "sha256": manifest["style_reference_sha256"]}]:
		for key in ("file", "display_file"):
			if key not in item:
				continue
			data_url = assets.get(item[key])
			match = re.fullmatch(r"data:image/png;base64,([A-Za-z0-9+/=]+)", data_url or "")
			if not match or base64.b64decode(match.group(1), validate=True) != (ROOT / item[key]).read_bytes():
				raise SystemExit(f"Gallery embedded image differs from source: {item[key]}")
	if [card.get("id") for card in cards] != list(range(1, 11)):
		raise SystemExit("Gallery card ordering differs from the ten variants")
	for card, item in zip(cards, variants):
		if card.get("height") != item["native_alpha_height"] or card.get("height") >= 152:
			raise SystemExit(f"Gallery native-height label mismatch: {card.get('id')}")
	for name in sheets:
		needle = "data:image/png;base64," + base64.b64encode((ROOT / name).read_bytes()).decode("ascii")
		if needle not in html:
			raise SystemExit(f"Gallery does not embed sheet {name}")
	if "width:min(70vh,80vw,768px)" not in html or "object-fit:cover" in html or "height:100%" in html:
		raise SystemExit("Modal must preserve image aspect ratio and avoid cropping")
	edge_ids = [item["id"] for item in variants if item["edge_sides"]]
	margin_ids = [item["id"] for item in variants if item["margin_violation"]]
	result = {"complete": True, "concepts": 10, "raw_pngs_verified": 10,
		"display_padding_verified": 10, "reference_matches_runtime": True,
		"reference_alpha_height": 152, "native_heights": [item["native_alpha_height"] for item in variants],
		"edge_contact_ids": edge_ids, "under_8px_margin_ids": margin_ids,
		"embedded_images": len(assets), "sheets": {name: list(size) for name, size in sheets.items()},
		"scope": "Artifact integrity and relative pixel-height only; no art acceptance or game integration"}
	(ROOT / "validation.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
	print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
	main()
