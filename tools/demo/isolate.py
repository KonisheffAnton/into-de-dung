"""Run the current working-tree demo without importing archived test reports."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import uuid


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--check", action="store_true", help="headless import, startup and demo input checks")
    modes.add_argument("--render-check", action="store_true", help="render demo checks and save screenshots")
    parser.add_argument("--full", action="store_true", help="also run the existing core regression")
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN"))
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    godot = args.godot or shutil.which("godot") or shutil.which("godot4")
    local = Path(r"D:\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe")
    if not godot and local.is_file():
        godot = str(local)
    if not godot:
        parser.error("Set GODOT_BIN or pass --godot with the Godot 4.7 executable path.")
    out = repo / "test_reports" / ("demo-" + uuid.uuid4().hex)
    project = out / "project"
    project.mkdir(parents=True)
    names = subprocess.check_output(["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"], cwd=repo).decode().split("\0")
    manifest = []
    for name in sorted(set(names) - {""}):
        if name.startswith(("test_reports/", ".godot/")):
            continue
        source = repo / name
        if not source.is_file():
            continue
        target = project / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        manifest.append({"path": name, "sha256": hashlib.sha256(source.read_bytes()).hexdigest()})
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    env = os.environ.copy()
    env["APPDATA"] = str(out / "profile")
    Path(env["APPDATA"]).mkdir()
    print(out, flush=True)
    hidden = {}
    if os.name == "nt":
        startup = subprocess.STARTUPINFO()
        startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        startup.wShowWindow = 0
        hidden = {"startupinfo": startup, "creationflags": subprocess.CREATE_NO_WINDOW}

    def run(label, command_args, headless=True, legacy=False):
        command = [godot, "--path", str(project)]
        if headless:
            command.append("--headless")
        command += command_args
        with (out / (label + ".log")).open("wb") as log:
            result = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=600 if legacy else 120, **hidden)
        output = (out / (label + ".log")).read_text(encoding="utf-8", errors="replace")
        invalid = result.returncode != 0 or "SCRIPT ERROR" in output or "Parse Error" in output
        if not legacy:
            invalid = invalid or "ERROR:" in output or "WARNING: ObjectDB" in output
        if label in ("demo", "battle", "forecast", "guard", "healing", "summon", "summon_snapshot", "attack_calculation", "attack_d1", "armor_calculation", "armor_snapshot", "armor_integration", "armor_recovery", "armor_ui"):
            marker = {"demo": "DEMO RESULTS:", "battle": "BATTLE RESULTS:", "forecast": "FORECAST RESULTS:", "guard": "GUARD RESULTS:", "healing": "HEALING RESULTS:", "summon": "SUMMON RESULTS:", "summon_snapshot": "SUMMON SNAPSHOT RESULTS:", "attack_calculation": "D1 CALCULATION RESULTS:", "attack_d1": "D1 INTEGRATION RESULTS:", "armor_calculation": "ARMOR RESULTS:", "armor_snapshot": "ARMOR SNAPSHOT RESULTS:", "armor_integration": "ARMOR INTEGRATION RESULTS:", "armor_recovery": "ARMOR RECOVERY RESULTS:", "armor_ui": "ARMOR UI RESULTS:"}[label]
            invalid = invalid or marker not in output or ", 0 failed" not in output
        if legacy:
            invalid = invalid or "0 failed" not in output
        print(label, "FAIL" if invalid else "PASS", flush=True)
        if invalid:
            print(output[-4000:])
            raise SystemExit(1)

    run("import", ["--import"])
    cache = (project / ".godot/global_script_class_cache.cfg").read_text(encoding="utf-8")
    if "test_reports" in cache:
        raise RuntimeError("Archived scripts leaked into the class cache")
    if args.check or args.render_check:
        run("startup", ["--quit-after", "3"])
        run("attack_calculation", ["--script", "tests/test_attack_damage_calculation.gd"])
        run("attack_d1", ["--script", "tests/test_attack_damage_d1.gd"])
        run("armor_calculation", ["--script", "tests/test_armor_hit_calculation.gd"])
        run("armor_snapshot", ["--script", "tests/test_armor_snapshot.gd"])
        run("armor_integration", ["--script", "tests/test_armor_integration.gd"])
        run("armor_recovery", ["--script", "tests/test_armor_recovery.gd"])
        run("forecast", ["--script", "tests/test_attack_forecast.gd"])
        run("guard", ["--script", "tests/test_guard_stance.gd"])
        run("summon_snapshot", ["--script", "tests/test_summon_snapshot.gd"])
        run("summon", ["--script", "tests/test_summoning_item.gd"])
        run("healing", ["--script", "tests/test_healing_item.gd"])
        if args.full:
            run("core", ["--script", "tests/run_tests.gd"], legacy=True)
        demo_args = ["--script", "tests/test_battle_demo.gd"]
        if args.render_check:
            captures = out / "screenshots"
            captures.mkdir()
            demo_args += ["--", "--captures=" + str(captures)]
        run("demo", demo_args, headless=not args.render_check)
        battle_args = ["--script", "tests/test_tactical_battle.gd"]
        if args.render_check:
            battle_args += ["--", "--captures=" + str(captures)]
        run("battle", battle_args, headless=not args.render_check)
        armor_args = ["--script", "tests/test_armor_battle.gd"]
        if args.render_check:
            armor_args += ["--", "--captures=" + str(captures)]
        run("armor_ui", armor_args, headless=not args.render_check)
    else:
        # This is the user-requested interactive window, so it is intentionally visible.
        with (out / "play.log").open("wb") as log:
            process = subprocess.Popen([godot, "--path", str(project)], env=env, stdout=log, stderr=subprocess.STDOUT)
        print("Demo window launched, PID", process.pid)


if __name__ == "__main__":
    main()
