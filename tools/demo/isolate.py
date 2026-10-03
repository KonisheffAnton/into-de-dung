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
    parser.add_argument("--screen", type=int, default=os.environ.get("GODOT_TEST_SCREEN"), help="Godot screen index for windowed runs (or GODOT_TEST_SCREEN)")
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
        elif args.screen is not None:
            command += ["--screen", str(args.screen)]
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
        if label in ("hero_progression", "hero_hub", "hero_hub_ui", "hero_hub_playthrough"):
            marker = {"hero_progression": "HERO PROGRESSION RESULTS:", "hero_hub": "HERO HUB RESULTS:", "hero_hub_ui": "HERO HUB UI RESULTS:", "hero_hub_playthrough": "HERO HUB PLAYTHROUGH RESULTS:"}[label]
            invalid = invalid or marker not in output or ", 0 failed" not in output
        if label.startswith("expedition_") or label == "battle_artifact_snapshot":
            marker = label.replace("_", " ").upper() + " RESULTS:"
            invalid = invalid or marker not in output or ", 0 failed" not in output
        if label == "ally_transit":
            invalid = invalid or "ALLY TRANSIT RESULTS:" not in output or ", 0 failed" not in output
        if label in ("balance_recovery", "compact_forecast", "reaction_bonus"):
            marker = label.replace("_", " ").upper() + " RESULTS:"
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
        if label in ("battle_execution_worker", "battle_execution_ui"):
            marker = "BATTLE EXECUTION WORKER RESULTS:" if label == "battle_execution_worker" else "BATTLE EXECUTION UI RESULTS:"
            invalid = invalid or marker not in output or ", 0 failed" not in output
        if label in ("presentation_capture", "battle_presentation", "presentation_foundation", "presentation_contact", "presentation_attack_styles", "presentation_consequences", "presentation_environment", "presentation_ranged", "presentation_mage", "presentation_reactions", "presentation_status", "battle_board_camera", "battle_camera_ui", "four_slot_bar", "battle_panels"):
            marker = label.replace("_", " ").upper() + " RESULTS:"
            invalid = invalid or marker not in output or ", 0 failed" not in output
        if label in ("snapshot_value_copy", "live_snapshot_capture", "summon_checkpoint"):
            marker = {"snapshot_value_copy": "SNAPSHOT VALUE COPY RESULTS:", "live_snapshot_capture": "LIVE SNAPSHOT CAPTURE RESULTS:", "summon_checkpoint": "SUMMON CHECKPOINT RESULTS:"}[label]
            invalid = invalid or marker not in output or ", 0 failed" not in output
        if label in ("counterattack", "counterattack_ui"):
            marker = "COUNTERATTACK RESULTS:" if label == "counterattack" else "COUNTERATTACK UI RESULTS:"
            invalid = invalid or marker not in output or ", 0 failed" not in output
        if label in ("combat_perks_state", "core_reactions", "core_reactions_ui"):
            marker = {"combat_perks_state": "COMBAT PERKS STATE RESULTS:", "core_reactions": "CORE REACTIONS RESULTS:", "core_reactions_ui": "CORE REACTIONS UI RESULTS:"}[label]
            invalid = invalid or marker not in output or ", 0 failed" not in output
        if label in ("action_forecast_worker", "action_async_ui"):
            marker = "ACTION FORECAST WORKER RESULTS:" if label == "action_forecast_worker" else "ACTION ASYNC UI RESULTS:"
            invalid = invalid or marker not in output or ", 0 failed" not in output
        if label in ("turn_forecast", "turn_forecast_ui"):
            marker = "TURN FORECAST RESULTS:" if label == "turn_forecast" else "TURN FORECAST UI RESULTS:"
            invalid = invalid or marker not in output or ", 0 failed" not in output
        if label in ("safe_retreat", "safe_retreat_ui"):
            marker = "SAFE RETREAT RESULTS:" if label == "safe_retreat" else "SAFE RETREAT UI RESULTS:"
            invalid = invalid or marker not in output or ", 0 failed" not in output
        if label == "safe_retreat_integration":
            invalid = invalid or "SAFE RETREAT INTEGRATION RESULTS:" not in output or ", 0 failed" not in output
        if label in ("push_chain", "push_chain_reactions", "push_chain_ui"):
            marker = {"push_chain": "PUSH CHAIN RESULTS:", "push_chain_reactions": "PUSH CHAIN REACTIONS RESULTS:", "push_chain_ui": "PUSH CHAIN UI RESULTS:"}[label]
            invalid = invalid or marker not in output or ", 0 failed" not in output
        if label in ("ability_catalog", "mage_cooldowns", "mage_guards", "mage_ui"):
            marker = {"ability_catalog": "ABILITY CATALOG RESULTS:", "mage_cooldowns": "MAGE COOLDOWNS RESULTS:", "mage_guards": "MAGE GUARDS RESULTS:", "mage_ui": "MAGE UI RESULTS:"}[label]
            invalid = invalid or marker not in output or ", 0 failed" not in output
        if label in ("status_models", "status_snapshots", "status_effects", "status_ui"):
            marker = {"status_models": "STATUS STATE MODEL RESULTS:", "status_snapshots": "ELEMENTAL SNAPSHOT RESULTS:", "status_effects": "STATUS EFFECTS RESULTS:", "status_ui": "STATUS EFFECTS UI RESULTS:"}[label]
            invalid = invalid or marker not in output or ", 0 failed" not in output
        if label == "core_readiness_status":
            invalid = invalid or "CORE READINESS STATUS RESULTS:" not in output or ", 0 failed" not in output
        if label == "enemy_first":
            invalid = invalid or "ENEMY FIRST RESULTS:" not in output or ", 0 failed" not in output
        if label in ("collapse_state", "collapse_phase", "collapse_ui"):
            marker = {"collapse_state": "COLLAPSE STATE RESULTS:", "collapse_phase": "COLLAPSE PHASE RESULTS:", "collapse_ui": "COLLAPSE UI RESULTS:"}[label]
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
        run("presentation_capture", ["--script", "tests/test_presentation_capture.gd"])
        presentation_args = ["--script", "tests/test_battle_presentation.gd"]
        if args.render_check:
            presentation_captures = out / "presentation-screenshots"
            presentation_captures.mkdir()
            presentation_args += ["--", "--captures=" + str(presentation_captures)]
        run("battle_presentation", presentation_args, headless=not args.render_check)
        foundation_args = ["--script", "tests/test_presentation_foundation.gd"]
        if args.render_check:
            foundation_captures = out / "foundation-screenshots"
            foundation_captures.mkdir()
            foundation_args += ["--", "--captures=" + str(foundation_captures)]
        run("presentation_foundation", foundation_args, headless=not args.render_check)
        status_args = ["--script", "tests/test_presentation_status.gd"]
        if args.render_check:
            status_captures = out / "presentation-status-screenshots"
            status_captures.mkdir()
            status_args += ["--", "--captures=" + str(status_captures)]
        run("presentation_status", status_args, headless=not args.render_check)
        run("four_slot_bar", ["--script", "tests/test_four_slot_bar.gd"])
        panel_args = ["--script", "tests/test_battle_panels.gd"]
        if args.render_check:
            panel_captures = out / "battle-panel-screenshots"
            panel_captures.mkdir()
            panel_args += ["--", "--captures=" + str(panel_captures)]
        run("battle_panels", panel_args, headless=not args.render_check)
        contact_args = ["--script", "tests/test_presentation_contact.gd"]
        if args.render_check:
            contact_captures = out / "contact-screenshots"
            contact_captures.mkdir()
            contact_args += ["--", "--captures=" + str(contact_captures)]
        run("presentation_contact", contact_args, headless=not args.render_check)
        style_args = ["--script", "tests/test_presentation_attack_styles.gd"]
        if args.render_check:
            style_captures = out / "attack-style-screenshots"
            style_captures.mkdir()
            style_args += ["--", "--captures=" + str(style_captures)]
        run("presentation_attack_styles", style_args, headless=not args.render_check)
        consequence_args = ["--script", "tests/test_presentation_consequences.gd"]
        if args.render_check:
            consequence_captures = out / "consequence-screenshots"
            consequence_captures.mkdir()
            consequence_args += ["--", "--captures=" + str(consequence_captures)]
        run("presentation_consequences", consequence_args, headless=not args.render_check)
        environment_args = ["--script", "tests/test_presentation_environment.gd"]
        if args.render_check:
            environment_captures = out / "environment-presentation-screenshots"
            environment_captures.mkdir()
            environment_args += ["--", "--captures=" + str(environment_captures)]
        run("presentation_environment", environment_args, headless=not args.render_check)
        ranged_args = ["--script", "tests/test_presentation_ranged.gd"]
        if args.render_check:
            ranged_captures = out / "ranged-screenshots"
            ranged_captures.mkdir()
            ranged_args += ["--", "--captures=" + str(ranged_captures)]
        run("presentation_ranged", ranged_args, headless=not args.render_check)
        mage_presentation_args = ["--script", "tests/test_presentation_mage.gd"]
        if args.render_check:
            mage_presentation_captures = out / "mage-presentation-screenshots"
            mage_presentation_captures.mkdir()
            mage_presentation_args += ["--", "--captures=" + str(mage_presentation_captures)]
        run("presentation_mage", mage_presentation_args, headless=not args.render_check)
        reaction_presentation_args = ["--script", "tests/test_presentation_reactions.gd"]
        if args.render_check:
            reaction_captures = out / "reaction-presentation-screenshots"
            reaction_captures.mkdir()
            reaction_presentation_args += ["--", "--captures=" + str(reaction_captures)]
        run("presentation_reactions", reaction_presentation_args, headless=not args.render_check)
        run("reaction_bonus", ["--script", "tests/test_reaction_bonus.gd"])
        run("battle_board_camera", ["--script", "tests/test_battle_board_camera.gd"])
        camera_args = ["--script", "tests/test_battle_camera_ui.gd"]
        if args.render_check:
            camera_captures = out / "camera-screenshots"
            camera_captures.mkdir()
            camera_args += ["--", "--captures=" + str(camera_captures)]
        run("battle_camera_ui", camera_args, headless=not args.render_check)
        run("hero_progression", ["--script", "tests/test_hero_progression.gd"])
        run("hero_hub", ["--script", "tests/test_hero_hub.gd"])
        run("hero_hub_playthrough", ["--script", "tests/test_hero_hub_playthrough.gd"])
        hero_ui_args = ["--script", "tests/test_hero_hub_ui.gd"]
        if args.render_check:
            hero_ui_args += ["--", "--captures=" + str(out / "captures")]
        run("hero_hub_ui", hero_ui_args, headless=not args.render_check)
        for label in ("expedition_generator", "expedition_transitions", "expedition_postbattle", "battle_artifact_snapshot", "expedition_artifacts", "expedition_playthrough"):
            run(label, ["--script", "tests/test_" + label + ".gd"])
        expedition_ui_args = ["--script", "tests/test_expedition_ui.gd"]
        if args.render_check:
            expedition_ui_args += ["--", "--captures=" + str(out / "expedition_ui")]
        run("expedition_ui", expedition_ui_args, headless=not args.render_check)
        run("ability_catalog", ["--script", "tests/test_ability_catalog.gd"])
        run("mage_cooldowns", ["--script", "tests/test_mage_cooldowns.gd"])
        run("mage_guards", ["--script", "tests/test_mage_boundaries_guards.gd"])
        mage_args = ["--script", "tests/test_mage_ui.gd"]
        if args.render_check:
            mage_captures = out / "mage-screenshots"
            mage_captures.mkdir()
            mage_args += ["--", "--captures=" + str(mage_captures)]
        run("mage_ui", mage_args, headless=not args.render_check)
        run("status_models", ["--script", "tests/test_status_state_models.gd"])
        run("status_snapshots", ["--script", "tests/test_elemental_snapshots.gd"])
        run("status_effects", ["--script", "tests/test_status_effects.gd"])
        run("core_readiness_status", ["--script", "tests/test_core_readiness_status.gd"])
        status_args = ["--script", "tests/test_status_effects_ui.gd"]
        if args.render_check:
            status_captures = out / "status-screenshots"
            status_captures.mkdir()
            status_args += ["--", "--captures=" + str(status_captures)]
        run("status_ui", status_args, headless=not args.render_check)
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
        run("battle_execution_worker", ["--script", "tests/test_battle_execution_worker.gd"])
        run("snapshot_value_copy", ["--script", "tests/test_snapshot_value_copy.gd"])
        run("live_snapshot_capture", ["--script", "tests/test_live_snapshot_capture.gd"])
        run("summon_checkpoint", ["--script", "tests/test_summon_checkpoint.gd"])
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
        run("counterattack", ["--script", "tests/test_counterattack.gd"])
        run("entangle_attack", ["--script", "tests/test_entangle_attack.gd"])
        run("forecast", ["--script", "tests/test_attack_forecast.gd"])
        run("attack_forecast_worker", ["--script", "tests/test_attack_forecast_worker.gd"])
        run("action_forecast_worker", ["--script", "tests/test_action_forecast_worker.gd"])
        run("turn_forecast", ["--script", "tests/test_turn_forecast.gd"])
        run("balance_recovery", ["--script", "tests/test_balance_recovery.gd"])
        run("compact_forecast", ["--script", "tests/test_compact_forecast.gd"])
        run("safe_retreat", ["--script", "tests/test_safe_retreat.gd"])
        run("safe_retreat_integration", ["--script", "tests/test_safe_retreat_integration.gd"])
        run("collapse_state", ["--script", "tests/test_collapse_state.gd"])
        run("collapse_phase", ["--script", "tests/test_collapse_phase.gd"])
        run("enemy_first", ["--script", "tests/test_enemy_first.gd"])
        run("push_chain", ["--script", "tests/test_push_chain.gd"])
        run("push_chain_reactions", ["--script", "tests/test_push_chain_reactions.gd"])
        run("spatial_guard_stats", ["--script", "tests/test_spatial_guard_stats.gd"])
        run("control_perks_codec", ["--script", "tests/test_control_perks_codec.gd"])
        run("control_package", ["--script", "tests/test_control_package.gd"])
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
        execution_args = ["--script", "tests/test_battle_execution_ui.gd"]
        if args.render_check:
            execution_args += ["--", "--captures=" + str(captures)]
        run("battle_execution_ui", execution_args, headless=not args.render_check)
        reactions_args = ["--script", "tests/test_core_reactions_ui.gd"]
        if args.render_check:
            reactions_args += ["--", "--captures=" + str(captures)]
        run("core_reactions_ui", reactions_args, headless=not args.render_check)
        counter_args = ["--script", "tests/test_counterattack_ui.gd"]
        if args.render_check:
            counter_args += ["--", "--captures=" + str(captures)]
        run("counterattack_ui", counter_args, headless=not args.render_check)
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
        turn_forecast_args = ["--script", "tests/test_turn_forecast_ui.gd"]
        if args.render_check:
            turn_forecast_args += ["--", "--captures=" + str(out)]
        run("turn_forecast_ui", turn_forecast_args, headless=not args.render_check)
        safe_retreat_args = ["--script", "tests/test_safe_retreat_ui.gd"]
        if args.render_check:
            safe_retreat_args += ["--", "--captures=" + str(out)]
        run("safe_retreat_ui", safe_retreat_args, headless=not args.render_check)
        chain_args = ["--script", "tests/test_push_chain_ui.gd"]
        if args.render_check:
            chain_args += ["--", "--captures=" + str(out)]
        run("push_chain_ui", chain_args, headless=not args.render_check)
        collapse_args = ["--script", "tests/test_collapse_ui.gd"]
        if args.render_check:
            collapse_args += ["--", "--captures=" + str(out)]
        run("collapse_ui", collapse_args, headless=not args.render_check)
        entangle_args = ["--script", "tests/test_entangle_ui.gd"]
        if args.render_check:
            entangle_args += ["--", "--captures=" + str(captures)]
        run("entangle_ui", entangle_args, headless=not args.render_check)
        move_forecast_args = ["--script", "tests/test_move_forecast_ui.gd"]
        if args.render_check:
            move_forecast_args += ["--", "--captures=" + str(captures)]
        run("move_forecast_ui", move_forecast_args, headless=not args.render_check)
    else:
        # This is the user-requested interactive window, so it is intentionally visible.
        with (out / "play.log").open("wb") as log:
            process = subprocess.Popen([godot, "--path", str(project)], env=env, stdout=log, stderr=subprocess.STDOUT)
        print("Demo window launched, PID", process.pid)


if __name__ == "__main__":
    main()
