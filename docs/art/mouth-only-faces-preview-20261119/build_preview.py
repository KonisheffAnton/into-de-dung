#!/usr/bin/env python3
"""Собирает проверяемые статичные примеры обработки ртов; исходники не меняет."""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parent
EXPECTED_KEYS = ("red_bastion", "watch_shield", "silver_ranger", "short_cape", "star_hood")
FONT_PATH = Path("C:/Windows/Fonts/arial.ttf")
BACKGROUND = (32, 42, 52)
TEXT = (235, 239, 242)
SUBTEXT = (166, 181, 193)


class BuildError(Exception):
    pass


def fail(message: str) -> None:
    raise BuildError(message)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def checked_path(value: Any, field: str) -> Path:
    if not isinstance(value, str):
        fail(f"{field}: ожидался относительный путь")
    candidate = (ROOT / value).resolve()
    try:
        candidate.relative_to(ROOT.resolve())
    except ValueError:
        fail(f"{field}: путь выходит за каталог пакета")
    if not candidate.is_file():
        fail(f"{field}: файл не найден: {value}")
    return candidate


def checked_box(value: Any, field: str, size: tuple[int, int]) -> tuple[int, int, int, int]:
    if (not isinstance(value, list) or len(value) != 4
            or any(type(part) is not int for part in value)):
        fail(f"{field}: ожидались четыре целых координаты")
    x0, y0, x1, y1 = value
    if x0 < 0 or y0 < 0 or x1 <= x0 or y1 <= y0 or x1 > size[0] or y1 > size[1]:
        fail(f"{field}: координаты вне изображения или пустой прямоугольник")
    return x0, y0, x1, y1


def load_inputs() -> list[dict[str, Any]]:
    manifest_path = ROOT / "selection.json"
    if not manifest_path.is_file():
        fail("не найден selection.json")
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"selection.json: {error}")
    items = manifest.get("items") if isinstance(manifest, dict) else None
    if not isinstance(items, list) or len(items) != len(EXPECTED_KEYS):
        fail("selection.json: ожидается ровно пять items")
    if [item.get("key") if isinstance(item, dict) else None for item in items] != list(EXPECTED_KEYS):
        fail("selection.json: ключи/порядок не совпадают с пятью классами")

    prepared: list[dict[str, Any]] = []
    for item in items:
        key = item["key"]
        paths = {name: checked_path(item.get(name), f"{key}.{name}")
                 for name in ("source", "patch", "mask", "request_mask")}
        for name, path in paths.items():
            expected = item.get(f"{name}_sha256")
            actual = sha256(path)
            if not isinstance(expected, str) or actual.lower() != expected.lower():
                fail(f"{key}.{name}: SHA-256 не совпал (ожидано {expected}, получено {actual})")

        source = Image.open(paths["source"])
        patch = Image.open(paths["patch"])
        mask = Image.open(paths["mask"])
        if source.mode != "RGBA" or source.size != (256, 256):
            fail(f"{key}.source: нужен RGBA 256x256")
        if patch.mode != "RGBA":
            fail(f"{key}.patch: нужен RGBA")
        request_mask = Image.open(paths["request_mask"])
        if mask.mode != "RGB" or request_mask.mode != "RGB":
            fail(f"{key}: нужны RGB маски без альфа-канала")
        crop = checked_box(item.get("crop_box"), f"{key}.crop_box", source.size)
        head = checked_box(item.get("head_box"), f"{key}.head_box", source.size)
        if (head[2] - head[0], head[3] - head[1]) != (72, 72):
            fail(f"{key}: head_box должен быть 72x72")
        width, height = crop[2] - crop[0], crop[3] - crop[1]
        if any(image.size != (width, height) for image in (patch, mask, request_mask)):
            fail(f"{key}: размеры patch/mask не совпадают с crop_box")
        if key == "red_bastion" and crop != (0, 0, 256, 256):
            fail(f"{key}: crop_box должен охватывать 256x256")
        if key != "red_bastion" and patch.size != (64, 64):
            fail(f"{key}: patch должен быть нативного размера 64x64")
        mask_data = list(mask.getdata())
        request_data = list(request_mask.getdata())
        for name, data in (("mask", mask_data), ("request_mask", request_data)):
            if any(pixel not in ((0, 0, 0), (255, 255, 255)) for pixel in data):
                fail(f"{key}.{name}: допускаются только чистые чёрные/белые пиксели")
        if not any(pixel == (255, 255, 255) for pixel in mask_data):
            fail(f"{key}.mask: финальная маска пуста")
        if any(final == (255, 255, 255) and requested != (255, 255, 255)
               for final, requested in zip(mask_data, request_data)):
            fail(f"{key}.mask: финальная маска выходит за request_mask")
        prepared.append({"key": key, "label": item.get("label"), "paths": paths,
                         "source": source.copy(), "patch": patch.copy(),
                         "mask_data": mask_data, "request_data": request_data,
                         "crop": crop, "head": head})
    return prepared


def prepare_edits(items: list[dict[str, Any]]) -> list[dict[str, Any]]:
    edits = []
    for item in items:
        source = item["source"]
        result = source.copy()
        patch = item["patch"]
        x0, y0, x1, y1 = item["crop"]
        original_crop = source.crop(item["crop"])
        raw_outside_request_changed = 0
        discarded_provider_changes = 0
        changed = 0
        source_pixels = list(original_crop.getdata())
        patch_pixels = list(patch.getdata())
        # Проверяем всю окрестность пикселя, чтобы финальная маска не касалась края силуэта.
        min_alpha_crop = source.getchannel("A").filter(ImageFilter.MinFilter(3)).crop(item["crop"])
        min_alpha_pixels = list(min_alpha_crop.getdata())
        for index, (before, after, mask_pixel) in enumerate(
                zip(source_pixels, patch_pixels, item["mask_data"])):
            requested = item["request_data"][index] == (255, 255, 255)
            if not requested and before != after:
                raw_outside_request_changed += 1
            if mask_pixel == (255, 255, 255):
                if min_alpha_pixels[index] < 240 or after[3] < 240:
                    fail(f"{item['key']}: финальная маска выбрала пиксель с окрестностью alpha < 240")
                if before[:3] != after[:3]:
                    changed += 1
            elif requested and before != after:
                discarded_provider_changes += 1
        if raw_outside_request_changed:
            fail(f"{item['key']}: patch изменил {raw_outside_request_changed} пикселей вне request_mask")
        if changed == 0:
            fail(f"{item['key']}: маскированный patch не содержит фактических изменений")

        # Сохраняем исходную альфу: край спрайта и силуэт остаются без изменений.
        result_pixels = result.load()
        patch_pixels = patch.load()
        for my in range(patch.height):
            for mx in range(patch.width):
                if item["mask_data"][my * patch.width + mx] == (255, 255, 255):
                    original_alpha = result_pixels[x0 + mx, y0 + my][3]
                    provider_pixel = patch_pixels[mx, my]
                    result_pixels[x0 + mx, y0 + my] = (
                        provider_pixel[0], provider_pixel[1], provider_pixel[2], original_alpha)
        outside_changes = 0
        for py in range(256):
            for px in range(256):
                allowed = (x0 <= px < x1 and y0 <= py < y1
                           and item["mask_data"][(py - y0) * patch.width + (px - x0)] == (255, 255, 255))
                if not allowed and source.getpixel((px, py)) != result.getpixel((px, py)):
                    outside_changes += 1
        if outside_changes:
            fail(f"{item['key']}: итог изменил {outside_changes} пикселей вне полной маски")
        alpha_identical = all(source.getpixel((px, py))[3] == result.getpixel((px, py))[3]
                              for py in range(256) for px in range(256))
        if not alpha_identical:
            fail(f"{item['key']}: итог изменил альфу относительно source")
        edits.append({**item, "result": result, "changed": changed,
                      "raw_outside_request_mask_changed": raw_outside_request_changed,
                      "discarded_provider_changes": discarded_provider_changes,
                      "outside_mask_changed": outside_changes,
                      "alpha_identical": alpha_identical})
    return edits


def font(size: int) -> ImageFont.FreeTypeFont:
    if not FONT_PATH.is_file():
        fail(f"шрифт не найден: {FONT_PATH}")
    return ImageFont.truetype(str(FONT_PATH), size=size)


def make_comparison(edits: list[dict[str, Any]]) -> Image.Image:
    canvas = Image.new("RGB", (1320, 1260), BACKGROUND)
    draw = ImageDraw.Draw(canvas)
    draw.text((40, 17), "Предпросмотр лиц пяти человеческих классов", font=font(26), fill=TEXT)
    draw.text((40, 49), "Статичные примеры · только рот", font=font(16), fill=SUBTEXT)
    card_w, card_h, gap_x, gap_y = 600, 370, 40, 20
    start_y = 82
    for index, item in enumerate(edits):
        row = index // 2
        col = index % 2 if index < 4 else 0
        x = 40 + col * (card_w + gap_x)
        y = start_y + row * (card_h + gap_y)
        if index == 4:
            x = (1320 - card_w) // 2
        draw.rounded_rectangle((x, y, x + card_w, y + card_h), radius=12, fill=(41, 53, 65))
        draw.text((x + 20, y + 14), item["label"], font=font(22), fill=TEXT)
        head = item["head"]
        for side, image, caption in ((0, item["source"], "Сейчас"),
                                     (1, item["result"], "Только рот")):
            hx = x + 12 + side * 300
            draw.text((hx, y + 48), caption, font=font(16), fill=SUBTEXT)
            crop = image.crop(head).resize((288, 288), Image.Resampling.NEAREST)
            canvas.paste(crop, (hx, y + 72), crop)
    return canvas


def make_characters(edits: list[dict[str, Any]]) -> Image.Image:
    canvas = Image.new("RGB", (1536, 1160), BACKGROUND)
    draw = ImageDraw.Draw(canvas)
    draw.text((40, 17), "Примеры на полных спрайтах", font=font(26), fill=TEXT)
    positions = ((0, 40), (512, 40), (1024, 40), (256, 580), (768, 580))
    for item, (x, y) in zip(edits, positions):
        draw.text((x + 8, y), item["label"], font=font(20), fill=TEXT)
        enlarged = item["result"].resize((512, 512), Image.Resampling.NEAREST)
        canvas.paste(enlarged, (x, y + 32), enlarged)
    return canvas


def write_report(edits: list[dict[str, Any]], artifacts: list[Path]) -> None:
    rows = []
    for item in edits:
        rows.append({"key": item["key"], "label": item["label"],
                     "source_sha256": sha256(item["paths"]["source"]),
                     "patch_sha256": sha256(item["paths"]["patch"]),
                     "mask_sha256": sha256(item["paths"]["mask"]),
                     "request_mask_sha256": sha256(item["paths"]["request_mask"]),
                     "source_dimensions": list(item["source"].size),
                     "patch_dimensions": list(item["patch"].size),
                     "raw_outside_request_mask_changed": item["raw_outside_request_mask_changed"],
                     "discarded_provider_changes": item["discarded_provider_changes"],
                     "changed_pixels": item["changed"],
                     "outside_mask_changed": item["outside_mask_changed"],
                     "alpha_identical": item["alpha_identical"]})
    payload = {"scope": "static_human_examples_only",
               "final_mask_alpha_threshold": 240,
               "alpha_policy": "original_alpha_retained_globally",
               "items": rows,
               "artifacts": [{"path": path.relative_to(ROOT).as_posix(),
                              "dimensions": list(Image.open(path).size), "sha256": sha256(path)}
                             for path in artifacts]}
    (ROOT / "art-validation.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")


def main() -> int:
    try:
        edits = prepare_edits(load_inputs())
        # Проверяем шрифт и готовим все монтажи до первого выходного файла.
        comparison = make_comparison(edits)
        characters = make_characters(edits)
        output_dir = ROOT / "edits"
        output_dir.mkdir(exist_ok=True)
        for item in edits:
            item["result"].save(output_dir / f"{item['key']}.png", format="PNG")
        artifacts = [ROOT / "faces-comparison.png", ROOT / "characters-preview.png"]
        comparison.save(artifacts[0], format="PNG")
        characters.save(artifacts[1], format="PNG")
        write_report(edits, artifacts)
        print("Preview built: five human examples validated.")
        return 0
    except (BuildError, OSError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
