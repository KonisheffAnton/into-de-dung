"""Run scale/sampling probes in the already imported task snapshot."""
from pathlib import Path
import json
import os
import re
import subprocess
import time

ROOT = Path(__file__).resolve().parents[3]
PROJECT = ROOT / "test_reports/demo-c47902f9a1d04e8c900334a12ad7a716/project"
OUT = ROOT / "test_reports/rogue-size-sampling-20261102"
GODOT = r"D:\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"


def main():
    assert PROJECT.is_dir() and PROJECT != ROOT
    for name in ["scenes/demo/visuals/art_trial_unit.tscn", "tests/test_current_art_zoom.gd",
                 "tests/test_rogue_animations.gd", "docs/art/rogue-size-sampling-20261102/sampling_probe.gd"]:
        assert (PROJECT / name).read_bytes() == (ROOT / name).read_bytes(), name
    OUT.mkdir(exist_ok=True)
    (OUT / "profile").mkdir(exist_ok=True)
    env = dict(os.environ, APPDATA=str(OUT / "profile"))
    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = 0
    checks = {}
    for label, script, headless in [
        ("current_art_zoom", "tests/test_current_art_zoom.gd", False),
        ("rogue_animations_headless", "tests/test_rogue_animations.gd", True),
        ("sampling_probe", "docs/art/rogue-size-sampling-20261102/sampling_probe.gd", False),
    ]:
        captures = OUT / (label + "-captures")
        args = [GODOT, "--path", str(PROJECT)] + (["--headless"] if headless else ["--screen", "0"])
        args += ["--script", script, "--", "--captures=" + str(captures)]
        started = time.perf_counter()
        with (OUT / (label + ".log")).open("wb") as log:
            result = subprocess.run(args, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=120,
                                    startupinfo=startup, creationflags=subprocess.CREATE_NO_WINDOW)
        output = (OUT / (label + ".log")).read_text(encoding="utf-8", errors="replace")
        counts = re.findall(r"(\d+) passed, (\d+) failed", output)
        ok = result.returncode == 0 and bool(counts) and not any(int(pair[1]) for pair in counts)
        ok = ok and not any(marker in output for marker in ["ERROR:", "SCRIPT ERROR", "Parse Error"])
        checks[label] = {"status": "PASS" if ok else "FAIL", "counts": counts,
                         "seconds": round(time.perf_counter() - started, 3), "exit_code": result.returncode}
        (OUT / "probe-validation.json").write_text(json.dumps(checks, indent=2), encoding="utf-8")
        print(label, checks[label], flush=True)
        if not ok:
            print(output)
            raise SystemExit(1)


if __name__ == "__main__":
    main()
