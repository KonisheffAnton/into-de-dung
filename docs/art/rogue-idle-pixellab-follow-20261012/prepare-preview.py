"""Builds unedited, ordered previews and descriptive validation for PixelLab frames."""
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

ROOT = Path(__file__).resolve().parent
PIXELLAB = ROOT / "pixellab"
paths = sorted(PIXELLAB.glob("frame-*.png"))
metadata = json.loads((PIXELLAB / "result.json").read_text(encoding="utf-8"))
expected = metadata["frame_count"]
assert len(paths) == expected == 33, "Ожидалось 32 запрошенных кадра и исходная поза"
frames = [Image.open(path).convert("RGBA") for path in paths]
assert all(frame.size == (128, 128) for frame in frames), "Ожидался формат кадров 128x128"

reference = Image.open(PIXELLAB / "reference-128.png").convert("RGBA")
assert frames[0].tobytes() == reference.tobytes(), "Первый кадр отличается от исходника по RGBA"

background = (39, 49, 43, 255)
previews = []
for frame in frames:
    preview = Image.new("RGBA", (512, 512), background)
    preview.alpha_composite(frame.resize((512, 512), Image.Resampling.NEAREST))
    previews.append(preview.convert("RGB"))

gif_info = {}
for name, clip in (("idle-native.gif", frames), ("preview.gif", previews)):
    durations = [80] * len(clip)
    clip[0].save(ROOT / name, save_all=True, append_images=clip[1:], duration=durations,
                 loop=0, disposal=2, optimize=False)
    gif = Image.open(ROOT / name)
    assert gif.n_frames == len(clip)
    actual = []
    for index in range(gif.n_frames):
        gif.seek(index)
        actual.append(gif.info["duration"])
    assert actual == durations
    gif_info[name] = {"frames": gif.n_frames, "size": gif.size, "frame_duration_ms": actual,
                      "total_duration_ms": sum(actual)}

# Исходные 128px кадры и увеличение 2x показаны целиком в исходном порядке.
sheet = Image.new("RGBA", (6 * 256, ((len(frames) + 5) // 6) * 280), background)
draw = ImageDraw.Draw(sheet)
checks = []
for index, (path, frame) in enumerate(zip(paths, frames)):
    x, y = index % 6 * 256, index // 6 * 280
    sheet.alpha_composite(frame.resize((256, 256), Image.Resampling.NEAREST), (x, y))
    draw.text((x + 8, y + 261), f"{index + 1:02}", fill=(230, 234, 220, 255))
    alpha = frame.getchannel("A")
    bbox = alpha.getbbox()
    assert bbox and alpha.getextrema() == (0, 255), f"Кадр {index + 1} не имеет ожидаемой прозрачности"
    checks.append({"frame": index + 1, "size": list(frame.size), "alpha_bbox": bbox,
                   "alpha_extrema": alpha.getextrema(),
                   "alpha_levels": sorted(set(alpha.get_flattened_data())),
                   "alpha_bbox_clipped": bbox[0] == 0 or bbox[1] == 0 or bbox[2] == 128 or bbox[3] == 128,
                   "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
sheet.save(ROOT / "filmstrip.png")

# Широкая область показывает капюшон и голову; лицо измеряется отдельно.
head_box = (54, 24, 90, 65)
face_box = (69, 45, 80, 56)
foot_rois = {"left": (40, 78, 56, 90), "right": (70, 90, 89, 103)}

def roi_metrics(base, current):
    rgba_diff = ImageChops.difference(base, current)
    rgba_values = list(rgba_diff.get_flattened_data())
    rgb_values = list(rgba_diff.convert("RGB").get_flattened_data())
    return {
        "mismatched_rgba_pixels": sum(1 for pixel in rgba_values if pixel != (0, 0, 0, 0)),
        "rgb_mae": round(sum(sum(pixel) for pixel in rgb_values) / (len(rgb_values) * 3), 4),
    }

def measure_region(box):
    base = frames[0].crop(box)
    metrics = []
    for index, frame in enumerate(frames):
        current = frame.crop(box)
        row = {"frame": index + 1, "raw": roi_metrics(base, current)}
        best = None
        for dy in range(-3, 4):
            for dx in range(-3, 4):
                # ROI берётся сдвинутым окном исходного кадра, чтобы не добавлять края прозрачного холста.
                shifted_box = (box[0] + dx, box[1] + dy, box[2] + dx, box[3] + dy)
                candidate_crop = frame.crop(shifted_box)
                score = roi_metrics(base, candidate_crop)
                rank = (score["rgb_mae"], score["mismatched_rgba_pixels"], dx, dy)
                if best is None or rank < best[0]:
                    best = (rank, score, dx, dy)
        row["best_translation_within_3px"] = {"dx": best[2], "dy": best[3]}
        row["translation_aligned"] = best[1]
        metrics.append(row)
    return metrics

head_metrics = measure_region(head_box)
face_metrics = measure_region(face_box)
foot_metrics = []
for index, frame in enumerate(frames):
    foot_metrics.append({"frame": index + 1, "rois": {
        name: roi_metrics(frames[0].crop(box), frame.crop(box))
        for name, box in foot_rois.items()
    }})

# Enlarged contact strip makes small facial changes inspectable without changing source pixels.
face_sheet = Image.new("RGBA", (6 * 216, ((len(frames) + 5) // 6) * 264), background)
face_draw = ImageDraw.Draw(face_sheet)
for index, frame in enumerate(frames):
    x, y = index % 6 * 216, index // 6 * 264
    crop = frame.crop(head_box).resize((180, 205), Image.Resampling.NEAREST)
    face_sheet.alpha_composite(crop, (x + 18, y))
    face_draw.text((x + 8, y + 225), f"{index + 1:02}", fill=(230, 234, 220, 255))
face_sheet.save(ROOT / "head-filmstrip.png")

validation = {
    "source_frames": checks,
    "previews": gif_info,
    "input_first_frame_rgba_parity": True,
    "head_roi_xyxy": head_box,
    "face_roi_xyxy": face_box,
    "fixed_foot_roi_xyxy": foot_rois,
    "head_change_metrics": head_metrics,
    "face_change_metrics": face_metrics,
    "fixed_foot_metrics": foot_metrics,
    "transforms": "Исходные PNG оставлены без изменений; порядок кадров сохранён. GIF использует все кадры один раз с шагом 80ms. Превью увеличено Nearest 4x на нейтральном фоне.",
    "art_acceptance": "Диагностические метрики не являются жёстким критерием стабильности генератора. Визуальная проверка и принятие художником/пользователем отдельны от файловой валидации."
}
(ROOT / "validation.json").write_text(json.dumps(validation, indent=2) + "\n", encoding="utf-8")
print(json.dumps(gif_info))
