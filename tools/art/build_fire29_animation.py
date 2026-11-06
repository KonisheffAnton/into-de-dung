#!/usr/bin/env python3
"""Собирает выбранную анимацию fire29 из зафиксированного preview manifest."""

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
OUTPUT = ROOT / "assets/art_presets/approved/fire29_selected_v1"
MANIFEST_SHA256 = "7d2799c6db6526f20a51b41f5f28701126d4464b9fc65ee35f7d21a50e736fb3"
SOURCE_SIZE = 1254
NATIVE_CROP = (288, 233, 966, 746)
DISPLAY_SIZE = (256, 194)
CELL_SIZE = (256, 194)
ATLAS_GRID = (4, 4)
ATLAS_COUNT = 6
SLOT_COUNT = 96
SLOT_MS = 80
FPS = 1000.0 / SLOT_MS
EXPECTED_RGBA_BYTES = SLOT_COUNT * CELL_SIZE[0] * CELL_SIZE[1] * 4


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def read_verified(path: Path, expected_sha256: str, label: str) -> bytes:
    data = path.read_bytes()
    require(digest(data) == expected_sha256, f"SHA-256 не совпадает: {label}")
    return data


def load_rgba(path: Path, expected_size: tuple[int, int], label: str) -> tuple[bytes, Image.Image]:
    data = path.read_bytes()
    with Image.open(BytesIO(data)) as opened:
        require(opened.mode == "RGBA" and opened.size == expected_size,
                f"Ожидался RGBA {expected_size[0]}x{expected_size[1]}: {label}")
        return data, opened.copy()


def compose_native(source: Image.Image, groups: list[dict[str, Any]], slot: dict[str, Any], raw_images: dict[tuple[str, int], Image.Image]) -> Image.Image:
    # Альфа-композит выполняется на исходном холсте и в исходных XY, чтобы повторять отобранный preview без новых поз.
    native = source.copy()
    poses = slot.get("poses")
    require(isinstance(poses, dict), f"Слот {slot.get('slot')} не содержит таблицу поз")
    for group in groups:
        key = group["key"]
        require(key in poses, f"В слоте {slot.get('slot')} отсутствует группа {key}")
        frame_index = int(poses[key])
        require((key, frame_index) in raw_images, f"Нет raw кадра {key}:{frame_index}")
        box = tuple(int(value) for value in group["crop_xyxy"])
        raw = raw_images[(key, frame_index)]
        require(raw.size == (box[2] - box[0], box[3] - box[1]),
                f"Raw кадр {key}:{frame_index} не совпадает с размером crop")
        patch = Image.alpha_composite(native.crop(box), raw)
        native.paste(patch, box[:2])
    return native


def atlas_png(frames: list[Image.Image], atlas_index: int) -> bytes:
    atlas = Image.new("RGBA", (CELL_SIZE[0] * ATLAS_GRID[0], CELL_SIZE[1] * ATLAS_GRID[1]))
    first = atlas_index * ATLAS_GRID[0] * ATLAS_GRID[1]
    for local_index, frame in enumerate(frames[first:first + 16]):
        require(frame.mode == "RGBA" and frame.size == CELL_SIZE, f"Неверная ячейка {first + local_index}")
        x = (local_index % ATLAS_GRID[0]) * CELL_SIZE[0]
        y = (local_index // ATLAS_GRID[0]) * CELL_SIZE[1]
        atlas.paste(frame, (x, y))
    stream = BytesIO()
    atlas.save(stream, format="PNG", optimize=False)
    return stream.getvalue()


def verify_atlas(encoded: bytes, frames: list[Image.Image], atlas_index: int) -> None:
    with Image.open(BytesIO(encoded)) as atlas:
        require(atlas.mode == "RGBA" and atlas.size == (1024, 776),
                f"Неверный размер атласа {atlas_index}")
        first = atlas_index * 16
        for local_index, expected in enumerate(frames[first:first + 16]):
            x = (local_index % 4) * CELL_SIZE[0]
            y = (local_index // 4) * CELL_SIZE[1]
            actual = atlas.crop((x, y, x + CELL_SIZE[0], y + CELL_SIZE[1]))
            require(actual.tobytes() == expected.tobytes(),
                    f"RGBA-пиксели слота {first + local_index} отличаются от источника")


def sprite_frames_text() -> bytes:
    lines = [
        f'[gd_resource type="SpriteFrames" load_steps={SLOT_COUNT + ATLAS_COUNT + 1} format=3]',
        "",
    ]
    for index in range(ATLAS_COUNT):
        lines.extend((
            f'[ext_resource type="Texture2D" path="res://assets/art_presets/approved/fire29_selected_v1/fire29_atlas_{index:02d}.png" id="atlas_{index:02d}"]',
        ))
    lines.append("")
    for slot in range(SLOT_COUNT):
        atlas_index = slot // 16
        local_index = slot % 16
        x = (local_index % 4) * CELL_SIZE[0]
        y = (local_index // 4) * CELL_SIZE[1]
        lines.extend((
            f'[sub_resource type="AtlasTexture" id="fire_{slot:02d}"]',
            f'atlas = ExtResource("atlas_{atlas_index:02d}")',
            f'region = Rect2({x}, {y}, {CELL_SIZE[0]}, {CELL_SIZE[1]})',
            "",
        ))
    lines.extend(("[resource]", "animations = [", "{", '"frames": ['))
    for slot in range(SLOT_COUNT):
        comma = "," if slot < SLOT_COUNT - 1 else ""
        lines.append(f'{{"duration": 1.000000000, "texture": SubResource("fire_{slot:02d}")}}{comma}')
    lines.extend(("],", '"loop": true,', '"name": &"fire",', f'"speed": {FPS:.1f}', "}]", ""))
    return "\n".join(lines).encode("utf-8")


def validate_inputs() -> tuple[dict[str, Any], bytes]:
    manifest_bytes = SOURCE_MANIFEST.read_bytes()
    require(digest(manifest_bytes) == MANIFEST_SHA256,
            "Preview manifest не соответствует закреплённому SHA-256")
    manifest = json.loads(manifest_bytes.decode("utf-8"))
    require(manifest.get("schema") == "fire-field-preview-v1", "Неизвестная схема preview manifest")
    require(manifest.get("slots") == SLOT_COUNT and manifest.get("slot_ms") == SLOT_MS
            and manifest.get("period_ms") == SLOT_COUNT * SLOT_MS,
            "Частота или длительность preview не совпадает с контрактом")
    require(manifest.get("slot96_is_endpoint_check_only") is True,
            "Manifest должен хранить slot96 только как проверку шва")
    styles = manifest.get("styles", [])
    require(len(styles) == 1 and styles[0].get("style") == "29", "Ожидался ровно один выбранный fire29")
    style = styles[0]
    require(style.get("selected_group_count") == 26 and len(style.get("groups", [])) == 26,
            "Manifest должен содержать все 26 выбранных групп")
    selection_path = ROOT / manifest["selection"]
    selection_bytes = read_verified(selection_path, manifest["selection_sha256"], "selection.json")
    return {"manifest": manifest, "style": style, "selection_bytes": selection_bytes}, manifest_bytes


def build(check: bool) -> None:
    validated, manifest_bytes = validate_inputs()
    manifest = validated["manifest"]
    style = validated["style"]
    source_path = ROOT / style["source"]
    source_bytes, source = load_rgba(source_path, (SOURCE_SIZE, SOURCE_SIZE), "source tile")
    require(digest(source_bytes) == style["source_sha256"], "SHA-256 source tile не совпадает с manifest")
    source_view_path = ROOT / style["source_view_256"]
    source_view_bytes = read_verified(source_view_path, style["source_view_256_sha256"], "source-256 display reference")

    groups = style["groups"]
    raw_images: dict[tuple[str, int], Image.Image] = {}
    group_manifest: list[dict[str, Any]] = []
    for group in groups:
        box = tuple(int(value) for value in group["crop_xyxy"])
        crop_size = (box[2] - box[0], box[3] - box[1])
        input_path = ROOT / group["input"]
        input_bytes = read_verified(input_path, group["input_sha256"], f"input {group['key']}")
        mask_path = ROOT / group["core_mask"]
        mask_bytes = read_verified(mask_path, group["core_mask_sha256"], f"core mask {group['key']}")
        raw_manifest: list[dict[str, Any]] = []
        for index_text, raw_record in sorted(group["raw_frames"].items(), key=lambda pair: int(pair[0])):
            index = int(index_text)
            raw_path = ROOT / raw_record["path"]
            raw_bytes, raw_image = load_rgba(raw_path, crop_size, f"raw {group['key']}:{index}")
            require(digest(raw_bytes) == raw_record["sha256"], f"SHA-256 raw {group['key']}:{index} не совпадает")
            raw_images[(group["key"], index)] = raw_image
            raw_manifest.append({"frame": index, "path": raw_path.relative_to(ROOT).as_posix(), "sha256": digest(raw_bytes)})
        group_manifest.append({
            "key": group["key"],
            "group_key": group["group_key"],
            "crop_xyxy": list(box),
            "input": input_path.relative_to(ROOT).as_posix(),
            "input_sha256": digest(input_bytes),
            "core_mask": mask_path.relative_to(ROOT).as_posix(),
            "core_mask_sha256": digest(mask_bytes),
            "raw_frames": raw_manifest,
            "order": group["order"],
            "passes_in_common_cycle": group["passes_in_common_cycle"],
            "phase_offset_slots": group["phase_offset_slots"],
        })

    mapping = style["mapping"]
    require(len(mapping) == SLOT_COUNT + 1, "Нужны 96 игровых слотов и один проверочный endpoint")
    for slot_index, slot in enumerate(mapping):
        require(slot.get("slot") == slot_index and slot.get("time_ms") == slot_index * SLOT_MS,
                f"Mapping слота {slot_index} нарушает сетку {SLOT_MS}ms")
    require(mapping[0]["poses"] == mapping[SLOT_COUNT]["poses"], "slot96 не повторяет pose mapping slot0")

    frames: list[Image.Image] = []
    native_keyframes: dict[int, bytes] = {}
    native_snapshots = {int(row["slot"]): row for row in style["native_snapshots"]}
    for slot_index, slot in enumerate(mapping):
        native = compose_native(source, groups, slot, raw_images)
        if slot_index in (0, SLOT_COUNT - 1):
            native_keyframes[slot_index] = native.tobytes()
        if slot_index in native_snapshots:
            snapshot_record = native_snapshots[slot_index]
            snapshot_path = ROOT / snapshot_record["path"]
            snapshot_bytes, snapshot = load_rgba(snapshot_path, (SOURCE_SIZE, SOURCE_SIZE), f"native snapshot slot {slot_index}")
            require(digest(snapshot_bytes) == snapshot_record["sha256"], f"SHA-256 native snapshot slot {slot_index} не совпадает")
            require(native.tobytes() == snapshot.tobytes(), f"Native composite slot {slot_index} расходится с сохранённым snapshot")
        if slot_index < SLOT_COUNT:
            # LANCZOS применяется только к display crop; native XY и исходные кадры остаются нетронуты.
            display = native.crop(NATIVE_CROP).resize(DISPLAY_SIZE, Image.Resampling.LANCZOS)
            require(display.mode == "RGBA", f"Слот {slot_index} потерял RGBA при display resize")
            frames.append(display)
    require(len(frames) == SLOT_COUNT, "Сборка должна дать ровно 96 игровых кадров")
    require(native_keyframes[0] != native_keyframes[SLOT_COUNT - 1],
            "Слоты 95 и 0 должны быть разными; slot96 служит точным endpoint")
    actual95_to0_identical = frames[95].tobytes() == frames[0].tobytes()
    require(not actual95_to0_identical, "Экспортированные слоты 95 и 0 не должны совпадать побайтно")

    output_files: dict[Path, bytes] = {}
    atlas_records: list[dict[str, Any]] = []
    for atlas_index in range(ATLAS_COUNT):
        encoded = atlas_png(frames, atlas_index)
        verify_atlas(encoded, frames, atlas_index)
        atlas_path = OUTPUT / f"fire29_atlas_{atlas_index:02d}.png"
        output_files[atlas_path] = encoded
        atlas_records.append({"path": atlas_path.relative_to(ROOT).as_posix(), "sha256": digest(encoded),
                              "size_px": [1024, 776], "slots": [atlas_index * 16, atlas_index * 16 + 15]})

    frame_records = [{"slot": slot, "rgba_sha256": digest(frame.tobytes()),
                      "pose_map": mapping[slot]["poses"]} for slot, frame in enumerate(frames)]
    sprite_frames = sprite_frames_text()
    output_files[OUTPUT / "fire29_frames.tres"] = sprite_frames
    readme = """# fire29 selected animation v1

Производственный пакет основан на закреплённом preview `docs/art/fire29-readable-20261106/preview/manifest.json`.
Сборщик повторяет зафиксированные raw RGBA кадры в исходных XY, композитит их поверх source, затем делает только display crop `[288,233,966,746]` и LANCZOS экспорт в 256×194.

- 96 кадров, 80 мс на кадр, `fire` loop со скоростью 12.5 кадров/с (цикл 7.68 с).
- Шесть RGBA атласов 1024×776; каждый содержит 4×4 ячейки 256×194 без изменения цвета или фильтрации ячеек.
- `fire29_frames.tres` сопоставляет slots 0–95 с атласами. Mipmap-данные не создаются сборщиком.
- Slot 96 — только проверка точного совпадения pose с slot 0; slot 95 и 0 остаются разными визуальными позами.
- Атласное RGBA-хранение: 6 × 1024 × 776 × 4 = 19,070,976 байт.

Пересборка: `python tools/art/build_fire29_animation.py`.
Проверка без записи: `python tools/art/build_fire29_animation.py --check`.
"""
    output_files[OUTPUT / "README.md"] = readme.encode("utf-8")
    output_files[OUTPUT / ".gitignore"] = (
        "# Локальные байткод-кэши не входят в детерминированный пакет арта.\n"
        "__pycache__/\n*.py[cod]\n"
    ).encode("utf-8")

    manifest_out = {
        "schema": "fire29-selected-animation-v1",
        "source_manifest": SOURCE_MANIFEST.relative_to(ROOT).as_posix(),
        "source_manifest_sha256": digest(manifest_bytes),
        "selection": manifest["selection"],
        "selection_sha256": manifest["selection_sha256"],
        "style": style["style"],
        "source": style["source"],
        "source_sha256": digest(source_bytes),
        "source_view_256": style["source_view_256"],
        "source_view_256_sha256": digest(source_view_bytes),
        "groups": group_manifest,
        "native_canvas_px": [SOURCE_SIZE, SOURCE_SIZE],
        "native_crop_xyxy": list(NATIVE_CROP),
        "native_crop_px": [NATIVE_CROP[2] - NATIVE_CROP[0], NATIVE_CROP[3] - NATIVE_CROP[1]],
        "display_cell_px": list(DISPLAY_SIZE),
        "atlas_grid": list(ATLAS_GRID),
        "atlas_count": ATLAS_COUNT,
        "atlas_size_px": [1024, 776],
        "atlases": atlas_records,
        "slots": SLOT_COUNT,
        "slot_ms": SLOT_MS,
        "duration_ms": SLOT_COUNT * SLOT_MS,
        "speed_fps": FPS,
        "loop": True,
        "endpoint_slot": SLOT_COUNT,
        "endpoint_pose_equals_slot0": True,
        "slot95_rgba_equals_slot0": actual95_to0_identical,
        "native_snapshots_checked": [0, 24, 48, 72],
        "rgba_memory_bytes": EXPECTED_RGBA_BYTES,
        "animation_resource": {"path": (OUTPUT / "fire29_frames.tres").relative_to(ROOT).as_posix(),
                                "sha256": digest(sprite_frames), "animation": "fire", "frames": SLOT_COUNT,
                                "loop": True, "speed_fps": FPS, "frame_duration": 1.0},
        "frames": frame_records,
    }
    output_files[OUTPUT / "manifest.json"] = (json.dumps(manifest_out, ensure_ascii=False, indent=2) + "\n").encode("utf-8")

    expected_names = {path.name for path in output_files}
    if check:
        actual_names = {path.name for path in OUTPUT.iterdir() if path.is_file()} if OUTPUT.is_dir() else set()
        require(actual_names == expected_names, f"Состав output отличается: expected={sorted(expected_names)}, actual={sorted(actual_names)}")
        for path, expected_bytes in output_files.items():
            require(path.is_file() and path.read_bytes() == expected_bytes,
                    f"Выход отсутствует или отличается от deterministic build: {path.relative_to(ROOT)}")
        for atlas_index in range(ATLAS_COUNT):
            verify_atlas(output_files[OUTPUT / f"fire29_atlas_{atlas_index:02d}.png"], frames, atlas_index)
    else:
        OUTPUT.mkdir(parents=True, exist_ok=True)
        for path, data in output_files.items():
            path.write_bytes(data)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="пересобрать в памяти и сравнить без записи")
    args = parser.parse_args()
    try:
        build(args.check)
    except (OSError, ValueError, KeyError, TypeError, IndexError, json.JSONDecodeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print("PASS: fire29 selected animation deterministic" if args.check else "PASS: fire29 selected animation built")
    print(f"RGBA memory: {EXPECTED_RGBA_BYTES} bytes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
