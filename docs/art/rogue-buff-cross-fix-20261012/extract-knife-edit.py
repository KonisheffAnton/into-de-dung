"""Extract three targeted edit frames and assemble an exact-byte corrected sequence."""

from __future__ import annotations

import argparse
import base64
import hashlib
import io
import json
from pathlib import Path
from typing import Any

from PIL import Image


ROOT = Path(__file__).resolve().parent
EDIT_ID = "42518d5b-de5d-4508-a3a8-d61d5eaff7ed"
EDITED_INDICES = (4, 5, 6)


def _json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(value, dict):
        raise ValueError(f"Ожидался JSON-объект: {path}")
    return value


def _decode(entry: Any, frame_number: int) -> bytes:
    encoded = entry.get("base64") if isinstance(entry, dict) else None
    if not isinstance(encoded, str):
        raise ValueError(f"Результат кадра {frame_number}: отсутствует base64")
    if encoded.startswith("data:"):
        encoded = encoded.split(",", 1)[1]
    try:
        data = base64.b64decode(encoded, validate=True)
    except (ValueError, base64.binascii.Error) as error:
        raise ValueError(f"Результат кадра {frame_number}: некорректный base64") from error
    if not data.startswith(b"\x89PNG\r\n\x1a\n"):
        raise ValueError(f"Результат кадра {frame_number}: содержимое не PNG")
    if isinstance(entry, dict) and (entry.get("width"), entry.get("height")) != (128, 128):
        raise ValueError(f"Результат кадра {frame_number}: метаданные размера не равны 128x128")
    try:
        with Image.open(io.BytesIO(data)) as image_file:
            if image_file.size != (128, 128):
                raise ValueError(f"Результат кадра {frame_number}: размер {image_file.size}, ожидался (128, 128)")
            image_file.load()
            if image_file.mode not in {"RGBA", "LA", "P"} or "transparency" not in image_file.info and image_file.mode not in {"RGBA", "LA"}:
                raise ValueError(f"Результат кадра {frame_number}: PNG не содержит альфа-канал")
            if image_file.convert("RGBA").getchannel("A").getextrema() == (255, 255):
                raise ValueError(f"Результат кадра {frame_number}: фон полностью непрозрачен")
    except OSError as error:
        raise ValueError(f"Результат кадра {frame_number}: PNG не читается") from error
    return data


def _write_unchanged(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        if path.read_bytes() != data:
            raise ValueError(f"Отказ перезаписывать отличающийся файл: {path}")
    else:
        path.write_bytes(data)


def extract(report_directory: Path) -> dict[str, Any]:
    edit_root = ROOT / "knife-edit"
    manifest = _json(edit_root / "manifest.json")
    response = _json(edit_root / "response.json")
    job = _json(report_directory / "knife-edit-job.json")
    accepted_id = response.get("background_job_id")
    if accepted_id != EDIT_ID or job.get("id") != accepted_id:
        raise ValueError(f"ID задания не совпал: принято {accepted_id!r}, получено {job.get('id')!r}")
    if job.get("status") != "completed":
        raise ValueError(f"Задание ещё не завершено: {job.get('status')!r}")
    last_response = job.get("last_response")
    if not isinstance(last_response, dict) or not isinstance(last_response.get("images"), list):
        raise ValueError("Завершённое задание не содержит last_response.images")
    entries = last_response["images"]
    if len(entries) != len(EDITED_INDICES):
        raise ValueError(f"Получено {len(entries)} результата; ожидалось ровно {len(EDITED_INDICES)}")
    quantized_entries = last_response.get("quantized_images")
    if not isinstance(quantized_entries, list) or len(quantized_entries) != len(EDITED_INDICES):
        raise ValueError("quantized_images отсутствует или содержит не три результата")

    input_records = manifest.get("sourceFrames")
    if not isinstance(input_records, list) or [record.get("index") for record in input_records] != list(EDITED_INDICES):
        raise ValueError("knife-edit/manifest.json должен описывать исходные кадры 4, 5, 6 именно в этом порядке")
    original_folder = ROOT / "buff-01-cross-fixed" / "pixellab"
    original_result = _json(original_folder / "result.json")
    original_hashes = {item.get("file"): item.get("sha256") for item in original_result.get("files", [])}
    for record in input_records:
        source = original_folder / f"frame-{record['index']:02d}.png"
        if not source.is_file() or hashlib.sha256(source.read_bytes()).hexdigest() != record.get("sha256"):
            raise ValueError(f"Исходный кадр {record.get('index')} не совпал с SHA-256 запроса")

    edit_folder = edit_root
    corrected_folder = ROOT / "corrected" / "pixellab"
    edit_records: list[dict[str, Any]] = []
    for order, (record, entry) in enumerate(zip(input_records, entries), start=1):
        data = _decode(entry, order)
        edit_name = f"frame-{order:02d}.png"
        _write_unchanged(edit_folder / edit_name, data)
        quantized_data = _decode(quantized_entries[order - 1], order)
        quantized_name = f"quantized-frame-{order:02d}.png"
        _write_unchanged(edit_folder / quantized_name, quantized_data)
        source_index = int(record["index"])
        edit_records.append({"source_frame": source_index, "edited_file": edit_name, "edited_sha256": hashlib.sha256(data).hexdigest(), "quantized_file": quantized_name, "quantized_sha256": hashlib.sha256(quantized_data).hexdigest()})

    corrected_records: list[dict[str, str]] = []
    for index in range(1, 10):
        if index in EDITED_INDICES:
            edited_data = (edit_folder / f"frame-{EDITED_INDICES.index(index) + 1:02d}.png").read_bytes()
            origin = f"knife-edit/frame-{EDITED_INDICES.index(index) + 1:02d}.png"
            data = edited_data
        else:
            source_path = original_folder / f"frame-{index:02d}.png"
            if not source_path.is_file():
                raise FileNotFoundError(f"Нет исходного кадра {index}: {source_path}")
            data = source_path.read_bytes()
            if hashlib.sha256(data).hexdigest() != original_hashes.get(source_path.name):
                raise ValueError(f"Исходный кадр {index} отличается от первой извлечённой версии")
            origin = f"buff-01-cross-fixed/pixellab/frame-{index:02d}.png"
        name = f"frame-{index:02d}.png"
        _write_unchanged(corrected_folder / name, data)
        corrected_records.append({"file": name, "sha256": hashlib.sha256(data).hexdigest(), "source": origin})

    metadata = {
        "job_id": job["id"],
        "status": job["status"],
        "requested_frame_count": 8,
        "frame_count": len(corrected_records),
        "files": [{"file": item["file"], "sha256": item["sha256"]} for item in corrected_records],
        "composition": "Frames 1-3 and 7-9 are unchanged original PNG bytes; frames 4-6 are complete replacement PNGs from the targeted edit.",
        "provenance": corrected_records,
        "edited_frames": edit_records,
        "job_metadata": {key: value for key, value in last_response.items() if key not in {"images", "quantized_images", "image"}},
        "job_usage": job.get("usage"),
        "last_response_metadata": {key: value for key, value in last_response.items() if key not in {"images", "quantized_images", "image"}},
    }
    (corrected_folder / "result.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (ROOT / "corrected" / "provenance.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    job_summary = {key: value for key, value in job.items() if key != "last_response"}
    job_summary["last_response"] = {key: value for key, value in last_response.items() if key not in {"images", "quantized_images", "image"}}
    (edit_folder / "job-status.json").write_text(json.dumps(job_summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return {"status": "assembled", "job_id": job["id"], "edited_frames": list(EDITED_INDICES), "corrected_frames": len(corrected_records), "unchanged_original_frames": [1, 2, 3, 7, 8, 9], "edited_png_bytes_preserved": True, "corrected_png_bytes_preserved": True}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report_directory", type=Path, help="каталог с raw knife-edit-job.json")
    args = parser.parse_args()
    try:
        result = extract(args.report_directory.resolve())
    except (OSError, ValueError, KeyError) as error:
        parser.exit(2, f"{error}\n")
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
