"""Package unmodified PixelLab PNGs as a readable GIF and contact sheet."""
import hashlib
import json
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent
frames = [Image.open(path).convert("RGBA") for path in sorted((ROOT / "pixellab").glob("frame-*.png"))]
assert len(frames) == 16, len(frames)
assert all(frame.size == (128, 128) for frame in frames)
background = (39, 49, 43, 255)
previews = []
for frame in frames:
    preview = Image.new("RGBA", (512, 512), background)
    preview.alpha_composite(frame.resize((512, 512), Image.Resampling.NEAREST))
    previews.append(preview.convert("RGB"))
frames[0].save(ROOT / "taunt-native.gif", save_all=True, append_images=frames[1:],
               duration=150, loop=0, disposal=2, optimize=False)
previews[0].save(ROOT / "preview.gif", save_all=True, append_images=previews[1:],
                 duration=[150] * 15 + [600], loop=0, disposal=2, optimize=False)
sheet = Image.new("RGBA", (4 * 384, 4 * 408), background)
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
    assert gif.n_frames == 16
    gif_info[name] = {"frames": gif.n_frames, "size": gif.size, "duration_ms": durations, "total_ms": sum(durations)}
(ROOT / "validation.json").write_text(json.dumps({"sources": validation, "previews": gif_info,
    "transforms": "Original PNGs retained. Nearest-neighbor enlargement and background compositing only. No pose edits, registration or interpolation.",
    "art_acceptance": "Open; visual review is separate from file validation."}, indent=2) + "\n", encoding="utf-8")
print(json.dumps(gif_info))
