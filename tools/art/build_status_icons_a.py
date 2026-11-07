#!/usr/bin/env python3
"""Подготавливает утверждённые значки статусов в игровых размерах."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import sys
from pathlib import Path
from typing import Any

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
PACKAGE = ROOT / "docs/art/status-icons-a-20261108"
SOURCE_DIR = PACKAGE / "sources"
OUTPUT_DIR = ROOT / "assets/art_presets/approved/status_icons_a_v1"
CATALOGUE = (
    "bleeding", "burning", "poison", "acid", "stunned", "entangled",
    "frozen", "wet", "shield", "raised_shield", "opportunist",
    "counterattack", "cover", "pending", "fire_on_tile", "acid_pool",
    "spikes", "corpse", "collapse_warning", "floor_trap", "wall_trap",
    "deep_acid", "void", "hazard",
)
SIZES = (16, 32)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def load_rgba(path: Path, label: str) -> Image.Image:
    try:
        with Image.open(path) as image:
            image.load()
            if image.size != (128, 128) or image.mode != "RGBA":
                raise ValueError(f"{label}: ожидался PNG RGBA 128x128, получено {image.mode} {image.size}")
            return image.copy()
    except FileNotFoundError as error:
        raise ValueError(f"{label}: файл не найден: {path.relative_to(ROOT).as_posix()}") from error
    except OSError as error:
        raise ValueError(f"{label}: не удалось прочитать PNG: {error}") from error


def png_bytes(image: Image.Image) -> bytes:
    from io import BytesIO

    buffer = BytesIO()
    image.save(buffer, format="PNG", optimize=False, compress_level=9)
    return buffer.getvalue()


def fitted_icon(source: Image.Image, size: int) -> tuple[bytes, list[int], list[int]]:
    alpha_box = source.getchannel("A").getbbox()
    if alpha_box is None:
        raise ValueError("пустой источник: альфа-канал полностью прозрачен")
    crop = source.crop(alpha_box)
    margin = 1 if size == 16 else 2
    available = size - margin * 2
    scale = min(available / crop.width, available / crop.height)
    width = max(1, math.floor(crop.width * scale + 0.5))
    height = max(1, math.floor(crop.height * scale + 0.5))
    resized = crop.resize((width, height), Image.Resampling.NEAREST)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    left = (size - width) // 2
    top = (size - height) // 2
    canvas.alpha_composite(resized, (left, top))
    if canvas.getchannel("A").getbbox() is None:
        raise ValueError("результат пуст после уменьшения")
    alpha = canvas.getchannel("A")
    if any(alpha.getpixel((x, y)) != 0 for x in range(size) for y in (0, size - 1)):
        raise ValueError("результат касается верхнего или нижнего края")
    if any(alpha.getpixel((x, y)) != 0 for y in range(size) for x in (0, size - 1)):
        raise ValueError("результат касается левого или правого края")
    return png_bytes(canvas), list(alpha_box), list(alpha.getbbox() or ())


def read_rows() -> list[dict[str, Any]]:
    try:
        rows = json.loads((SOURCE_DIR / "manifest.json").read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"не удалось прочитать sources/manifest.json: {error}") from error
    if not isinstance(rows, list):
        raise ValueError("sources/manifest.json должен содержать массив записей")
    ids = [row.get("id") if isinstance(row, dict) else None for row in rows]
    if len(ids) != len(set(ids)):
        raise ValueError("manifest содержит повторяющиеся ID")
    expected = set(CATALOGUE)
    actual = set(ids)
    if actual != expected or len(rows) != len(CATALOGUE):
        missing = sorted(expected - actual)
        unexpected = sorted(actual - expected, key=str)
        raise ValueError(f"manifest ID не совпадают с каталогом; missing={missing}, unexpected={unexpected}")
    return rows


def build() -> tuple[dict[str, bytes], dict[str, Any]]:
    rows = read_rows()
    outputs: dict[str, bytes] = {}
    result_rows: list[dict[str, Any]] = []
    for icon_id in CATALOGUE:
        row = next(item for item in rows if item["id"] == icon_id)
        original_path = SOURCE_DIR / f"{icon_id}.png"
        original_bytes = original_path.read_bytes()
        sheet_path = ROOT / row["sheet"]
        if sha256(sheet_path.read_bytes()) != row["sheet_sha256"]:
            raise ValueError(f"{icon_id}: исходный лист изменился")
        x, y, width, height = row["region"]
        with Image.open(sheet_path) as sheet:
            selected = sheet.convert("RGBA").crop((x, y, x + width, y + height))
        selected = selected.crop(selected.getchannel("A").getbbox())
        original = Image.new("RGBA", (128, 128))
        original.paste(selected, ((128 - selected.width) // 2, (128 - selected.height) // 2))
        if original.tobytes() != load_rgba(original_path, icon_id).tobytes():
            raise ValueError(f"{icon_id}: источник не равен выбранной области A")
        actual_source_hash = sha256(original_bytes)
        if actual_source_hash != row.get("source_sha256"):
            raise ValueError(f"{icon_id}: SHA-256 sources/{icon_id}.png не совпадает с manifest")
        repair_needed = row.get("repair_needed")
        if not isinstance(repair_needed, bool):
            raise ValueError(f"{icon_id}: repair_needed должен быть boolean")
        used_path = PACKAGE / "repairs" / f"{icon_id}.png" if repair_needed else original_path
        if repair_needed and not used_path.is_file():
            raise ValueError(f"{icon_id}: требуется repair-файл {used_path.relative_to(ROOT).as_posix()}")
        used_bytes = used_path.read_bytes() if repair_needed else original_bytes
        if repair_needed:
            receipt = json.loads((PACKAGE / "requests" / f"{icon_id}-result.json").read_text())
            if receipt["output_sha256"] != sha256(used_bytes):
                raise ValueError(f"{icon_id}: repair изменён относительно ответа PixelLab")
        source = load_rgba(used_path, icon_id)
        source_alpha_box = source.getchannel("A").getbbox()
        if source_alpha_box is None:
            raise ValueError(f"{icon_id}: использованный источник полностью прозрачен")
        if not repair_needed and list(source_alpha_box) != row.get("alpha_box"):
            raise ValueError(f"{icon_id}: alpha_box в manifest не совпадает с PNG")
        used_hash = sha256(used_bytes)
        output_info: dict[str, Any] = {}
        for size in SIZES:
            encoded, alpha_box, output_bbox = fitted_icon(source, size)
            relpath = f"{size}/{icon_id}.png"
            outputs[relpath] = encoded
            output_info[str(size)] = {
                "path": relpath,
                "dimensions": [size, size],
                "source_alpha_box": alpha_box,
                "output_alpha_box": output_bbox,
                "sha256": sha256(encoded),
            }
        result_rows.append({
            "id": icon_id,
            "sheet": row["sheet"],
            "sheet_sha256": row["sheet_sha256"],
            "region": row["region"],
            "repair_needed": repair_needed,
            "source_path": original_path.relative_to(ROOT).as_posix(),
            "source_sha256": actual_source_hash,
            "used_path": used_path.relative_to(ROOT).as_posix(),
            "used_sha256": used_hash,
            "outputs": output_info,
        })
    manifest = {
        "catalogue": "status_icons_a_v1",
        "source_manifest": "docs/art/status-icons-a-20261108/sources/manifest.json",
        "sizes": list(SIZES),
        "resampling": "nearest",
        "icons": result_rows,
    }
    outputs["manifest.json"] = (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    return outputs, manifest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="сверить готовые файлы с детерминированной сборкой")
    args = parser.parse_args()
    try:
        outputs, manifest = build()
        if args.check:
            mismatches = [
                relpath for relpath, expected in outputs.items()
                if not (OUTPUT_DIR / relpath).is_file() or (OUTPUT_DIR / relpath).read_bytes() != expected
            ]
            if mismatches:
                raise ValueError(f"--check обнаружил отсутствующие или отличающиеся файлы: {mismatches}")
            for icon_id in CATALOGUE:
                for size in SIZES:
                    sidecar = OUTPUT_DIR / str(size) / f"{icon_id}.png.import"
                    settings = sidecar.read_text()
                    for required in ("compress/mode=0", "mipmaps/generate=false", "process/fix_alpha_border=false", "process/premult_alpha=false"):
                        if not re.search(r"^" + re.escape(required) + r"$", settings, re.M):
                            raise ValueError(f"{sidecar.name}: неверная настройка {required}")
        else:
            for relpath, content in outputs.items():
                destination = OUTPUT_DIR / relpath
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes(content)
        total_bytes = sum(len(data) for data in outputs.values())
        print(json.dumps({"mode": "check" if args.check else "write", "count": len(manifest["icons"]), "files": len(outputs), "bytes": total_bytes}, ensure_ascii=False))
        return 0
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"build_status_icons_a: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
