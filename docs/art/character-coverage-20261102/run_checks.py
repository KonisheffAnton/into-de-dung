"""Rerun targeted probes in an already imported isolated project, one native Godot at a time."""
from pathlib import Path
import argparse
import json
import os
import re
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "test_reports/character-coverage-20261102"
GODOT = Path(r"D:\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("project", type=Path)
    parser.add_argument("checks", nargs="+")
    parser.add_argument("--headless", action="store_true")
    parser.add_argument("--negative", action="store_true")
    parser.add_argument("--baseline-production", action="store_true")
    args = parser.parse_args()
    project = args.project.resolve()
    assert project.parent.parent == ROOT / "test_reports" and project.name == "project"
    assert (project / ".godot").is_dir()
    processes = subprocess.check_output(["powershell", "-NoProfile", "-Command",
        "@(Get-Process Godot* -ErrorAction SilentlyContinue).Count"], text=True).strip()
    assert processes == "0", "another Godot runner is active"
    OUT.mkdir(exist_ok=True)
    baseline = OUT / "baseline"
    baseline.mkdir(exist_ok=True)
    for name in ["native_sprite.gdshader", "character_palette.gdshader"]:
        content = subprocess.check_output(["git", "show", "8f405fe:assets/art_presets/trials/pixel_zoom_v1/" + name], cwd=ROOT)
        (baseline / name).write_bytes(content)
    # Копируем только собственные текущие изменения; root никогда не импортируется.
    changed = subprocess.check_output(["git", "diff", "--name-only", "-z"], cwd=ROOT).decode().split("\0")
    added = subprocess.check_output(["git", "ls-files", "--others", "--exclude-standard", "-z"], cwd=ROOT).decode().split("\0")
    for name in changed + added:
        if not name or name == "scenes/demo/main_menu.tscn" or name.startswith("docs/art/battlefield-reference-03-20261017/"): continue
        source = ROOT / name
        if not source.is_file(): continue
        destination = project / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)
    originals = {}
    if args.negative:
        for name in ["native_sprite.gdshader", "character_palette.gdshader"]:
            target = project / "assets/art_presets/trials/pixel_zoom_v1" / name
            originals[target] = target.read_bytes()
            target.write_bytes((baseline / name).read_bytes())
    if args.baseline_production:
        assert args.negative, "baseline comparison is an expected-failure diagnostic"
        for name in ["scenes/demo/visuals/art_trial_unit.tscn", "scripts/demo/battle_character_skin_visual.gd"]:
            target = project / name
            originals[target] = target.read_bytes()
            target.write_bytes(subprocess.check_output(["git", "show", "8f405fe:" + name], cwd=ROOT))
    env = dict(os.environ, APPDATA=str(OUT / "profile"))
    Path(env["APPDATA"]).mkdir(exist_ok=True)
    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = 0
    try:
        for check in args.checks:
            suffix = ("-headless" if args.headless else "-gpu") + ("-negative" if args.negative else "")
            if args.baseline_production: suffix += "-baseline"
            label = check + suffix
            script = "docs/art/character-coverage-20261102/render_probe.gd" if check == "render_probe" else f"tests/test_{check}.gd"
            captures = OUT / (label + "-captures")
            captures.mkdir(exist_ok=True)
            command = [str(GODOT), "--path", str(project)] + (["--headless"] if args.headless else ["--screen", "0"])
            command += ["--script", script, "--", "--captures=" + str(captures), "--baseline=" + str(baseline)]
            started = time.perf_counter()
            with (OUT / (label + ".log")).open("wb") as log:
                result = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT,
                    timeout=120, startupinfo=startup, creationflags=subprocess.CREATE_NO_WINDOW)
            output = (OUT / (label + ".log")).read_text(encoding="utf-8", errors="replace")
            counts = re.findall(r"(\d+) passed, (\d+) failed", output)
            clean = not any(marker in output for marker in ["ERROR:", "SCRIPT ERROR", "Parse Error"])
            ok = clean and bool(counts) and (result.returncode != 0 and any(int(p[1]) for p in counts) if args.negative else result.returncode == 0 and all(int(p[1]) == 0 for p in counts))
            report = {"status": "PASS" if ok else "FAIL", "negative_control": args.negative, "counts": counts,
                "seconds": round(time.perf_counter() - started, 3), "exit_code": result.returncode, "command": command}
            (OUT / (label + ".json")).write_text(json.dumps(report, indent=2), encoding="utf-8")
            print(label, report["status"], counts, report["seconds"], flush=True)
            if not ok:
                print(output)
                raise SystemExit(1)
    finally:
        for target, data in originals.items(): target.write_bytes(data)


if __name__ == "__main__":
    main()
