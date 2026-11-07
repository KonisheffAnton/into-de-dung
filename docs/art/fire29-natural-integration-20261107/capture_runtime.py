"""Capture the integrated scene in a fresh imported isolated project and compare to accepted art."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

import numpy as np
from PIL import Image

PACKAGE = Path(__file__).resolve().parent
REPO = PACKAGE.parents[2]
REPORT = REPO / "test_reports/fire29-natural-integration-20261107"
REFERENCE = REPO / "test_reports/fire29-natural-20261107/natural29-02-middle-field"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("--project", type=Path, required=True)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--label", default="gpu", help="unique report directory name")
    args = parser.parse_args()
    assert args.label.isascii() and args.label.replace("-", "").isalnum()
    project = args.project.resolve()
    assert project.name == "project" and project.parent.name.startswith("demo-")
    assert project.parent.parent == (REPO / "test_reports").resolve()
    assert (project / ".godot/global_script_class_cache.cfg").is_file()
    hidden = {}
    if os.name == "nt":
        startup = subprocess.STARTUPINFO()
        startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        startup.wShowWindow = 0
        hidden = {"startupinfo": startup, "creationflags": subprocess.CREATE_NO_WINDOW}
        active = subprocess.check_output(["powershell", "-NoProfile", "-Command",
            "@(Get-CimInstance Win32_Process | Where-Object { $_.Name -like '*Godot*' }).Count"],
            **hidden).decode().strip()
        assert active == "0", "Another Godot runner is active"
    capture = REPORT / args.label
    capture.mkdir(exist_ok=False)
    for size in ("128", "384", "profile"): (capture / size).mkdir()
    script = capture / "capture_runtime.gd"
    script.write_bytes((PACKAGE / script.name).read_bytes())
    env = os.environ.copy()
    env["APPDATA"] = str(capture / "profile")
    command = [str(args.godot), "--path", str(project), "--screen", "0", "--script",
               str(script), "--", "--captures=" + str(capture)]
    (capture / "command.json").write_bytes((json.dumps(command, indent=2) + "\n").encode())
    with (capture / "capture.log").open("wb") as log:
        result = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT,
                                timeout=90, **hidden)
    output = (capture / "capture.log").read_text(encoding="utf-8")
    print(output)
    assert result.returncode == 0 and "FIRE29 RUNTIME CAPTURE PASS:" in output
    assert "ERROR" not in output
    reference_hashes = json.loads((REFERENCE / "completion.json").read_bytes())["files"]
    comparisons = {}
    exports = {}
    for size in ("128", "384"):
        images = []
        for index in range(12):
            name = f"{size}/{index:03d}.png"
            source, target = REFERENCE / name, capture / name
            assert sha(source) == reference_hashes[name], "Accepted capture changed"
            with Image.open(source) as im: a = np.array(im.convert("RGBA"))
            with Image.open(target) as im: b = np.array(im.convert("RGBA"))
            delta = np.abs(a.astype(np.int16) - b.astype(np.int16))
            comparisons[name] = {"reference_sha256": sha(source), "runtime_sha256": sha(target),
                                 "different_pixels": int(np.count_nonzero(np.any(delta, axis=2))),
                                 "max_channel_delta": int(delta.max())}
            images.append(Image.fromarray(b))
        destination = PACKAGE / f"fire29-runtime-{size}.webp"
        images[0].save(destination, save_all=True, append_images=images[1:], duration=120,
                       loop=0, lossless=True, method=6)
        with Image.open(destination) as im:
            assert im.n_frames == 12 and im.info["loop"] == 0
            for index, original in enumerate(images):
                im.seek(index)
                decoded = im.convert("RGBA")
                assert decoded.tobytes() == original.tobytes() and im.info["duration"] == 120
        exports[size] = {"path": destination.relative_to(REPO).as_posix(), "sha256": sha(destination),
                         "frames": 12, "slot_ms": 120, "rgba_and_timing": "PASS"}
    report = {"project": str(project), "script_sha256": sha(script),
              "comparisons": comparisons, "exports": exports,
              "exact_rgba": all(v["different_pixels"] == 0 for v in comparisons.values())}
    (capture / "completion.json").write_bytes((json.dumps(report, indent=2) + "\n").encode())
    print(json.dumps({"exact_rgba": report["exact_rgba"], "compared": len(comparisons)}))
    assert report["exact_rgba"], "Runtime pixels differ from accepted art; inspect before accepting"


if __name__ == "__main__":
    main()
