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
SOURCES = ROOT
BASE_COMMIT = "f7c2f79aefc43df77aabb220591718ac293ce660"
MAIN_MENU_OVERRIDE = "scenes/demo/main_menu.tscn"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(name, data):
    (ROOT / name).write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def read_base_blobs(paths):
    """Читает базовые git blobs одним процессом, не подмешивая текущий checkout."""
    result = {}
    process = subprocess.Popen(["git", "cat-file", "--batch"], cwd=REPO,
                               stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    assert process.stdin is not None and process.stdout is not None
    for path in paths:
        process.stdin.write(f"{BASE_COMMIT}:{path}\n".encode("utf-8"))
        process.stdin.flush()
        header = process.stdout.readline().rstrip(b"\n").split()
        if len(header) < 3 or header[1] != b"blob":
            result[path] = None
            continue
        size = int(header[2])
        data = process.stdout.read(size)
        assert len(data) == size
        assert process.stdout.read(1) == b"\n"
        result[path] = data
    process.stdin.close()
    assert process.wait() == 0
    return result


def crlf_equivalent(left, right):
    # Учёт только эквивалентных CRLF/LF сохраняет проверку содержимого и точные хеши обоих файлов.
    return left != right and b"\r\n" in left + right and left.replace(b"\r\n", b"\n") == right.replace(b"\r\n", b"\n")


def verify_runtime_snapshot(project, manifest):
    runtime_rows = [row for row in manifest if row["path"].startswith(("scripts/", "scenes/", "assets/"))
                    or row["path"] == "project.godot"]
    runtime_paths = [row["path"] for row in runtime_rows]
    base_blobs = read_base_blobs(runtime_paths)
    base_exact, base_crlf_equivalent, live_differences = [], [], []
    main_menu_override = None
    for row in runtime_rows:
        path = row["path"]
        isolated_path = project / path
        live_path = REPO / path
        assert isolated_path.is_file(), f"isolated runtime file missing: {path}"
        isolated_bytes = isolated_path.read_bytes()
        live_bytes = live_path.read_bytes() if live_path.is_file() else None
        isolated_sha = hashlib.sha256(isolated_bytes).hexdigest()
        assert isolated_sha == row["sha256"], f"isolated snapshot differs from manifest: {path}"
        base_bytes = base_blobs[path]
        assert base_bytes is not None, f"base git blob missing: {path}"
        base_sha = hashlib.sha256(base_bytes).hexdigest()

        if path == MAIN_MENU_OVERRIDE:
            # Сцену меню разрешаем только как byte-exact копию текущего защищённого live-файла.
            assert live_bytes is not None and isolated_bytes == live_bytes, \
                "main_menu override is allowed only when isolated bytes equal current live bytes"
            main_menu_override = {"path": path, "base_sha256": base_sha,
                                  "isolated_sha256": isolated_sha, "live_sha256": isolated_sha,
                                  "reason": "authorized protected-scene override; isolated bytes equal live bytes"}
        elif isolated_bytes == base_bytes:
            base_exact.append(path)
        elif crlf_equivalent(isolated_bytes, base_bytes):
            base_crlf_equivalent.append({"path": path, "base_sha256": base_sha,
                                         "isolated_sha256": isolated_sha})
        else:
            raise AssertionError(f"isolated runtime differs from fixed base commit: {path}")

        if live_bytes != isolated_bytes:
            # Конкурирующие незакоммиченные изменения описываем отдельно, не копируя их в снимок.
            live_differences.append({"path": path,
                                     "isolated_sha256": isolated_sha,
                                     "live_sha256": hashlib.sha256(live_bytes).hexdigest() if live_bytes is not None else None,
                                     "base_sha256": base_sha,
                                     "classification": "expected concurrent working-tree change; isolated snapshot remains at fixed base"})

    return runtime_paths, {
        "base_commit": BASE_COMMIT,
        "runtime_files": len(runtime_paths),
        "base_exact_count": len(base_exact),
        "base_crlf_equivalent_count": len(base_crlf_equivalent),
        "base_exact_paths": base_exact,
        "base_crlf_equivalent_paths": base_crlf_equivalent,
        "base_mismatches": [],
        "protected_scene_override": main_menu_override,
        "live_vs_isolated_expected_concurrent_changes": live_differences,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", type=Path, required=True)
    parser.add_argument("--godot", type=Path, required=True)
    args = parser.parse_args()
    project = args.project.resolve()
    project.relative_to(REPO / "test_reports")
    assert project.name == "project" and project.parent.name.startswith("demo-")
    manifest = json.loads((project.parent / "manifest.json").read_text(encoding="utf-8"))
    runtime, snapshot_check = verify_runtime_snapshot(project, manifest)
    choices = json.loads((SOURCES / "selection.json").read_text(encoding="utf-8"))
    variants = []
    hashes = {}
    identifiers = [f"G{i}" for i in range(41, 51)] + [f"PL{i}" for i in range(49, 59)]
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
    save("runtime-check.json", {"isolated_project": str(project), "snapshot_check": snapshot_check,
         "script_sha256": sha(ROOT / "capture_all.gd"),
         "checkout_head": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
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
