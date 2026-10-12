"""Build proposal previews from complete, unmodified PixelLab death clips."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw, ImageFont


VARIANTS = (
    ("01-forward-shield", "1.FORWARD"),
    ("02-backward", "2.BACKWARD"),
    ("03-last-knee", "3.LAST KNEE"),
)
FRAME_COUNT = 33
FRAME_SIZE = (128, 128)
BACKGROUND_RGB = (22, 33, 43)
BACKGROUND_RGBA = (*BACKGROUND_RGB, 255)
FRAME_DURATIONS_MS = [60] * 32 + [900]
GIF_LOOP = 0


def _reference_path(root: Path) -> Path | None:
    candidates = (
        root / "pixellab" / "reference-128.png",
        root / "reference-128.png",
        *(root / folder / "pixellab" / "reference-128.png" for folder, _ in VARIANTS),
    )
    return next((path for path in candidates if path.is_file()), None)


def _frame_paths(folder: Path) -> tuple[list[Path], list[str]]:
    frame_dir = folder / "pixellab"
    expected = [frame_dir / f"frame-{index:02}.png" for index in range(1, FRAME_COUNT + 1)]
    missing = [str(path.relative_to(folder.parent)) for path in expected if not path.is_file()]
    return expected, missing


def _open_sources(paths: list[Path], label: str) -> list[Image.Image]:
    frames: list[Image.Image] = []
    for path in paths:
        with Image.open(path) as source:
            if source.size != FRAME_SIZE:
                raise ValueError(f"{label}: {path.name} has size {source.size}, expected {FRAME_SIZE}")
            frames.append(source.convert("RGBA"))
    return frames


def _composite(frame: Image.Image, size: tuple[int, int]) -> Image.Image:
    canvas = Image.new("RGBA", size, BACKGROUND_RGBA)
    enlarged = frame.resize(size, Image.Resampling.NEAREST)
    canvas.alpha_composite(enlarged)
    return canvas.convert("RGB")


def _output_frames(frames: list[Image.Image], scale: int) -> list[Image.Image]:
    size = (FRAME_SIZE[0] * scale, FRAME_SIZE[1] * scale)
    return [_composite(frame, size) for frame in frames]


def _save_gif(path: Path, frames: list[Image.Image], durations: list[int]) -> dict[str, Any]:
    if len(frames) != len(durations):
        raise ValueError(f"{path.name}: frame and duration counts differ")
    frames[0].save(
        path,
        save_all=True,
        append_images=frames[1:],
        duration=durations,
        loop=GIF_LOOP,
        disposal=2,
        optimize=False,
    )

    actual_frames: list[Image.Image] = []
    actual_durations: list[int] = []
    with Image.open(path) as gif:
        for index in range(gif.n_frames):
            gif.seek(index)
            actual_frames.append(gif.convert("RGB").copy())
            actual_durations.append(int(gif.info.get("duration", 0)))

    if sum(actual_durations) != sum(durations):
        raise ValueError(
            f"{path.name}: encoded total is {sum(actual_durations)}ms, expected {sum(durations)}ms"
        )

    # Pillow may combine identical adjacent frames. Check the elapsed time for
    # each decoded run so such merging cannot silently alter the death rhythm.
    expected_runs: list[int] = []
    actual_runs: list[int] = []
    previous: bytes | None = None
    for frame, duration in zip(frames, durations):
        signature = frame.convert("RGB").tobytes()
        if signature == previous:
            expected_runs[-1] += duration
        else:
            expected_runs.append(duration)
            previous = signature
    previous = None
    for frame, duration in zip(actual_frames, actual_durations):
        signature = frame.tobytes()
        if signature == previous:
            actual_runs[-1] += duration
        else:
            actual_runs.append(duration)
            previous = signature
    if expected_runs != actual_runs:
        raise ValueError(f"{path.name}: decoded adjacent-frame timing differs from requested timing")

    return {
        "frames": len(actual_frames),
        "size": list(actual_frames[0].size),
        "duration_ms": actual_durations,
        "total_ms": sum(actual_durations),
        "merged_adjacent_runs_ms": actual_runs,
    }


def _frame_validation(path: Path, frame: Image.Image, index: int) -> dict[str, Any]:
    alpha = frame.getchannel("A")
    alpha_values = alpha.tobytes()
    return {
        "frame": index,
        "size": list(frame.size),
        "file_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "rgba_sha256": hashlib.sha256(frame.tobytes()).hexdigest(),
        "alpha_bbox": list(alpha.getbbox()) if alpha.getbbox() else None,
        "alpha_min": min(alpha_values),
        "alpha_max": max(alpha_values),
        "transparent_pixels": sum(value == 0 for value in alpha_values),
        "partial_alpha_pixels": sum(0 < value < 255 for value in alpha_values),
    }


def _write_filmstrip(path: Path, frames: list[Image.Image]) -> None:
    columns = 6
    cell_width = 256
    cell_height = 280
    rows = (len(frames) + columns - 1) // columns
    sheet = Image.new("RGBA", (columns * cell_width, rows * cell_height), BACKGROUND_RGBA)
    draw = ImageDraw.Draw(sheet)
    for index, frame in enumerate(frames):
        x = index % columns * cell_width
        y = index // columns * cell_height
        sheet.alpha_composite(frame.resize((256, 256), Image.Resampling.NEAREST), (x, y))
        draw.text((x + 8, y + 261), f"{index + 1:02d}", fill=(230, 234, 238, 255))
    sheet.save(path)


def _comparison_frames(clips: list[list[Image.Image]], titles: list[str]) -> list[Image.Image]:
    scale = 3
    panel_size = (FRAME_SIZE[0] * scale, FRAME_SIZE[1] * scale)
    title_height = 28
    combined: list[Image.Image] = []
    font = ImageFont.load_default()
    for frame_index in range(FRAME_COUNT):
        canvas = Image.new(
            "RGB",
            (panel_size[0] * len(clips), panel_size[1] + title_height),
            BACKGROUND_RGB,
        )
        draw = ImageDraw.Draw(canvas)
        for variant_index, clip in enumerate(clips):
            x = panel_size[0] * variant_index
            draw.text((x + 10, 7), titles[variant_index], fill=(238, 242, 246), font=font)
            canvas.paste(_composite(clip[frame_index], panel_size), (x, title_height))
        combined.append(canvas)
    return combined


def _prepare(root: Path) -> dict[str, Any]:
    missing: list[str] = []
    variant_paths: dict[str, list[Path]] = {}
    for folder_name, _ in VARIANTS:
        paths, absent = _frame_paths(root / folder_name)
        variant_paths[folder_name] = paths
        missing.extend(absent)
    reference_path = _reference_path(root)
    if reference_path is None:
        missing.append(str(root / "pixellab" / "reference-128.png") + " (reference not found)")
    if missing:
        raise FileNotFoundError("Missing required source files; no previews were written:\n" + "\n".join(missing))

    reference = _open_sources([reference_path], "reference")[0]
    sources: dict[str, list[Image.Image]] = {}
    for folder_name, _ in VARIANTS:
        sources[folder_name] = _open_sources(variant_paths[folder_name], folder_name)
    return {
        "reference_path": reference_path,
        "reference": reference,
        "variant_paths": variant_paths,
        "sources": sources,
    }


def build_previews(root: Path) -> dict[str, Any]:
    prepared = _prepare(root)
    reference: Image.Image = prepared["reference"]
    sources: dict[str, list[Image.Image]] = prepared["sources"]
    variants: dict[str, Any] = {}
    comparison_clips: list[list[Image.Image]] = []
    titles: list[str] = []

    reference_hash = hashlib.sha256(reference.tobytes()).hexdigest()
    for folder_name, title in VARIANTS:
        folder = root / folder_name
        source_frames = sources[folder_name]
        preview_frames = _output_frames(source_frames, 4)
        native_frames = _output_frames(source_frames, 1)
        paths: list[Path] = prepared["variant_paths"][folder_name]

        preview_info = _save_gif(folder / "preview.gif", preview_frames, FRAME_DURATIONS_MS)
        native_info = _save_gif(folder / "native.gif", native_frames, FRAME_DURATIONS_MS)
        _write_filmstrip(folder / "filmstrip.png", source_frames)

        first_hash = hashlib.sha256(source_frames[0].tobytes()).hexdigest()
        variants[folder_name] = {
            "source_directory": str((folder / "pixellab").relative_to(root)),
            "source_frames": [
                _frame_validation(path, frame, index)
                for index, (path, frame) in enumerate(zip(paths, source_frames), start=1)
            ],
            "first_frame_rgba_sha256": first_hash,
            "reference_rgba_sha256": reference_hash,
            "first_frame_matches_reference": first_hash == reference_hash,
            "previews": {"preview.gif": preview_info, "native.gif": native_info},
        }
        comparison_clips.append(source_frames)
        titles.append(title)

    comparison = _comparison_frames(comparison_clips, titles)
    comparison_info = _save_gif(root / "comparison.gif", comparison, FRAME_DURATIONS_MS)
    validation = {
        "variants": variants,
        "reference": {
            "path": str(prepared["reference_path"].relative_to(root)),
            "size": list(reference.size),
            "rgba_sha256": reference_hash,
        },
        "comparison": {"comparison.gif": comparison_info},
        "timing": {
            "frames_01_32_ms": 60,
            "frame_33_ms": 900,
            "total_ms": sum(FRAME_DURATIONS_MS),
            "loop": True,
        },
        "presentation": {
            "order": "source order 01-33",
            "source_edits": "none",
            "transforms": "RGBA composite on #16212b; nearest-neighbor enlargement only",
            "filmstrip": "all 33 frames, numbered, 6 columns, 2x nearest-neighbor",
            "comparison": "three 128x128 canvases enlarged 3x side by side with ASCII titles",
        },
    }
    (root / "validation.json").write_text(
        json.dumps(validation, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    return validation


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parent,
        help="variant package directory (defaults to the script directory)",
    )
    arguments = parser.parse_args()
    root = arguments.root.resolve()
    try:
        validation = build_previews(root)
    except (FileNotFoundError, OSError, ValueError) as error:
        print(str(error), file=sys.stderr)
        return 2
    print(json.dumps({"comparison": validation["comparison"], "variants": {
        name: details["previews"] for name, details in validation["variants"].items()
    }}, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
