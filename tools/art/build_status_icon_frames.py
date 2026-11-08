#!/usr/bin/env python3
"""Подкладывает общий деревянно-железный фон под неизменённые значки A."""
from __future__ import annotations

import argparse
import hashlib
import io
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
PACKAGE = ROOT / "docs/art/status-icon-frame-20261108"
RAW = ROOT / "assets/art_presets/approved/status_icons_a_v1"
OUT = ROOT / "assets/art_presets/approved/status_icons_framed_v1"


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def encoded(image: Image.Image) -> bytes:
    buffer = io.BytesIO()
    image.save(buffer, format="PNG", optimize=False, compress_level=9)
    return buffer.getvalue()


def build() -> dict[str, bytes]:
    source_path = PACKAGE / "wood-iron-panel.png"
    source_bytes = source_path.read_bytes()
    receipt = json.loads((PACKAGE / "fill-result.json").read_text())
    assert digest(source_bytes) == receipt["output_sha256"], "PixelLab panel changed"
    panel = Image.open(io.BytesIO(source_bytes)).convert("RGBA")
    assert panel.size == (32, 32), "expected native 32px panel"
    assert panel.getchannel("A").getextrema() == (255, 255), "wood must be opaque"
    raw_manifest = json.loads((RAW / "manifest.json").read_text(encoding="utf-8"))
    assert len(raw_manifest["icons"]) == 24
    outputs: dict[str, bytes] = {}
    records: list[dict] = []
    for size in (16, 32):
        background = panel.resize((size, size), Image.Resampling.NEAREST)
        outputs[f"frame-{size}.png"] = encoded(background)
        for entry in raw_manifest["icons"]:
            name = entry["id"]
            relative = f"{size}/{name}.png"
            raw_bytes = (RAW / relative).read_bytes()
            assert digest(raw_bytes) == entry["outputs"][str(size)]["sha256"], relative
            icon = Image.open(io.BytesIO(raw_bytes)).convert("RGBA")
            assert icon.size == (size, size)
            # A остаётся верхним слоем без сдвига, масштабирования или замены цветов.
            framed = Image.alpha_composite(background, icon)
            foreground_bytes, final_bytes = icon.tobytes(), framed.tobytes()
            for offset in range(0, len(foreground_bytes), 4):
                if foreground_bytes[offset + 3] == 255:
                    assert foreground_bytes[offset:offset + 4] == final_bytes[offset:offset + 4], "opaque foreground must remain exact"
            outputs[relative] = encoded(framed)
            records.append({"id": name, "size": size, "source": (RAW / relative).relative_to(ROOT).as_posix(),
                            "source_sha256": digest(raw_bytes), "output": relative,
                            "output_sha256": digest(outputs[relative])})
    manifest = {"panel_source": source_path.relative_to(ROOT).as_posix(),
                "panel_source_sha256": digest(source_bytes), "resampling": "nearest (panel only)",
                "composition": "unchanged A source-over opaque panel; no offset or recoloring",
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
                settings = target.with_suffix(".png.import").read_text()
                for setting in ("compress/mode=0", "mipmaps/generate=false", "process/fix_alpha_border=false", "process/premult_alpha=false"):
                    assert setting in settings.splitlines(), f"invalid import {relative}: {setting}"
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
    print(json.dumps({"mode": "check" if args.check else "write", "framed_icons": 48, "panels": 2, "files": len(outputs)}))


if __name__ == "__main__":
    main()
