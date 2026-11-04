#!/usr/bin/env python3
"""Собирает проверяемую Godot-анимацию из неизменённых кадров PixelLab."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Any

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
SOURCE_DIR = ROOT / "docs/art/acid05-animation-20261103/pixellab/acid-01"
OUTPUT_DIR = ROOT / "assets/art_presets/approved/acid05_selected_v1"
SHEET_SOURCE = SOURCE_DIR / "sheet.png"
CLIP_SOURCE = SOURCE_DIR / "clip.json"
SHEET_OUTPUT = OUTPUT_DIR / "acid01.png"
FRAMES_OUTPUT = OUTPUT_DIR / "acid01_frames.tres"
MANIFEST_OUTPUT = OUTPUT_DIR / "manifest.json"
FRAME_SIZE = 256
COLUMNS = 8
ROWS = 5
FRAME_COUNT = 33
FPS = 10.0


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def source_frames() -> list[Path]:
    return [SOURCE_DIR / "frames" / f"frame-{index:02d}.png" for index in range(FRAME_COUNT)]


def frame_resource_text() -> str:
    lines = [
        "[gd_resource type=\"SpriteFrames\" load_steps=35 format=3]",
        "",
        '[ext_resource type="Texture2D" path="res://assets/art_presets/approved/acid05_selected_v1/acid01.png" id="atlas_acid"]',
        "",
    ]
    for index in range(FRAME_COUNT):
        x = (index % COLUMNS) * FRAME_SIZE
        y = (index // COLUMNS) * FRAME_SIZE
        lines.extend(
            [
                f'[sub_resource type="AtlasTexture" id="acid_{index:02d}"]',
                'atlas = ExtResource("atlas_acid")',
                f"region = Rect2({x}, {y}, {FRAME_SIZE}, {FRAME_SIZE})",
                "",
            ]
        )
    # SpriteFrames сериализует коллекцию именно в `animations`; `_animations` не является свойством ресурса.
    lines.extend(["[resource]", "animations = [", "{", '"frames": ['])
    for index in range(FRAME_COUNT):
        comma = "," if index < FRAME_COUNT - 1 else ""
        lines.append(f'{{"duration": 1.000000000, "texture": SubResource("acid_{index:02d}")}}{comma}')
    lines.extend(
        [
            "],",
            '"loop": true,',
            '"name": &"acid",',
            '"speed": 10.0',
            "}]",
            "",
        ]
    )
    return "\n".join(lines)


def expected_manifest(sheet_bytes: bytes, frame_paths: list[Path], clip: dict[str, Any]) -> dict[str, Any]:
    return {
        "source_paths": {
            "sheet": "docs/art/acid05-animation-20261103/pixellab/acid-01/sheet.png",
            "clip": "docs/art/acid05-animation-20261103/pixellab/acid-01/clip.json",
            "frames": [f"docs/art/acid05-animation-20261103/pixellab/acid-01/frames/frame-{i:02d}.png" for i in range(FRAME_COUNT)],
        },
        "source_sha256": {
            "sheet": sha256(sheet_bytes),
            "frames": [sha256(path.read_bytes()) for path in frame_paths],
        },
        "canvas_px": [FRAME_SIZE, FRAME_SIZE],
        "grid": [COLUMNS, ROWS],
        "frames": FRAME_COUNT,
        "fps": FPS,
        "provider": clip["provider"],
        "job_id": clip["job_id"],
        "variant": 1,
        "selection": "selected",
        "integration_asset_purpose": "acid pool animation atlas for current scene integration",
    }


def validate_source() -> tuple[bytes, list[Path], dict[str, Any]]:
    sheet_bytes = SHEET_SOURCE.read_bytes()
    clip = json.loads(CLIP_SOURCE.read_text(encoding="utf-8"))
    frame_paths = source_frames()
    if clip.get("variant") != 1 or clip.get("expected_frames") != FRAME_COUNT or clip.get("actual_frames") != FRAME_COUNT:
        raise ValueError("clip.json не подтверждает variant 01 и 33 кадра")
    if clip.get("artifact_sha256", {}).get("sheet.png") != sha256(sheet_bytes):
        raise ValueError("SHA-256 исходного sheet.png не совпадает с clip.json")
    actual_frame_hashes = [sha256(path.read_bytes()) for path in frame_paths]
    if actual_frame_hashes != clip.get("frame_sha256"):
        raise ValueError("SHA-256 исходных кадров не совпадают с clip.json")
    with Image.open(SHEET_SOURCE) as sheet:
        if sheet.size != (COLUMNS * FRAME_SIZE, ROWS * FRAME_SIZE) or sheet.mode != "RGBA":
            raise ValueError("Лист должен быть RGBA 2048x1280 без преобразования")
        for index, path in enumerate(frame_paths):
            with Image.open(path) as frame:
                if frame.size != (FRAME_SIZE, FRAME_SIZE) or frame.mode != "RGBA":
                    raise ValueError(f"Кадр {index:02d} должен быть RGBA 256x256")
                x = (index % COLUMNS) * FRAME_SIZE
                y = (index // COLUMNS) * FRAME_SIZE
                if sheet.crop((x, y, x + FRAME_SIZE, y + FRAME_SIZE)).tobytes() != frame.tobytes():
                    raise ValueError(f"Ячейка листа {index:02d} отличается от исходного кадра")
        # Неиспользованные семь ячеек обязаны быть прозрачными, чтобы atlas не показывал мусор.
        for index in range(FRAME_COUNT, COLUMNS * ROWS):
            x = (index % COLUMNS) * FRAME_SIZE
            y = (index // COLUMNS) * FRAME_SIZE
            if sheet.crop((x, y, x + FRAME_SIZE, y + FRAME_SIZE)).getchannel("A").getbbox() is not None:
                raise ValueError(f"Неиспользованная ячейка {index:02d} не прозрачна")
    return sheet_bytes, frame_paths, clip


def build(check: bool) -> None:
    sheet_bytes, frame_paths, clip = validate_source()
    manifest = json.dumps(expected_manifest(sheet_bytes, frame_paths, clip), ensure_ascii=False, indent=2) + "\n"
    resources = frame_resource_text()
    if check:
        for path, expected in ((SHEET_OUTPUT, sheet_bytes), (FRAMES_OUTPUT, resources.encode("utf-8")), (MANIFEST_OUTPUT, manifest.encode("utf-8"))):
            if not path.is_file() or path.read_bytes() != expected:
                raise ValueError(f"Выход отсутствует или отличается от детерминированного результата: {path.relative_to(ROOT)}")
        return
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    # Лист копируется побайтно: Godot сам импортирует атлас, а пиксели остаются исходными.
    SHEET_OUTPUT.write_bytes(sheet_bytes)
    FRAMES_OUTPUT.write_text(resources, encoding="utf-8", newline="\n")
    MANIFEST_OUTPUT.write_text(manifest, encoding="utf-8", newline="\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="проверить выходы без их изменения")
    args = parser.parse_args()
    try:
        build(args.check)
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print("PASS: acid pool animation assets are deterministic" if args.check else "PASS: acid pool animation assets built")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
