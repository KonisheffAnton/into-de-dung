"""Capture adjacent units using the verified, imported project copy."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("--project", type=Path, required=True)
parser.add_argument("--godot", type=Path, required=True)
args = parser.parse_args()
package = Path(__file__).resolve().parent
repo = package.parents[2]
project = args.project.resolve()
project.relative_to(repo / "test_reports")
if project.name != "project" or not project.parent.name.startswith("demo-"):
    raise SystemExit("Expected an isolated demo-*/project")
manifest = json.loads((project.parent / "manifest.json").read_text(encoding="utf-8"))
runtime = [row["path"] for row in manifest if row["path"].startswith(("scripts/", "scenes/", "assets/"))
           or row["path"] == "project.godot"]
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
mismatches = [path for path in runtime if sha(repo / path) != sha(project / path)]
if mismatches:
    raise SystemExit("Runtime differs from isolated copy: " + repr(mismatches))
shutil.copyfile(package / "capture_field.gd", project / "tools/demo/capture_adjacent_unit_bars.gd")
env = dict(os.environ, APPDATA=str(project.parent / "profile"))
hidden = {}
if os.name == "nt":
    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = 0
    hidden = {"startupinfo": startup, "creationflags": subprocess.CREATE_NO_WINDOW}
command = [str(args.godot), "--path", str(project), "--screen", "0", "--script",
           "tools/demo/capture_adjacent_unit_bars.gd", "--", "--captures=" + str(package)]
with (package / "capture.log").open("wb") as log:
    result = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT,
                            timeout=120, **hidden)
output = (package / "capture.log").read_text(encoding="utf-8", errors="replace")
print(output)
(package / "runtime-check.json").write_text(json.dumps({"isolated_project": str(project),
    "runtime_files": len(runtime), "mismatches": mismatches,
    "script_sha256": sha(package / "capture_field.gd"), "exit_code": result.returncode}, indent=2) + "\n",
    encoding="utf-8")
if result.returncode or "SCRIPT ERROR" in output or "ERROR:" in output:
    raise SystemExit(1)

report = json.loads((package / "capture-field.json").read_text(encoding="utf-8"))
if report["failed_checks"] or len(report["captures"]) != 6:
    raise SystemExit("Capture checks did not pass")
panels = [("Без выбора", "no-selection"), ("Выбран воин", "selected"),
          ("Наведение атаки", "attack-hover")]
composition = {"output": str(package / "comparison.png"), "rows": []}
for zoom, crop in [(100, [735, 475, 150, 170]), (75, [730, 493, 150, 170])]:
    composition["rows"].append({
        "title": f"Камера {zoom}% · фрагменты увеличены 2× без сглаживания",
        "crop": crop, "enlarge": 2,
        "panels": [{"title": title, "source": str(package / f"adjacent-{state}-{zoom:03}.png")}
                   for title, state in panels]})
manifest_path = package / "composition.json"
manifest_path.write_text(json.dumps(composition, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
shutil.copyfile(package / "compose.gd", project / "tools/demo/compose_adjacent_unit_bars.gd")
command = [str(args.godot), "--path", str(project), "--screen", "0", "--script",
           "tools/demo/compose_adjacent_unit_bars.gd", "--", "--manifest=" + str(manifest_path)]
with (package / "composition.log").open("wb") as log:
    result = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT,
                            timeout=60, **hidden)
output = (package / "composition.log").read_text(encoding="utf-8", errors="replace")
print(output)
if result.returncode or "SCRIPT ERROR" in output or "ERROR:" in output:
    raise SystemExit(1)
