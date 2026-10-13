"""Сравнивает неизменённые кадры каждой пробы только с её первым кадром."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent
REGIONS_128 = {
    "full_canvas": (0, 0, 128, 128),
    "lower_legs": (0, 100, 128, 128),
    "left_foot": (24, 104, 53, 119),
    "right_foot": (81, 107, 108, 123),
    "bow_hand": (92, 42, 123, 99),
    "head": (43, 10, 93, 51),
}


def compare(a: Image.Image, b: Image.Image) -> dict[str, int]:
    """Считает пиксели с отличием; прозрачные RGB отдельно не маскируются в rgba_changed."""
    pixels_a = list(a.get_flattened_data())
    pixels_b = list(b.get_flattened_data())
    return {
        "rgba_changed": sum(x != y for x, y in zip(pixels_a, pixels_b)),
        "visible_rgba_changed": sum(
            x != y and (x[3] != 0 or y[3] != 0)
            for x, y in zip(pixels_a, pixels_b)
        ),
        "alpha128_changed": sum((x[3] >= 128) != (y[3] >= 128) for x, y in zip(pixels_a, pixels_b)),
    }


def bbox_alpha128(image: Image.Image) -> list[int] | None:
    mask = image.getchannel("A").point(lambda alpha: 255 if alpha >= 128 else 0)
    box = mask.getbbox()
    return list(box) if box else None


def scaled_regions(width: int, height: int) -> dict[str, tuple[int, int, int, int]]:
    if width != height or width not in (64, 128):
        raise ValueError(f"Ожидался квадратный кадр 64 или 128 px, получен {width}x{height}")
    factor = width / 128
    return {
        name: tuple(round(coord * factor) for coord in box)
        for name, box in REGIONS_128.items()
    }


def measure_variant(variant: dict) -> dict:
    folder = ROOT / variant["path"]
    result_path = folder / "result.json"
    if not result_path.is_file():
        return {"id": variant["id"], "status": "missing_result"}
    result = json.loads(result_path.read_text(encoding="utf-8-sig"))
    if result.get("status") != "completed":
        return {"id": variant["id"], "status": f"provider_{result.get('status', 'unknown')}"}
    if not result.get("files") or len(result["files"]) != result.get("frame_count"):
        raise ValueError(f"{variant['id']}: frame_count не совпадает с files")

    frames = []
    for item in result["files"]:
        frame_path = folder / item["file"]
        raw = frame_path.read_bytes()
        actual_hash = hashlib.sha256(raw).hexdigest()
        if actual_hash != item["sha256"]:
            raise ValueError(f"{variant['id']}/{item['file']}: SHA-256 mismatch")
        with Image.open(frame_path) as image:
            rgba = image.convert("RGBA")
        if rgba.size != (variant["width"], variant["height"]):
            raise ValueError(f"{variant['id']}/{item['file']}: неверный размер {rgba.size}")
        if frames and rgba.size != frames[0]["image"].size:
            raise ValueError(f"{variant['id']}: размеры кадров различаются")
        frames.append({"file": item["file"], "sha256": actual_hash, "image": rgba})

    first = frames[0]["image"]
    regions = scaled_regions(*first.size)
    measured = []
    for frame in frames:
        image = frame["image"]
        row = {
            "file": frame["file"],
            "sha256": frame["sha256"],
            "bbox_alpha128": bbox_alpha128(image),
            "vs_first_rgba": compare(first, image),
            "regions_vs_first": {
                name: compare(first.crop(box), image.crop(box))
                for name, box in regions.items()
            },
        }
        measured.append(row)
    seam = compare(frames[-1]["image"], first)
    return {
        "id": variant["id"],
        "status": "measured",
        "basis": (
            "Фиксированные приблизительные прямоугольные области заданы в координатах 128x128 "
            "и равномерно уменьшены для 64x64. Они могут включать пустое место и соседние части. "
            "Счётчики показывают различие пикселей, а не величину или направление смещения; "
            "это не измерение переноса и не точное утверждение о движении."
        ),
        "regions_xyxy": regions,
        "frames": measured,
        "seam_last_to_first": seam,
    }


def main() -> None:
    manifest = json.loads((ROOT / "variants.json").read_text(encoding="utf-8-sig"))
    reports = []
    for variant in manifest["variants"]:
        report = measure_variant(variant)
        if report["status"] == "measured":
            out = ROOT / variant["path"] / "motion-measurements.json"
            out.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        reports.append({"id": report["id"], "status": report["status"]})
    print(json.dumps(reports, ensure_ascii=False))


if __name__ == "__main__":
    main()
