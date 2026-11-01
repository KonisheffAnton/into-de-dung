"""Recheck final edits in the completed isolated GPU snapshot, never in repo root."""
from pathlib import Path
import hashlib
import json
import os
import re
import shutil
import subprocess
import time
import uuid

ROOT = Path(__file__).resolve().parents[3]
SNAPSHOT = ROOT / "test_reports/demo-e818b1f6c1374944b682fba8602ad8e4"
PROJECT = SNAPSHOT / "project"
GODOT = Path(r"D:\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe")
PATCHED = {
    "scripts/demo/character_skin_catalog.gd",
    "tests/test_character_skins.gd",
    "tests/test_rogue_animations.gd",
}
# Эти производные отчёты не загружаются Godot; их проверяет builder --check.
ASSET_DOCS = {
    "assets/art_presets/approved/character_skins_v1/" + name
    for name in ("README.md", "manifest.json", "index.json", "validation.json")
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    assert PROJECT.is_dir() and PROJECT != ROOT
    manifest = json.loads((SNAPSHOT / "manifest.json").read_text(encoding="utf-8"))
    checked = 0
    for entry in manifest:
        name = entry["path"]
        if not name.startswith(("scripts/", "scenes/", "assets/", "tests/", "tools/demo/")):
            continue
        if name in ASSET_DOCS:
            continue
        if name not in PATCHED:
            assert sha(ROOT / name) == entry["sha256"] == sha(PROJECT / name), name
            checked += 1
    output = ROOT / "test_reports/rogue02-integration-20261101" / ("rerun-" + uuid.uuid4().hex[:8])
    output.mkdir(parents=True)
    hashes = {}
    for name in sorted(PATCHED):
        shutil.copy2(ROOT / name, PROJECT / name)
        hashes[name] = sha(ROOT / name)
    env = dict(os.environ, APPDATA=str(output / "profile"))
    (output / "profile").mkdir()
    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = 0
    records = {"snapshot": str(SNAPSHOT), "unchanged_source_files": checked, "patched_sha256": hashes, "checks": {}}
    tests = [
        ("import", True, ["--import"]),
        ("startup", True, ["--quit-after", "90"]),
        ("character_skins_headless", True, ["--script", "tests/test_character_skins.gd"]),
        ("character_skins_hub_headless", True, ["--script", "tests/test_character_skins_hub.gd"]),
        ("rogue_animations_headless", True, ["--script", "tests/test_rogue_animations.gd"]),
        ("defender_buff_headless", True, ["--script", "tests/test_defender_buff.gd"]),
        ("rogue_buff_headless", True, ["--script", "tests/test_defender_buff.gd", "--", "--rogue"]),
        ("character_skins_gpu", False, ["--script", "tests/test_character_skins.gd", "--", "--captures=" + str(output / "captures")]),
        ("rogue_animations_gpu", False, ["--script", "tests/test_rogue_animations.gd"]),
    ]
    for label, headless, args in tests:
        command = [str(GODOT), "--path", str(PROJECT)] + (["--headless"] if headless else ["--screen", "0"]) + args
        start = time.perf_counter()
        with (output / (label + ".log")).open("wb") as log:
            result = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=120,
                                    startupinfo=startup, creationflags=subprocess.CREATE_NO_WINDOW)
        text = (output / (label + ".log")).read_text(encoding="utf-8", errors="replace")
        errors = any(marker in text for marker in ("SCRIPT ERROR", "Parse Error", "ERROR:"))
        counts = re.findall(r"(\d+) passed, (\d+) failed", text)
        success = result.returncode == 0 and not errors and not any(int(pair[1]) for pair in counts)
        if label not in ("import", "startup"):
            success = success and bool(counts)
        records["checks"][label] = {"status": "PASS" if success else "FAIL", "counts": counts,
                                     "seconds": round(time.perf_counter() - start, 3), "exit_code": result.returncode}
        (output / "validation.json").write_text(json.dumps(records, indent=2), encoding="utf-8")
        print(label, records["checks"][label], flush=True)
        if not success:
            print(text)
            raise SystemExit(1)
    print(output, flush=True)


if __name__ == "__main__":
    main()
