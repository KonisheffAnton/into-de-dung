"""Render the actual scene's death frames from an imported isolated checkout."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import subprocess
from PIL import Image

parser = argparse.ArgumentParser()
parser.add_argument("--project", type=Path, required=True)
parser.add_argument("--godot", default=r"D:\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe")
args = parser.parse_args()
report = Path(__file__).resolve().parent
env = os.environ.copy()
env["APPDATA"] = str(args.project.parent / "death-audit-profile")
Path(env["APPDATA"]).mkdir(exist_ok=True)
startup = subprocess.STARTUPINFO()
startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
startup.wShowWindow = 0
command = [args.godot, "--path", str(args.project), "--screen", "0", "--script",
           "res://docs/art/enemy-warrior-death-20261023/render_audit.gd", "--", f"--output={report}"]
with (report / "render-audit.txt").open("w", encoding="utf-8") as log:
    result = subprocess.run(command, env=env, startupinfo=startup, creationflags=subprocess.CREATE_NO_WINDOW,
                            stdout=log, stderr=subprocess.STDOUT, timeout=90)
text = (report / "render-audit.txt").read_text(encoding="utf-8")
assert result.returncode == 0 and ", 0 failed" in text and "ERROR:" not in text, text[-6000:]
frames = sorted((report / "frames").glob("frame-*.png"))
assert len(frames) == 17
images = [Image.open(frame).convert("RGB") for frame in frames]
assert all(im.size == (640, 640) for im in images)
# GIF is only a repeatable preview of rendered gameplay frames, not a source asset.
images[0].save(report / "death-2-in-game.gif", save_all=True, append_images=images[1:],
               duration=[150] * 17, loop=0, disposal=2, optimize=False)
gif = Image.open(report / "death-2-in-game.gif")
assert gif.n_frames == 17
for index in range(17):
    gif.seek(index)
    assert gif.info["duration"] == 150
summary = {"renderResult": text.strip().splitlines()[-1], "renderedFrames": 17,
           "gifPreviewRepeats": True, "gameResourceLoops": False, "frameDurationMs": 150,
           "files": [{"path": p.relative_to(report).as_posix(), "sha256": hashlib.sha256(p.read_bytes()).hexdigest()} for p in frames]}
(report / "render-validation.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
print(summary["renderResult"])
