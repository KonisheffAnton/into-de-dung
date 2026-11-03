#!/usr/bin/env python3
"""Собирает побайтные пресеты скинов и SpriteFrames из выбранных листов PixelLab."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
from collections import Counter
from pathlib import Path
from typing import Any

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
WARRIOR_SOURCE = ROOT / "docs/art/warrior-animation-six-20261031"
ROGUE_SOURCE = ROOT / "docs/art/rogue-animation-02-20261101"
MAGE_SOURCE = ROOT / "docs/art/mage02-animation-20261103"
ARCHER_SOURCE = ROOT / "docs/art/archer14-04-animation-20261103"
EXTENSION_BASE_COMMIT = "f74a863f086861e00a89d8136235246d94620ced"
PACKAGE = ROOT / "assets/art_presets/approved/character_skins_v1"
BASE_COMMIT = "541c6e508cde3c35db2cab28cdc9aeb8e738373a"
FRAME_SIZE = 256
SHEET_COLUMNS = 8
FRAME_COUNT = 33

SKINS: tuple[dict[str, Any], ...] = (
    {
        "slug": "watch_shield", "class": "shieldbearer", "id": "02",
        "model": "model02", "display_name": "Щит дозора",
        "source_facing_x": 1, "shieldbearer_palette_strength": 0.0,
        "source_root": "warrior",
        "clips": {"idle": "02-idle-1", "idle_secondary": "02-idle-2",
                  "death": "02-death-3", "buff": "02-ability-2"},
    },
    {
        "slug": "grey_bastion", "class": "shieldbearer", "id": "17",
        "model": "model17", "display_name": "Седой бастион",
        "source_facing_x": 1, "shieldbearer_palette_strength": 1.0,
        "source_root": "warrior",
        "clips": {"idle": "17-idle-1", "death": "17-death-3", "buff": "17-ability-2"},
    },
    {
        "slug": "red_bastion", "class": "fighter", "id": "11",
        "model": "model11", "display_name": "Красный бастион",
        "source_facing_x": -1, "shieldbearer_palette_strength": 0.0,
        "source_root": "warrior",
        "clips": {"idle": "11-idle-1", "death": "11-death-3", "buff": "11-ability-2"},
    },
    {
        "slug": "short_cape", "class": "rogue", "id": "02",
        "model": "model02", "display_name": "Короткая накидка",
        "source_facing_x": 1, "shieldbearer_palette_strength": 0.0,
        "source_root": "rogue",
        "clips": {"idle": "idle-3", "death": "death-2", "buff": "ability-3"},
    },
    {
        "slug": "star_hood", "class": "mage", "id": "02",
        "model": "model02", "display_name": "Капюшон звёзд",
        "source_facing_x": 1, "shieldbearer_palette_strength": 0.0,
        "source_root": "mage",
        "clips": {"idle": "idle-1", "idle_secondary": "idle-5",
                  "death": "death-3", "buff": "ability-5"},
    },
    {
        "slug": "silver_ranger", "class": "archer", "id": "14-04",
        "model": "model14-04", "display_name": "Серебряная лучница",
        "source_facing_x": 1, "shieldbearer_palette_strength": 0.0,
        "source_root": "archer",
        "clips": {"idle": "idle-1", "idle_secondary": "idle-5", "death": "death-3", "buff": "ability-4"},
    },
)
CLIP_NAMES = ("idle", "idle_secondary", "buff", "death")


def sha256(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def relative(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def image_info(payload: bytes, label: str) -> tuple[tuple[int, int], str, tuple[int, int, int, int] | None]:
    from io import BytesIO

    with Image.open(BytesIO(payload)) as image:
        image.load()
        return image.size, image.mode, image.getchannel("A").getbbox() if "A" in image.getbands() else None


def read_clip(source_root: Path, expected_id: str, key: str) -> tuple[dict[str, Any], bytes, dict[str, Any]]:
    folder = source_root / "pixellab" / key
    meta_path = folder / "clip.json"
    sheet_path = folder / "spritesheet.png"
    if not meta_path.is_file() or not sheet_path.is_file():
        raise ValueError(f"Missing selected clip files: {relative(folder)}")
    metadata = json.loads(meta_path.read_text(encoding="utf-8"))
    sheet = sheet_path.read_bytes()
    if metadata.get("key") != key or (source_root == WARRIOR_SOURCE and metadata.get("id") != expected_id) or (metadata.get("id") is not None and metadata["id"] != expected_id):
        raise ValueError(f"Clip identity mismatch: {relative(meta_path)}")
    if metadata.get("actual_frames") != FRAME_COUNT:
        raise ValueError(f"Expected {FRAME_COUNT} source frames: {relative(meta_path)}")
    durations = metadata.get("durations_ms")
    if not isinstance(durations, list) or len(durations) != FRAME_COUNT or any(
        not isinstance(value, int) or value <= 0 for value in durations
    ):
        raise ValueError(f"Invalid durations_ms: {relative(meta_path)}")
    if metadata.get("canvas") != [FRAME_SIZE, FRAME_SIZE] or metadata.get("anchor") != [128, 200]:
        raise ValueError(f"Canvas/anchor mismatch: {relative(meta_path)}")
    expected_loop = key.startswith("idle-") or key.split("-")[1] == "idle"
    if not isinstance(metadata.get("loop"), bool) or metadata["loop"] is not expected_loop:
        raise ValueError(f"Unexpected loop flag for selected clip: {relative(meta_path)}")
    size, mode, _bbox = image_info(sheet, relative(sheet_path))
    expected_size = (FRAME_SIZE * SHEET_COLUMNS, FRAME_SIZE * math.ceil(FRAME_COUNT / SHEET_COLUMNS))
    if size != expected_size or mode != "RGBA":
        raise ValueError(f"Expected RGBA sheet {expected_size}: {relative(sheet_path)} got {size} {mode}")
    source_frames = folder / "frames"
    frame_paths = [source_frames / f"frame-{index:02d}.png" for index in range(FRAME_COUNT)]
    present_frames = [path.is_file() for path in frame_paths]
    if any(present_frames) and not all(present_frames):
        raise ValueError(f"Partial optional source frame set: {relative(source_frames)}")
    can_compare_optional_frames = all(present_frames)
    visible = 0
    with Image.open(sheet_path) as atlas:
        atlas.load()
        for index in range(FRAME_COUNT):
            x = index % SHEET_COLUMNS * FRAME_SIZE
            y = index // SHEET_COLUMNS * FRAME_SIZE
            cell = atlas.crop((x, y, x + FRAME_SIZE, y + FRAME_SIZE))
            if cell.getchannel("A").getbbox() is None:
                raise ValueError(f"Empty atlas region {index}: {relative(sheet_path)}")
            visible += 1
            # Необязательные PNG кадров — только независимая проверка; сборка от них не зависит.
            frame_path = frame_paths[index]
            if can_compare_optional_frames:
                with Image.open(frame_path) as source_frame:
                    source_frame.load()
                    if source_frame.mode != "RGBA" or source_frame.size != (FRAME_SIZE, FRAME_SIZE):
                        raise ValueError(f"Unexpected source frame geometry: {relative(frame_path)}")
                    source_rgba = source_frame.convert("RGBA")
                    # Скрытый RGB прозрачных пикселей у листа может отличаться, поэтому
                    # сопоставляем альфу и видимые пиксели, сохраняя источник без правок.
                    if cell.getchannel("A").tobytes() != source_rgba.getchannel("A").tobytes():
                        raise ValueError(f"Atlas/source frame alpha mismatch: {relative(frame_path)}")
                    cell_rgb = cell.convert("RGB")
                    source_rgb = source_rgba.convert("RGB")
                    alpha = cell.getchannel("A")
                    visible_mask = alpha.point(lambda value: 255 if value > 0 else 0)
                    black = Image.new("RGB", cell.size)
                    if Image.composite(cell_rgb, black, visible_mask).tobytes() != Image.composite(source_rgb, black, visible_mask).tobytes():
                        raise ValueError(f"Atlas/source visible pixel mismatch: {relative(frame_path)}")
    record = {
        "source_clip": key,
        "source_clip_json": relative(meta_path),
        "source_sheet": relative(sheet_path),
        "source_sha256": sha256(sheet),
        "actual_frames": FRAME_COUNT,
        "durations_ms": durations,
        "loop": metadata["loop"],
        "first_frame_rgba_equal_to_input": metadata.get("first_frame_rgba_equal"),
        "last_frame_rgba_equal_to_input": metadata.get("last_frame_rgba_equal"),
        "visible_atlas_regions": visible,
    }
    return metadata, sheet, record


def animation_names(skin: dict[str, Any]) -> list[str]:
    return [name for name in CLIP_NAMES if name in skin["clips"]]


def sprite_frames(skin: dict[str, Any], clip_records: dict[str, dict[str, Any]]) -> bytes:
    clip_count = len(skin["clips"])
    load_steps = clip_count + clip_count * FRAME_COUNT + 1
    lines = [f'[gd_resource type="SpriteFrames" load_steps={load_steps} format=3]', ""]
    for animation in animation_names(skin):
        lines.append(
            f'[ext_resource type="Texture2D" path="res://assets/art_presets/approved/character_skins_v1/'
            f'{skin["slug"]}/{animation}.png" id="atlas_{animation}"]'
        )
    atlas_ids: dict[str, list[str]] = {}
    for animation in animation_names(skin):
        ids: list[str] = []
        for index in range(FRAME_COUNT):
            sub_id = f"{animation}_{index:02d}"
            ids.append(sub_id)
            x = index % SHEET_COLUMNS * FRAME_SIZE
            y = index // SHEET_COLUMNS * FRAME_SIZE
            lines.extend([
                "",
                f'[sub_resource type="AtlasTexture" id="{sub_id}"]',
                f'atlas = ExtResource("atlas_{animation}")',
                f"region = Rect2({x}, {y}, {FRAME_SIZE}, {FRAME_SIZE})",
            ])
        atlas_ids[animation] = ids
    lines.extend(["", "[resource]", "animations = ["])
    for animation_index, animation in enumerate(animation_names(skin)):
        clip = clip_records[animation]
        durations = clip["durations_ms"]
        base_duration = Counter(durations).most_common(1)[0][0]
        speed = 1000.0 / base_duration
        lines.extend(["{", '"frames": ['])
        for index, duration_ms in enumerate(durations):
            suffix = "," if index < FRAME_COUNT - 1 else ""
            frame_duration = duration_ms / base_duration
            lines.append(
                f'{{"duration": {frame_duration:.9f}, "texture": SubResource("{atlas_ids[animation][index]}")}}{suffix}'
            )
        lines.extend([
            "],",
            f'"loop": {str(bool(clip["loop"])).lower()},',
            f'"name": &"{animation}",',
            f'"speed": {speed:.9f}',
            "}," if animation_index < len(animation_names(skin)) - 1 else "}",
        ])
    lines.extend([
        "]",
        "",
    ])
    return ("\n".join(lines)).encode("utf-8")


def skin_resource(skin: dict[str, Any]) -> bytes:
    slug = skin["slug"]
    text = "\n".join([
        '[gd_resource type="Resource" script_class="CharacterSkinDefinition" load_steps=4 format=3]',
        "",
        '[ext_resource type="Script" path="res://scripts/demo/character_skin_definition.gd" id="1_script"]',
        f'[ext_resource type="Texture2D" path="res://assets/art_presets/approved/character_skins_v1/{slug}/still.png" id="2_still"]',
        f'[ext_resource type="SpriteFrames" path="res://assets/art_presets/approved/character_skins_v1/{slug}/frames.tres" id="3_animations"]',
        "",
        "[resource]",
        'script = ExtResource("1_script")',
        f'id = &"{slug}"',
        f'class_id = &"{skin["class"]}"',
        f'display_name = "{skin["display_name"]}"',
        'still = ExtResource("2_still")',
        'animations = ExtResource("3_animations")',
        'anchor = Vector2(128, 200)',
        'texture_scale = 0.5',
        f'source_facing_x = {skin["source_facing_x"]}',
        f'shieldbearer_palette_strength = {skin["shieldbearer_palette_strength"]:.1f}',
        "",
    ])
    return text.encode("utf-8")


def readme_bytes() -> bytes:
    text = """# Character skins v1

Шесть обликов с выбранными анимационными листами. Пакет содержит PNG, `SpriteFrames` и `skin.tres` типа `CharacterSkinDefinition`; runtime-сцены и shader/материалы находятся у владельцев показа.

## Выбор

| Skin | Class/id/model | PixelLab clips |
|---|---|---|
| `watch_shield` — Щит дозора | `shieldbearer` / `02` / `model02` | idle-1, idle-2, death-3, ability-2 |
| `grey_bastion` — Седой бастион | `shieldbearer` / `17` / `model17` | idle-1, death-3, ability-2 |
| `red_bastion` — Красный бастион | `fighter` / `11` / `model11` | idle-1, death-3, ability-2 |
| `short_cape` — Короткая накидка | `rogue` / `02` / `model02` | idle-3, death-2, ability-3 |
| `star_hood` — Капюшон звёзд | `mage` / `02` / `model02` | idle-1, idle-5, death-3, ability-5 |
| `silver_ranger` — Серебряная лучница | `archer` / `14-04` / `model14-04` | idle-1, idle-5, death-3, ability-4 |

`buff` в `SpriteFrames` — имя runtime-анимации для выбранного источника `ability`; новую механику оно не вводит. Idle-secondary есть у `watch_shield`, `star_hood` и `silver_ranger`.

## Происхождение и геометрия

`still.png` — побайтная копия выбранного `input-256.png`; каждый clip PNG — побайтная копия выбранного PixelLab `spritesheet.png`. Листы RGBA, 2048×1280, восемь колонок по 256 px и 33 позы. Кадры не извлекаются и не пересохраняются: `SpriteFrames` использует `AtlasTexture`-регионы исходного листа. Ресурсы четырёх прежних обликов сохраняют прежнее происхождение `base_commit`; поле `extension_base_commit` указывает базу расширения двумя новыми обликами.

В каталоге каждого облика лежат `still.png`, выбранные clip PNG, `frames.tres` и `skin.tres`. Координаты опоры исходника — (128,200), texture scale — 0.5. Палитра Щита дозора и Серого бастиона соответствует заданным значениям; у остальных сила палитры 0. Направление берётся из утверждённого источника.

## Тайминг и ограничения источников

Тайминги и loop берутся из выбранных `clip.json`. Частота `SpriteFrames.speed` равна `1000 / base_duration_ms`, где база — наиболее частая длительность клипа; frame `duration` хранит отношение его `duration_ms` к этой базе. Длинные последние кадры сохраняются: например, ability у новых mage/archer — 32×70ms и последний кадр700ms (2.94s). Источники содержат false для `first_frame_rgba_equal` и `last_frame_rgba_equal`: крайние позы не являются точной RGBA-копией still. Это выбранные PixelLab результаты, не утверждение о ручной художественной приёмке.

Исходные картинки не изменяются, кадры не генерируются. Покадровые PNG служат независимой необязательной проверкой видимых пикселей и alpha, если полный набор доступен; скрытый RGB прозрачных пикселей может отличаться. Частичный набор считается ошибкой. Сборка требует sheets, input images и clip metadata.

## Сборка и проверка

`python tools/art/build_character_skins.py` собирает пакет. `python tools/art/build_character_skins.py --check` сравнивает ожидаемые байты без записи. `manifest.json` содержит источники и SHA-256 27 PNG; `validation.json` фиксирует 693 видимых региона и записи длительностей.
"""
    return text.encode("utf-8")


def outputs() -> tuple[dict[str, bytes], dict[str, Any], dict[str, Any]]:
    generated: dict[str, bytes] = {}
    index_skins: list[dict[str, Any]] = []
    manifest_skins: list[dict[str, Any]] = []
    source_records: list[dict[str, Any]] = []
    source_png_count = 0
    frame_count = 0
    visible_regions = 0
    timing_frames = 0

    for skin in SKINS:
        slug = skin["slug"]
        source_root = {
            "warrior": WARRIOR_SOURCE,
            "rogue": ROGUE_SOURCE,
            "mage": MAGE_SOURCE,
            "archer": ARCHER_SOURCE,
        }[skin["source_root"]]
        model_dir = (source_root / "model" if skin["source_root"] == "rogue"
                     else source_root / "models" / f"warrior-{skin['id']}"
                     if skin["source_root"] == "warrior" else source_root / "model")
        still_path = model_dir / "input-256.png"
        if not still_path.is_file():
            raise ValueError(f"Missing still source: {relative(still_path)}")
        still = still_path.read_bytes()
        size, mode, bbox = image_info(still, relative(still_path))
        if size != (FRAME_SIZE, FRAME_SIZE) or mode != "RGBA" or bbox is None:
            raise ValueError(f"Still must be visible RGBA {FRAME_SIZE}²: {relative(still_path)}")
        runtime_dir = f"{slug}/still.png"
        generated[runtime_dir] = still
        source_png_count += 1
        source_records.append({
            "source": relative(still_path), "runtime": f"{PACKAGE.relative_to(ROOT).as_posix()}/{runtime_dir}",
            "sha256": sha256(still), "kind": "still",
        })
        clip_records: dict[str, dict[str, Any]] = {}
        output_paths: dict[str, str] = {"still": runtime_dir}
        for animation, clip_key in skin["clips"].items():
            metadata, sheet, clip_record = read_clip(source_root, skin["id"], clip_key)
            output_name = "buff.png" if animation == "buff" else f"{animation}.png"
            output_path = f"{slug}/{output_name}"
            generated[output_path] = sheet
            clip_records[animation] = clip_record
            output_paths[animation] = output_path
            source_png_count += 1
            source_records.append({
                "source": clip_record["source_sheet"],
                "runtime": f"{PACKAGE.relative_to(ROOT).as_posix()}/{output_path}",
                "sha256": sha256(sheet), "kind": animation, "clip_key": clip_key,
            })
            frame_count += clip_record["actual_frames"]
            visible_regions += clip_record["visible_atlas_regions"]
            timing_frames += len(clip_record["durations_ms"])
        frame_resource = sprite_frames(skin, clip_records)
        generated[f"{slug}/frames.tres"] = frame_resource
        generated[f"{slug}/skin.tres"] = skin_resource(skin)
        runtime_clips = {name: f"{slug}/{name}.png" if name != "buff" else f"{slug}/buff.png"
                         for name in skin["clips"]}
        index_skins.append({
            "class": skin["class"], "class_id": skin["class"], "id": skin["id"],
            "name": skin["display_name"], "slug": slug, "model": skin["model"],
            "still_path": f"{PACKAGE.relative_to(ROOT).as_posix()}/{slug}/still.png",
            "frame_path": f"{PACKAGE.relative_to(ROOT).as_posix()}/{slug}/frames.tres",
            "clip_paths": {key: f"{PACKAGE.relative_to(ROOT).as_posix()}/{value}" for key, value in runtime_clips.items()},
        })
        manifest_skins.append({
            "class": skin["class"], "id": skin["id"], "name": skin["display_name"], "slug": slug,
            "model": skin["model"], "anchor": [128, 200], "canvas": [FRAME_SIZE, FRAME_SIZE],
            "source_facing_x": skin["source_facing_x"],
            "shieldbearer_palette_strength": skin["shieldbearer_palette_strength"],
            "still_source": relative(still_path), "clips": clip_records,
            "runtime_paths": output_paths,
        })

    index = {"format": 1, "base_commit": BASE_COMMIT,
             "extension_base_commit": EXTENSION_BASE_COMMIT, "skins": index_skins}
    generated["index.json"] = (json.dumps(index, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    generated["README.md"] = readme_bytes()
    artifact_hashes = {name: sha256(data) for name, data in sorted(generated.items())}
    manifest = {
        "format": 1,
        "base_commit": BASE_COMMIT,
        "extension_base_commit": EXTENSION_BASE_COMMIT,
        "selection": "U selected PixelLab clips for four existing warrior/Rogue skins and two approved mage/archer skins.",
        "canvas": [FRAME_SIZE, FRAME_SIZE],
        "anchor": [128, 200],
        "sheet_layout": {"columns": SHEET_COLUMNS, "cell": [FRAME_SIZE, FRAME_SIZE], "frames_per_clip": FRAME_COUNT},
        "source_png_count": source_png_count,
        "source_pngs": source_records,
        "skins": manifest_skins,
        "artifact_sha256": artifact_hashes,
    }
    generated["manifest.json"] = (json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8")
    validation = {
        "format": 1, "base_commit": BASE_COMMIT,
        "extension_base_commit": EXTENSION_BASE_COMMIT,
        "source_sha_exact_count": source_png_count,
        "source_sha_exact_pass": source_png_count == 27,
        "atlas_cell_count": frame_count,
        "atlas_visible_count": visible_regions,
        "atlas_all_visible": frame_count == visible_regions == 693,
        "optional_raw_frame_sets_validated": True,
        "optional_raw_frame_slots": {
            source_type: sum(len(skin["clips"]) * FRAME_COUNT for skin in SKINS if skin["source_root"] == source_type)
            for source_type in ("warrior", "rogue", "mage", "archer")
        },
        "optional_raw_frame_policy": "compare complete available sets; reject partial sets",
        "duration_entry_count": timing_frames,
        "duration_entries_match_frames": timing_frames == frame_count == 693,
        "skins": [
            {"slug": skin["slug"], "id": skin["id"], "class": skin["class"],
             "clip_count": len(skin["clips"]), "frame_count": len(skin["clips"]) * FRAME_COUNT}
            for skin in SKINS
        ],
        "skin_resource_created": True,
        "runtime_or_image_processing": False,
    }
    generated["validation.json"] = (json.dumps(validation, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8")
    return generated, manifest, validation


def main() -> int:
    parser = argparse.ArgumentParser(description="Build approved warrior skin assets without image processing")
    parser.add_argument("--check", action="store_true", help="compare deterministic expected bytes without writing")
    args = parser.parse_args()
    expected, _manifest, validation = outputs()
    if not all((validation[key] for key in ("source_sha_exact_pass", "atlas_all_visible",
                                             "optional_raw_frame_sets_validated", "duration_entries_match_frames"))):
        print(f"FAIL: validation did not pass: {validation}", file=sys.stderr)
        return 1
    if args.check:
        failures = [
            name for name, payload in expected.items()
            if not (PACKAGE / name).is_file() or (PACKAGE / name).read_bytes() != payload
        ]
        if failures:
            print("FAIL: " + ", ".join(failures), file=sys.stderr)
            return 1
        print("PASS: 43 deterministic outputs; 27 source PNGs byte-exact; 693 visible atlas cells and durations validated")
        return 0
    for name, payload in expected.items():
        path = PACKAGE / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(payload)
    print(f"Built {len(expected)} deterministic outputs in {PACKAGE}")
    print("PASS: 27 source PNGs byte-exact; 693 visible atlas cells and durations validated")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as exc:
        raise SystemExit(f"BUILD FAILED: {exc}") from exc
