"""Собрать проверяемые превью из PNG, полученных целиком от провайдера."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parent
FRAME_SIZE = (128, 128)
BACKGROUND = (63, 75, 67)
BACKGROUND_RGBA = (*BACKGROUND, 255)


def _json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(value, dict):
        raise ValueError(f"Ожидался JSON-объект: {path}")
    return value


def _hash(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _open_frames(root: Path, manifest: dict[str, Any]) -> tuple[list[Path], list[Image.Image], list[int]]:
    entries = manifest.get("frames")
    if not isinstance(entries, list) or len(entries) != 5:
        raise ValueError("manifest.frames должен явно задавать все 5 кадров")
    paths: list[Path] = []
    frames: list[Image.Image] = []
    durations: list[int] = []
    for index, entry in enumerate(entries, 1):
        if not isinstance(entry, dict) or not isinstance(entry.get("source"), str):
            raise ValueError(f"Кадр {index}: требуется source в манифесте")
        source_path = (root / entry["source"]).resolve()
        if not source_path.is_relative_to(root.resolve()):
            raise ValueError(f"Кадр {index}: источник выходит за пределы пакета")
        if entry.get("sha256") != _hash(source_path.read_bytes()):
            raise ValueError(f"Кадр {index}: SHA256 не совпадает с происхождением")
        duration = entry.get("duration_ms")
        if not isinstance(duration, int) or duration <= 0:
            raise ValueError(f"Кадр {index}: duration_ms должен быть положительным целым числом")
        with Image.open(source_path) as source:
            if source.format != "PNG" or source.size != FRAME_SIZE:
                raise ValueError(f"Кадр {index}: ожидался PNG {FRAME_SIZE}, получено {source.format} {source.size}")
            frame = source.convert("RGBA")
        paths.append(source_path)
        frames.append(frame)
        durations.append(duration)
    return paths, frames, durations


def _composite(frame: Image.Image, scale: int) -> Image.Image:
    canvas = Image.new("RGBA", (FRAME_SIZE[0] * scale, FRAME_SIZE[1] * scale), BACKGROUND_RGBA)
    canvas.alpha_composite(frame.resize(canvas.size, Image.Resampling.NEAREST))
    return canvas.convert("RGB")


def _native_frame(frame: Image.Image) -> Image.Image:
    indexed = frame.convert("RGB").quantize(colors=255, method=Image.Quantize.MEDIANCUT)
    pixels = list(indexed.getdata())
    alpha = list(frame.getchannel("A").getdata())
    indexed.putdata([255 if value == 0 else index for index, value in zip(pixels, alpha)])
    palette = indexed.getpalette() or []
    palette.extend([0] * (768 - len(palette)))
    palette[765:768] = [0, 0, 0]
    indexed.putpalette(palette)
    indexed.info["transparency"] = 255
    return indexed


def _runs(frames: list[Image.Image], durations: list[int]) -> list[tuple[bytes, int]]:
    result: list[tuple[bytes, int]] = []
    for frame, duration in zip(frames, durations):
        signature = frame.convert("RGBA").tobytes()
        if result and result[-1][0] == signature:
            result[-1] = (signature, result[-1][1] + duration)
        else:
            result.append((signature, duration))
    return result


def _save_gif(path: Path, frames: list[Image.Image], durations: list[int], transparent: bool = False) -> dict[str, Any]:
    encoded = [_native_frame(frame) for frame in frames] if transparent else frames
    encoded[0].save(path, save_all=True, append_images=encoded[1:], duration=durations, loop=0, disposal=2, optimize=False, **({"transparency": 255} if transparent else {}))
    decoded: list[Image.Image] = []
    actual_durations: list[int] = []
    with Image.open(path) as gif:
        for index in range(gif.n_frames):
            gif.seek(index)
            decoded.append(gif.convert("RGBA").copy())
            actual_durations.append(int(gif.info.get("duration", 0)))
    expected_frames = frames
    if transparent:
        # GIF alpha is binary; parity compares visible source RGBA pixels per logical frame below.
        if len(decoded) != len(frames):
            raise ValueError(f"{path.name}: число кадров изменилось при кодировании")
        if actual_durations != durations:
            raise ValueError(f"{path.name}: длительности отличаются от манифеста")
        for index, (source, output) in enumerate(zip(frames, decoded), 1):
            if any(a[3] != b[3] or (a[3] > 0 and a != b) for a, b in zip(source.getdata(), output.getdata())):
                raise ValueError(f"{path.name}, кадр {index}: видимые RGBA отличаются от PNG")
    elif _runs(decoded, actual_durations) != _runs(expected_frames, durations):
        raise ValueError(f"{path.name}: кадры или длительности изменились при кодировании")
    return {"encoded_frame_count": len(decoded), "logical_frame_count": len(frames), "size": list(decoded[0].size), "actual_frame_durations_ms": actual_durations, "actual_total_duration_ms": sum(actual_durations), "loop": 0, "transparent_index": 255 if transparent else None}


def _filmstrip(path: Path, frames: list[Image.Image]) -> None:
    cell, label_height = 256, 30
    sheet = Image.new("RGBA", (len(frames) * cell, cell + label_height), BACKGROUND_RGBA)
    draw = ImageDraw.Draw(sheet)
    font_path = Path("C:/Windows/Fonts/arial.ttf")
    font = ImageFont.truetype(str(font_path), 18) if font_path.is_file() else ImageFont.load_default()
    for index, frame in enumerate(frames):
        x = index * cell
        sheet.alpha_composite(frame.resize((cell, cell), Image.Resampling.NEAREST), (x, 0))
        draw.text((x + 8, cell + 5), f"{index + 1:02}", fill=(240, 243, 236, 255), font=font)
    sheet.save(path)


def _metrics(root: Path, path: Path, frame: Image.Image, index: int, provenance: Any) -> dict[str, Any]:
    alpha = frame.getchannel("A")
    bbox = alpha.getbbox()
    values = list(alpha.getdata())
    if bbox is None:
        raise ValueError(f"Кадр {index}: пустой")
    touches_edge = bbox[0] == 0 or bbox[1] == 0 or bbox[2] == 128 or bbox[3] == 128
    if touches_edge:
        raise ValueError(f"Кадр {index}: возможное обрезание границей холста")
    return {"frame": index, "source": str(path.relative_to(root)), "provenance": provenance, "file_sha256": _hash(path.read_bytes()), "rgba_sha256": _hash(frame.tobytes()), "size": list(frame.size), "alpha_bbox": list(bbox), "touches_canvas_edge": touches_edge, "visible_pixels": sum(value > 0 for value in values), "transparent_pixels": values.count(0), "partial_alpha_pixels": sum(0 < value < 255 for value in values), "alpha_levels": len(set(values))}


def _edge_diff(first: Image.Image, last: Image.Image) -> dict[str, Any]:
    left, right = list(first.getdata()), list(last.getdata())
    changed = [a != b for a, b in zip(left, right)]
    return {"different_pixels": sum(changed), "visible_union_different_pixels": sum(flag and (a[3] > 0 or b[3] > 0) for flag, a, b in zip(changed, left, right)), "alpha_mismatch_pixels": sum(a[3] != b[3] for a, b in zip(left, right)), "first_rgba_sha256": _hash(first.tobytes()), "last_rgba_sha256": _hash(last.tobytes())}


def build(root: Path) -> dict[str, Any]:
    manifest_path = root / "final" / "manifest.json"
    manifest = _json(manifest_path)
    paths, frames, durations = _open_frames(root, manifest)
    target = root / "final"
    large = [_composite(frame, 4) for frame in frames]
    uniform = [200] * len(frames)
    previews = {
        "preview.gif": _save_gif(target / "preview.gif", large, durations),
        "native.gif": _save_gif(target / "native.gif", frames, durations, transparent=True),
        "uniform-preview.gif": _save_gif(target / "uniform-preview.gif", large, uniform),
    }
    _filmstrip(target / "filmstrip.png", frames)
    records = []
    for index, (path, frame, entry) in enumerate(zip(paths, frames, manifest["frames"]), 1):
        records.append(_metrics(root, path, frame, index, entry.get("provenance")))
    report = {
        "status": "ready",
        "manifest": str(manifest_path.relative_to(root)),
        "frame_count": len(frames),
        "distinct_rgba_frames": len({frame.tobytes() for frame in frames}),
        "frames": records,
        "first_vs_last": _edge_diff(frames[0], frames[-1]),
        "requested_timing_ms": {"primary": durations, "primary_total": sum(durations), "uniform_diagnostic": uniform, "uniform_total": sum(uniform)},
        "previews": previews,
        "native_visible_rgba_parity": "verified for each logical frame",
        "preview_composite": "128x128 RGBA source, nearest-neighbor 4x, RGB background #3f4b43",
        "native_gif": "128x128 with transparent palette index 255",
    }
    (target / "validation.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT, help="корень пакета")
    args = parser.parse_args()
    try:
        report = build(args.root.resolve())
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as error:
        print(str(error), file=sys.stderr)
        return 2
    print(json.dumps({"status": report["status"], "frames": report["frame_count"], "previews": report["previews"]}, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
