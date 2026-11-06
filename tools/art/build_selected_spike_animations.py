#!/usr/bin/env python3
"""Собирает выбранные trap01 и редкие блики caltrops03 без изменения пикселей."""

from __future__ import annotations

import argparse
import hashlib
from io import BytesIO
import json
import sys
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = ROOT / "docs/art/hazard-motion-20261106"
OUTPUT = ROOT / "assets/art_presets/approved/spikes_selected_v2"
FRAME_SIZE = 256


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read_rgba(path: Path) -> tuple[bytes, bytes]:
    raw = path.read_bytes()
    with Image.open(path) as image:
        if image.size != (FRAME_SIZE, FRAME_SIZE) or image.mode != "RGBA":
            raise ValueError(f"Кадр должен быть RGBA 256x256: {path.relative_to(ROOT)}")
        return raw, image.tobytes()


def atlas_png(cells: list[bytes]) -> bytes:
    image = Image.new("RGBA", (FRAME_SIZE * len(cells), FRAME_SIZE))
    for index, pixels in enumerate(cells):
        image.paste(Image.frombytes("RGBA", (FRAME_SIZE, FRAME_SIZE), pixels), (index * FRAME_SIZE, 0))
    from io import BytesIO

    stream = BytesIO()
    image.save(stream, format="PNG", optimize=False)
    return stream.getvalue()


def mask_png(cells: list[bytes]) -> bytes:
    image = Image.new("RGBA", (FRAME_SIZE * len(cells), FRAME_SIZE))
    for index, pixels in enumerate(cells):
        with Image.open(BytesIO(pixels)) as mask:
            if mask.size != (FRAME_SIZE, FRAME_SIZE) or mask.mode != "L":
                raise ValueError("Маска трапа должна быть L 256x256")
            luminance = mask.tobytes()
        rgba = bytes(channel for value in luminance for channel in (value, value, value, 255))
        image.paste(Image.frombytes("RGBA", (FRAME_SIZE, FRAME_SIZE), rgba), (index * FRAME_SIZE, 0))
    stream = BytesIO()
    image.save(stream, format="PNG", optimize=False)
    return stream.getvalue()


def sprite_frames(stem: str, animation: str, atlas_count: int, frame_indices: list[int], durations: list[float], loop: bool) -> bytes:
    atlas_id = "atlas_" + animation
    lines = [
        f'[gd_resource type="SpriteFrames" load_steps={atlas_count + 2} format=3]',
        "",
        f'[ext_resource type="Texture2D" path="res://assets/art_presets/approved/spikes_selected_v2/{stem}.png" id="{atlas_id}"]',
        "",
    ]
    for index in range(atlas_count):
        lines.extend((
            f'[sub_resource type="AtlasTexture" id="{animation}_{index:02d}"]',
            f'atlas = ExtResource("{atlas_id}")',
            f'region = Rect2({index * FRAME_SIZE}, 0, {FRAME_SIZE}, {FRAME_SIZE})',
            "",
        ))
    lines.extend(("[resource]", "animations = [", "{" , '"frames": ['))
    for index, (frame_index, duration) in enumerate(zip(frame_indices, durations, strict=True)):
        comma = "," if index < len(durations) - 1 else ""
        lines.append(f'{{"duration": {duration:.9f}, "texture": SubResource("{animation}_{frame_index:02d}")}}{comma}')
    lines.extend(("],", f'"loop": {str(loop).lower()},', f'"name": &"{animation}",', '"speed": 1.0', "}]", ""))
    return "\n".join(lines).encode("utf-8")


def build(check: bool) -> None:
    trap_dir = SOURCE_ROOT / "trap"
    caltrops_dir = SOURCE_ROOT / "caltrops"
    trap_metrics = json.loads((trap_dir / "candidate-metrics.json").read_text(encoding="utf-8"))
    caltrops_metrics = json.loads((caltrops_dir / "candidate-metrics.json").read_text(encoding="utf-8"))

    files: dict[Path, bytes] = {}
    manifest: dict[str, object] = {"selections": []}

    trap_names = ["closed", "half", "extended"]
    trap_cells: list[bytes] = []
    trap_sources: list[dict[str, object]] = []
    for name, expected in zip(trap_names, trap_metrics["poses"], strict=True):
        path = trap_dir / f"{name}.png"
        raw, pixels = read_rgba(path)
        if expected["pose"] != name or digest(raw) != expected["assembled_sha256"]:
            raise ValueError(f"{name}: собранные пиксели не совпадают с candidate-metrics.json")
        trap_cells.append(pixels)
        mask_path = trap_dir / f"{name}-mask.png"
        mask_raw = mask_path.read_bytes()
        with Image.open(mask_path) as mask:
            if mask.mode != "L" or mask.size != (FRAME_SIZE, FRAME_SIZE):
                raise ValueError(f"Маска должна быть L 256x256: {mask_path.relative_to(ROOT)}")
            mask_pixels = mask.tobytes()
        raw_path = ROOT / "docs/art/fire-spikes-animation-20261105/pixellab/spike01-01/frames" / f"frame-{expected['raw_frame']:02}.png"
        raw_frame_bytes = raw_path.read_bytes()
        if digest(raw_frame_bytes) != expected["raw_sha256"]:
            raise ValueError(f"raw pose {name} не совпадает с candidate-metrics.json")
        trap_sources.append({
            "name": name,
            "png": path.relative_to(ROOT).as_posix(),
            "png_sha256": digest(raw),
            "mask_png": mask_path.relative_to(ROOT).as_posix(),
            "mask_png_sha256": digest(mask_raw),
            "assembled_sha256": digest(raw),
            "raw_provenance": {"path": raw_path.relative_to(ROOT).as_posix(), "candidate_metrics": (trap_dir / "candidate-metrics.json").relative_to(ROOT).as_posix(), "raw_frame": expected["raw_frame"], "raw_sha256": expected["raw_sha256"]},
            "mask_l_sha256": digest(mask_pixels),
        })
    trap_base = trap_metrics.get("base_sha256")
    if trap_sources[0]["assembled_sha256"] != trap_base:
        raise ValueError("closed не совпадает с базовым кадром трапа")
    trap_atlas = atlas_png(trap_cells)
    files[OUTPUT / "trap01.png"] = trap_atlas
    files[OUTPUT / "trap01_masks.png"] = mask_png([ (trap_dir / f"{name}-mask.png").read_bytes() for name in trap_names ])
    files[OUTPUT / "trap01_frames.tres"] = sprite_frames("trap01", "poses", 3, [0, 1, 2], [1.0, 1.0, 1.0], False)
    manifest["selections"].append({"asset": "trap01", "animation": "poses", "cells": trap_sources, "grid": [3, 1], "frame_size": [256, 256], "loop": False, "speed": 1.0})  # type: ignore[union-attr]

    caltrops_names = ["rest", "glint-low-peak", "glint-low-tail", "glint-high-peak", "glint-high-hold"]
    caltrops_cells: list[bytes] = []
    caltrops_sources: list[dict[str, object]] = []
    metric_by_name = {pose["pose"]: pose for pose in caltrops_metrics["poses"]}
    for name in caltrops_names:
        path = caltrops_dir / f"{name}.png"
        raw, pixels = read_rgba(path)
        expected = metric_by_name.get(name)
        if name == "rest":
            if digest(raw) != caltrops_metrics["base_sha256"]:
                raise ValueError("rest не совпадает с base_sha256")
            provenance = {"candidate_metrics": (caltrops_dir / "candidate-metrics.json").relative_to(ROOT).as_posix(), "base_sha256": caltrops_metrics["base_sha256"]}
        else:
            if expected is None or digest(raw) != expected["assembled_sha256"]:
                raise ValueError(f"{name}: собранные пиксели не совпадают с candidate-metrics.json")
            raw_path = ROOT / "docs/art/hazard-animations-20261104/pixellab/caltrops03-01/frames" / f"frame-{expected['raw_frame']:02}.png"
            if digest(raw_path.read_bytes()) != expected["raw_sha256"]:
                raise ValueError(f"raw pose {name} не совпадает с candidate-metrics.json")
            provenance = {"path": raw_path.relative_to(ROOT).as_posix(), "candidate_metrics": (caltrops_dir / "candidate-metrics.json").relative_to(ROOT).as_posix(), "raw_frame": expected["raw_frame"], "raw_sha256": expected["raw_sha256"]}
        caltrops_cells.append(pixels)
        caltrops_sources.append({"name": name, "png": path.relative_to(ROOT).as_posix(), "png_sha256": digest(raw), "assembled_sha256": digest(raw), "raw_provenance": provenance})
    schedule = ["rest", "glint-low-peak", "glint-low-tail", "rest", "glint-high-peak", "glint-high-hold", "rest"]
    duration_by_name = {"rest": 5.0, "glint-low-peak": 0.15, "glint-low-tail": 0.15, "glint-high-peak": 0.15, "glint-high-hold": 0.15}
    duration_indices = [{"rest": 0, "glint-low-peak": 1, "glint-low-tail": 2, "glint-high-peak": 3, "glint-high-hold": 4}[name] for name in schedule]
    durations = [duration_by_name[name] for name in schedule]
    caltrops_atlas = atlas_png(caltrops_cells)
    files[OUTPUT / "caltrops03_rare.png"] = caltrops_atlas
    files[OUTPUT / "caltrops03_rare_frames.tres"] = sprite_frames("caltrops03_rare", "caltrops", len(caltrops_cells), duration_indices, durations, True)
    manifest["selections"].append({"asset": "caltrops03_rare", "animation": "caltrops", "cells": caltrops_sources, "grid": [5, 1], "frame_size": [256, 256], "schedule_indices": duration_indices, "duration_seconds": durations, "loop": True, "speed": 1.0, "cycle_seconds": sum(durations)})  # type: ignore[union-attr]

    # Сохраняем provenance исходников и raw-кадров отдельно от атласа, чтобы выбор можно было перепроверить.
    files[OUTPUT / "manifest.json"] = (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    if check:
        for path, expected_bytes in files.items():
            if not path.is_file() or path.read_bytes() != expected_bytes:
                raise ValueError(f"Выход отсутствует или отличается от детерминированной сборки: {path.relative_to(ROOT)}")
        verify_atlas(files[OUTPUT / "trap01.png"], trap_cells)
        verify_atlas(files[OUTPUT / "caltrops03_rare.png"], caltrops_cells)
        verify_atlas_masks(files[OUTPUT / "trap01_masks.png"], trap_names, trap_dir)
    else:
        OUTPUT.mkdir(parents=True, exist_ok=True)
        for path, data in files.items():
            path.write_bytes(data)


def verify_atlas(encoded: bytes, cells: list[bytes]) -> None:
    from io import BytesIO

    with Image.open(BytesIO(encoded)) as image:
        if image.mode != "RGBA" or image.size != (FRAME_SIZE * len(cells), FRAME_SIZE):
            raise ValueError("Неверный размер или формат собранного атласа")
        for index, expected in enumerate(cells):
            if image.crop((index * FRAME_SIZE, 0, (index + 1) * FRAME_SIZE, FRAME_SIZE)).tobytes() != expected:
                raise ValueError(f"Ячейка атласа {index} не совпадает с исходными пикселями")


def verify_atlas_masks(encoded: bytes, names: list[str], source_dir: Path) -> None:
    from io import BytesIO

    with Image.open(BytesIO(encoded)) as image:
        if image.mode != "RGBA" or image.size != (FRAME_SIZE * len(names), FRAME_SIZE):
            raise ValueError("Неверный размер или формат атласа масок")
        for index, name in enumerate(names):
            with Image.open(source_dir / f"{name}-mask.png") as source:
                actual = image.crop((index * FRAME_SIZE, 0, (index + 1) * FRAME_SIZE, FRAME_SIZE))
                pixels = actual.tobytes()
                expected_l = source.tobytes()
                for pixel_index, value in enumerate(expected_l):
                    rgba = pixels[pixel_index * 4:pixel_index * 4 + 4]
                    if rgba != bytes((value, value, value, 255)):
                        raise ValueError(f"Маска {name}, пиксель {pixel_index}: ожидался L в RGB и непрозрачный alpha")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="проверить выходы без записи")
    args = parser.parse_args()
    try:
        build(args.check)
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print("PASS: spike animation atlases are deterministic" if args.check else "PASS: spike animation atlases built")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
