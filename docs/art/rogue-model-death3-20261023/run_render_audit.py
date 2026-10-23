"""Render actual production sprites from an imported isolated checkout."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
from PIL import Image

parser = argparse.ArgumentParser()
parser.add_argument("--project", type=Path, required=True)
parser.add_argument("--godot", default=r"D:\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe")
args = parser.parse_args()
report = Path(__file__).resolve().parent
env = os.environ.copy()
env["APPDATA"] = str(args.project.parent / "rogue-art-audit-profile")
Path(env["APPDATA"]).mkdir(exist_ok=True)
startup = subprocess.STARTUPINFO()
startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
startup.wShowWindow = 0
command = [args.godot, "--path", str(args.project), "--screen", "0", "--script",
           "res://docs/art/rogue-model-death3-20261023/render_audit.gd", "--", f"--output={report}"]
with (report / "render-audit.txt").open("w", encoding="utf-8") as log:
    result = subprocess.run(command, env=env, startupinfo=startup, creationflags=subprocess.CREATE_NO_WINDOW,
                            stdout=log, stderr=subprocess.STDOUT, timeout=90)
text = (report / "render-audit.txt").read_text(encoding="utf-8")
assert result.returncode == 0 and ", 0 failed" in text and "ERROR:" not in text, text[-6000:]
files = []
for side in ["player", "enemy"]:
    frames = sorted((report / side).glob("frame-*.png"))
    fades = sorted((report / side).glob("fade-*.png"))
    assert len(frames) == 17 and len(fades) == 4
    images = [Image.open(p).convert("RGB") for p in frames + fades]
    assert all(im.size == (640, 640) for im in images)
    durations = [150] * 16 + [400] + [200] * 4
    images[0].save(report / f"death-3-{side}.gif", save_all=True, append_images=images[1:],
                   duration=durations, loop=0, disposal=2, optimize=False)
    with Image.open(report / f"death-3-{side}.gif") as gif:
        total = 0
        for i in range(gif.n_frames):
            gif.seek(i)
            total += gif.info["duration"]
        assert total == 3600
    files += frames + fades + [report / side / "still.png"]
files += [report / "rogue-warrior-in-game.png"]
summary = {"result": text.strip().splitlines()[-1], "runtime_frames": 34,
           "preview_repeats_only_for_review": True, "preview_lifecycle_ms": 3600,
           "files": [{"path": p.relative_to(report).as_posix(), "sha256": hashlib.sha256(p.read_bytes()).hexdigest()} for p in files]}
(report / "render-validation.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8", newline="\n")
print(summary["result"])
