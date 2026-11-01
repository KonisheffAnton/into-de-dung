"""Проверяет девять экспортов; художественные отклонения сообщает отдельно."""
from pathlib import Path
from PIL import Image
import hashlib
import json
import numpy as np

ROOT = Path(__file__).resolve().parent


def read(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    errors = []
    requests = read(ROOT / "requests.json")
    exported = read(ROOT / "pixellab-validation.json")
    transform = read(ROOT / "model" / "transform.json")
    if len(requests) != 9 or len({r["key"] for r in requests}) != 9:
        errors.append("nine unique requests")
    if not exported["complete"] or exported["completed"] != 9:
        errors.append("nine completed exports")
    if sha(ROOT / "model" / "source-full.png") != transform["source_sha256"]:
        errors.append("source hash")
    if sha(ROOT / "model" / "input-256.png") != transform["input_sha256"]:
        errors.append("input hash")
    source = np.asarray(Image.open(ROOT / "model" / "input-256.png").convert("RGBA"))
    diagnostics = []
    total_frames = total_cells = total_gifs = 0
    for row in requests:
        key = row["key"]
        folder = ROOT / "pixellab" / key
        meta = read(folder / "clip.json")
        frames = sorted((folder / "frames").glob("frame-*.png"))
        count = meta["actual_frames"]
        if len(frames) != count or count != 33:
            errors.append(f"frame count {key}")
        if meta["kind"] != row["kind"] or meta["loop"] != (row["kind"] == "idle"):
            errors.append(f"metadata {key}")
        if len(meta["durations_ms"]) != count:
            errors.append(f"timing count {key}")
        sheet = Image.open(folder / "spritesheet.png").convert("RGBA")
        if sheet.size != (2048, 256 * ((count + 7) // 8)):
            errors.append(f"sheet size {key}")
        actual = []
        for i, path in enumerate(frames):
            image = Image.open(path).convert("RGBA")
            if image.size != (256, 256):
                errors.append(f"canvas {key}:{i}")
            array = np.asarray(image)
            if not np.any(array[:, :, 3]):
                errors.append(f"empty alpha {key}:{i}")
            if sha(path) != meta["frame_sha256"][i]:
                errors.append(f"original PNG hash {key}:{i}")
            if not np.array_equal(array, np.asarray(sheet.crop(((i % 8) * 256, (i // 8) * 256,
                                                                (i % 8 + 1) * 256, (i // 8 + 1) * 256)))):
                errors.append(f"sheet cell {key}:{i}")
            actual.append(array)
            total_frames += 1
            total_cells += 1
        with Image.open(folder / "preview.gif") as gif:
            timings = []
            for i in range(gif.n_frames):
                gif.seek(i)
                timings.append(gif.info.get("duration", 0))
            # Pillow объединяет соседние одинаковые кадры GIF, сохраняя суммарное время.
            if not (1 <= len(timings) <= count) or sum(timings) != sum(meta["durations_ms"]):
                errors.append(f"GIF timing {key}")
            total_gifs += 1
        first, last = actual[0], actual[-1]
        first_changed = np.any(first != source, axis=2)
        first_diff = int(first_changed.sum())
        first_visible_diff = int((first_changed & ((first[:, :, 3] > 0) | (source[:, :, 3] > 0))).sum())
        first_alpha_equal = bool(np.array_equal(first[:, :, 3], source[:, :, 3]))
        last_diff = int(np.any(last != source, axis=2).sum())
        seam_diff = int(np.any(last != first, axis=2).sum())
        last_alpha_diff = int((last[:, :, 3] != source[:, :, 3]).sum())
        unique = len({hashlib.sha256(frame.tobytes()).hexdigest() for frame in actual})
        if first_visible_diff or not first_alpha_equal:
            errors.append(f"first frame visible/alpha {key}")
        if unique < 2:
            errors.append(f"no motion {key}")
        diagnostics.append({"key": key, "kind": row["kind"], "frames": count,
                            "unique_rgba_frames": unique, "gif_encoded_frames": len(timings),
                            "first_frame_rgba_changed_pixels": first_diff,
                            "first_frame_visible_changed_pixels": first_visible_diff,
                            "first_frame_alpha_equal": first_alpha_equal,
                            "last_vs_input_changed_pixels": last_diff, "last_vs_first_changed_pixels": seam_diff,
                            "last_alpha_changed_pixels": last_alpha_diff,
                            "raw_edge_frames": meta["edge_frames"],
                            "raw_margin_violation_frames": meta["margin_violation_frames"],
                            "strong_margin_violation_frames": meta["strong_margin_violation_frames"],
                            "last_frame_exact": last_diff == 0,
                            "seam_review_needed": row["kind"] == "idle" and seam_diff > 0,
                            "endpoint_review_needed": row["kind"] == "ability" and last_diff > 0})
    result = {"pass": not errors, "meaning": "structural/source/export checks only; no artistic or runtime acceptance",
              "requests": len(requests), "clips": len(diagnostics), "kind_counts": {k: sum(d["kind"] == k for d in diagnostics)
                                                                  for k in ("idle", "death", "ability")},
              "checked_png_frames": total_frames, "checked_sheet_cells": total_cells,
              "checked_gifs": total_gifs, "diagnostics": diagnostics, "errors": errors,
              "integration": False, "art_acceptance": False, "runtime_validation": False}
    (ROOT / "validation.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({k: v for k, v in result.items() if k != "diagnostics"}, ensure_ascii=False))
    if errors:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
