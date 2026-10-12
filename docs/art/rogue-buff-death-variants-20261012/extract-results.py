"""Extract original PNG frames from the six accepted PixelLab jobs."""

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


def _read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(value, dict):
        raise ValueError(f"Expected JSON object: {path}")
    return value


def extract(variant: dict[str, Any], report: Path, requested_count: int) -> dict[str, Any]:
    variant_id = str(variant["id"])
    target = ROOT / variant_id / "pixellab"
    response_path = target / "response.json"
    if not response_path.is_file():
        return {"variant": variant_id, "status": "not_submitted"}
    accepted = _read_json(response_path)
    raw_path = report / f"{variant_id}-job.json"
    if not raw_path.is_file():
        return {"variant": variant_id, "status": "not_polled"}
    job = _read_json(raw_path)
    accepted_id = accepted.get("background_job_id")
    if not accepted_id or job.get("id") != accepted_id:
        raise ValueError(f"Wrong job for {variant_id}: accepted {accepted_id!r}, got {job.get('id')!r}")
    if job.get("status") != "completed":
        return {"variant": variant_id, "status": job.get("status")}

    result = job.get("last_response")
    if not isinstance(result, dict) or not isinstance(result.get("images"), list):
        raise ValueError(f"Completed job {variant_id} has no images array")
    entries = result["images"]
    expected_count = requested_count + 1
    if len(entries) != expected_count:
        raise ValueError(f"{variant_id}: received {len(entries)} frames, expected requested {requested_count} plus source frame")

    decoded: list[tuple[str, bytes]] = []
    records: list[dict[str, str]] = []
    for index, entry in enumerate(entries, start=1):
        encoded = entry.get("base64") if isinstance(entry, dict) else None
        if not isinstance(encoded, str):
            raise ValueError(f"{variant_id} frame {index}: missing base64 data")
        if encoded.startswith("data:"):
            encoded = encoded.split(",", 1)[1]
        try:
            data = base64.b64decode(encoded, validate=True)
        except (ValueError, base64.binascii.Error) as error:
            raise ValueError(f"{variant_id} frame {index}: invalid base64") from error
        if not data.startswith(b"\x89PNG\r\n\x1a\n"):
            raise ValueError(f"{variant_id} frame {index}: payload is not PNG")
        try:
            with Image.open(io.BytesIO(data)) as image:
                if image.size != (128, 128):
                    raise ValueError(f"{variant_id} frame {index}: size {image.size}, expected (128, 128)")
                image.load()
        except OSError as error:
            raise ValueError(f"{variant_id} frame {index}: unreadable PNG") from error
        name = f"frame-{index:02d}.png"
        decoded.append((name, data))
        records.append({"file": name, "sha256": hashlib.sha256(data).hexdigest()})

    expected_names = {name for name, _ in decoded}
    extras = {path.name for path in target.glob("frame-*.png")} - expected_names
    if extras:
        raise ValueError(f"{variant_id}: unexpected existing frames: {sorted(extras)}")
    for name, data in decoded:
        path = target / name
        if path.exists() and path.read_bytes() != data:
            raise ValueError(f"Refusing to overwrite changed source frame: {path}")

    for name, data in decoded:
        path = target / name
        if not path.exists():
            path.write_bytes(data)
    metadata = {key: value for key, value in result.items() if key not in {"images", "image"}}
    metadata.update({
        "job_id": job["id"],
        "status": job["status"],
        "requested_frame_count": requested_count,
        "frame_count": len(entries),
        "files": records,
    })
    (target / "result.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    summary = {key: value for key, value in job.items() if key != "last_response"}
    summary["last_response"] = {key: value for key, value in metadata.items() if key != "files"}
    (target / "job-status.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return {"variant": variant_id, "status": "completed", "frames": len(entries)}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report_directory", type=Path, help="directory containing raw <variant-id>-job.json files")
    parser.add_argument("--variant", help="extract only this manifest variant")
    args = parser.parse_args()
    report = args.report_directory.resolve()
    manifest = _read_json(ROOT / "request-manifest.json")
    variants = manifest.get("variants", [])
    if args.variant:
        variants = [variant for variant in variants if variant.get("id") == args.variant]
        if not variants:
            parser.error(f"unknown variant ID: {args.variant}")
    try:
        requested_count = int(manifest["requestedFrames"])
        results = [extract(variant, report, requested_count) for variant in variants]
    except (OSError, ValueError, KeyError) as error:
        parser.exit(2, f"{error}\n")
    print(json.dumps(results, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
