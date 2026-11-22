#!/usr/bin/env python3
"""Собирает палитровые атласы пламени из полученных кадров PixelLab."""

from __future__ import annotations

import argparse
import colorsys
import hashlib
import json
import sys
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
SOURCE_DIR = ROOT / "docs/art/mage-host-flame-pixellab-20261122/raw"
OUTPUT_DIR = ROOT / "assets/ui/host_flame"
FRAME_COUNT = 17
FRAME_SIZE = 64
ATLAS_SIZE = (FRAME_COUNT * FRAME_SIZE, FRAME_SIZE)
PALETTES: dict[str, tuple[float, float, str]] = {
    "amber": (0.0, 1.0, "Исходные пиксели RGBA без изменений."),
    "blue": (196.0 / 360.0, 0.8, "H=196/360; S=S×0.8; V и alpha исходные."),
    "violet": (270.0 / 360.0, 0.7, "H=270/360; S=S×0.7; V и alpha исходные."),
    "white": (45.0 / 360.0, 0.05, "H=45/360; S=S×0.05; V и alpha исходные."),
}


def sha256(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def source_paths() -> list[Path]:
    return [SOURCE_DIR / f"frame-{index:02d}.png" for index in range(FRAME_COUNT)]


def load_frames() -> tuple[list[Image.Image], list[bytes]]:
    paths = source_paths()
    frames: list[Image.Image] = []
    payloads: list[bytes] = []
    for index, path in enumerate(paths):
        payload = path.read_bytes()
        with Image.open(path) as source:
            if source.size != (FRAME_SIZE, FRAME_SIZE) or source.mode != "RGBA":
                raise ValueError(f"Кадр {index:02d} должен быть RGBA 64x64")
            source.load()
            frames.append(source.copy())
        payloads.append(payload)
    return frames, payloads


def recolor(frame: Image.Image, palette: str) -> Image.Image:
    if palette == "amber":
        return frame.copy()
    hue, saturation_scale, _description = PALETTES[palette]
    pixels: list[tuple[int, int, int, int]] = []
    raw_pixels = frame.tobytes()
    for offset in range(0, len(raw_pixels), 4):
        red, green, blue, alpha = raw_pixels[offset:offset + 4]
        if alpha == 0:
            pixels.append((red, green, blue, alpha))
            continue
        _old_hue, saturation, value = colorsys.rgb_to_hsv(red / 255.0, green / 255.0, blue / 255.0)
        out_red, out_green, out_blue = colorsys.hsv_to_rgb(hue, saturation * saturation_scale, value)
        pixels.append((round(out_red * 255), round(out_green * 255), round(out_blue * 255), alpha))
    result = Image.new("RGBA", frame.size)
    result.putdata(pixels)
    return result


def make_atlas(frames: list[Image.Image], palette: str) -> Image.Image:
    atlas = Image.new("RGBA", ATLAS_SIZE, (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        atlas.paste(recolor(frame, palette), (index * FRAME_SIZE, 0))
    return atlas


def provenance(source_payloads: list[bytes]) -> dict[str, object]:
    return {
        "source_dir": "docs/art/mage-host-flame-pixellab-20261122/raw",
        "rawsha256": [
            {"file": f"frame-{index:02d}.png", "sha256": sha256(payload)}
            for index, payload in enumerate(source_payloads)
        ],
        "frames": FRAME_COUNT,
        "frame_size_px": [FRAME_SIZE, FRAME_SIZE],
        "duration_ms": 80,
        "anchor_px": [31, 40],
        "scale": 0.25,
        "atlases": {
            name: {"file": f"{name}.png", "recolor": description}
            for name, (_hue, _saturation_scale, description) in PALETTES.items()
        },
        "construction": "Каждый атлас — кадры 00..16 в исходном порядке; позы, альфа, геометрия и тайминг не изменяются.",
    }


def build(check: bool) -> None:
    frames, source_payloads = load_frames()
    expected = {
        f"{name}.png": make_atlas(frames, name)
        for name in PALETTES
    }
    metadata = json.dumps(provenance(source_payloads), ensure_ascii=False, indent=2) + "\n"
    if check:
        for filename, expected_image in expected.items():
            path = OUTPUT_DIR / filename
            if not path.is_file():
                raise ValueError(f"Выход отсутствует: {path.relative_to(ROOT)}")
            with Image.open(path) as actual:
                if actual.mode != "RGBA" or actual.size != ATLAS_SIZE:
                    raise ValueError(f"Неверный размер или формат: {path.relative_to(ROOT)}")
                actual.load()
                if actual.tobytes() != expected_image.tobytes():
                    raise ValueError(f"Пиксели отличаются от расчётного атласа: {path.relative_to(ROOT)}")
        metadata_path = OUTPUT_DIR / "provenance.json"
        if not metadata_path.is_file() or metadata_path.read_bytes() != metadata.encode("utf-8"):
            raise ValueError(f"Provenance отсутствует или отличается: {metadata_path.relative_to(ROOT)}")
        return

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    for filename, atlas in expected.items():
        atlas.save(OUTPUT_DIR / filename, format="PNG", optimize=False)
    (OUTPUT_DIR / "provenance.json").write_text(metadata, encoding="utf-8", newline="\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="сверить пиксели и provenance без записи")
    args = parser.parse_args()
    try:
        build(args.check)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print("PASS: host flame atlases are deterministic" if args.check else "PASS: host flame atlases built")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
