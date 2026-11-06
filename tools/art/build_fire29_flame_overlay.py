#!/usr/bin/env python3
"""Build a deterministic coverage overlay for the selected fire29 animation."""

from __future__ import annotations

import argparse
from io import BytesIO
import hashlib
import json
import sys
from pathlib import Path
from typing import Any

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
SOURCE_MANIFEST = ROOT / "docs/art/fire29-readable-20261106/preview/manifest.json"
SOURCE_MANIFEST_SHA256 = "7d2799c6db6526f20a51b41f5f28701126d4464b9fc65ee35f7d21a50e736fb3"
BASE_PACKAGE = ROOT / "assets/art_presets/approved/fire29_selected_v1"
OUTPUT = ROOT / "assets/art_presets/approved/fire29_flame_overlay_v1"
SOURCE_SIZE = (1254, 1254)
NATIVE_CROP = (288, 233, 966, 746)
CELL_SIZE = (256, 194)
ATLAS_GRID = (4, 4)
ATLAS_SIZE = (1024, 776)
SLOT_COUNT = 96
SLOT_MS = 80
SPEED_FPS = 12.5
ATLAS_COUNT = 6
RGBA_BYTES = SLOT_COUNT * CELL_SIZE[0] * CELL_SIZE[1] * 4
FLAT_CENTER = (627.0, 496.0)
FLAT_HALF = (305.0, 231.0)
RUNTIME_PLANE_CENTER = (128.0, 99.45809)
RUNTIME_PLANE_HALF = (115.16224, 87.35673)


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def read_verified(path: Path, expected_sha256: str, label: str) -> bytes:
    data = path.read_bytes()
    require(digest(data) == expected_sha256, f"SHA-256 не совпадает: {label}")
    return data


def load_rgba(path: Path, size: tuple[int, int], label: str) -> tuple[bytes, Image.Image]:
    data = path.read_bytes()
    with Image.open(BytesIO(data)) as opened:
        require(opened.mode == "RGBA" and opened.size == size,
                f"Ожидался RGBA {size[0]}x{size[1]}: {label}")
        return data, opened.copy()


def source_inputs() -> tuple[dict[str, Any], bytes, Image.Image, list[dict[str, Any]], dict[tuple[str, int], Image.Image], list[dict[str, Any]]]:
    manifest_bytes = SOURCE_MANIFEST.read_bytes()
    require(digest(manifest_bytes) == SOURCE_MANIFEST_SHA256,
            "Preview manifest не совпадает с закреплённым SHA-256")
    manifest = json.loads(manifest_bytes.decode("utf-8"))
    require(manifest.get("schema") == "fire-field-preview-v1" and manifest.get("slots") == SLOT_COUNT
            and manifest.get("slot_ms") == SLOT_MS and manifest.get("period_ms") == 7680,
            "Preview manifest имеет несовместимую схему или тайминг")
    require(manifest.get("slot96_is_endpoint_check_only") is True,
            "Slot 96 должен оставаться только проверкой endpoint")
    require(len(manifest.get("styles", [])) == 1 and manifest["styles"][0].get("style") == "29",
            "Ожидалась одна закреплённая выборка fire29")
    style = manifest["styles"][0]
    require(style.get("selected_group_count") == 26 and len(style.get("groups", [])) == 26,
            "Ожидались все 26 выбранных raw-групп")
    selection_path = ROOT / manifest["selection"]
    selection_bytes = read_verified(selection_path, manifest["selection_sha256"], "selection.json")
    source_path = ROOT / style["source"]
    source_bytes, source = load_rgba(source_path, SOURCE_SIZE, "native source tile")
    require(digest(source_bytes) == style["source_sha256"], "SHA-256 native source не совпадает")
    source_view_path = ROOT / style["source_view_256"]
    source_view_bytes = read_verified(source_view_path, style["source_view_256_sha256"], "source-256 display reference")

    raw_images: dict[tuple[str, int], Image.Image] = {}
    groups_manifest: list[dict[str, Any]] = []
    for group in style["groups"]:
        box = tuple(int(value) for value in group["crop_xyxy"])
        expected_size = (box[2] - box[0], box[3] - box[1])
        input_path = ROOT / group["input"]
        input_bytes = read_verified(input_path, group["input_sha256"], f"group input {group['key']}")
        mask_path = ROOT / group["core_mask"]
        mask_bytes = read_verified(mask_path, group["core_mask_sha256"], f"core mask {group['key']}")
        raw_records: list[dict[str, Any]] = []
        for index_text, raw_record in sorted(group["raw_frames"].items(), key=lambda item: int(item[0])):
            index = int(index_text)
            raw_path = ROOT / raw_record["path"]
            raw_bytes, raw_image = load_rgba(raw_path, expected_size, f"raw {group['key']}:{index}")
            require(digest(raw_bytes) == raw_record["sha256"], f"SHA-256 raw {group['key']}:{index} не совпадает")
            raw_images[(group["key"], index)] = raw_image
            raw_records.append({"frame": index, "path": raw_path.relative_to(ROOT).as_posix(),
                                "sha256": digest(raw_bytes), "size_px": list(expected_size)})
        groups_manifest.append({
            "key": group["key"],
            "group_key": group["group_key"],
            "crop_xyxy": list(box),
            "input": input_path.relative_to(ROOT).as_posix(),
            "input_sha256": digest(input_bytes),
            "core_mask": mask_path.relative_to(ROOT).as_posix(),
            "core_mask_sha256": digest(mask_bytes),
            "raw_frames": raw_records,
        })
    require(len(raw_images) == 145, f"Ожидалось 145 raw frames, найдено {len(raw_images)}")
    return {"manifest": manifest, "style": style, "selection_sha256": digest(selection_bytes),
            "groups_manifest": groups_manifest, "source_view_sha256": digest(source_view_bytes)}, manifest_bytes, source, style["groups"], raw_images, groups_manifest


def read_base_frames(style: dict[str, Any]) -> tuple[dict[int, Image.Image], list[dict[str, Any]]]:
    base_manifest_path = BASE_PACKAGE / "manifest.json"
    base_manifest_bytes = base_manifest_path.read_bytes()
    base_manifest = json.loads(base_manifest_bytes.decode("utf-8"))
    require(base_manifest.get("source_manifest_sha256") == SOURCE_MANIFEST_SHA256
            and base_manifest.get("slots") == SLOT_COUNT and base_manifest.get("style") == "29",
            "Существующий fire29 package не соответствует выбранному source manifest")
    resource = base_manifest["animation_resource"]
    resource_path = ROOT / resource["path"]
    resource_bytes = read_verified(resource_path, resource["sha256"], "selected fire29 SpriteFrames")
    require(resource["animation"] == "fire" and resource["frames"] == SLOT_COUNT
            and resource["loop"] is True and resource["speed_fps"] == SPEED_FPS,
            "Выбранный fire29 resource имеет другой контракт")
    require(len(base_manifest.get("atlases", [])) == ATLAS_COUNT
            and len(base_manifest.get("frames", [])) == SLOT_COUNT,
            "Выбранный fire29 package должен содержать 6 атласов и 96 кадров")
    atlases: list[Image.Image] = []
    atlas_records: list[dict[str, Any]] = []
    for atlas_index, record in enumerate(base_manifest["atlases"]):
        atlas_path = ROOT / record["path"]
        atlas_bytes, atlas = load_rgba(atlas_path, ATLAS_SIZE, f"selected atlas {atlas_index}")
        require(digest(atlas_bytes) == record["sha256"], f"Выбранный atlas {atlas_index} изменён")
        atlases.append(atlas)
        atlas_records.append({"path": atlas_path.relative_to(ROOT).as_posix(),
                              "sha256": digest(atlas_bytes), "bytes": len(atlas_bytes)})

    frames: dict[int, Image.Image] = {}
    for slot in range(SLOT_COUNT):
        atlas_index = slot // 16
        local_index = slot % 16
        x = (local_index % 4) * CELL_SIZE[0]
        y = (local_index // 4) * CELL_SIZE[1]
        frame = atlases[atlas_index].crop((x, y, x + CELL_SIZE[0], y + CELL_SIZE[1]))
        record = base_manifest["frames"][slot]
        require(record.get("slot") == slot and digest(frame.tobytes()) == record["rgba_sha256"],
                f"Существующий fire29 cell {slot} не совпадает с его manifest")
        frames[slot] = frame
    return frames, [{"manifest_path": base_manifest_path.relative_to(ROOT).as_posix(),
                     "manifest_sha256": digest(base_manifest_bytes),
                     "resource_path": resource_path.relative_to(ROOT).as_posix(),
                     "resource_sha256": digest(resource_bytes),
                     "atlases": atlas_records}]


def build_coverage(source: Image.Image, groups: list[dict[str, Any]], slot: dict[str, Any],
                   raw_images: dict[tuple[str, int], Image.Image]) -> Image.Image:
    # Прозрачный native холст сохраняет только площадь покрытия исходных языков и не добавляет цвет.
    canvas = Image.new("RGBA", SOURCE_SIZE, (0, 0, 0, 0))
    poses = slot.get("poses")
    require(isinstance(poses, dict), f"Mapping slot {slot.get('slot')} lacks poses")
    for group in groups:
        key = group["key"]
        require(key in poses, f"Mapping slot {slot.get('slot')} lacks group {key}")
        frame_index = int(poses[key])
        require((key, frame_index) in raw_images, f"Raw frame is missing: {key}:{frame_index}")
        box = tuple(int(value) for value in group["crop_xyxy"])
        raw = raw_images[(key, frame_index)]
        patch = Image.alpha_composite(canvas.crop(box), raw)
        canvas.paste(patch, box[:2])
    # Понижаем только alpha coverage по тому же display crop/размеру, что и выбранная композиция.
    return canvas.getchannel("A").crop(NATIVE_CROP).resize(CELL_SIZE, Image.Resampling.LANCZOS)


def combine_base_rgb_and_coverage(base: Image.Image, coverage: Image.Image) -> tuple[bytes, bytes, bytes, int, int, int]:
    base_data = base.tobytes()
    coverage_data = coverage.tobytes()
    output = bytearray(base_data)
    base_rgb = bytearray(CELL_SIZE[0] * CELL_SIZE[1] * 3)
    rgb_index = 0
    coverage_count = 0
    overlay_count = 0
    outside_count = 0
    for pixel_index in range(CELL_SIZE[0] * CELL_SIZE[1]):
        source_index = pixel_index * 4
        red, green, blue, base_alpha = base_data[source_index:source_index + 4]
        coverage_alpha = coverage_data[pixel_index]
        output[source_index] = red
        output[source_index + 1] = green
        output[source_index + 2] = blue
        output[source_index + 3] = (coverage_alpha * base_alpha + 127) // 255
        base_rgb[rgb_index:rgb_index + 3] = bytes((red, green, blue))
        rgb_index += 3
        overlay_alpha = output[source_index + 3]
        if coverage_alpha > 8:
            coverage_count += 1
        if overlay_alpha > 8:
            overlay_count += 1
            x = pixel_index % CELL_SIZE[0]
            y = pixel_index // CELL_SIZE[0]
            flat_distance = abs((x + 0.5 - RUNTIME_PLANE_CENTER[0]) / RUNTIME_PLANE_HALF[0]) + abs((y + 0.5 - RUNTIME_PLANE_CENTER[1]) / RUNTIME_PLANE_HALF[1])
            if flat_distance > 1.0:
                outside_count += 1
    return bytes(output), bytes(base_rgb), coverage_data, coverage_count, overlay_count, outside_count


def atlas_png(frames: list[bytes], atlas_index: int) -> bytes:
    atlas = Image.new("RGBA", ATLAS_SIZE)
    first = atlas_index * 16
    for local_index, frame_data in enumerate(frames[first:first + 16]):
        frame = Image.frombytes("RGBA", CELL_SIZE, frame_data)
        x = (local_index % 4) * CELL_SIZE[0]
        y = (local_index // 4) * CELL_SIZE[1]
        atlas.paste(frame, (x, y))
    stream = BytesIO()
    atlas.save(stream, format="PNG", optimize=False)
    return stream.getvalue()


def verify_atlas(encoded: bytes, frames: list[bytes], atlas_index: int) -> None:
    with Image.open(BytesIO(encoded)) as atlas:
        require(atlas.mode == "RGBA" and atlas.size == ATLAS_SIZE,
                f"Overlay atlas {atlas_index} must be 1024x776 RGBA")
        first = atlas_index * 16
        for local_index, expected in enumerate(frames[first:first + 16]):
            x = (local_index % 4) * CELL_SIZE[0]
            y = (local_index // 4) * CELL_SIZE[1]
            actual = atlas.crop((x, y, x + CELL_SIZE[0], y + CELL_SIZE[1]))
            require(actual.tobytes() == expected,
                    f"Overlay atlas cell {first + local_index} differs from frame RGBA")


def sprite_frames_text() -> bytes:
    lines = [f'[gd_resource type="SpriteFrames" load_steps={SLOT_COUNT + ATLAS_COUNT + 1} format=3]', ""]
    for atlas_index in range(ATLAS_COUNT):
        lines.append(f'[ext_resource type="Texture2D" path="res://assets/art_presets/approved/fire29_flame_overlay_v1/fire29_flames_{atlas_index:02d}.png" id="atlas_{atlas_index:02d}"]')
    lines.append("")
    for slot in range(SLOT_COUNT):
        atlas_index = slot // 16
        local_index = slot % 16
        x = (local_index % 4) * CELL_SIZE[0]
        y = (local_index // 4) * CELL_SIZE[1]
        lines.extend((f'[sub_resource type="AtlasTexture" id="fire_{slot:02d}"]',
                      f'atlas = ExtResource("atlas_{atlas_index:02d}")',
                      f'region = Rect2({x}, {y}, {CELL_SIZE[0]}, {CELL_SIZE[1]})', ""))
    lines.extend(("[resource]", "animations = [", "{", '"frames": ['))
    for slot in range(SLOT_COUNT):
        comma = "," if slot < SLOT_COUNT - 1 else ""
        lines.append(f'{{"duration": 1.000000000, "texture": SubResource("fire_{slot:02d}")}}{comma}')
    lines.extend(("],", '"loop": true,', '"name": &"fire",', f'"speed": {SPEED_FPS:.1f}', "}]", ""))
    return "\n".join(lines).encode("utf-8")


def build(check: bool) -> None:
    validated, source_manifest_bytes, source, groups, raw_images, group_manifest = source_inputs()
    style = validated["style"]
    crop_width = NATIVE_CROP[2] - NATIVE_CROP[0]
    crop_height = NATIVE_CROP[3] - NATIVE_CROP[1]
    computed_plane_center = (
        (FLAT_CENTER[0] - NATIVE_CROP[0]) * CELL_SIZE[0] / crop_width,
        (FLAT_CENTER[1] - NATIVE_CROP[1]) * CELL_SIZE[1] / crop_height,
    )
    computed_plane_half = (
        FLAT_HALF[0] * CELL_SIZE[0] / crop_width,
        FLAT_HALF[1] * CELL_SIZE[1] / crop_height,
    )
    require(all(abs(actual - expected) < 0.0001 for actual, expected in zip(computed_plane_center, RUNTIME_PLANE_CENTER, strict=True))
            and all(abs(actual - expected) < 0.0001 for actual, expected in zip(computed_plane_half, RUNTIME_PLANE_HALF, strict=True)),
            "Runtime flat-plane bounds no longer match the selected native crop/export geometry")
    base_frames, base_provenance = read_base_frames(style)
    mapping = style["mapping"]
    require(len(mapping) == SLOT_COUNT + 1, "Expected 96 poses and an endpoint slot")
    for slot_index, record in enumerate(mapping):
        require(record.get("slot") == slot_index and record.get("time_ms") == slot_index * SLOT_MS,
                f"Mapping slot {slot_index} is not on the 80ms grid")
    require(mapping[0]["poses"] == mapping[SLOT_COUNT]["poses"], "Mapping endpoint 96 must use slot 0 poses")

    coverage_frames: list[bytes] = []
    rgba_frames: list[bytes] = []
    frame_records: list[dict[str, Any]] = []
    endpoint_coverage: bytes | None = None
    for slot_index, slot in enumerate(mapping):
        coverage = build_coverage(source, groups, slot, raw_images)
        coverage_data = coverage.tobytes()
        if slot_index == 0:
            endpoint_coverage = coverage_data
        if slot_index == SLOT_COUNT:
            require(endpoint_coverage == coverage_data, "Slot 96 alpha coverage must exactly match slot 0")
            continue
        base = base_frames[slot_index]
        rgba_data, base_rgb, saved_coverage, coverage_count, overlay_count, outside_count = combine_base_rgb_and_coverage(base, coverage)
        require(saved_coverage == coverage_data, f"Coverage bytes changed while combining slot {slot_index}")
        overlay_rgb = bytes(rgba_data[index + channel] for index in range(0, len(rgba_data), 4) for channel in range(3))
        require(overlay_rgb == base_rgb, "Overlay RGB differs from its selected base frame")
        require(outside_count > 0, f"Slot {slot_index} has no alpha coverage outside the runtime flat plane")
        rgba_frames.append(rgba_data)
        coverage_frames.append(coverage_data)
        frame_records.append({
            "slot": slot_index,
            "pose_map": mapping[slot_index]["poses"],
            "base_rgb_sha256": digest(base_rgb),
            "coverage_alpha_sha256": digest(coverage_data),
            "overlay_rgba_sha256": digest(rgba_data),
            "coverage_pixels_alpha_gt8": coverage_count,
            "overlay_pixels_alpha_gt8": overlay_count,
            "overlay_pixels_alpha_gt8_outside_runtime_flat_plane": outside_count,
        })
    require(len(rgba_frames) == SLOT_COUNT and len(coverage_frames) == SLOT_COUNT,
            "Overlay export must contain exactly 96 slots")
    different_endpoint_pixels = sum(
        rgba_frames[0][i:i + 4] != rgba_frames[95][i:i + 4]
        for i in range(0, len(rgba_frames[0]), 4)
    )
    require(different_endpoint_pixels > 0, "Slot 95 must remain measurably different from slot 0")

    output_files: dict[Path, bytes] = {}
    atlases: list[dict[str, Any]] = []
    for atlas_index in range(ATLAS_COUNT):
        encoded = atlas_png(rgba_frames, atlas_index)
        verify_atlas(encoded, rgba_frames, atlas_index)
        path = OUTPUT / f"fire29_flames_{atlas_index:02d}.png"
        output_files[path] = encoded
        atlases.append({"path": path.relative_to(ROOT).as_posix(), "sha256": digest(encoded),
                        "bytes": len(encoded), "size_px": list(ATLAS_SIZE),
                        "slots": [atlas_index * 16, atlas_index * 16 + 15]})

    frames_resource = sprite_frames_text()
    resource_path = OUTPUT / "fire29_flames_frames.tres"
    output_files[resource_path] = frames_resource
    readme = """# fire29 flame coverage overlay v1

Этот пакет содержит только alpha-покрытие выбранных языков огня. 26 исходных групп композитятся с исходными XY на прозрачном native холсте 1254×1254; альфа вырезается тем же crop `[288,233,966,746]` и LANCZOS уменьшается до 256×194.

RGB каждой ячейки побайтно совпадает с соответствующим кадром `fire29_selected_v1`. Итоговая alpha — alpha coverage × alpha выбранного кадра / 255 с округлением к ближайшему целому. Новые формы и движение не добавляются.

- 96 ячеек по 80 мс; клип `fire`, loop, 12.5 кадров/с, цикл 7.68 с.
- Шесть RGBA атласов 1024×776, по 4×4 ячейки 256×194.
- Вне flat runtime-плоскости считается alpha > 8; geometry рассчитана из native center (627,496), half-size (305,231) и crop/resize. Manifest содержит оба набора bounds и счётчик каждого кадра.
- Дополнительный декодированный RGBA объём: 19,070,976 байт.

Пересборка: `python tools/art/build_fire29_flame_overlay.py`.
Проверка без записи: `python tools/art/build_fire29_flame_overlay.py --check`.
"""
    output_files[OUTPUT / "README.md"] = readme.encode("utf-8")
    output_files[OUTPUT / ".gitignore"] = (
        "# Python caches are local and are not generated atlas assets.\n__pycache__/\n*.py[cod]\n"
    ).encode("utf-8")

    manifest_out = {
        "schema": "fire29-flame-coverage-overlay-v1",
        "source_manifest": SOURCE_MANIFEST.relative_to(ROOT).as_posix(),
        "source_manifest_sha256": digest(source_manifest_bytes),
        "selection": validated["manifest"]["selection"],
        "selection_sha256": validated["selection_sha256"],
        "source": style["source"],
        "source_sha256": digest((ROOT / style["source"]).read_bytes()),
        "source_view_256": style["source_view_256"],
        "source_view_256_sha256": validated["source_view_sha256"],
        "source_rgb_sha256": digest(source.convert("RGB").tobytes()),
        "source_alpha_sha256": digest(source.getchannel("A").tobytes()),
        "source_size_px": list(SOURCE_SIZE),
        "groups": group_manifest,
        "raw_frame_count": len(raw_images),
        "selected_animation": base_provenance[0],
        "native_crop_xyxy": list(NATIVE_CROP),
        "display_cell_px": list(CELL_SIZE),
        "resampling": "PIL LANCZOS on alpha only for overlay; selected base RGB is copied exact",
        "combine_rule": "out.rgb = selected_frame.rgb; out.a = round(coverage_alpha * selected_frame.a / 255)",
        "slots": SLOT_COUNT,
        "slot_ms": SLOT_MS,
        "duration_ms": SLOT_COUNT * SLOT_MS,
        "speed_fps": SPEED_FPS,
        "loop": True,
        "atlas_grid": list(ATLAS_GRID),
        "atlas_size_px": list(ATLAS_SIZE),
        "atlas_count": ATLAS_COUNT,
        "atlases": atlases,
        "runtime_flat_plane": {"center": list(RUNTIME_PLANE_CENTER), "half_size": list(RUNTIME_PLANE_HALF),
                               "alpha_threshold": 8, "outside_alpha_pixels": [row["overlay_pixels_alpha_gt8_outside_runtime_flat_plane"] for row in frame_records]},
        "source_flat_plane_native": {"center": list(FLAT_CENTER), "half_size": list(FLAT_HALF)},
        "endpoint_slot": SLOT_COUNT,
        "endpoint_coverage_equals_slot0": True,
        "slot95_rgba_differs_from_slot0": True,
        "slot95_different_rgba_pixels_vs_slot0": different_endpoint_pixels,
        "rgba_memory_bytes": RGBA_BYTES,
        "source_input_rgb_and_alpha_sha256": {"rgb": digest(source.convert("RGB").tobytes()), "alpha": digest(source.getchannel("A").tobytes())},
        "frames_resource": {"path": resource_path.relative_to(ROOT).as_posix(), "sha256": digest(frames_resource),
                            "animation": "fire", "frames": SLOT_COUNT, "loop": True,
                            "speed_fps": SPEED_FPS, "duration_per_frame": 1.0, "shared_definition": True},
        "frames": frame_records,
    }
    output_files[OUTPUT / "manifest.json"] = (json.dumps(manifest_out, ensure_ascii=False, indent=2) + "\n").encode("utf-8")

    expected_names = {path.name for path in output_files}
    if check:
        actual_names = {path.name for path in OUTPUT.iterdir()} if OUTPUT.is_dir() else set()
        require(actual_names == expected_names,
                f"Состав overlay output отличается: expected={sorted(expected_names)}, actual={sorted(actual_names)}")
        for path, expected in output_files.items():
            require(path.is_file() and path.read_bytes() == expected,
                    f"Overlay output missing or changed: {path.relative_to(ROOT)}")
        for atlas_index in range(ATLAS_COUNT):
            verify_atlas(output_files[OUTPUT / f"fire29_flames_{atlas_index:02d}.png"], rgba_frames, atlas_index)
    else:
        OUTPUT.mkdir(parents=True, exist_ok=True)
        for path, data in output_files.items():
            path.write_bytes(data)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="пересобрать в памяти и проверить outputs")
    args = parser.parse_args()
    try:
        build(args.check)
    except (OSError, ValueError, KeyError, TypeError, IndexError, json.JSONDecodeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print("PASS: fire29 flame coverage overlay deterministic" if args.check else "PASS: fire29 flame coverage overlay built")
    print(f"Additional RGBA memory: {RGBA_BYTES} bytes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
