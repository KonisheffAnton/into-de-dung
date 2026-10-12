"""Извлечь неизменённые PNG из завершённой задачи PixelLab."""

from __future__ import annotations

import argparse
import base64
import hashlib
import io
import json
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parent
FRAME_SIZE = (128, 128)
HIDDEN_IMAGE_KEYS = {"images", "image", "quantized_images", "quantized_image", "base64"}


def _read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(value, dict):
        raise ValueError(f"Ожидался JSON-объект: {path}")
    return value


def _without_images(value: Any) -> Any:
    if isinstance(value, dict):
        return {key: _without_images(item) for key, item in value.items() if key.lower() not in HIDDEN_IMAGE_KEYS and "base64" not in key.lower()}
    if isinstance(value, list):
        return [_without_images(item) for item in value]
    return value


def _image_bytes(entry: Any, number: int) -> bytes:
    if isinstance(entry, str):
        encoded = entry
    elif isinstance(entry, dict):
        encoded = entry.get("base64")
    else:
        encoded = None
    if not isinstance(encoded, str) or not encoded:
        raise ValueError(f"Кадр {number}: отсутствует base64 PNG")
    if encoded.startswith("data:"):
        encoded = encoded.split(",", 1)[-1]
    try:
        data = base64.b64decode(encoded, validate=True)
    except (ValueError, base64.binascii.Error) as error:
        raise ValueError(f"Кадр {number}: некорректный base64") from error
    if not data.startswith(b"\x89PNG\r\n\x1a\n"):
        raise ValueError(f"Кадр {number}: данные не являются PNG")
    try:
        with Image.open(io.BytesIO(data)) as image:
            if image.format != "PNG" or image.size != FRAME_SIZE:
                raise ValueError(f"Кадр {number}: ожидался PNG {FRAME_SIZE}, получено {image.format} {image.size}")
            image.load()
    except OSError as error:
        raise ValueError(f"Кадр {number}: PNG повреждён") from error
    return data


def _filmstrip(path: Path, files: list[Path]) -> None:
    cell, label_height = 256, 28
    sheet = Image.new("RGBA", (len(files) * cell, cell + label_height), (63, 75, 67, 255))
    draw = ImageDraw.Draw(sheet)
    font_path = Path("C:/Windows/Fonts/arial.ttf")
    font = ImageFont.truetype(str(font_path), 18) if font_path.is_file() else ImageFont.load_default()
    for index, source_path in enumerate(files):
        with Image.open(source_path) as source:
            frame = source.convert("RGBA")
        sheet.alpha_composite(frame.resize((cell, cell), Image.Resampling.NEAREST), (index * cell, 0))
        draw.text((index * cell + 8, cell + 4), f"{index + 1:02}", fill=(240, 243, 236, 255), font=font)
    sheet.save(path)


def extract(job_directory: Path, raw_path: Path, expected_frames: int) -> dict[str, Any]:
    accepted = _read_json(job_directory / "response.json")
    job = _read_json(raw_path)
    expected_id = accepted.get("background_job_id")
    if not isinstance(expected_id, str) or not expected_id or job.get("id") != expected_id:
        raise ValueError("Сохранённый ответ принадлежит другой задаче или ID не задан")
    if job.get("status") != "completed":
        raise ValueError(f"Внешний статус задачи должен быть completed, получено {job.get('status')!r}")
    response = job.get("last_response")
    if not isinstance(response, dict):
        raise ValueError("Отсутствует last_response")
    entries = response.get("images")
    if not isinstance(entries, list) or len(entries) != expected_frames:
        raise ValueError(f"Ожидалось {expected_frames} изображений, получено {len(entries) if isinstance(entries, list) else 'не список'}")

    target = job_directory / "pixellab"
    target.mkdir(parents=True, exist_ok=True)
    def collect(image_entries: list[Any], prefix: str) -> tuple[list[tuple[Path, bytes]], list[dict[str, Any]]]:
        values: list[tuple[Path, bytes]] = []
        metadata: list[dict[str, Any]] = []
        for index, entry in enumerate(image_entries, 1):
            data = _image_bytes(entry, index)
            name = f"{prefix}-{index:02}.png" if prefix else f"frame-{index:02}.png"
            destination = target / name
            if destination.exists() and destination.read_bytes() != data:
                raise ValueError(f"Отказ перезаписывать отличающийся кадр: {destination}")
            values.append((destination, data))
            metadata.append({"file": name, "sha256": hashlib.sha256(data).hexdigest()})
        return values, metadata

    decoded, records = collect(entries, "")
    quantized = response.get("quantized_images", [])
    if quantized is None:
        quantized = []
    if not isinstance(quantized, list):
        raise ValueError("last_response.quantized_images должен быть списком")
    quantized_decoded, quantized_records = collect(quantized, "quantized-frame")
    for prefix, values in (("frame-", decoded), ("quantized-frame-", quantized_decoded)):
        expected_names = {path.name for path, _ in values}
        extras = {path.name for path in target.glob(prefix + "*.png")} - expected_names
        if extras:
            raise ValueError("Каталог содержит лишние кадры: " + ", ".join(sorted(extras)))
    for path, data in [*decoded, *quantized_decoded]:
        if not path.exists():
            path.write_bytes(data)
    frame_paths = [path for path, _ in decoded]
    _filmstrip(target / "filmstrip.png", frame_paths)

    sanitized = _without_images(job)
    sanitized_response = sanitized.get("last_response", {})
    sanitized_response["files"] = records
    sanitized_response["frame_count"] = len(records)
    sanitized_response["quantized_files"] = quantized_records
    sanitized["last_response"] = sanitized_response
    (job_directory / "job-status.json").write_text(json.dumps(sanitized, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    report = {
        "job_id": expected_id,
        "status": job["status"],
        "usage": job.get("usage"),
        "last_response": sanitized_response,
    }
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("job_directory", type=Path, help="каталог пакета с response.json")
    parser.add_argument("raw_response", type=Path, help="путь к полному JSON ответа фоновой задачи")
    parser.add_argument("expected_frames", type=int, help="точное число изображений в last_response")
    parser.add_argument("--report", type=Path, help="куда записать компактный отчёт")
    args = parser.parse_args()
    try:
        report = extract(args.job_directory.resolve(), args.raw_response.resolve(), args.expected_frames)
        if args.report:
            args.report.parent.mkdir(parents=True, exist_ok=True)
            args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as error:
        parser.exit(2, f"{error}\n")
    print(json.dumps({"job_id": report["job_id"], "status": report["status"], "frames": report["last_response"]["frame_count"]}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
