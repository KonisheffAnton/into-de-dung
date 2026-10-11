"""Package unmodified PixelLab PNGs as a readable GIF and contact sheet."""
import hashlib
import json
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent
frames = [Image.open(path).convert("RGBA") for path in sorted((ROOT / "pixellab").glob("frame-*.png"))]
expected = json.loads((ROOT / "pixellab/result.json").read_text(encoding="utf-8"))["frame_count"]
assert len(frames) == expected and len(frames) > 1, len(frames)
assert all(frame.size == (128, 128) for frame in frames)
background = (39, 49, 43, 255)
previews = []
for frame in frames:
    preview = Image.new("RGBA", (512, 512), background)
    preview.alpha_composite(frame.resize((512, 512), Image.Resampling.NEAREST))
    previews.append(preview.convert("RGB"))
frames[0].save(ROOT / "taunt-native.gif", save_all=True, append_images=frames[1:],
               duration=100, loop=0, disposal=2, optimize=False)
previews[0].save(ROOT / "preview.gif", save_all=True, append_images=previews[1:],
                 duration=[100] * (len(frames) - 1) + [550], loop=0, disposal=2, optimize=False)
sheet = Image.new("RGBA", (4 * 384, ((len(frames) + 3) // 4) * 408), background)
draw = ImageDraw.Draw(sheet)
for index, frame in enumerate(frames):
    x, y = index % 4 * 384, index // 4 * 408
    sheet.alpha_composite(frame.resize((384, 384), Image.Resampling.NEAREST), (x, y))
    draw.text((x + 12, y + 387), str(index + 1).zfill(2), fill=(230, 234, 220, 255))
sheet.save(ROOT / "filmstrip.png")
validation = []
for index, frame in enumerate(frames):
    alpha = frame.getchannel("A")
    box = alpha.getbbox()
    assert box is not None and alpha.getextrema()[0] == 0
    validation.append({"frame": index + 1, "size": frame.size, "alpha_bbox": box,
                       "alpha_extrema": alpha.getextrema(),
                       "sha256": hashlib.sha256((ROOT / "pixellab" / f"frame-{index+1:02}.png").read_bytes()).hexdigest()})
gif_info = {}
for name in ["taunt-native.gif", "preview.gif"]:
    gif = Image.open(ROOT / name)
    durations = []
    for index in range(gif.n_frames):
        gif.seek(index)
        durations.append(gif.info["duration"])
    assert gif.n_frames == len(frames)
    gif_info[name] = {"frames": gif.n_frames, "size": gif.size, "duration_ms": durations, "total_ms": sum(durations)}
(ROOT / "validation.json").write_text(json.dumps({"sources": validation, "previews": gif_info,
    "transforms": "Original PNGs retained. Nearest-neighbor enlargement and background compositing only. No pose edits, registration or interpolation.",
    "art_acceptance": "Open; visual review is separate from file validation."}, indent=2) + "\n", encoding="utf-8")
print(json.dumps(gif_info))

# Вспышки исключены выбором кадров; два замаха собраны монтажом, PNG не меняются.
source_numbers = [1, 3, 4, 7, 8, 4, 3, 4, 7, 9, 12, 14, 15, 16, 17]
durations = [120, 120, 60, 60, 80, 70, 100, 60, 60, 90, 90, 260, 100, 100, 550]
edited = [frames[number - 1] for number in source_numbers]
edited_previews = [previews[number - 1] for number in source_numbers]
for name, clip in [("taunt-edited-native.gif", edited), ("preview-edited.gif", edited_previews)]:
    clip[0].save(ROOT / name, save_all=True, append_images=clip[1:], duration=durations,
                 loop=0, disposal=2, optimize=False)
    gif = Image.open(ROOT / name)
    assert gif.n_frames == len(source_numbers), (name, gif.n_frames)
    actual_durations = []
    for index in range(gif.n_frames):
        gif.seek(index)
        actual_durations.append(gif.info["duration"])
    assert actual_durations == durations
edited_sheet = Image.new("RGBA", (4 * 384, 4 * 408), background)
draw = ImageDraw.Draw(edited_sheet)
for index, (number, frame) in enumerate(zip(source_numbers, edited)):
    x, y = index % 4 * 384, index // 4 * 408
    edited_sheet.alpha_composite(frame.resize((384, 384), Image.Resampling.NEAREST), (x, y))
    draw.text((x + 12, y + 387), f"{index+1:02} / source {number:02} / {durations[index]}ms", fill=(230, 234, 220, 255))
edited_sheet.save(ROOT / "filmstrip-edited.png")
timeline = {"source_frames": source_numbers, "duration_ms": durations, "total_ms": sum(durations),
            "excluded_effect_frames": [5, 6, 13],
            "first_contact_index_1based": 4, "second_contact_index_1based": 9,
            "method": "Editorial frame selection, repetition and timing from original PixelLab PNGs; no pixel edits or interpolation. Raw animation retained.",
            "art_acceptance": "Open; inspect edited rhythm and pose jumps before integration."}
(ROOT / "edited-timeline.json").write_text(json.dumps(timeline, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"edited_frame_count": len(source_numbers), "edited_total_ms": sum(durations)}))
