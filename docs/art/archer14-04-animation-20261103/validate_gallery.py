"""Проверяет автономные base64-ассеты HTML и ссылки на все клипы."""
from pathlib import Path
import base64
import json
import re

ROOT = Path(__file__).resolve().parent


def main() -> None:
	html = (ROOT / "gallery.html").read_text(encoding="utf-8")
	match = re.search(r"const ASSETS=(\{.*?\});const CLIPS=(\[.*?\]);const LABELS=", html, re.DOTALL)
	if not match:
		raise SystemExit("Missing embedded asset and clip tables")
	assets, clips = json.loads(match[1]), json.loads(match[2])
	requests = json.loads((ROOT / "requests.json").read_text(encoding="utf-8"))
	expected_assets = 2 + 2 * len(requests)
	expected_model = {"model/source-full.png", "model/input-256.png"}
	errors = []
	if len(assets) != expected_assets or len(clips) != len(requests):
		errors.append("asset or clip count")
	if not expected_model.issubset(assets):
		errors.append("missing full-source or prepared model image")
	for key, data_url in assets.items():
		if not key.startswith(("model/", "pixellab/")) or not data_url.startswith("data:image/"):
			errors.append(f"invalid embedded asset {key}")
			continue
		try:
			raw = base64.b64decode(data_url.split(",", 1)[1], validate=True)
		except Exception:
			errors.append(f"bad base64 {key}")
			continue
		asset_path = ROOT / key
		if not asset_path.is_file() or raw != asset_path.read_bytes():
			errors.append(f"embedded payload mismatch {key}")
	for row, clip in zip(requests, clips):
		if (clip["key"] != row["key"] or clip["kind"] != row["kind"]
				or clip["count"] != row["expected_frames"] or len(clip["timing"]) != clip["count"]
				or clip["loop"] != (row["kind"] == "idle")
				or clip["sheet"] not in assets or clip["gif"] not in assets):
			errors.append(f"clip references or playback settings {row['key']}")
	for text in ("file://", 'src="pixellab/', 'src="model/', "https://", "http://"):
		if text in html:
			errors.append(f"external dependency {text}")
	for required in ("Ожидание зациклено", "удерживают последний кадр", "data-slider", "__galleryState"):
		if required not in html:
			errors.append(f"missing playback feature marker {required}")
	report = {
		"pass": not errors, "clips": len(clips), "embedded_assets": len(assets),
		"expected_embedded_assets": expected_assets,
		"payloads_byte_equal": len(assets) - len([error for error in errors if error.startswith("embedded payload mismatch")]),
		"html_bytes": (ROOT / "gallery.html").stat().st_size, "errors": errors,
		"meaning": "Embedded-payload and link check; browser visual check is separate",
	}
	(ROOT / "gallery-validation.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
	print(json.dumps(report, ensure_ascii=False))
	if errors:
		raise SystemExit(1)


if __name__ == "__main__":
	main()
