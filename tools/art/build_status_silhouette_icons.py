#!/usr/bin/env python3
"""Строит проверяемый каталог силуэтных значков и компактную плашку наведения."""
from __future__ import annotations

import argparse
import hashlib
import io
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
PACKAGE = ROOT / "docs/art/status-icons-silhouette-20261108"
HOVER_PACKAGE = ROOT / "docs/art/status-hover04-color-20261108"
FRAMES = ROOT / "assets/art_presets/approved/status_icons_framed_v1"
OUT = ROOT / "assets/art_presets/approved/status_icons_silhouette_v1"


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def png(image: Image.Image) -> bytes:
    buffer = io.BytesIO()
    image.save(buffer, format="PNG", optimize=False, compress_level=9)
    return buffer.getvalue()


def build() -> dict[str, bytes]:
    receipts = json.loads((PACKAGE / "receipts.json").read_text(encoding="utf-8"))
    assert len(receipts) == 24, "expected 24 source receipts"
    outputs: dict[str, bytes] = {}
    records: list[dict[str, object]] = []
    for receipt in receipts:
        name = str(receipt["id"])
        source_rel = f"16/{name}.png"
        source_bytes = (PACKAGE / source_rel).read_bytes()
        assert digest(source_bytes) == receipt["sha256"], f"source receipt mismatch: {name}"
        source = Image.open(io.BytesIO(source_bytes)).convert("RGBA")
        assert source.size == (16, 16), f"invalid source size: {name}"
        outputs[source_rel] = source_bytes
        doubled = source.resize((32, 32), Image.Resampling.NEAREST)
        doubled_rel = f"32/{name}.png"
        outputs[doubled_rel] = png(doubled)
        for size, relative in ((16, source_rel), (32, doubled_rel)):
            frame_bytes = (FRAMES / f"frame-{size}.png").read_bytes()
            background = Image.open(io.BytesIO(frame_bytes)).convert("RGBA")
            icon = Image.open(io.BytesIO(outputs[relative])).convert("RGBA")
            composed = Image.alpha_composite(background, icon)
            framed_rel = f"framed/{size}/{name}.png"
            outputs[framed_rel] = png(composed)
            records.append({"id": name, "size": size, "source": f"{PACKAGE.relative_to(ROOT).as_posix()}/{source_rel}" if size == 16 else f"{OUT.relative_to(ROOT).as_posix()}/{relative}",
                            "source_sha256": digest(source_bytes) if size == 16 else digest(outputs[relative]),
                            "output": relative, "output_sha256": digest(outputs[relative]),
                            "framed_output": framed_rel, "framed_sha256": digest(outputs[framed_rel])})
    for size in (16, 32):
        outputs[f"framed/frame-{size}.png"] = (FRAMES / f"frame-{size}.png").read_bytes()

    hover_path = HOVER_PACKAGE / "after.png"
    hover_bytes = hover_path.read_bytes()
    hover_receipt = json.loads((HOVER_PACKAGE / "receipt.json").read_text(encoding="utf-8"))
    assert digest(hover_bytes) == hover_receipt["sha256"], "hover panel source receipt mismatch"
    hover = Image.open(io.BytesIO(hover_bytes)).convert("RGBA")
    assert hover.size == (128, 48)
    # Вырезаем заданные границы прозрачной рамки, сохраняя каждый пиксель переднего плана.
    outputs["hover-panel.png"] = png(hover.crop((1, 12, 127, 32)))
    manifest = {"source_package": PACKAGE.relative_to(ROOT).as_posix(), "hover_source": hover_path.relative_to(ROOT).as_posix(),
                "hover_source_sha256": digest(hover_bytes), "hover_crop_xyxy": [1, 12, 127, 32],
                "raw_16_copy": "byte-exact", "scale_32": "nearest exact 2x", "framing": "source-over existing approved frame PNGs",
                "icons": records}
    outputs["manifest.json"] = (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode()
    return outputs


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    outputs = build()
    for relative, data in outputs.items():
        target = OUT / relative
        if args.check:
            assert target.read_bytes() == data, f"changed/missing {relative}"
            if relative.endswith(".png"):
                settings = target.with_suffix(".png.import").read_text(encoding="utf-8")
                for setting in ("compress/mode=0", "mipmaps/generate=false", "process/fix_alpha_border=false", "process/premult_alpha=false"):
                    assert setting in settings.splitlines(), f"invalid import {relative}: {setting}"
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
    print(json.dumps({"mode": "check" if args.check else "write", "icons": 24, "sizes": [16, 32], "files": len(outputs)}))


if __name__ == "__main__":
    main()
