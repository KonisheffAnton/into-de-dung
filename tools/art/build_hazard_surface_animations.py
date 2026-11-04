#!/usr/bin/env python3
"""Собирает выбранные анимации опасностей из неизменённых листов PixelLab."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = ROOT / "docs/art/hazard-animations-20261104/pixellab"
OUTPUT = ROOT / "assets/art_presets/approved/environment_hazards_selected_v1"
FRAME_SIZE = 256
COLUMNS = 8
ROWS = 5
FRAME_COUNT = 33
FPS = 10.0
SELECTIONS = (
    ("acidfilm-05", "acid_film05", "acid"),
    ("caltrops03-01", "caltrops03_glints01", "caltrops"),
)


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def resource_text(stem: str, animation: str) -> str:
    atlas_id = "atlas_" + animation
    lines = [
        '[gd_resource type="SpriteFrames" load_steps=35 format=3]',
        "",
        f'[ext_resource type="Texture2D" path="res://assets/art_presets/approved/environment_hazards_selected_v1/{stem}.png" id="{atlas_id}"]',
        "",
    ]
    for index in range(FRAME_COUNT):
        x, y = (index % COLUMNS) * FRAME_SIZE, (index // COLUMNS) * FRAME_SIZE
        lines.extend((
            f'[sub_resource type="AtlasTexture" id="{animation}_{index:02d}"]',
            f'atlas = ExtResource("{atlas_id}")',
            f'region = Rect2({x}, {y}, {FRAME_SIZE}, {FRAME_SIZE})',
            "",
        ))
    lines.extend(("[resource]", "animations = [", "{", '"frames": ['))
    for index in range(FRAME_COUNT):
        comma = "," if index < FRAME_COUNT - 1 else ""
        lines.append(f'{{"duration": 1.000000000, "texture": SubResource("{animation}_{index:02d}")}}{comma}')
    lines.extend(("],", '"loop": true,', f'"name": &"{animation}",', '"speed": 10.0', "}]", ""))
    return "\n".join(lines).encode("utf-8")


def validated_selection(key: str, stem: str, animation: str) -> tuple[dict, dict[Path, bytes]]:
    source = SOURCE_ROOT / key
    clip = json.loads((source / "clip.json").read_text(encoding="utf-8"))
    if (clip.get("key"), clip.get("provider"), clip.get("actual_frames"), clip.get("expected_frames")) != (key, "PixelLab PixMiniMax", FRAME_COUNT, FRAME_COUNT):
        raise ValueError(f"{key}: источник не подтверждает выбранный PixMiniMax-клип из 33 кадров")
    sheet_bytes = (source / "sheet.png").read_bytes()
    if clip.get("artifact_sha256", {}).get("sheet.png") != digest(sheet_bytes):
        raise ValueError(f"{key}: SHA-256 листа отличается от clip.json")
    frame_paths = [source / "frames" / f"frame-{i:02d}.png" for i in range(FRAME_COUNT)]
    frame_bytes = [path.read_bytes() for path in frame_paths]
    frame_hashes = [digest(data) for data in frame_bytes]
    if frame_hashes != clip.get("frame_sha256"):
        raise ValueError(f"{key}: SHA-256 кадров отличаются от clip.json")
    with Image.open(source / "sheet.png") as sheet:
        if sheet.size != (COLUMNS * FRAME_SIZE, ROWS * FRAME_SIZE) or sheet.mode != "RGBA":
            raise ValueError(f"{key}: лист должен быть RGBA 2048x1280")
        for index, path in enumerate(frame_paths):
            with Image.open(path) as frame:
                if frame.size != (FRAME_SIZE, FRAME_SIZE) or frame.mode != "RGBA":
                    raise ValueError(f"{key}: неверный формат кадра {index}")
                x, y = (index % COLUMNS) * FRAME_SIZE, (index // COLUMNS) * FRAME_SIZE
                if sheet.crop((x, y, x + FRAME_SIZE, y + FRAME_SIZE)).tobytes() != frame.tobytes():
                    raise ValueError(f"{key}: ячейка {index} отличается от кадра")
        for index in range(FRAME_COUNT, COLUMNS * ROWS):
            x, y = (index % COLUMNS) * FRAME_SIZE, (index // COLUMNS) * FRAME_SIZE
            if sheet.crop((x, y, x + FRAME_SIZE, y + FRAME_SIZE)).getchannel("A").getbbox() is not None:
                raise ValueError(f"{key}: неиспользованная ячейка {index} непрозрачна")
    relative_source = source.relative_to(ROOT).as_posix()
    manifest = {
        "key": key,
        "selection": "selected",
        "source_paths": {
            "sheet": f"{relative_source}/sheet.png",
            "clip": f"{relative_source}/clip.json",
            "frames": [path.relative_to(ROOT).as_posix() for path in frame_paths],
        },
        "source_sha256": {"sheet": digest(sheet_bytes), "frames": frame_hashes},
        "provider": clip["provider"],
        "job_id": clip["job_id"],
        "variant": clip["variant"],
        "canvas_px": [FRAME_SIZE, FRAME_SIZE],
        "grid": [COLUMNS, ROWS],
        "frames": FRAME_COUNT,
        "fps": FPS,
        "animation": animation,
        "loop": True,
        "integration_asset_purpose": "selected hazard surface animation atlas",
    }
    files = {
        OUTPUT / f"{stem}.png": sheet_bytes,
        OUTPUT / f"{stem}_frames.tres": resource_text(stem, animation),
    }
    return manifest, files


def build(check: bool) -> None:
    manifests = []
    files: dict[Path, bytes] = {}
    for selection in SELECTIONS:
        manifest, selected_files = validated_selection(*selection)
        manifests.append(manifest)
        files.update(selected_files)
    files[OUTPUT / "manifest.json"] = (json.dumps({"selections": manifests}, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    if check:
        for path, expected in files.items():
            if not path.is_file() or path.read_bytes() != expected:
                raise ValueError(f"Выход отсутствует или отличается от детерминированной сборки: {path.relative_to(ROOT)}")
    else:
        OUTPUT.mkdir(parents=True, exist_ok=True)
        for path, data in files.items():
            path.write_bytes(data)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="проверить выходы без записи")
    args = parser.parse_args()
    try:
        build(args.check)
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print("PASS: selected hazard atlases are deterministic" if args.check else "PASS: selected hazard atlases built")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
