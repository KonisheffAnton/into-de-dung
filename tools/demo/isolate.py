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
        if label == "demo":
            invalid = invalid or "DEMO RESULTS:" not in output or ", 0 failed" not in output
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
        if args.full:
            run("core", ["--script", "tests/run_tests.gd"], legacy=True)
        demo_args = ["--script", "tests/test_battle_demo.gd"]
        if args.render_check:
            captures = out / "screenshots"
            captures.mkdir()
            demo_args += ["--", "--captures=" + str(captures)]
        run("demo", demo_args, headless=not args.render_check)
    else:
        # This is the user-requested interactive window, so it is intentionally visible.
        with (out / "play.log").open("wb") as log:
            process = subprocess.Popen([godot, "--path", str(project)], env=env, stdout=log, stderr=subprocess.STDOUT)
        print("Demo window launched, PID", process.pid)


if __name__ == "__main__":
    main()
