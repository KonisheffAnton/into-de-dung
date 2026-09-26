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
        if label == "ally_transit":
            invalid = invalid or "ALLY TRANSIT RESULTS:" not in output or ", 0 failed" not in output
        if label in ("initiative_session", "initiative_ui"):
            marker = {"initiative_session": "INITIATIVE SESSION RESULTS:", "initiative_ui": "INITIATIVE UI RESULTS:"}[label]
            invalid = invalid or marker not in output or ", 0 failed" not in output
        if label in ("attack_modifiers", "critical_control", "control_ui"):
            marker = {"attack_modifiers": "ATTACK MODIFIERS RESULTS:", "critical_control": "Critical control:", "control_ui": "CONTROL UI RESULTS:"}[label]
            invalid = invalid or marker not in output or ", 0 failed" not in output
        if label in ("summon_definition", "summon_definition_ui"):
            invalid = invalid or "M1 RESULTS:" not in output or ", 0 failed" not in output
        if label == "item_use":
            invalid = invalid or "ITEM USE RESULTS:" not in output or ", 0 failed" not in output
        if label in ("item_forecast", "item_forecast_ui"):
            marker = "ITEM FORECAST RESULTS:" if label == "item_forecast" else "ITEM FORECAST UI RESULTS:"
            invalid = invalid or marker not in output or ", 0 failed" not in output
        if label in ("move_forecast", "move_forecast_ui"):
            marker = "MOVE FORECAST RESULTS:" if label == "move_forecast" else "MOVE FORECAST UI RESULTS:"
            invalid = invalid or marker not in output or ", 0 failed" not in output
        if label in ("raise_forecast", "raise_forecast_ui"):
            marker = "RAISE FORECAST RESULTS:" if label == "raise_forecast" else "RAISE FORECAST UI RESULTS:"
            invalid = invalid or marker not in output or ", 0 failed" not in output
        if label in ("guard_forecast", "guard_forecast_ui"):
            marker = "GUARD FORECAST RESULTS:" if label == "guard_forecast" else "GUARD FORECAST UI RESULTS:"
            invalid = invalid or marker not in output or ", 0 failed" not in output
        if label in ("core_combinations", "core_combination_turns"):
            marker = "CORE COMBINATIONS RESULTS:" if label == "core_combinations" else "CORE COMBINATION TURNS RESULTS:"
            invalid = invalid or marker not in output or ", 0 failed" not in output
        if label in ("core_combination_session", "core_combination_ui"):
            marker = "CORE COMBINATION SESSION RESULTS:" if label == "core_combination_session" else "CORE COMBINATION UI RESULTS:"
            invalid = invalid or marker not in output or ", 0 failed" not in output
        if label in ("core_batch", "core_batch_ui", "summon_composition"):
            marker = {"core_batch": "CORE BATCH RESULTS:", "core_batch_ui": "CORE BATCH UI RESULTS:", "summon_composition": "SUMMON COMPOSITION RESULTS:"}[label]
            invalid = invalid or marker not in output or ", 0 failed" not in output
        if label in ("snapshot_walk", "unit_snapshot_performance"):
            marker = "SNAPSHOT WALK RESULTS:" if label == "snapshot_walk" else "UNIT SNAPSHOT PERFORMANCE RESULTS:"
            invalid = invalid or marker not in output or ", 0 failed" not in output
        if label in ("combat_perks_state", "core_reactions", "core_reactions_ui"):
            marker = {"combat_perks_state": "COMBAT PERKS STATE RESULTS:", "core_reactions": "CORE REACTIONS RESULTS:", "core_reactions_ui": "CORE REACTIONS UI RESULTS:"}[label]
            invalid = invalid or marker not in output or ", 0 failed" not in output
        if label in ("action_forecast_worker", "action_async_ui"):
            marker = "ACTION FORECAST WORKER RESULTS:" if label == "action_forecast_worker" else "ACTION ASYNC UI RESULTS:"
            invalid = invalid or marker not in output or ", 0 failed" not in output
        if label in ("attack_forecast_worker", "attack_async_ui", "spatial_guard_stats"):
            marker = {"attack_forecast_worker": "ATTACK FORECAST WORKER RESULTS:", "attack_async_ui": "ATTACK ASYNC UI RESULTS:", "spatial_guard_stats": "SPATIAL GUARD STATS RESULTS:"}[label]
            invalid = invalid or marker not in output or ", 0 failed" not in output
        if label in ("control_perks_codec", "control_package", "control_package_ui"):
            marker = {"control_perks_codec": "CONTROL PERKS CODEC RESULTS:", "control_package": "CONTROL PACKAGE RESULTS:", "control_package_ui": "CONTROL PACKAGE UI RESULTS:"}[label]
            invalid = invalid or marker not in output or ", 0 failed" not in output
        if label in ("entangle_attack", "entangle_ui"):
            marker = "ENTANGLE ATTACK RESULTS:" if label == "entangle_attack" else "ENTANGLE UI RESULTS:"
            invalid = invalid or marker not in output or ", 0 failed" not in output
        if label in ("piercing_calculation", "piercing"):
            marker = "ARMOR PIERCING CALCULATION RESULTS:" if label == "piercing_calculation" else "ARMOR PIERCING RESULTS:"
            invalid = invalid or marker not in output or ", 0 failed" not in output
        if label.startswith("bleeding"):
            marker = {"bleeding": "BLEEDING RESULTS:", "bleeding_snapshot": "BLEEDING SNAPSHOT RESULTS:", "bleeding_ui": "BLEEDING UI RESULTS:"}[label]
            invalid = invalid or marker not in output or ", 0 failed" not in output
        if label.startswith("d4_"):
            marker = {"d4_run": "D4 RUN RESULTS:", "d4_integration": "D4 INTEGRATION RESULTS:", "d4_ui": "D4 UI RESULTS:"}[label]
            invalid = invalid or marker not in output or ", 0 failed" not in output
        if label.startswith("d5_"):
            marker = {"d5_state": "D5 STATE RESULTS:", "d5_integration": "D5 INTEGRATION RESULTS:", "d5_ui": "D5 UI RESULTS:"}[label]
            invalid = invalid or marker not in output or ", 0 failed" not in output
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
        run("summon_definition", ["--script", "tests/test_summon_definition.gd"])
        run("item_use", ["--script", "tests/test_item_use_action.gd"])
        run("item_forecast", ["--script", "tests/test_item_use_forecast.gd"])
        run("move_forecast", ["--script", "tests/test_move_forecast.gd"])
        run("raise_forecast", ["--script", "tests/test_raise_corpse_forecast.gd"])
        run("guard_forecast", ["--script", "tests/test_guard_forecast.gd"])
        run("attack_calculation", ["--script", "tests/test_attack_damage_calculation.gd"])
        run("attack_d1", ["--script", "tests/test_attack_damage_d1.gd"])
        run("attack_modifiers", ["--script", "tests/test_attack_modifiers.gd"])
        run("critical_control", ["--script", "tests/test_critical_control.gd"])
        run("armor_calculation", ["--script", "tests/test_armor_hit_calculation.gd"])
        run("piercing_calculation", ["--script", "tests/test_armor_piercing_calculation.gd"])
        run("piercing", ["--script", "tests/test_armor_piercing.gd"])
        run("armor_snapshot", ["--script", "tests/test_armor_snapshot.gd"])
        run("snapshot_walk", ["--script", "tests/test_snapshot_walk_performance.gd"])
        run("unit_snapshot_performance", ["--script", "tests/test_unit_snapshot_performance.gd"])
        run("armor_integration", ["--script", "tests/test_armor_integration.gd"])
        run("armor_recovery", ["--script", "tests/test_armor_recovery.gd"])
        run("bleeding_snapshot", ["--script", "tests/test_bleeding_snapshot.gd"])
        run("bleeding", ["--script", "tests/test_bleeding.gd"])
        run("d4_run", ["--script", "tests/test_d4_run.gd"])
        run("d4_integration", ["--script", "tests/test_d4_integration.gd"])
        run("d5_state", ["--script", "tests/test_d5_state.gd"])
        run("d5_integration", ["--script", "tests/test_d5_integration.gd"])
        run("core_combinations", ["--script", "tests/test_core_combinations.gd"])
        run("core_combination_turns", ["--script", "tests/test_core_combination_turns.gd"])
        run("core_combination_session", ["--script", "tests/test_core_combination_session.gd"])
        run("summon_composition", ["--script", "tests/test_summon_composition.gd"])
        run("core_batch", ["--script", "tests/test_core_batch.gd"])
        run("combat_perks_state", ["--script", "tests/test_combat_perks_state.gd"])
        run("core_reactions", ["--script", "tests/test_core_reactions.gd"])
        run("entangle_attack", ["--script", "tests/test_entangle_attack.gd"])
        run("forecast", ["--script", "tests/test_attack_forecast.gd"])
        run("attack_forecast_worker", ["--script", "tests/test_attack_forecast_worker.gd"])
        run("action_forecast_worker", ["--script", "tests/test_action_forecast_worker.gd"])
        run("spatial_guard_stats", ["--script", "tests/test_spatial_guard_stats.gd"])
        run("control_perks_codec", ["--script", "tests/test_control_perks_codec.gd"])
        run("control_package", ["--script", "tests/test_control_package.gd"])
        run("guard", ["--script", "tests/test_guard_stance.gd"])
        run("summon_snapshot", ["--script", "tests/test_summon_snapshot.gd"])
        run("summon", ["--script", "tests/test_summoning_item.gd"])
        run("healing", ["--script", "tests/test_healing_item.gd"])
        run("initiative_session", ["--script", "tests/test_initiative_session.gd"])
        if args.full:
            run("core", ["--script", "tests/run_tests.gd"], legacy=True)
        demo_args = ["--script", "tests/test_battle_demo.gd"]
        if args.render_check:
            captures = out / "screenshots"
            captures.mkdir()
            run("summon_definition_ui", ["--script", "tests/test_summon_definition.gd", "--", "--captures=" + str(captures)], headless=False)
            demo_args += ["--", "--captures=" + str(captures)]
        run("demo", demo_args, headless=not args.render_check)
        battle_args = ["--script", "tests/test_tactical_battle.gd"]
        if args.render_check:
            battle_args += ["--", "--captures=" + str(captures)]
        run("battle", battle_args, headless=not args.render_check)
        item_forecast_args = ["--script", "tests/test_item_forecast_ui.gd"]
        if args.render_check:
            item_forecast_args += ["--", "--captures=" + str(captures)]
        run("item_forecast_ui", item_forecast_args, headless=not args.render_check)
        raise_forecast_args = ["--script", "tests/test_raise_forecast_ui.gd"]
        if args.render_check:
            raise_forecast_args += ["--", "--captures=" + str(captures)]
        run("raise_forecast_ui", raise_forecast_args, headless=not args.render_check)
        guard_forecast_args = ["--script", "tests/test_guard_forecast_ui.gd"]
        if args.render_check:
            guard_forecast_args += ["--", "--captures=" + str(captures)]
        run("guard_forecast_ui", guard_forecast_args, headless=not args.render_check)
        armor_args = ["--script", "tests/test_armor_battle.gd"]
        if args.render_check:
            armor_args += ["--", "--captures=" + str(captures)]
        run("armor_ui", armor_args, headless=not args.render_check)
        transit_args = ["--script", "tests/test_ally_transit.gd"]
        if args.render_check:
            transit_args += ["--", "--captures=" + str(captures)]
        run("ally_transit", transit_args, headless=not args.render_check)
        bleeding_args = ["--script", "tests/test_bleeding_battle.gd"]
        if args.render_check:
            bleeding_args += ["--", "--captures=" + str(captures)]
        run("bleeding_ui", bleeding_args, headless=not args.render_check)
        d4_args = ["--script", "tests/test_d4_ui.gd"]
        if args.render_check:
            d4_args += ["--", "--captures=" + str(captures)]
        run("d4_ui", d4_args, headless=not args.render_check)
        d5_args = ["--script", "tests/test_d5_ui.gd"]
        if args.render_check:
            d5_args += ["--", "--captures=" + str(captures)]
        run("d5_ui", d5_args, headless=not args.render_check)
        control_args = ["--script", "tests/test_control_battle.gd"]
        if args.render_check:
            control_args += ["--", "--captures=" + str(captures)]
        run("control_ui", control_args, headless=not args.render_check)
        combination_args = ["--script", "tests/test_core_combination_battle.gd"]
        if args.render_check:
            combination_args += ["--", "--captures=" + str(captures)]
        run("core_combination_ui", combination_args, headless=not args.render_check)
        batch_args = ["--script", "tests/test_core_batch_ui.gd"]
        if args.render_check:
            batch_args += ["--", "--captures=" + str(captures)]
        run("core_batch_ui", batch_args, headless=not args.render_check)
        reactions_args = ["--script", "tests/test_core_reactions_ui.gd"]
        if args.render_check:
            reactions_args += ["--", "--captures=" + str(captures)]
        run("core_reactions_ui", reactions_args, headless=not args.render_check)
        control_package_args = ["--script", "tests/test_control_package_ui.gd"]
        if args.render_check:
            control_package_args += ["--", "--captures=" + str(captures)]
        run("control_package_ui", control_package_args, headless=not args.render_check)
        attack_async_args = ["--script", "tests/test_attack_forecast_async_ui.gd"]
        if args.render_check:
            attack_async_args += ["--", "--captures=" + str(out)]
        run("attack_async_ui", attack_async_args, headless=not args.render_check)
        action_async_args = ["--script", "tests/test_action_forecast_async_ui.gd"]
        if args.render_check:
            action_async_args += ["--", "--captures=" + str(captures)]
        run("action_async_ui", action_async_args, headless=not args.render_check)
        entangle_args = ["--script", "tests/test_entangle_ui.gd"]
        if args.render_check:
            entangle_args += ["--", "--captures=" + str(captures)]
        run("entangle_ui", entangle_args, headless=not args.render_check)
        move_forecast_args = ["--script", "tests/test_move_forecast_ui.gd"]
        if args.render_check:
            move_forecast_args += ["--", "--captures=" + str(captures)]
        run("move_forecast_ui", move_forecast_args, headless=not args.render_check)
        initiative_args = ["--script", "tests/test_initiative_battle.gd"]
        if args.render_check:
            initiative_args += ["--", "--captures=" + str(captures)]
        run("initiative_ui", initiative_args, headless=not args.render_check)
    else:
        # This is the user-requested interactive window, so it is intentionally visible.
        with (out / "play.log").open("wb") as log:
            process = subprocess.Popen([godot, "--path", str(project)], env=env, stdout=log, stderr=subprocess.STDOUT)
        print("Demo window launched, PID", process.pid)


if __name__ == "__main__":
    main()
