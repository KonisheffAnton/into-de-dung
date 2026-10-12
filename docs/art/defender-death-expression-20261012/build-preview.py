"""Apply a provider inpaint sheet only inside the approved face mask."""

from __future__ import annotations

import hashlib
import json
import shutil
import sys
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parent
SOURCE = ROOT.parent / "defender-death-variants-20261012" / "03-last-knee" / "pixellab"
FRAME_COUNT = 33
FRAME_SIZE = (128, 128)
SHEET_SIZE = (384, 192)
FACE_CROP = [32, 24, 96, 88]
FIRST_EDIT_FRAME = 2
LAST_EDIT_FRAME = 19
BACKGROUND_RGB = (22, 33, 43)
BACKGROUND_RGBA = (*BACKGROUND_RGB, 255)
DURATIONS_MS = [60] * 32 + [900]
OUTPUT_DIR = ROOT / "frames"


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _load_manifest() -> list[dict[str, Any]]:
    path = ROOT / "request-manifest.json"
    if not path.is_file():
        raise FileNotFoundError(f"Missing manifest: {path}")
    manifest = json.loads(path.read_text(encoding="utf-8"))
    entries = manifest.get("entries")
    if not isinstance(entries, list):
        raise ValueError("request-manifest.json must contain an entries array")
    expected_frames = set(range(FIRST_EDIT_FRAME, LAST_EDIT_FRAME + 1))
    seen_frames: set[int] = set()
    seen_cells: set[tuple[int, int]] = set()
    normalized: list[dict[str, Any]] = []
    for entry in entries:
        if not isinstance(entry, dict):
            raise ValueError("Each manifest entry must be an object")
        frame = entry.get("frame")
        cell = entry.get("cell")
        crop = entry.get("crop")
        if not isinstance(frame, int) or isinstance(frame, bool) or frame not in expected_frames:
            raise ValueError(f"Manifest frame must be an integer from {FIRST_EDIT_FRAME} to {LAST_EDIT_FRAME}: {frame!r}")
        if frame in seen_frames:
            raise ValueError(f"Duplicate manifest frame: {frame}")
        if crop != FACE_CROP:
            raise ValueError(f"Frame {frame}: crop must be exactly {FACE_CROP}")
        if not isinstance(cell, list) or len(cell) != 2 or any(not isinstance(value, int) or isinstance(value, bool) for value in cell):
            raise ValueError(f"Frame {frame}: cell must be [x, y] integer coordinates")
        x, y = cell
        if x < 0 or y < 0 or x + 64 > SHEET_SIZE[0] or y + 64 > SHEET_SIZE[1]:
            raise ValueError(f"Frame {frame}: contact sheet cell is out of bounds: {cell}")
        cell_key = (x, y)
        if cell_key in seen_cells:
            raise ValueError(f"Duplicate or overlapping contact sheet cell at {cell}")
        if x % 64 != 0 or y % 64 != 0:
            raise ValueError(f"Frame {frame}: cell must align to the 64x64 contact sheet grid")
        seen_frames.add(frame)
        seen_cells.add(cell_key)
        normalized.append({"frame": frame, "cell": [x, y], "crop": crop})
    if seen_frames != expected_frames:
        missing = sorted(expected_frames - seen_frames)
        raise ValueError(f"Manifest must map every edited frame 02-19 exactly once; missing: {missing}")
    if len(seen_cells) != len(normalized):
        raise ValueError("Manifest contact sheet cells overlap")
    return normalized


def _load_inputs() -> tuple[list[bytes], list[Image.Image], Image.Image, Image.Image, list[dict[str, Any]]]:
    missing = [str(SOURCE / f"frame-{index:02}.png") for index in range(1, FRAME_COUNT + 1)
               if not (SOURCE / f"frame-{index:02}.png").is_file()]
    for name in ("pixellab/result.png", "sheet-mask.png"):
        if not (ROOT / name).is_file():
            missing.append(str(ROOT / name))
    if missing:
        raise FileNotFoundError("Missing required inputs:\n" + "\n".join(missing))

    manifest_entries = _load_manifest()
    original_bytes: list[bytes] = []
    original_frames: list[Image.Image] = []
    for index in range(1, FRAME_COUNT + 1):
        path = SOURCE / f"frame-{index:02}.png"
        data = path.read_bytes()
        with Image.open(path) as image:
            if image.size != FRAME_SIZE:
                raise ValueError(f"{path.name}: expected {FRAME_SIZE}, got {image.size}")
            original_frames.append(image.convert("RGBA"))
        original_bytes.append(data)

    provider_path = ROOT / "pixellab" / "result.png"
    with Image.open(provider_path) as image:
        if image.size != SHEET_SIZE:
            raise ValueError(f"result.png: expected {SHEET_SIZE}, got {image.size}")
        provider = image.convert("RGBA")
    mask_path = ROOT / "sheet-mask.png"
    with Image.open(mask_path) as image:
        if image.size != SHEET_SIZE:
            raise ValueError(f"sheet-mask.png: expected {SHEET_SIZE}, got {image.size}")
        if image.mode != "L":
            raise ValueError(f"sheet-mask.png: expected L mode, got {image.mode}")
        mask = image.copy()
    mask_values = mask.tobytes()
    invalid_mask = sum(value not in (0, 255) for value in mask_values)
    if invalid_mask:
        raise ValueError(f"sheet-mask.png contains {invalid_mask} non-binary pixels; only 0 and 255 are allowed")

    mapped_mask = bytearray(SHEET_SIZE[0] * SHEET_SIZE[1])
    for entry in manifest_entries:
        cell_x, cell_y = entry["cell"]
        for local_y in range(64):
            start = (cell_y + local_y) * SHEET_SIZE[0] + cell_x
            for local_x in range(64):
                mapped_mask[start + local_x] = 1
    outside_white = sum(value == 255 and not mapped_mask[index] for index, value in enumerate(mask_values))
    if outside_white:
        raise ValueError(f"sheet-mask.png has {outside_white} white pixels outside mapped frame cells")
    return original_bytes, original_frames, provider, mask, manifest_entries


def _apply_masked_rgb(
    originals: list[Image.Image], provider: Image.Image, mask: Image.Image,
    entries: list[dict[str, Any]],
) -> tuple[list[Image.Image], list[dict[str, Any]], list[dict[str, Any]], int]:
    outputs = [frame.copy() for frame in originals]
    frame_records: dict[int, dict[str, Any]] = {}
    mask_pixels = mask.load()
    provider_pixels = provider.load()

    # Одинаковый исходный ракурс получает одну позу лица, чтобы не мерцало выражение.
    signature_groups: dict[tuple[Any, ...], list[dict[str, Any]]] = {}
    for entry in entries:
        frame_number = entry["frame"]
        cell_x, cell_y = entry["cell"]
        original_pixels = originals[frame_number - 1].load()
        mask_coordinates: list[tuple[int, int]] = []
        original_values: list[tuple[int, int, int, int]] = []
        for local_y in range(64):
            for local_x in range(64):
                if mask_pixels[cell_x + local_x, cell_y + local_y] != 255:
                    continue
                x = FACE_CROP[0] + local_x
                y = FACE_CROP[1] + local_y
                pixel = original_pixels[x, y]
                if pixel[3] != 255:
                    raise ValueError(f"Frame {frame_number:02} has masked source pixel with alpha {pixel[3]} at ({x},{y})")
                mask_coordinates.append((x, y))
                original_values.append(pixel)
        signature = (tuple(mask_coordinates), tuple(original_values))
        signature_groups.setdefault(signature, []).append(entry)

    provider_entries: dict[int, dict[str, Any]] = {}
    reuse_groups: list[dict[str, Any]] = []
    for grouped_entries in signature_groups.values():
        grouped_entries.sort(key=lambda item: item["frame"])
        canonical = grouped_entries[0]
        frames = [item["frame"] for item in grouped_entries]
        reuse_groups.append({"provider_frame_used": canonical["frame"], "frames": frames})
        for entry in grouped_entries:
            provider_entries[entry["frame"]] = canonical

    provider_alpha_violations = 0
    for entry in entries:
        cell_x, cell_y = entry["cell"]
        for local_y in range(64):
            for local_x in range(64):
                if mask_pixels[cell_x + local_x, cell_y + local_y] == 255:
                    if provider_pixels[cell_x + local_x, cell_y + local_y][3] != 255:
                        provider_alpha_violations += 1
    if provider_alpha_violations:
        raise ValueError(f"Provider result contains {provider_alpha_violations} non-opaque pixels under the edit mask")

    for entry in entries:
        frame_number = entry["frame"]
        frame_index = frame_number - 1
        cell_x, cell_y = entry["cell"]
        provider_entry = provider_entries[frame_number]
        provider_cell_x, provider_cell_y = provider_entry["cell"]
        original = originals[frame_index]
        output = outputs[frame_index]
        original_pixels = original.load()
        output_pixels = output.load()
        changed: list[tuple[int, int]] = []
        for local_y in range(64):
            for local_x in range(64):
                sheet_x = cell_x + local_x
                sheet_y = cell_y + local_y
                if mask_pixels[sheet_x, sheet_y] != 255:
                    continue
                x = FACE_CROP[0] + local_x
                y = FACE_CROP[1] + local_y
                source_pixel = original_pixels[x, y]
                provider_pixel = provider_pixels[provider_cell_x + local_x, provider_cell_y + local_y]
                replacement = (*provider_pixel[:3], source_pixel[3])
                output_pixels[x, y] = replacement
                if replacement != source_pixel:
                    changed.append((x, y))

        if changed:
            xs = [point[0] for point in changed]
            ys = [point[1] for point in changed]
            bbox = [min(xs), min(ys), max(xs) + 1, max(ys) + 1]
        else:
            bbox = None
        frame_records[frame_number] = {
            "frame": frame_number,
            "masked_pixels": sum(
                mask_pixels[entry["cell"][0] + local_x, entry["cell"][1] + local_y] == 255
                for local_y in range(64) for local_x in range(64)
            ),
            "changed_pixel_count": len(changed),
            "changed_bbox": bbox,
            "provider_frame_used": provider_entry["frame"],
        }

    total_changes = sum(record["changed_pixel_count"] for record in frame_records.values())
    if total_changes == 0:
        raise ValueError("Provider result changes no masked RGB pixels; refusing a no-op edit")
    if provider_alpha_violations:
        raise ValueError(f"Provider result has {provider_alpha_violations} masked alpha violations")
    return outputs, [frame_records[number] for number in sorted(frame_records)], reuse_groups, provider_alpha_violations


def _composite(frame: Image.Image, scale: int) -> Image.Image:
    size = (FRAME_SIZE[0] * scale, FRAME_SIZE[1] * scale)
    enlarged = frame.resize(size, Image.Resampling.NEAREST)
    canvas = Image.new("RGBA", size, BACKGROUND_RGBA)
    canvas.alpha_composite(enlarged)
    return canvas.convert("RGB")


def _write_gif(path: Path, frames: list[Image.Image], *, loop: int | None) -> dict[str, Any]:
    options: dict[str, Any] = {
        "save_all": True,
        "append_images": frames[1:],
        "duration": DURATIONS_MS,
        "disposal": 2,
        "optimize": False,
    }
    if loop is not None:
        options["loop"] = loop
    frames[0].save(path, **options)

    decoded: list[Image.Image] = []
    actual_durations: list[int] = []
    with Image.open(path) as gif:
        for index in range(gif.n_frames):
            gif.seek(index)
            decoded.append(gif.convert("RGB").copy())
            actual_durations.append(int(gif.info.get("duration", 0)))
    if sum(actual_durations) != sum(DURATIONS_MS):
        raise ValueError(f"{path.name}: GIF duration sum {sum(actual_durations)}ms != expected {sum(DURATIONS_MS)}ms")

    expected_runs: list[int] = []
    actual_runs: list[int] = []
    previous: bytes | None = None
    for frame, duration in zip(frames, DURATIONS_MS):
        signature = frame.convert("RGB").tobytes()
        if signature == previous:
            expected_runs[-1] += duration
        else:
            expected_runs.append(duration)
            previous = signature
    previous = None
    for frame, duration in zip(decoded, actual_durations):
        signature = frame.tobytes()
        if signature == previous:
            actual_runs[-1] += duration
        else:
            actual_runs.append(duration)
            previous = signature
    if expected_runs != actual_runs:
        raise ValueError(f"{path.name}: adjacent identical frames do not conserve their requested durations")
    with Image.open(path) as gif:
        return {
            "frame_count": gif.n_frames,
            "size": list(gif.size),
            "duration_ms": actual_durations,
            "total_ms": sum(actual_durations),
            "loop": gif.info.get("loop"),
            "merged_identical_run_durations_ms": actual_runs,
        }


def _filmstrip(path: Path, frames: list[Image.Image]) -> None:
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
        draw.text((x + 8, y + 261), f"{index + 1:02}", fill=(230, 234, 238, 255))
    sheet.save(path)


def _before_after(original_frames: list[Image.Image], frames: list[Image.Image]) -> list[Image.Image]:
    scale = 3
    title_height = 28
    panel_size = (FRAME_SIZE[0] * scale, FRAME_SIZE[1] * scale)
    output: list[Image.Image] = []
    for index, (before, after) in enumerate(zip(original_frames, frames), start=1):
        canvas = Image.new("RGB", (panel_size[0] * 2, panel_size[1] + title_height), BACKGROUND_RGB)
        draw = ImageDraw.Draw(canvas)
        draw.text((10, 7), f"BEFORE FRAME {index:02}", fill=(238, 242, 246))
        draw.text((panel_size[0] + 10, 7), f"AFTER FRAME {index:02}", fill=(238, 242, 246))
        canvas.paste(_composite(before, scale), (0, title_height))
        canvas.paste(_composite(after, scale), (panel_size[0], title_height))
        output.append(canvas)
    return output


def build() -> dict[str, Any]:
    original_bytes, original_frames, provider, mask, entries = _load_inputs()
    outputs, edits, reuse_groups, provider_alpha_violations = _apply_masked_rgb(original_frames, provider, mask, entries)

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    source_records: list[dict[str, Any]] = []
    edits_by_frame = {record["frame"]: record for record in edits}
    for index, (source_data, original, output) in enumerate(zip(original_bytes, original_frames, outputs), start=1):
        output_path = OUTPUT_DIR / f"frame-{index:02}.png"
        if index < FIRST_EDIT_FRAME or index > LAST_EDIT_FRAME:
            shutil.copyfile(SOURCE / f"frame-{index:02}.png", output_path)
        else:
            output.save(output_path, format="PNG")
        written = output_path.read_bytes()
        with Image.open(output_path) as saved_image:
            saved = saved_image.convert("RGBA")
        if saved.size != FRAME_SIZE:
            raise ValueError(f"Output frame {index:02} has invalid dimensions")
        if saved.getchannel("A").tobytes() != original.getchannel("A").tobytes():
            raise ValueError(f"Output frame {index:02} changed original alpha")
        if index < FIRST_EDIT_FRAME or index > LAST_EDIT_FRAME:
            if written != source_data:
                raise ValueError(f"Unedited frame {index:02} was not copied byte-for-byte")
        else:
            entry = next(item for item in entries if item["frame"] == index)
            cell_x, cell_y = entry["cell"]
            provider_entry = next(item for item in entries if item["frame"] == edits_by_frame[index]["provider_frame_used"])
            provider_cell_x, provider_cell_y = provider_entry["cell"]
            original_pixels = original.load()
            saved_pixels = saved.load()
            mask_pixels = mask.load()
            provider_pixels = provider.load()
            mask_coordinates = {
                (FACE_CROP[0] + local_x, FACE_CROP[1] + local_y)
                for local_y in range(64) for local_x in range(64)
                if mask_pixels[cell_x + local_x, cell_y + local_y] == 255
            }
            for y in range(FRAME_SIZE[1]):
                for x in range(FRAME_SIZE[0]):
                    if (x, y) in mask_coordinates:
                        local_x = x - FACE_CROP[0]
                        local_y = y - FACE_CROP[1]
                        expected_rgb = provider_pixels[provider_cell_x + local_x, provider_cell_y + local_y][:3]
                        if saved_pixels[x, y][:3] != expected_rgb:
                            raise ValueError(f"Output frame {index:02} has an unexpected masked RGB value at ({x},{y})")
                    elif saved_pixels[x, y] != original_pixels[x, y]:
                        raise ValueError(f"Output frame {index:02} changed an unmasked pixel at ({x},{y})")
        record: dict[str, Any] = {
            "frame": index,
            "original_sha256": _sha256(source_data),
            "output_sha256": _sha256(written),
            "size": list(saved.size),
            "alpha_unchanged": True,
        }
        if index in edits_by_frame:
            record.update(edits_by_frame[index])
        else:
            record.update({"masked_pixels": 0, "changed_pixel_count": 0, "changed_bbox": None})
        source_records.append(record)

    preview = [_composite(frame, 4) for frame in outputs]
    native = [_composite(frame, 1) for frame in outputs]
    before_after = _before_after(original_frames, outputs)
    gif_data = {
        "preview.gif": _write_gif(ROOT / "preview.gif", preview, loop=0),
        "native.gif": _write_gif(ROOT / "native.gif", native, loop=0),
        "before-after.gif": _write_gif(ROOT / "before-after.gif", before_after, loop=0),
    }
    _filmstrip(ROOT / "filmstrip.png", outputs)
    validation = {
        "source_directory": str(SOURCE),
        "provider_result_sha256": _sha256((ROOT / "pixellab" / "result.png").read_bytes()),
        "mask_sha256": _sha256((ROOT / "sheet-mask.png").read_bytes()),
        "edited_frames": [FIRST_EDIT_FRAME, LAST_EDIT_FRAME],
        "contact_sheet": {"size": list(SHEET_SIZE), "crop": FACE_CROP, "mask_values": [0, 255]},
        "timing": {"frames_01_32_ms": 60, "frame_33_ms": 900, "total_ms": sum(DURATIONS_MS)},
        "source_edits": "Only RGB under the white mask for frames 02-19; original alpha retained. No transforms.",
        "frames": source_records,
        "total_changed_pixels": sum(record["changed_pixel_count"] for record in source_records),
        "provider_masked_alpha_violations": provider_alpha_violations,
        "provider_reuse_groups": reuse_groups,
        "gifs": gif_data,
    }
    (ROOT / "validation.json").write_text(json.dumps(validation, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return validation


def main() -> int:
    try:
        validation = build()
    except (FileNotFoundError, OSError, ValueError, json.JSONDecodeError) as error:
        print(str(error), file=sys.stderr)
        return 2
    print(json.dumps({"total_changed_pixels": validation["total_changed_pixels"], "gifs": validation["gifs"]}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
