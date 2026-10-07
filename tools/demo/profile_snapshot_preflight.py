"""Reproducible control/probe run for snapshot and worker preflight costs."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import statistics
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
RUNNER = Path("tools/demo/profile_production_smoothness.gd")
SENTINEL = "PRODUCTION SMOOTHNESS DONE"
TARGETS: dict[str, tuple[str, ...]] = {
    "scripts/core/actions/forecast_simulation.gd": ("prepare",),
    "scripts/core/actions/item_simulation_snapshot.gd": (
        "capture", "_live_shape_error", "_live_structure", "_validate", "_normalize",
    ),
    "scripts/core/actions/simulation_snapshot.gd": ("capture_board",),
    "scripts/demo/battle_execution_worker.gd": ("can_transfer", "start"),
    "scripts/demo/battle_demo.gd": ("_mage_card_cache", "_elemental_cast_cache"),
}


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def tracked_sources() -> list[str]:
    raw = subprocess.check_output(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
        cwd=ROOT,
    )
    return sorted({name for name in raw.decode("utf-8").split("\0") if name
                   and not name.startswith((".godot/", "test_reports/"))})


def snapshot(project: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    for name in tracked_sources():
        src = ROOT / name
        if not src.is_file():
            continue
        target = project / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, target)
        result[name] = digest(target.read_bytes())
    return result


def split_parameters(text: str) -> list[str]:
    parts: list[str] = []
    start = 0
    stack: list[str] = []
    pairs = {"(": ")", "[": "]", "{": "}"}
    quote = ""
    escaped = False
    for index, char in enumerate(text):
        if quote:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = ""
            continue
        if char in ("'", '"'):
            quote = char
        elif char in pairs:
            stack.append(pairs[char])
        elif char in (")", "]", "}"):
            if not stack or stack.pop() != char:
                raise ValueError("unbalanced signature parameters")
        elif char == "," and not stack:
            parts.append(text[start:index].strip())
            start = index + 1
    if quote or stack:
        raise ValueError("unbalanced signature parameters")
    tail = text[start:].strip()
    if tail:
        parts.append(tail)
    return parts


def parameter_name(parameter: str) -> str:
    head = parameter.split("=", 1)[0].strip()
    if ":" not in head:
        raise ValueError(f"untyped parameter unsupported: {parameter}")
    name = head.split(":", 1)[0].strip().lstrip("@").strip()
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", name):
        raise ValueError(f"unsupported parameter syntax: {parameter}")
    return name


def instrument(source: str, path: str, methods: tuple[str, ...]) -> str:
    for method in methods:
        pattern = re.compile(
            rf"^(static )?func {re.escape(method)}\((.*)\) -> ([^:\n]+):$", re.MULTILINE
        )
        matches = list(pattern.finditer(source))
        if len(matches) != 1:
            raise ValueError(f"unsupported signature: {path}:{method} ({len(matches)} matches)")
        match = matches[0]
        static, args, result_type = match.groups()
        try:
            names = [parameter_name(arg) for arg in split_parameters(args)]
        except ValueError as error:
            raise ValueError(f"unsupported signature: {path}:{method}: {error}") from error
        renamed = f"_profile_original_{method}"
        call = f"{renamed}({', '.join(names)})"
        key = f"{Path(path).stem}.{method}"
        is_void = result_type.strip() == "void"
        ret = f"\t{call}\n" if is_void else f"\tvar profile_result: {result_type.strip()} = {call}\n"
        tail = "\treturn\n" if is_void else "\treturn profile_result\n"
        wrapper = "".join((
            f"{static or ''}func {method}({args}) -> {result_type.strip()}:\n",
            "\t# Вне главного потока измерение не читает Engine meta и сразу вызывает оригинал.\n",
            f"\tif not Thread.is_main_thread():\n\t\t{'return ' if not is_void else ''}{call}\n",
            "\t\treturn\n" if is_void else "",
            "\tvar profile_start := Time.get_ticks_usec()\n",
            ret,
            "\tvar profile_values: Dictionary = Engine.get_meta(&\"snapshot_preflight_probe\", {})\n",
            f"\tvar profile_key := \"{key}\"\n",
            "\tif not profile_values.has(profile_key): profile_values[profile_key] = []\n",
            "\tprofile_values[profile_key].append(float(Time.get_ticks_usec() - profile_start) / 1000.0)\n",
            "\tEngine.set_meta(&\"snapshot_preflight_probe\", profile_values)\n",
            tail,
        ))
        original = match.group(0).replace(f"func {method}(", f"func {renamed}(", 1)
        source = source[:match.start()] + wrapper + "\n" + original + source[match.end():]
    return source


def prepare(output: Path) -> None:
    if output.exists():
        raise FileExistsError(f"output already exists: {output}")
    output.mkdir(parents=True)
    status = subprocess.check_output(["git", "status", "--short"], cwd=ROOT, text=True)
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    common = {"base_head": head, "git_status_short": status, "source_hashes": snapshot(output / "control" / "project")}
    (output / "control" / "manifest.json").write_text(json.dumps(common, indent=2), encoding="utf-8")
    control_project = output / "control" / "project"
    probe_project = output / "probe" / "project"
    probe_hashes: dict[str, str] = {}
    for name, expected in common["source_hashes"].items():
        source = control_project / name
        target = probe_project / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        actual = digest(target.read_bytes())
        if actual != expected:
            raise ValueError(f"control/probe snapshot mismatch: {name}")
        probe_hashes[name] = actual
    for path, methods in TARGETS.items():
        target = output / "probe" / "project" / path
        text = target.read_text(encoding="utf-8")
        target.write_text(instrument(text, path, methods), encoding="utf-8", newline="\n")
        probe_hashes[path] = digest(target.read_bytes())
    runner = output / "probe" / "project" / RUNNER
    runner_text = runner.read_text(encoding="utf-8")
    reset_source = "var intervals: Array[float] = []"
    emit_source = '"label":label,'
    if runner_text.count(reset_source) != 1 or runner_text.count(emit_source) != 1:
        raise ValueError("unsupported production runner layout; expected unique reset and JSON label")
    runner_text = runner_text.replace(reset_source,
                                      "Engine.set_meta(&\"snapshot_preflight_probe\", {})\n\tvar intervals: Array[float] = []")
    runner_text = runner_text.replace(emit_source, '"label":label,"timings":Engine.get_meta(&"snapshot_preflight_probe",{}),')
    runner.write_text(runner_text, encoding="utf-8", newline="\n")
    probe_hashes[str(RUNNER).replace("\\", "/")] = digest(runner.read_bytes())
    common_probe = {"base_head": head, "git_status_short": status, "source_hashes": common["source_hashes"],
                    "transformed_probe_hashes": probe_hashes}
    (output / "probe" / "manifest.json").write_text(json.dumps(common_probe, indent=2), encoding="utf-8")


def check_prepared(output: Path) -> None:
    for mode in ("control", "probe"):
        manifest = output / mode / "manifest.json"
        project = output / mode / "project"
        if not manifest.is_file() or not project.is_dir():
            raise FileNotFoundError(f"prepared {mode} copy is missing")
        info = json.loads(manifest.read_text(encoding="utf-8"))
        hashes = info["transformed_probe_hashes"] if mode == "probe" else info["source_hashes"]
        for name, expected in hashes.items():
            file = project / name
            if not file.is_file() or digest(file.read_bytes()) != expected:
                raise ValueError(f"prepared {mode} source changed: {name}")


def run_copy(godot: str, output: Path, mode: str, screen: int) -> None:
    project = output / mode / "project"
    run_dir = output / mode / "run"
    run_dir.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env["APPDATA"] = str(run_dir / "appdata")
    Path(env["APPDATA"]).mkdir(parents=True, exist_ok=True)
    flags = getattr(subprocess, "CREATE_NO_WINDOW", 0) if os.name == "nt" else 0
    for label, args in (("import", ["--headless", "--editor", "--import"]),
                        ("render", ["--screen", str(screen), "--script", str(RUNNER)])):
        log_path = run_dir / f"{label}.log"
        with log_path.open("x", encoding="utf-8") as log:
            try:
                result = subprocess.run([godot, "--path", str(project), *args], env=env,
                                        stdout=log, stderr=subprocess.STDOUT, timeout=180,
                                        creationflags=flags, check=False)
            except subprocess.TimeoutExpired as error:
                raise RuntimeError(f"{mode} {label} timed out after 180s; see {log_path}") from error
        contents = log_path.read_text(encoding="utf-8", errors="replace")
        if result.returncode != 0 or "SCRIPT ERROR:" in contents or "Parse Error" in contents or re.search(r"(?m)^ERROR:", contents):
            raise RuntimeError(f"{mode} {label} failed with exit {result.returncode}; see {log_path}")
        if label == "render" and SENTINEL not in contents:
            raise RuntimeError(f"{mode} runner completion sentinel missing; see {log_path}")


def ensure_no_run_logs(output: Path) -> None:
    log_paths = [output / mode / "run" / f"{label}.log"
                 for mode in ("control", "probe") for label in ("import", "render")]
    existing_logs = [path for path in log_paths if path.exists()]
    if existing_logs:
        raise FileExistsError(f"run logs already exist; refusing overwrite: {existing_logs[0]}")


def stats(values: list[float]) -> dict[str, float | int]:
    ordered = sorted(values)
    return {"count": len(values), "median_ms": round(statistics.median(values), 3),
            "p95_ms": round(ordered[math.ceil(len(ordered) * .95) - 1], 3),
            "max_ms": round(max(values), 3), "total_ms": round(sum(values), 3)}


def summarize(output: Path) -> None:
    parsed: dict[str, list[dict[str, Any]]] = {}
    parities: dict[str, dict[str, Any]] = {}
    for mode in ("control", "probe"):
        log = output / mode / "run" / "render.log"
        lines: list[dict[str, Any]] = []
        for line in log.read_text(encoding="utf-8", errors="replace").splitlines():
            if not line.startswith("{"):
                continue
            try:
                value = json.loads(line)
            except json.JSONDecodeError:
                continue
            if value.get("label") == "parity":
                parities[mode] = value
            elif "frame_ms" in value:
                lines.append(value)
        parsed[mode] = lines
    if set(parities) != {"control", "probe"}:
        raise RuntimeError("parity JSON missing in one or both runs")
    for key in ("before", "after", "publications"):
        if any(key not in parities[mode] for mode in ("control", "probe")):
            raise RuntimeError(f"parity field missing: {key}")
        if parities["control"][key] != parities["probe"][key]:
            raise RuntimeError(f"parity mismatch: {key}")
    summary: dict[str, Any] = {"parity": {key: True for key in ("before", "after", "publications")}}
    required_windows = {"idle_processing_on", "hover_processing_on", "live_raise_shields", "end_turn_and_ai"}
    for mode, windows in parsed.items():
        by_label = {entry.get("label"): entry for entry in windows}
        if not required_windows.issubset(by_label):
            raise RuntimeError(f"{mode} missing required measurement window")
        if "PRODUCTION SMOOTHNESS DONE" not in (output / mode / "run" / "render.log").read_text(encoding="utf-8", errors="replace"):
            raise RuntimeError(f"{mode} AI completion sentinel missing")
        summary[mode] = {}
        for label in sorted(required_windows):
            entry = by_label[label]
            if label == "end_turn_and_ai" and len(entry["frame_ms"]) <= 180:
                raise RuntimeError(f"{mode} AI window did not include completion frames")
            summary[mode][label] = {"frames": stats(entry["frame_ms"])}
            if "timings" in entry:
                summary[mode][label]["timings"] = {key: stats(values) for key, values in entry["timings"].items() if values}
    (output / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(json.dumps(summary, separators=(",", ":")))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN"), help="Godot executable (or GODOT_BIN)")
    parser.add_argument("--output", required=True, type=Path, help="new result directory")
    parser.add_argument("--screen", type=int, default=0)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--prepare-only", action="store_true")
    modes.add_argument("--run-existing", action="store_true")
    args = parser.parse_args()
    output = args.output.resolve()
    try:
        if args.run_existing:
            check_prepared(output)
        else:
            prepare(output)
        if args.prepare_only:
            print(f"prepared control and probe copies: {output}")
            return 0
        if not args.godot:
            raise ValueError("--godot or GODOT_BIN is required to run")
        ensure_no_run_logs(output)
        run_copy(args.godot, output, "control", args.screen)
        run_copy(args.godot, output, "probe", args.screen)
        summarize(output)
        return 0
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
