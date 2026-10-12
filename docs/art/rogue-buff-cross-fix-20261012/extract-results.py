"""Extract the completed single-variant PixelLab job without changing PNG bytes."""

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
VARIANT_ID = "buff-01-cross-fixed"


def _read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(value, dict):
        raise ValueError(f"Ожидался JSON-объект: {path}")
    return value


def extract(report: Path) -> dict[str, Any]:
    manifest = _read_json(ROOT / "request-manifest.json")
    requested_count = int(manifest["requestedFrames"])
    variants = manifest["variants"]
    selected = [item for item in variants if item.get("id") == VARIANT_ID]
    if len(variants) != 1 or len(selected) != 1:
        raise ValueError(f"Манифест должен содержать только вариант {VARIANT_ID}")
    folder = ROOT / VARIANT_ID / "pixellab"
    accepted = _read_json(folder / "response.json")
    raw_path = report / f"{VARIANT_ID}-job.json"
    job = _read_json(raw_path)
    accepted_id = accepted.get("background_job_id")
    if not accepted_id or job.get("id") != accepted_id:
        raise ValueError(f"Задание не совпало: принято {accepted_id!r}, получено {job.get('id')!r}")
    if job.get("status") != "completed":
        raise ValueError(f"Задание ещё не завершено: {job.get('status')!r}")
    result = job.get("last_response")
    if not isinstance(result, dict) or not isinstance(result.get("images"), list):
        raise ValueError("Завершённое задание не содержит массива images")
    entries = result["images"]
    expected_count = requested_count + 1
    if len(entries) != expected_count:
        raise ValueError(f"Получено {len(entries)} кадров; ожидалось {requested_count} + исходный кадр = {expected_count}")

    decoded: list[tuple[str, bytes]] = []
    records: list[dict[str, str]] = []
    for index, entry in enumerate(entries, start=1):
        encoded = entry.get("base64") if isinstance(entry, dict) else None
        if not isinstance(encoded, str):
            raise ValueError(f"Кадр {index}: отсутствуют base64-данные")
        if encoded.startswith("data:"):
            encoded = encoded.split(",", 1)[1]
        try:
            data = base64.b64decode(encoded, validate=True)
        except (ValueError, base64.binascii.Error) as error:
            raise ValueError(f"Кадр {index}: неверные base64-данные") from error
        if not data.startswith(b"\x89PNG\r\n\x1a\n"):
            raise ValueError(f"Кадр {index}: содержимое не является PNG")
        try:
            with Image.open(io.BytesIO(data)) as image:
                if image.size != (128, 128):
                    raise ValueError(f"Кадр {index}: размер {image.size}, ожидался (128, 128)")
                image.load()
        except OSError as error:
            raise ValueError(f"Кадр {index}: PNG не читается") from error
        name = f"frame-{index:02d}.png"
        decoded.append((name, data))
        records.append({"file": name, "sha256": hashlib.sha256(data).hexdigest()})

    folder.mkdir(parents=True, exist_ok=True)
    expected_names = {name for name, _ in decoded}
    extras = {path.name for path in folder.glob("frame-*.png")} - expected_names
    if extras:
        raise ValueError(f"Найдены неожиданные PNG-кадры: {sorted(extras)}")
    for name, data in decoded:
        path = folder / name
        if path.exists() and path.read_bytes() != data:
            raise ValueError(f"Отказ перезаписывать изменённый исходный кадр: {path}")
    for name, data in decoded:
        path = folder / name
        if not path.exists():
            path.write_bytes(data)

    metadata = {key: value for key, value in result.items() if key not in {"images", "image"}}
    metadata.update({"job_id": job["id"], "status": job["status"], "requested_frame_count": requested_count, "frame_count": len(entries), "files": records})
    (folder / "result.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    summary = {key: value for key, value in job.items() if key != "last_response"}
    summary["last_response"] = {key: value for key, value in metadata.items() if key != "files"}
    (folder / "job-status.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return {"variant": VARIANT_ID, "status": "completed", "requested_frames": requested_count, "actual_frames": len(entries), "source_png_bytes_preserved": True}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report_directory", type=Path, help="каталог с исходным <variant-id>-job.json")
    args = parser.parse_args()
    try:
        result = extract(args.report_directory.resolve())
    except (OSError, ValueError, KeyError) as error:
        parser.exit(2, f"{error}\n")
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
