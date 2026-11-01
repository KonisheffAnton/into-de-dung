"""Проверяет автономность HTML и точность встроенных файлов."""
from pathlib import Path
import base64
import json
import re

ROOT = Path(__file__).resolve().parent


def main() -> None:
    html = (ROOT / "gallery.html").read_text(encoding="utf-8")
    match = re.search(r"const ASSETS=(\{.*?\});const CLIPS=(\[.*?\]);const LABELS=", html, re.DOTALL)
    if not match:
        raise SystemExit("Missing embedded asset/data tables")
    assets, clips = json.loads(match[1]), json.loads(match[2])
    errors = []
    if len(assets) != 20 or len(clips) != 9:
        errors.append("asset or clip count")
    for key, data_url in assets.items():
        if not key.startswith(("model/", "pixellab/")) or not data_url.startswith("data:image/"):
            errors.append(f"invalid embedded asset {key}")
            continue
        try:
            raw = base64.b64decode(data_url.split(",", 1)[1], validate=True)
        except Exception:
            errors.append(f"bad base64 {key}")
            continue
        if raw != (ROOT / key).read_bytes():
            errors.append(f"payload mismatch {key}")
    for clip in clips:
        if clip["sheet"] not in assets or clip["gif"] not in assets or clip["count"] != 33:
            errors.append(f"clip references {clip['key']}")
    for text in ("file://", "src=\"pixellab/", "src=\"model/"):
        if text in html:
            errors.append(f"external asset reference {text}")
    report = {"pass": not errors, "clips": len(clips), "embedded_assets": len(assets),
              "payloads_byte_equal": len(assets) - len([e for e in errors if e.startswith("payload mismatch")]),
              "html_bytes": (ROOT / "gallery.html").stat().st_size, "errors": errors,
              "meaning": "embedded payload/link checks; browser visual acceptance separate"}
    (ROOT / "gallery-validation.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False))
    if errors:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
