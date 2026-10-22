"""Rerun only corrected shared route tests in the existing imported isolation."""
from pathlib import Path
import hashlib
import json
import os
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[3]
REPORT = Path(__file__).resolve().parent
RUN = ROOT / "test_reports/demo-e511e79f6aac438f898cf2830fb52d90"
PROJECT = RUN / "project"
GODOT = r"D:\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
TEST = "tests/test_defender_death_routes.gd"
baseline = json.loads((RUN / "manifest.json").read_text())
runtime_count = 0
for entry in baseline:
    path = entry["path"]
    if path.startswith(("scripts/", "scenes/", "assets/")):
        assert hashlib.sha256((ROOT / path).read_bytes()).hexdigest() == entry["sha256"], path
        assert (ROOT / path).read_bytes() == (PROJECT / path).read_bytes(), path
        runtime_count += 1
shutil.copyfile(ROOT / TEST, PROJECT / TEST)
env = os.environ.copy()
env["APPDATA"] = str(RUN / "profile")
startup = subprocess.STARTUPINFO()
startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
startup.wShowWindow = 0
results = {}
for label, extra in [("parse", ["--headless", "--check-only"]), ("defender_death_routes", []), ("rogue_death_routes", [])]:
    command = [GODOT, "--path", str(PROJECT), "--screen", "0"] + extra + ["--script", TEST]
    if label != "parse":
        captures = RUN / (label + "-corrected-captures")
        captures.mkdir(exist_ok=True)
        command += ["--", f"--captures={captures}"] + (["--rogue"] if label.startswith("rogue") else [])
    start = time.monotonic()
    log_path = RUN / (label + "-corrected.log")
    with log_path.open("w", encoding="utf-8") as log:
        completed = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT,
                                   startupinfo=startup, creationflags=subprocess.CREATE_NO_WINDOW, timeout=90)
    output = log_path.read_text(encoding="utf-8")
    valid = completed.returncode == 0 and "ERROR:" not in output and "FAIL " not in output
    if label != "parse": valid = valid and label.replace("_", " ").upper() + " RESULTS:" in output and ", 0 failed" in output
    results[label] = {"status": "PASS" if valid else "FAIL", "seconds": time.monotonic() - start,
                      "result": [line for line in output.splitlines() if "RESULTS:" in line], "log": str(log_path)}
    print(label, results[label]["status"], results[label]["result"], flush=True)
    if not valid: print(output[-6000:], flush=True)
summary = {"importedRun": str(RUN), "runtimeFilesUnchanged": runtime_count,
           "correctedTest": TEST, "testSha256": hashlib.sha256((ROOT / TEST).read_bytes()).hexdigest(),
           "checks": results}
(REPORT / "corrected-routes.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
assert all(value["status"] == "PASS" for value in results.values())
