#!/usr/bin/env python3
"""Проверяет автономный HTML и декодирует каждый встроенный файл изображения."""
from __future__ import annotations

import argparse
import base64
import hashlib
import io
import json
import re
import sys
from collections import Counter
from pathlib import Path
from typing import Any

from PIL import Image

ROOT = Path(__file__).resolve().parent


class VerifyError(RuntimeError):
    pass


def extract_json(html: str, marker: str, next_marker: str) -> Any:
    start = html.find(marker)
    if start < 0:
        raise VerifyError(f"missing embedded declaration: {marker}")
    start += len(marker)
    end = html.find(next_marker, start)
    if end < 0:
        raise VerifyError(f"unterminated embedded declaration: {marker}")
    try:
        return json.loads(html[start:end])
    except Exception as exc:
        raise VerifyError(f"invalid JSON after {marker}: {exc}") from exc


def decode_image(key: str, item: dict[str, Any]) -> bytes:
    try:
        raw = base64.b64decode(item["base64"], validate=True)
    except Exception as exc:
        raise VerifyError(f"invalid base64: {key}: {exc}") from exc
    if len(raw) != item.get("bytes"):
        raise VerifyError(f"byte length mismatch: {key}")
    digest = hashlib.sha256(raw).hexdigest()
    if digest != item.get("sha256"):
        raise VerifyError(f"sha256 mismatch: {key}")
    source_root = ROOT.resolve()
    try:
        source_path = (source_root / key).resolve(strict=True)
    except OSError as exc:
        raise VerifyError(f"missing source asset: {key}: {exc}") from exc
    if not source_path.is_relative_to(source_root):
        raise VerifyError(f"source asset escapes ROOT: {key}")
    if not source_path.is_file():
        raise VerifyError(f"source asset is not a file: {key}")
    try:
        source = source_path.read_bytes()
    except OSError as exc:
        raise VerifyError(f"cannot read source asset: {key}: {exc}") from exc
    if raw != source:
        raise VerifyError(f"embedded bytes differ from source: {key}")
    try:
        image = Image.open(io.BytesIO(raw))
        image.load()
        if item.get("mime") == "image/gif":
            for frame in range(image.n_frames):
                image.seek(frame)
                image.load()
    except Exception as exc:
        raise VerifyError(f"image decode failed: {key}: {exc}") from exc
    return raw


def verify(html_path: Path) -> dict[str, Any]:
    if not html_path.is_file():
        raise VerifyError(f"HTML not found: {html_path}")
    html = html_path.read_text(encoding="utf-8")
    assets = extract_json(html, "const ASSETS=", ";\nconst DATA=")
    models = extract_json(html, "const DATA=", ";\nlet current=")
    if not isinstance(assets, dict) or len(assets) != 156:
        raise VerifyError(f"expected 156 embedded assets, got {len(assets) if isinstance(assets, dict) else 'non-object'}")
    if not isinstance(models, list) or len(models) != 6:
        raise VerifyError(f"expected 6 models, got {len(models) if isinstance(models, list) else 'non-array'}")

    kind_counts: Counter[str] = Counter()
    hashes: dict[str, str] = {}
    raw_bytes = 0
    for key, item in assets.items():
        if not isinstance(item, dict):
            raise VerifyError(f"invalid asset entry: {key}")
        if key.endswith("/spritesheet.png"):
            category = "spritesheet_png"
        elif key.endswith("/preview.gif"):
            category = "preview_gif"
        elif key.endswith("/input-256.png"):
            category = "input_png"
        elif key.endswith("/source-full.png"):
            category = "source_full_png"
        else:
            raise VerifyError(f"unexpected embedded asset key: {key}")
        raw = decode_image(key, item)
        raw_bytes += len(raw)
        kind_counts[category] += 1
        hashes[key] = hashlib.sha256(raw).hexdigest()

    expected = {"spritesheet_png": 72, "preview_gif": 72, "input_png": 6, "source_full_png": 6}
    if dict(kind_counts) != expected:
        raise VerifyError(f"asset counts mismatch: {dict(kind_counts)}")
    clips = 0
    ids: set[str] = set()
    for model in models:
        ids.add(model.get("id"))
        if len(model.get("clips", [])) != 12:
            raise VerifyError(f"model {model.get('id')} does not have 12 clips")
        for key_name in ("input", "source_full"):
            if model.get(key_name) not in assets:
                raise VerifyError(f"missing embedded model image: {model.get('id')} {key_name}")
        for clip in model["clips"]:
            clips += 1
            if clip.get("sheet") not in assets or clip.get("gif") not in assets:
                raise VerifyError(f"missing embedded clip image: {model.get('id')} {clip.get('kind')}")
            if len(clip.get("durations_ms", [])) != clip.get("actual_frames"):
                raise VerifyError(f"frame timing mismatch: {model.get('id')} {clip.get('kind')}")
    if ids != {"02", "05", "11", "12", "17", "18"} or clips != 72:
        raise VerifyError(f"model/clip set mismatch: ids={sorted(ids)} clips={clips}")

    required_runtime = (
        "URL.createObjectURL", "new Blob", "dataUrl(key)", "p.img.onerror",
        "modelImage.onerror", "[data-open-asset]", "requestAnimationFrame(tick)",
    )
    missing_runtime = [token for token in required_runtime if token not in html]
    if missing_runtime:
        raise VerifyError(f"missing portable runtime features: {missing_runtime}")
    if re.search(r"<(?:img|script|link)\b[^>]*(?:src|href)=[\"'](?:https?:|//)", html, re.I):
        raise VerifyError("HTML contains an external media/script/style URL")
    if re.search(r"\bfetch\s*\(|\bXMLHttpRequest\b|\bWebSocket\b", html):
        raise VerifyError("HTML contains a network loading API")

    return {
        "passed": True,
        "html": str(html_path),
        "html_bytes": html_path.stat().st_size,
        "model_count": len(models),
        "clips_per_model": 12,
        "clip_count": clips,
        "asset_count": len(assets),
        "asset_counts": dict(kind_counts),
        "decoded_asset_bytes": raw_bytes,
        "source_compared_count": len(assets),
        "sha256_by_asset": hashes,
        "browser_launched": False,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--html", type=Path, default=ROOT / "gallery.html")
    parser.add_argument("--report", type=Path, default=ROOT / "standalone-validation.json")
    parser.add_argument("--no-report", action="store_true",
                        help="verify only; do not write the validation report")
    args = parser.parse_args()
    try:
        report = verify(args.html)
    except VerifyError as exc:
        print(f"VERIFY FAILED: {exc}", file=sys.stderr)
        return 1
    if not args.no_report:
        report_path = args.report if args.report.is_absolute() else (Path.cwd() / args.report)
        report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: v for k, v in report.items() if k != "sha256_by_asset"}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
