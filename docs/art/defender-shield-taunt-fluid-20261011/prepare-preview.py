"""Preview every returned PixelLab frame in original order, no pose edits."""
import hashlib
import json
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent
paths = sorted((ROOT / "pixellab").glob("frame-*.png"))
expected = json.loads((ROOT / "pixellab/result.json").read_text())["frame_count"]
assert len(paths) == expected and expected > 1
frames = [Image.open(path).convert("RGBA") for path in paths]
assert all(frame.size == (128, 128) for frame in frames)
background = (39, 49, 43, 255)
previews = []
for frame in frames:
    preview = Image.new("RGBA", (512,512), background)
    preview.alpha_composite(frame.resize((512,512), Image.Resampling.NEAREST))
    previews.append(preview.convert("RGB"))
gif_info = {}
for name, clip, durations in [
    ("taunt-native.gif", frames, [80] * len(frames)),
    ("preview.gif", previews, [80] * (len(frames)-1) + [550]),
    # Темп тихих участков сокращён; все позы и интервалы внутри ударов сохранены.
    ("preview-compact.gif", previews, [40]*8 + [80]*16 + [40]*8 + [350])
]:
    assert len(durations) == len(clip)
    clip[0].save(ROOT / name, save_all=True, append_images=clip[1:], duration=durations,
                 loop=0, disposal=2, optimize=False)
    gif = Image.open(ROOT / name)
    assert gif.n_frames == len(clip)
    actual = []
    for index in range(gif.n_frames):
        gif.seek(index)
        actual.append(gif.info["duration"])
    assert actual == durations
    gif_info[name] = {"frames":gif.n_frames, "size":gif.size, "duration_ms":actual, "total_ms":sum(actual)}
sheet = Image.new("RGBA", (6*256, ((len(frames)+5)//6)*280), background)
draw = ImageDraw.Draw(sheet)
checks = []
for index, (path, frame) in enumerate(zip(paths, frames)):
    x, y = index % 6 * 256, index // 6 * 280
    sheet.alpha_composite(frame.resize((256,256), Image.Resampling.NEAREST), (x,y))
    draw.text((x+8,y+261), f"{index+1:02}", fill=(230,234,220,255))
    alpha = frame.getchannel("A")
    assert alpha.getbbox() and alpha.getextrema() == (0,255)
    checks.append({"frame":index+1, "size":frame.size, "alpha_bbox":alpha.getbbox(),
                   "alpha_extrema":alpha.getextrema(), "sha256":hashlib.sha256(path.read_bytes()).hexdigest()})
sheet.save(ROOT / "filmstrip.png")
(ROOT / "validation.json").write_text(json.dumps({"sources":checks, "previews":gif_info,
    "transforms":"Unmodified PNGs, original order, no repetitions/reversal/pose edits. Nearest enlargement and preview background only.",
    "art_acceptance":"Open; file validation is separate from visual review and user acceptance."}, indent=2) + "\n", encoding="utf-8")
print(json.dumps(gif_info))
