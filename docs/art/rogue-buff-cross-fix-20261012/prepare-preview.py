"""Build review previews and fidelity validation for one rogue buff animation."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parent
VARIANT_ID = "buff-01-cross-fixed"
FRAME_SIZE = (128, 128)
BACKGROUND = (63, 75, 67)
BACKGROUND_RGBA = (*BACKGROUND, 255)
WHITE = (240, 243, 236)
LOOP = 0
DEFAULT_DURATIONS_MS = [200, 80, 80, 120, 240, 80, 80, 100, 200]


def _json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(value, dict):
        raise ValueError(f"Ожидался JSON-объект: {path}")
    return value


def _manifest(root: Path) -> tuple[dict[str, Any], Image.Image, Path]:
    manifest = _json(root / "request-manifest.json")
    if len(manifest.get("variants", [])) != 1 or manifest["variants"][0].get("id") != VARIANT_ID:
        raise ValueError(f"Манифест должен содержать только {VARIANT_ID}")
    reference_path = root / "reference-128.png"
    with Image.open(reference_path) as image:
        if image.size != FRAME_SIZE:
            raise ValueError(f"Размер reference {image.size}, ожидался {FRAME_SIZE}")
        reference = image.convert("RGBA")
    expected_sha256 = manifest.get("sourceSha256")
    if expected_sha256 and hashlib.sha256(reference_path.read_bytes()).hexdigest() != expected_sha256:
        raise ValueError("reference-128.png не совпадает с sourceSha256 манифеста")
    return manifest, reference, reference_path


def _sources(root: Path, requested_count: int, variant_id: str) -> tuple[list[Path], list[Image.Image]]:
    folder = root / variant_id / "pixellab"
    result = _json(folder / "result.json")
    if result.get("requested_frame_count") != requested_count:
        raise ValueError(f"requested_frame_count должен быть {requested_count}")
    frame_count = result.get("frame_count")
    if frame_count != requested_count + 1:
        raise ValueError(f"Фактическое число кадров {frame_count!r}; ожидалось {requested_count} + исходный")
    paths = [folder / f"frame-{index:02d}.png" for index in range(1, frame_count + 1)]
    missing = [path for path in paths if not path.is_file()]
    if missing:
        raise FileNotFoundError("Не найдены кадры:\n" + "\n".join(map(str, missing)))
    if {path.name for path in folder.glob("frame-*.png")} != {path.name for path in paths}:
        raise ValueError("Набор кадров содержит пропуски или лишние PNG")
    files = result.get("files", [])
    frames: list[Image.Image] = []
    for index, path in enumerate(paths):
        raw = path.read_bytes()
        expected_hash = files[index].get("sha256") if index < len(files) else None
        if not expected_hash or hashlib.sha256(raw).hexdigest() != expected_hash:
            raise ValueError(f"Кадр {index + 1}: байты не совпадают с хешем извлечения")
        with Image.open(path) as source:
            if source.size != FRAME_SIZE:
                raise ValueError(f"{path}: размер {source.size}, ожидался {FRAME_SIZE}")
            frames.append(source.convert("RGBA"))
    return paths, frames


def _composite(frame: Image.Image, scale: int = 4) -> Image.Image:
    canvas = Image.new("RGBA", (FRAME_SIZE[0] * scale, FRAME_SIZE[1] * scale), BACKGROUND_RGBA)
    canvas.alpha_composite(frame.resize(canvas.size, Image.Resampling.NEAREST))
    return canvas.convert("RGB")


def _native_gif_frame(frame: Image.Image) -> Image.Image:
    # Для прозрачного фона GIF нужен отдельный индекс палитры; видимые RGB-пиксели остаются исходными.
    rgb = frame.convert("RGB").quantize(colors=255, method=Image.Quantize.MEDIANCUT)
    pixels, alpha = list(rgb.getdata()), list(frame.getchannel("A").getdata())
    rgb.putdata([255 if value == 0 else index for index, value in zip(pixels, alpha)])
    palette = rgb.getpalette() or []
    palette.extend([0] * (768 - len(palette)))
    palette[765:768] = [0, 0, 0]
    rgb.putpalette(palette)
    rgb.info["transparency"] = 255
    return rgb


def _runs(frames: list[Image.Image], durations: list[int]) -> list[int]:
    result: list[int] = []
    previous: bytes | None = None
    for frame, duration in zip(frames, durations):
        signature = frame.convert("RGBA").tobytes()
        if signature == previous:
            result[-1] += duration
        else:
            result.append(duration)
            previous = signature
    return result


def _save_gif(path: Path, frames: list[Image.Image], durations: list[int], transparent: bool = False) -> dict[str, Any]:
    if len(frames) != len(durations) or not frames:
        raise ValueError(f"{path.name}: число кадров и длительностей не совпадает")
    encoded = [_native_gif_frame(frame) for frame in frames] if transparent else frames
    encoded[0].save(path, save_all=True, append_images=encoded[1:], duration=durations, loop=LOOP, disposal=2, optimize=False, **({"transparency": 255} if transparent else {}))
    decoded: list[Image.Image] = []
    decoded_durations: list[int] = []
    with Image.open(path) as gif:
        for index in range(gif.n_frames):
            gif.seek(index)
            decoded.append(gif.convert("RGBA").copy())
            decoded_durations.append(int(gif.info.get("duration", 0)))
    if _runs(decoded, decoded_durations) != _runs(frames, durations):
        raise ValueError(f"{path.name}: GIF изменил последовательность кадров или интервалы")
    return {"encoded_frames": len(decoded), "logical_frames": len(frames), "size": list(decoded[0].size), "duration_ms": decoded_durations, "total_ms": sum(decoded_durations), "merged_adjacent_runs_ms": _runs(decoded, decoded_durations), "transparent_index": 255 if transparent else None}


def _metrics(path: Path, frame: Image.Image, index: int) -> dict[str, Any]:
    alpha = list(frame.getchannel("A").getdata())
    bbox = frame.getchannel("A").getbbox()
    return {"frame": index, "file_sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "rgba_sha256": hashlib.sha256(frame.tobytes()).hexdigest(), "size": list(frame.size), "alpha_bbox": list(bbox) if bbox else None, "touches_canvas_edge_possible_clipping": bool(bbox and (bbox[0] == 0 or bbox[1] == 0 or bbox[2] == 128 or bbox[3] == 128)), "alpha_min": min(alpha), "alpha_max": max(alpha), "distinct_alpha_levels": len(set(alpha)), "transparent_pixels": alpha.count(0), "partial_alpha_pixels": sum(0 < value < 255 for value in alpha), "visible_pixels": sum(value > 0 for value in alpha)}


def _filmstrip(path: Path, frames: list[Image.Image]) -> None:
    columns, cell, label_height = 5, 256, 30
    rows = (len(frames) + columns - 1) // columns
    sheet = Image.new("RGBA", (columns * cell, rows * (cell + label_height)), BACKGROUND_RGBA)
    draw = ImageDraw.Draw(sheet)
    font_path = Path("C:/Windows/Fonts/arial.ttf")
    font = ImageFont.truetype(str(font_path), 18) if font_path.is_file() else ImageFont.load_default()
    for index, frame in enumerate(frames):
        x, y = index % columns * cell, index // columns * (cell + label_height)
        sheet.alpha_composite(frame.resize((cell, cell), Image.Resampling.NEAREST), (x, y))
        draw.text((x + 8, y + cell + 6), str(index + 1), fill=WHITE, font=font)
    sheet.save(path)


def _edge_report(first: Image.Image, last: Image.Image) -> dict[str, Any]:
    left, right = list(first.getdata()), list(last.getdata())
    changed = [a != b for a, b in zip(left, right)]
    return {"different_pixels": sum(changed), "visible_union_different_pixels": sum(flag and (a[3] > 0 or b[3] > 0) for flag, a, b in zip(changed, left, right)), "alpha_mismatch_pixels": sum(a[3] != b[3] for a, b in zip(left, right)), "hidden_transparent_rgb_only_changes": sum(a[:3] != b[:3] and a[3] == 0 and b[3] == 0 for a, b in zip(left, right)), "first_rgba_sha256": hashlib.sha256(first.tobytes()).hexdigest(), "last_rgba_sha256": hashlib.sha256(last.tobytes()).hexdigest()}


def build(root: Path, variant_id: str = VARIANT_ID, validation_name: str = "validation.json") -> dict[str, Any]:
    manifest, reference, reference_path = _manifest(root)
    requested_count = int(manifest["requestedFrames"])
    durations = manifest.get("previewDurationsMs", DEFAULT_DURATIONS_MS)
    if not isinstance(durations, list) or len(durations) != requested_count + 1 or any(not isinstance(value, int) or value <= 0 for value in durations):
        raise ValueError("previewDurationsMs должен содержать положительную длительность для каждого кадра")
    folder = root / variant_id
    paths, frames = _sources(root, requested_count, variant_id)
    durations = list(durations)
    root_preview = _save_gif(folder / "preview.gif", [_composite(frame) for frame in frames], durations)
    native_preview = _save_gif(folder / "native.gif", frames, durations, transparent=True)
    uniform_preview = _save_gif(folder / "uniform-preview.gif", [_composite(frame) for frame in frames], [200] * len(frames))
    _filmstrip(folder / "filmstrip.png", frames)
    native_visible_parity: list[dict[str, Any]] = []
    with Image.open(folder / "native.gif") as native:
        if native.n_frames != len(frames):
            raise ValueError("native.gif: число кадров отличается от источника")
        for index, source in enumerate(frames):
            native.seek(index)
            decoded = native.convert("RGBA")
            source_visible = [pixel for pixel in source.getdata() if pixel[3] > 0]
            decoded_visible = [pixel for pixel in decoded.getdata() if pixel[3] > 0]
            if decoded_visible != source_visible:
                raise ValueError(f"native.gif кадр {index + 1}: видимые пиксели отличаются от PNG")
            native_visible_parity.append({"frame": index + 1, "visible_pixels": len(source_visible), "exact_visible_rgba_match": True, "hidden_transparent_rgb_pixel_differences": sum(a[:3] != b[:3] and a[3] == 0 and b[3] == 0 for a, b in zip(source.getdata(), decoded.getdata()))})

    frame_reports = [_metrics(path, frame, index) for index, (path, frame) in enumerate(zip(paths, frames), 1)]
    reference_pixels, first_pixels = list(reference.getdata()), list(frames[0].getdata())
    reference_changed = [a != b for a, b in zip(first_pixels, reference_pixels)]
    reference_report = {"reference": str(reference_path.relative_to(root)), "exact_rgba_match": frames[0].tobytes() == reference.tobytes(), "different_pixels": sum(reference_changed), "visible_union_different_pixels": sum(flag and (a[3] > 0 or b[3] > 0) for flag, a, b in zip(reference_changed, first_pixels, reference_pixels)), "alpha_mismatch_pixels": sum(a[3] != b[3] for a, b in zip(first_pixels, reference_pixels)), "hidden_transparent_rgb_only_changes": sum(a[:3] != b[:3] and a[3] == 0 and b[3] == 0 for a, b in zip(first_pixels, reference_pixels))}
    sequence_metadata = _json(folder / "pixellab" / "result.json")
    result = {"variant": variant_id, "kind": "buff", "title": manifest["variants"][0].get("title"), "old_b1_reference": {"path": "../rogue-buff-death-variants-20261012/buff-01-cross", "role": "metadata/reference only; no composite generated"}, "source_frames": frame_reports, "requested_frame_count": requested_count, "actual_frame_count": len(frames), "distinct_rgba_frames": len({frame.tobytes() for frame in frames}), "first_frame_vs_reference": reference_report, "first_vs_last": _edge_report(frames[0], frames[-1]), "previews": {"preview.gif": root_preview, "native.gif": native_preview, "uniform-preview.gif": uniform_preview}, "native_visible_pixel_parity": native_visible_parity, "timing_ms": {"primary": durations, "uniform_diagnostic": [200] * len(frames), "primary_total": sum(durations), "uniform_total": len(frames) * 200}, "source_edits": sequence_metadata.get("composition", "none; every source PNG is read without modification"), "provenance": sequence_metadata.get("provenance"), "preview_transform": "nearest-neighbor 4x RGB composite on #3f4b43", "native_gif": "128x128 with transparent palette index; visible RGBA pixels checked against each source frame"}
    (root / validation_name).write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT, help="каталог пакета")
    parser.add_argument("--variant-id", default=VARIANT_ID, help="каталог варианта внутри пакета")
    parser.add_argument("--validation-name", default="validation.json", help="имя JSON отчёта в корне пакета")
    args = parser.parse_args()
    try:
        result = build(args.root.resolve(), args.variant_id, args.validation_name)
    except (OSError, ValueError, KeyError) as error:
        print(str(error), file=sys.stderr)
        return 2
    print(json.dumps({"variant": result["variant"], "status": "ready", "actual_frames": result["actual_frame_count"], "previews": result["previews"]}, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
