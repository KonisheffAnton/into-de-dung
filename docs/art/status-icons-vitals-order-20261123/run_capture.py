"""Run the field evidence only in an already imported isolate.py project."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("--project", required=True, type=Path)
parser.add_argument("--godot", required=True, type=Path)
args = parser.parse_args()
package = Path(__file__).resolve().parent
repo = package.parents[2]
project = args.project.resolve()
project.relative_to(repo / "test_reports")
if project.name != "project" or not project.parent.name.startswith("demo-"):
    raise SystemExit("Expected an isolated demo-*/project")
target = project / "tools/demo/capture_status_field.gd"
shutil.copy2(package / "capture_field.gd", target)
env = dict(os.environ, APPDATA=str(project.parent / "profile"))
hidden = {}
if os.name == "nt":
    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = 0
    hidden = {"startupinfo": startup, "creationflags": subprocess.CREATE_NO_WINDOW}
command = [str(args.godot), "--path", str(project), "--screen", "0",
           "--script", "tools/demo/capture_status_field.gd", "--", "--captures=" + str(package)]
with (package / "field.log").open("wb") as log:
    result = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT,
                            timeout=120, **hidden)
output = (package / "field.log").read_text(encoding="utf-8", errors="replace")
print(output)
if result.returncode or "SCRIPT ERROR" in output or "ERROR:" in output \
        or "STATUS FIELD RESULTS: 0 failed" not in output:
    raise SystemExit(1)
