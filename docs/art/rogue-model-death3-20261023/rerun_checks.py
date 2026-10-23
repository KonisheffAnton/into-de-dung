"""Repeat only the corrected fixtures; verify runtime/assets match the first gate."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[3]
STAGE = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--project", type=Path, required=True)
parser.add_argument("--godot", default=r"D:\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe")
args = parser.parse_args()
project = args.project.resolve()
manifest = json.loads((project.parent / "manifest.json").read_text(encoding="utf-8"))


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


verified = []
for item in manifest:
    name = item["path"]
    if name.startswith(("scripts/", "scenes/", "assets/")) or name == "project.godot":
        assert sha(ROOT / name) == item["sha256"] == sha(project / name), name
        verified.append(item)
assert len(verified) > 500
fixtures = ["tests/test_defender_buff.gd", "docs/art/rogue-model-death3-20261023/render_audit.gd"]
for name in fixtures:
    (project / name).write_bytes((ROOT / name).read_bytes())
env = os.environ.copy()
env["APPDATA"] = str(project.parent / "corrected-rogue-guard-profile")
Path(env["APPDATA"]).mkdir(exist_ok=True)
startup = subprocess.STARTUPINFO()
startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
startup.wShowWindow = 0
results = {}
for name, extra in [("rogue_buff", ["--rogue"]), ("defender_buff", [])]:
    capture = STAGE / "corrected-captures" / name
    capture.mkdir(parents=True, exist_ok=True)
    command = [args.godot, "--path", str(project), "--screen", "0", "--script",
               "res://tests/test_defender_buff.gd", "--", *extra, f"--captures={capture}"]
    with (STAGE / f"corrected-{name}.log").open("w", encoding="utf-8") as log:
        result = subprocess.run(command, env=env, startupinfo=startup, creationflags=subprocess.CREATE_NO_WINDOW,
                                stdout=log, stderr=subprocess.STDOUT, timeout=90)
    output = (STAGE / f"corrected-{name}.log").read_text(encoding="utf-8")
    ok = result.returncode == 0 and ", 0 failed" in output and "ERROR:" not in output
    results[name] = {"exit_code": result.returncode, "status": "PASS" if ok else "FAIL", "output": output}
    print(name + ": " + results[name]["status"])
    assert ok, output
report = {"snapshot": str(project), "runtime_asset_scene_files_verified": len(verified),
          "runtime_changes_since_first_gate": False,
          "fixtures": [{"path": name, "sha256": sha(ROOT / name)} for name in fixtures], "checks": results}
(STAGE / "corrected-checks.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8", newline="\n")
