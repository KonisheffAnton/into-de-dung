"""Проверяет SHA, исходные пары, геометрию и полные встроенные ресурсы галереи."""
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


def canonical_file_sha(path: Path) -> str:
	return sha(path.read_text(encoding="utf-8-sig").encode("utf-8"))


def bbox(image: Image.Image) -> list[int] | None:
	box = image.getchannel("A").getbbox()
	return list(box) if box else None


def flags_for(image: Image.Image, source_height: int, warrior_height: int) -> list[str]:
	box = bbox(image)
	if box is None:
		return ["empty_alpha"]
	height = box[3] - box[1]
	flags = []
	if not 90 <= height <= 110:
		flags.append("height_outside_target_90_110")
	if not 80 <= height <= 112:
		flags.append("height_outside_technical_80_112")
	if height >= source_height:
		flags.append("not_shorter_than_prior")
	if height >= warrior_height:
		flags.append("not_shorter_than_warrior")
	if min(box[0], box[1], 160 - box[2], 128 - box[3]) < 8:
		flags.append("margin_under_8px")
	if not np.any(np.asarray(image.getchannel("A")) == 0):
		flags.append("no_transparency")
	return flags


def main() -> None:
	requests_path, source_path = ROOT / "requests.json", ROOT / "input-source.json"
	requests, inputs = json.loads(requests_path.read_text(encoding="utf-8-sig")), json.loads(source_path.read_text(encoding="utf-8-sig"))
	rows, input_records = requests.get("variants", []), inputs.get("sources", [])
	if len(rows) != 5 or [x.get("id") for x in rows] != list(range(1, 6)) or len(input_records) != 5:
		raise SystemExit("Expected five numbered request/source records")
	manifest_path = ROOT / "sources.json"
	if not manifest_path.is_file():
		raise SystemExit("Missing sources.json; run export_pixellab.py")
	manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
	if not manifest.get("complete") or len(manifest.get("variants", [])) != 5:
		raise SystemExit("Expected five completed exports")
	if manifest.get("request_manifest_sha256") != canonical_file_sha(requests_path) or manifest.get("input_source_manifest_sha256") != canonical_file_sha(source_path):
		raise SystemExit("Canonical LF manifest SHA mismatch")
	selection_path = ROOT / "selection.json"
	selection_manifest = json.loads(selection_path.read_text(encoding="utf-8-sig"))
	if manifest.get("selection_manifest_sha256") != canonical_file_sha(selection_path):
		raise SystemExit("Canonical LF selection manifest SHA mismatch")
	if manifest.get("input_sources") != inputs:
		raise SystemExit("Export input-source provenance differs from current manifest")
	warrior = ROOT / inputs["warrior_file"]
	if sha(warrior.read_bytes()) != inputs.get("warrior_sha256"):
		raise SystemExit("Warrior SHA mismatch")
	with Image.open(warrior) as im:
		if im.size != (256, 256) or im.mode != "RGBA" or not bbox(im) or bbox(im)[3] - bbox(im)[1] != inputs["warrior_height"]:
			raise SystemExit("Warrior reference geometry mismatch")
	items = manifest["variants"]
	selections = selection_manifest.get("variants", [])
	if len(selections) != 5 or selection_manifest.get("returned_per_job") != 4:
		raise SystemExit("Expected a five-entry selection across four outputs per job")
	for row, source, item, selection in zip(rows, input_records, items, selections):
		if item.get("id") != row["id"] or item.get("name") != row["name"] or item.get("focus") != row.get("focus"):
			raise SystemExit(f"Variant identity mismatch: {row['id']}")
		before = ROOT / source["file"]
		if not before.is_file() or sha(before.read_bytes()) != source["sha256"]:
			raise SystemExit(f"Prior variant source bytes mismatch: {row['id']}")
		with Image.open(before) as im:
			if im.size != (256, 256) or im.mode != "RGBA" or bbox(im) != source["bbox"] or bbox(im)[3] - bbox(im)[1] != source["height"]:
				raise SystemExit(f"Source geometry mismatch: {row['id']}")
		path = ROOT / item["file"]
		data = path.read_bytes()
		if sha(data) != item.get("sha256"):
			raise SystemExit(f"Variant SHA mismatch: {path}")
		generated_path = ROOT / item.get("generated_file", "")
		if not generated_path.is_file() or sha(generated_path.read_bytes()) != item.get("generated_sha256"):
			raise SystemExit(f"Primary generated PNG SHA mismatch: {generated_path}")
		outputs = item.get("generation_outputs", [])
		if len(outputs) != 4:
			raise SystemExit(f"Expected four preserved generation candidates: {row['id']}")
		for candidate in outputs:
			candidate_path = ROOT / candidate["candidate_file"]
			if not candidate_path.is_file() or sha(candidate_path.read_bytes()) != candidate.get("sha256"):
				raise SystemExit(f"Provider candidate bytes/hash mismatch: {row['id']} / {candidate.get('index')}")
		choice = selection.get("output_index")
		if (item.get("selected_output_index"), item.get("selected_output_name"), item.get("generated_sha256")) != (choice, selection.get("output_name"), selection.get("sha256")) or not 0 <= choice < 4 or outputs[choice].get("file") != selection.get("output_name") or outputs[choice].get("sha256") != selection.get("sha256") or outputs[choice].get("candidate_file") != selection.get("candidate_file") or generated_path.read_bytes() != (ROOT / selection["candidate_file"]).read_bytes():
			raise SystemExit(f"Selection manifest does not identify generated candidate: {row['id']}")
		cleanup = item.get("cleanup")
		if cleanup:
			cleanup_rows = json.loads((ROOT / "cleanup.json").read_text(encoding="utf-8-sig")).get("variants", [])
			cleanup_rows = [x for x in cleanup_rows if x.get("id") == row["id"]]
			if len(cleanup_rows) != 1:
				raise SystemExit(f"Cleanup mapping is missing or duplicated: {row['id']}")
			public_cleanup = cleanup_rows[0]
			if (sha(data) != cleanup.get("output_sha256") or sha(data) != public_cleanup.get("output_sha256")
					or sha(generated_path.read_bytes()) != cleanup.get("input_sha256")
					or cleanup.get("input_sha256") != public_cleanup.get("input_sha256")
					or public_cleanup.get("input_file") != item.get("generated_file")
					or cleanup.get("endpoint") != public_cleanup.get("endpoint")
					or cleanup.get("usage") != public_cleanup.get("usage")):
				raise SystemExit(f"Final PNG does not match mapped cleanup result: {row['id']}")
		else:
			if data != generated_path.read_bytes():
				raise SystemExit(f"No-cleanup final PNG differs from generated raw: {row['id']}")
		with Image.open(path) as im:
			if im.size != (160, 128) or im.mode != "RGBA":
				raise SystemExit(f"Variant must remain raw 160x128 RGBA: {path}")
			box, a = bbox(im), im.getchannel("A")
			if not box:
				raise SystemExit(f"Variant alpha is empty: {path}")
			height = box[3] - box[1]
			flags = flags_for(im, source["height"], inputs["warrior_height"])
		if item.get("source_file") != source["file"] or item.get("source_height") != source["height"] or item.get("bbox") != box or item.get("native_height") != height:
			raise SystemExit(f"Variant geometry/provenance metadata mismatch: {path}")
		preview_path = ROOT / item["preview_file"]
		preview_data = preview_path.read_bytes()
		if sha(preview_data) != item.get("preview_sha256"):
			raise SystemExit(f"Preview SHA mismatch: {preview_path}")
		with Image.open(path) as raw_image, Image.open(preview_path) as preview:
			offset = item.get("preview_offset")
			if raw_image.size != (160, 128) or preview.size != (256, 256) or preview.mode != "RGBA" or not isinstance(offset, list) or len(offset) != 2:
				raise SystemExit(f"Raw/preview dimensions mismatch: {item['id']}")
			expected_offset = [48, source["bbox"][3] - box[3]]
			if offset != expected_offset or offset[1] < 0 or offset[0] + 160 > 256 or offset[1] + 128 > 256:
				raise SystemExit(f"Feet-aligned raw offset mismatch or clipping: {item['id']}")
			crop = preview.crop((offset[0], offset[1], offset[0] + 160, offset[1] + 128))
			if crop.tobytes() != raw_image.tobytes():
				raise SystemExit(f"Preview does not contain exact raw RGBA pixels: {item['id']}")
			outside = preview.copy()
			outside.paste((0, 0, 0, 0), (offset[0], offset[1], offset[0] + 160, offset[1] + 128))
			if np.any(np.asarray(outside.getchannel("A")) != 0):
				raise SystemExit(f"Preview has unexpected pixels outside centered raw image: {item['id']}")
			preview_box = bbox(preview)
			if preview_box != [box[0] + offset[0], box[1] + offset[1], box[2] + offset[0], box[3] + offset[1]]:
				raise SystemExit(f"Preview bbox/offset mismatch: {item['id']}")
		if item.get("height_delta") != height - source["height"] or item.get("shrink_percent") != round((source["height"] - height) * 100 / source["height"], 2):
			raise SystemExit(f"Variant shrink metadata mismatch: {path}")
		if item.get("geometry_flags") != flags or item.get("geometry_pass") != (not flags) or item.get("needs_review") != bool(flags):
			raise SystemExit(f"Variant geometry flag mismatch: {path}")
		if not np.any(np.asarray(a) == 0):
			raise SystemExit(f"Variant has no transparent canvas: {path}")
	sheet_sizes = {"contact-sheet.png": (1280, 290), "before-after-sheet.png": (1280, 568), "reference-strip.png": (1536, 290), "showcase.png": (1600, 290)}
	for filename, size in sheet_sizes.items():
		with Image.open(ROOT / filename) as im:
			if im.size != size or im.mode != "RGB":
				raise SystemExit(f"Unexpected sheet dimensions/mode: {filename}")
	html_path = ROOT / "gallery.html"
	if not html_path.is_file():
		raise SystemExit("Missing gallery.html; run build_gallery.py")
	html = html_path.read_text(encoding="utf-8")
	match = re.search(r"const ASSETS=(\{.*?\}),RAW=", html, re.S)
	raw_match = re.search(r"RAW=(\{.*?\}),CARDS=", html, re.S)
	cards_match = re.search(r"CARDS=(\[.*?\]),SOURCES=", html, re.S)
	if not match or not raw_match or not cards_match:
		raise SystemExit("Could not parse embedded gallery asset/card manifests")
	assets, raw_assets, cards = json.loads(match.group(1)), json.loads(raw_match.group(1)), json.loads(cards_match.group(1))
	expected = [*(x["file"] for x in input_records), *(x["preview_file"] for x in items), inputs["warrior_file"]]
	if len(assets) != 11 or set(assets) != set(expected) or len(raw_assets) != 5 or set(raw_assets) != {x["file"] for x in items} or len(cards) != 5:
		raise SystemExit(f"Expected 11 preview embeds, five raw downloads and five cards; found {len(assets)} / {len(raw_assets)} / {len(cards)}")
	for name in expected:
		m = re.fullmatch(r"data:image/png;base64,([A-Za-z0-9+/=]+)", assets[name])
		if not m or base64.b64decode(m.group(1), validate=True) != (ROOT / name).read_bytes():
			raise SystemExit(f"Embedded PNG mismatch: {name}")
	for item in items:
		m = re.fullmatch(r"data:image/png;base64,([A-Za-z0-9+/=]+)", raw_assets[item["file"]])
		if not m or base64.b64decode(m.group(1), validate=True) != (ROOT / item["file"]).read_bytes():
			raise SystemExit(f"Raw download bytes mismatch: {item['file']}")
	for card, item in zip(cards, items):
		for key in ("id", "name", "focus", "file", "preview_file", "source_file", "source_height", "native_height", "height_delta", "shrink_percent", "needs_review", "geometry_flags"):
			if card.get(key) != item.get(key):
				raise SystemExit(f"Gallery card metadata mismatch: {item['id']} / {key}")
	for filename in sheet_sizes:
		encoded = "data:image/png;base64," + base64.b64encode((ROOT / filename).read_bytes()).decode("ascii")
		if encoded not in html:
			raise SystemExit(f"Gallery does not embed {filename}")
	if "width:min(70vh,80vw,768px)" not in html or "object-fit:cover" in html:
		raise SystemExit("Modal must preserve aspect ratio without cropping")
	result = {"complete": True, "variants": 5, "embedded_gallery_images": 11, "raw_downloads": 5,
		"warrior_sha256": inputs["warrior_sha256"], "geometry": [{"id": x["id"], "source_height": x["source_height"],
		"height": x["native_height"], "shrink_percent": x["shrink_percent"], "needs_review": x["needs_review"], "flags": x["geometry_flags"]} for x in items],
		"sheets": {name: list(size) for name, size in sheet_sizes.items()}, "raw_images_unmodified": True,
		"generation_outputs": [{"id": x["id"], "count": len(x.get("generation_outputs", [])), "selected_index": x["selected_output_index"], "generated_sha256": x["generated_sha256"]} for x in items],
		"cleanup_ids": [x["id"] for x in items if x.get("cleanup")],
		"scope": "Generated and optional cleanup PNG provenance plus geometry flags, exact translated 160x128-to-256 preview pixels, and embedded-gallery integrity; geometry/style acceptance remains human review"}
	(ROOT / "validation.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
	print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
	main()
