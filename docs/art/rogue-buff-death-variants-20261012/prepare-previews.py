"""Create review previews and source validation for completed rogue variants."""

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
FRAME_MS = 200
DEATH_HOLD_MS = 800
BACKGROUND = (63, 75, 67)
BACKGROUND_RGBA = (*BACKGROUND, 255)
WHITE = (240, 243, 236)
LOOP = 0


def _manifest(root: Path) -> tuple[list[dict[str, Any]], Image.Image, Path]:
    manifest = json.loads((root / "request-manifest.json").read_text(encoding="utf-8-sig"))
    variants = manifest["variants"]
    reference_path = root / "reference-128.png"
    if not reference_path.is_file():
        raise FileNotFoundError(f"Missing reference image: {reference_path}")
    with Image.open(reference_path) as image:
        if image.size != FRAME_SIZE:
            raise ValueError(f"Reference has size {image.size}, expected {FRAME_SIZE}")
        reference = image.convert("RGBA")
    return variants, reference, reference_path


def _sources(root: Path, variant: dict[str, Any], requested_count: int) -> tuple[list[Path], list[Image.Image]]:
    folder = root / variant["id"] / "pixellab"
    result_path = folder / "result.json"
    if not result_path.is_file():
        raise FileNotFoundError(f"Missing extraction metadata: {result_path}")
    result = json.loads(result_path.read_text(encoding="utf-8-sig"))
    frame_count = result.get("frame_count")
    recorded_requested = result.get("requested_frame_count")
    if recorded_requested != requested_count:
        raise ValueError(f"{variant['id']}: requested_frame_count {recorded_requested!r}, expected {requested_count}")
    if not isinstance(frame_count, int) or frame_count != requested_count + 1:
        raise ValueError(f"{variant['id']}: actual frame_count {frame_count!r} must equal requested count plus one")
    paths = [folder / f"frame-{index:02d}.png" for index in range(1, frame_count + 1)]
    missing = [path for path in paths if not path.is_file()]
    if missing:
        raise FileNotFoundError("Missing frames; no previews were written:\n" + "\n".join(map(str, missing)))
    expected_names = {path.name for path in paths}
    extra_frames = {path.name for path in folder.glob("frame-*.png")} - expected_names
    if extra_frames:
        raise ValueError(f"{variant['id']}: unexpected extra frames: {sorted(extra_frames)}")
    frames: list[Image.Image] = []
    for path in paths:
        with Image.open(path) as source:
            if source.size != FRAME_SIZE:
                raise ValueError(f"{path}: size {source.size}, expected {FRAME_SIZE}")
            frames.append(source.convert("RGBA"))
    return paths, frames


def _composite(frame: Image.Image, scale: int) -> Image.Image:
    canvas = Image.new("RGBA", (FRAME_SIZE[0] * scale, FRAME_SIZE[1] * scale), BACKGROUND_RGBA)
    enlarged = frame.resize(canvas.size, Image.Resampling.NEAREST)
    canvas.alpha_composite(enlarged)
    return canvas.convert("RGB")


def _native_gif_frame(frame: Image.Image) -> Image.Image:
    # GIF допускает только двоичную прозрачность, поэтому сохраняем силуэт и
    # резервируем отдельный индекс палитры для полностью прозрачных пикселей.
    rgb = frame.convert("RGB").quantize(colors=255, method=Image.Quantize.MEDIANCUT)
    pixels = list(rgb.getdata())
    alpha = list(frame.getchannel("A").getdata())
    rgb.putdata([255 if value == 0 else index for index, value in zip(pixels, alpha)])
    palette = rgb.getpalette() or []
    palette.extend([0] * (768 - len(palette)))
    palette[255 * 3 : 255 * 3 + 3] = [0, 0, 0]
    rgb.putpalette(palette)
    rgb.info["transparency"] = 255
    return rgb


def _run_durations(frames: list[Image.Image], durations: list[int]) -> list[int]:
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


def _save_gif(path: Path, frames: list[Image.Image], durations: list[int], *, transparent: bool = False) -> dict[str, Any]:
    if not frames or len(frames) != len(durations):
        raise ValueError(f"{path.name}: frame and duration counts differ or are empty")
    encoded = [_native_gif_frame(frame) for frame in frames] if transparent else frames
    encoded[0].save(
        path,
        save_all=True,
        append_images=encoded[1:],
        duration=durations,
        loop=LOOP,
        disposal=2,
        optimize=False,
        **({"transparency": 255} if transparent else {}),
    )
    actual_frames: list[Image.Image] = []
    actual_durations: list[int] = []
    with Image.open(path) as gif:
        for index in range(gif.n_frames):
            gif.seek(index)
            actual_frames.append(gif.convert("RGBA").copy())
            actual_durations.append(int(gif.info.get("duration", 0)))
    expected_runs = _run_durations(frames, durations)
    actual_runs = _run_durations(actual_frames, actual_durations)
    if expected_runs != actual_runs:
        raise ValueError(f"{path.name}: decoded adjacent-frame timing {actual_runs}, expected {expected_runs}")
    return {
        "encoded_frames": len(actual_frames),
        "logical_frames": len(frames),
        "size": list(actual_frames[0].size),
        "duration_ms": actual_durations,
        "total_ms": sum(actual_durations),
        "merged_adjacent_runs_ms": actual_runs,
        "transparent_index": 255 if transparent else None,
    }


def _alpha_validation(path: Path, frame: Image.Image, index: int) -> dict[str, Any]:
    alpha = list(frame.getchannel("A").getdata())
    bbox = frame.getchannel("A").getbbox()
    edge_touched = bool(bbox and (bbox[0] == 0 or bbox[1] == 0 or bbox[2] == 128 or bbox[3] == 128))
    return {
        "frame": index,
        "file_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "rgba_sha256": hashlib.sha256(frame.tobytes()).hexdigest(),
        "size": list(frame.size),
        "alpha_bbox": list(bbox) if bbox else None,
        "touches_canvas_edge_possible_clipping": edge_touched,
        "alpha_min": min(alpha),
        "alpha_max": max(alpha),
        "distinct_alpha_levels": len(set(alpha)),
        "transparent_pixels": alpha.count(0),
        "partial_alpha_pixels": sum(0 < value < 255 for value in alpha),
        "visible_pixels": sum(value > 0 for value in alpha),
    }


def _filmstrip(path: Path, frames: list[Image.Image]) -> None:
    columns, cell, label_height = 6, 256, 28
    rows = (len(frames) + columns - 1) // columns
    sheet = Image.new("RGBA", (columns * cell, rows * (cell + label_height)), BACKGROUND_RGBA)
    draw = ImageDraw.Draw(sheet)
    font = _font()
    for index, frame in enumerate(frames):
        x, y = index % columns * cell, index // columns * (cell + label_height)
        sheet.alpha_composite(frame.resize((cell, cell), Image.Resampling.NEAREST), (x, y))
        draw.text((x + 8, y + cell + 6), f"Кадр {index + 1:02d}", fill=WHITE, font=font)
    sheet.save(path)


def _font() -> ImageFont.ImageFont:
    for candidate in (Path("C:/Windows/Fonts/arial.ttf"), Path("C:/Windows/Fonts/Arial.ttf")):
        if candidate.is_file():
            return ImageFont.truetype(str(candidate), 18)
    return ImageFont.load_default()


def _comparison_frames(clips: list[list[Image.Image]], titles: list[str], frame_count: int) -> list[Image.Image]:
    panel = 384
    label_height = 32
    font = _font()
    result: list[Image.Image] = []
    for frame_index in range(frame_count):
        canvas = Image.new("RGB", (panel * 3, panel + label_height), BACKGROUND)
        draw = ImageDraw.Draw(canvas)
        for variant_index in range(3):
            x = panel * variant_index
            draw.text((x + 10, 7), titles[variant_index], fill=WHITE, font=font)
            canvas.paste(_composite(clips[variant_index][frame_index], 3), (x, label_height))
        result.append(canvas)
    return result


def _comparison(root: Path, variants: list[dict[str, Any]], available: dict[str, list[Image.Image]], kind: str) -> dict[str, Any] | None:
    selected = [item for item in variants if item.get("kind") == kind]
    if len(selected) != 3 or any(item["id"] not in available for item in selected):
        return None
    clips = [available[item["id"]] for item in selected]
    frame_count = len(clips[0])
    if any(len(clip) != frame_count for clip in clips):
        return None
    frames = _comparison_frames(clips, [item["title"] for item in selected], frame_count)
    durations = [FRAME_MS] * frame_count
    if kind == "death":
        durations[-1] += DEATH_HOLD_MS
    path = root / ("buff-comparison.gif" if kind == "buff" else "death-comparison.gif")
    return _save_gif(path, frames, durations)


def build_previews(root: Path) -> dict[str, Any]:
    variants, reference, reference_path = _manifest(root)
    manifest = json.loads((root / "request-manifest.json").read_text(encoding="utf-8-sig"))
    requested_count = int(manifest["requestedFrames"])
    available: dict[str, list[Image.Image]] = {}
    prepared: dict[str, tuple[list[Path], list[Image.Image]]] = {}
    for variant in variants:
        try:
            prepared[variant["id"]] = _sources(root, variant, requested_count)
            available[variant["id"]] = prepared[variant["id"]][1]
        except FileNotFoundError:
            # Варианты можно строить по мере готовности; незавершённые остаются в отчёте.
            continue

    report: dict[str, Any] = {}
    reference_pixels = list(reference.getdata())
    for variant in variants:
        variant_id = variant["id"]
        if variant_id not in prepared:
            report[variant_id] = {"status": "frames_missing"}
            continue
        paths, frames = prepared[variant_id]
        folder = root / variant_id
        is_death = variant.get("kind") == "death"
        frame_count = len(frames)
        durations = [FRAME_MS] * frame_count
        preview_frames = [_composite(frame, 4) for frame in frames]
        preview_durations = durations[:-1] + [durations[-1] + (DEATH_HOLD_MS if is_death else 0)]
        native_durations = preview_durations
        preview_info = _save_gif(folder / "preview.gif", preview_frames, preview_durations)
        native_info = _save_gif(folder / "native.gif", frames, native_durations, transparent=True)
        _filmstrip(folder / "filmstrip.png", frames)
        if is_death:
            frames[-1].save(folder / "final-corpse.png")

        frame_reports = [_alpha_validation(path, frame, index) for index, (path, frame) in enumerate(zip(paths, frames), 1)]
        first = list(frames[0].getdata())
        differences = [tuple(abs(a - b) for a, b in zip(left, right)) for left, right in zip(first, reference_pixels)]
        different_pixels = [left != right for left, right in zip(first, reference_pixels)]
        report[variant_id] = {
            "status": "ready",
            "kind": variant.get("kind"),
            "title": variant.get("title"),
            "source_frames": frame_reports,
            "requested_frame_count": requested_count,
            "actual_frame_count": frame_count,
            "distinct_rgba_frames": len({frame.tobytes() for frame in frames}),
            "first_frame_vs_reference": {
                "reference": str(reference_path.relative_to(root)),
                "reference_rgba_sha256": hashlib.sha256(reference.tobytes()).hexdigest(),
                "first_rgba_sha256": hashlib.sha256(frames[0].tobytes()).hexdigest(),
                "exact_match": frames[0].tobytes() == reference.tobytes(),
                "different_pixels": sum(different_pixels),
                "visible_union_different_pixels": sum(
                    changed and (left[3] > 0 or right[3] > 0)
                    for changed, left, right in zip(different_pixels, first, reference_pixels)
                ),
                "alpha_mismatch_pixels": sum(left[3] != right[3] for left, right in zip(first, reference_pixels)),
                "hidden_transparent_rgb_only_changes": sum(
                    left[:3] != right[:3] and left[3] == 0 and right[3] == 0
                    for left, right in zip(first, reference_pixels)
                ),
                "mean_absolute_rgba_channel_delta": sum(sum(pixel) for pixel in differences) / (len(differences) * 4),
            },
            "final_frame_visible": frame_reports[-1]["visible_pixels"] > 0,
            "final_frame_alpha_bbox": frame_reports[-1]["alpha_bbox"],
            "previews": {"preview.gif": preview_info, "native.gif": native_info},
            "timing_ms": {
                "uniform_frame_ms": FRAME_MS,
                "base_total_ms": frame_count * FRAME_MS,
                "death_final_hold_extra_ms": DEATH_HOLD_MS if is_death else 0,
                "review_total_ms": frame_count * FRAME_MS + (DEATH_HOLD_MS if is_death else 0),
            },
        }

    comparisons = {
        "buff-comparison.gif": _comparison(root, variants, available, "buff"),
        "death-comparison.gif": _comparison(root, variants, available, "death"),
    }
    result = {
        "reference": {"path": str(reference_path.relative_to(root)), "size": list(reference.size), "rgba_sha256": hashlib.sha256(reference.tobytes()).hexdigest()},
        "variants": report,
        "comparisons": comparisons,
        "presentation": {
            "source_order": [variant["id"] for variant in variants],
            "source_edits": "none; source PNG bytes are only read",
            "preview_transform": "nearest-neighbor 4x RGBA composite on neutral #3f4b43",
            "native_gif": "nearest-source-size palette GIF; GIF stores binary transparency",
            "death_hold": "extra 800ms on final frame for review only; no recovery frame is generated",
            "comparison": "three 384x384 panels side by side with Russian manifest titles above",
        },
    }
    (root / "validation.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT, help="variant package root")
    args = parser.parse_args()
    try:
        result = build_previews(args.root.resolve())
    except (OSError, ValueError, KeyError) as error:
        print(str(error), file=sys.stderr)
        return 2
    print(json.dumps({"variants": {key: value.get("status") for key, value in result["variants"].items()}, "comparisons": result["comparisons"]}, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
