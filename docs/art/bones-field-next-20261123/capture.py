"""Render the latest twenty concepts in a verified isolated Godot project."""
from pathlib import Path
import argparse
import hashlib
import json
import math
import os
import shutil
import subprocess
from PIL import Image

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[2]
SOURCES = ROOT.parent / "bones-twenty-next-20261123"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(name, data):
    (ROOT / name).write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", type=Path, required=True)
    parser.add_argument("--godot", type=Path, required=True)
    args = parser.parse_args()
    project = args.project.resolve()
    project.relative_to(REPO / "test_reports")
    assert project.name == "project" and project.parent.name.startswith("demo-")
    manifest = json.loads((project.parent / "manifest.json").read_text(encoding="utf-8"))
    runtime = [row["path"] for row in manifest if row["path"].startswith(("scripts/", "scenes/", "assets/"))
               or row["path"] == "project.godot"]
    mismatches = [name for name in runtime if sha(REPO / name) != sha(project / name)]
    assert not mismatches, mismatches
    choices = json.loads((SOURCES / "selection.json").read_text(encoding="utf-8"))
    variants = []
    hashes = {}
    identifiers = [f"G{i}" for i in range(31, 41)] + [f"PL{i}" for i in range(39, 49)]
    for name in identifiers:
        path = SOURCES / choices[name]
        im = Image.open(path).convert("RGBA")
        if name.startswith("PL"):
            assert im.size == (64, 64)
            region, display = None, [64, 64]
        else:
            box = im.getchannel("A").point(lambda a: 255 if a >= 128 else 0).getbbox()
            assert box
            x, y, right, bottom = box
            width, height = right - x, bottom - y
            scale = min(60 / width, 32 / height, 1)
            region = [x, y, width, height]
            display = [max(1, round(width * scale)), max(1, round(height * scale))]
        variants.append({"id": name, "path": str(path), "region": region, "display_size": display})
        hashes[str(path)] = sha(path)
    save("variants.json", variants)
    save("source-hashes.json", hashes)
    shutil.copyfile(ROOT / "capture_all.gd", project / "tools/demo/capture_bones_next.gd")
    env = dict(os.environ, APPDATA=str(project.parent / "profile"))
    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = 0
    command = [str(args.godot), "--path", str(project), "--screen", "0", "--script",
               "tools/demo/capture_bones_next.gd", "--", "--captures=" + str(ROOT),
               "--variants=" + str(ROOT / "variants.json")]
    with (ROOT / "capture.log").open("wb") as log:
        result = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT,
                                startupinfo=startup, creationflags=subprocess.CREATE_NO_WINDOW, timeout=90)
    output = (ROOT / "capture.log").read_text(encoding="utf-8", errors="replace")
    print(output)
    save("runtime-check.json", {"isolated_project": str(project), "runtime_files": len(runtime),
         "mismatches": mismatches, "script_sha256": sha(ROOT / "capture_all.gd"),
         "capture_base": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
         "exit_code": result.returncode})
    assert result.returncode == 0 and "SCRIPT ERROR" not in output and "ERROR:" not in output
    report = json.loads((ROOT / "capture-all.json").read_text(encoding="utf-8"))
    assert not report["failed_checks"] and report["snapshot_unchanged"]
    assert len(report["variants"]) == 20 and report["selected_cells_unique"] == 20
    assert report["camera_zoom"] == 1.0
    frame = Image.open(ROOT / "field-all-100.png").convert("RGB")
    checks = []
    for variant in report["variants"]:
        if not variant["id"].startswith("PL"):
            continue
        im = Image.open(variant["path"]).convert("RGBA")
        x, y = [math.floor(value) for value in variant["viewport_bounds"][:2]]
        opaque = [(px, py, im.getpixel((px, py))[:3]) for py in range(64) for px in range(64)
                  if im.getpixel((px, py))[3] == 255]
        exact = sum(frame.getpixel((x + px, y + py)) == rgb for px, py, rgb in opaque)
        checks.append({"id": variant["id"], "opaque_pixels": len(opaque), "exact_rgb": exact})
    crop_box = [190, 235, 1250, 855]
    frame.crop(crop_box).save(ROOT / "all-twenty-100.png")
    save("pixel-check-all.json", {"crop_box": crop_box, "crop_scale": 1, "PL_pixel_checks": checks})
    assert all(row["opaque_pixels"] > 0 and row["opaque_pixels"] == row["exact_rgb"] for row in checks), checks
    assert all(sha(Path(path)) == expected for path, expected in hashes.items())
    print("PASS: twenty variants, unchanged state/RNG, exact native PixelLab pixels and unchanged sources")


if __name__ == "__main__":
    main()
