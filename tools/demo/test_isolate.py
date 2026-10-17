"""Launcher selection/failure checks without starting Godot or touching user saves."""
import contextlib
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import isolate


class IsolateSelectionTests(unittest.TestCase):
    def test_confirmed_diagnostic_is_exact_and_core_only(self):
        expected = "ERROR: BattleBoard.add_unit: клетка (2, 2) уже занята"
        self.assertFalse(isolate.has_engine_errors("core", expected))
        self.assertTrue(isolate.has_engine_errors("battle", expected))
        self.assertTrue(isolate.has_engine_errors("core", expected + "\n" + expected))
        self.assertTrue(isolate.has_engine_errors("core", expected + " changed"))
        self.assertTrue(isolate.has_engine_errors("core", expected + "\nERROR: unrelated"))
        self.assertTrue(isolate.has_engine_errors("core", "WARNING: 47 ObjectDB instances were leaked"))

    def exercise(self, options, failure=None):
        calls = []
        commands = []
        self.last_commands = commands
        with tempfile.TemporaryDirectory(prefix="into-dedung-launcher-") as directory:
            repo = Path(directory)
            source = repo / "tools/demo/isolate.py"
            source.parent.mkdir(parents=True)
            source.write_text(Path(isolate.__file__).read_text(encoding="utf-8"), encoding="utf-8")
            (repo / "project.godot").write_text("config_version=5\n", encoding="utf-8")

            def fake_run(command, **kwargs):
                commands.append((list(command), kwargs.get("timeout"), "--headless" in command))
                project = Path(command[command.index("--path") + 1])
                label = "import" if "--import" in command else "startup"
                if "--script" in command:
                    script = command[command.index("--script") + 1]
                    label = "core" if script == "tests/run_tests.gd" else Path(script).stem.removeprefix("test_")
                    if script == "tools/demo/profile_forecast_clone.gd": label = "forecast_clone_probe"
                    if "--forecast-clone" in command:
                        label = "action_clone_ui" if script.endswith("test_action_forecast_async_ui.gd") else "action_clone_worker"
                    if "--rogue" in command:
                        label = "rogue_buff" if script.endswith("test_defender_buff.gd") else "rogue_death_routes"
                calls.append(label)
                if label == "import":
                    (project / ".godot").mkdir()
                    (project / ".godot/global_script_class_cache.cfg").write_text("", encoding="utf-8")
                failure_kind, separator, failure_label = (failure or "").partition(":")
                if not separator:
                    failure_kind, failure_label = failure_kind, "battle_hud_authoring"
                if label == "import" and failure_label == label:
                    cache = project / ".godot/global_script_class_cache.cfg"
                    if failure_kind == "cache_missing": cache.unlink()
                    if failure_kind == "cache_archived": cache.write_text("res://test_reports/old.gd", encoding="utf-8")
                if failure_kind == "timeout" and label == failure_label:
                    raise subprocess.TimeoutExpired(command, kwargs["timeout"])
                if failure_kind == "launch" and label == failure_label:
                    raise OSError("cannot start test process")
                markers = {
                    "battle_action_descriptors": "BATTLE ACTION DESCRIPTORS RESULTS:",
                    "battle_mage_presenter": "BATTLE MAGE PRESENTER RESULTS:",
                    "battle_hud_authoring": "BATTLE HUD AUTHORING RESULTS:",
                    "environment_visual_contract": "ENVIRONMENT VISUAL CONTRACT RESULTS:",
                    "unit_visual_contract": "UNIT VISUAL CONTRACT RESULTS:",
                    "defender_idle": "DEFENDER IDLE RESULTS:",
                    "defender_idle_clock": "DEFENDER IDLE CLOCK RESULTS:",
                    "defender_buff": "DEFENDER BUFF RESULTS:",
                    "defender_death": "DEFENDER DEATH RESULTS:",
                    "defender_death_routes": "DEFENDER DEATH ROUTES RESULTS:",
                    "defender_cloth_palette": "DEFENDER CLOTH PALETTE RESULTS:",
                    "rogue_cloth_palette": "ROGUE CLOTH PALETTE RESULTS:",
                    "rogue_animations": "ROGUE ANIMATIONS RESULTS:",
                    "rogue_buff": "ROGUE BUFF RESULTS:",
                    "rogue_death_routes": "ROGUE DEATH ROUTES RESULTS:",
                    "archer_idle": "ARCHER IDLE RESULTS:",
                    "archer_cloth_palette": "ARCHER CLOTH PALETTE RESULTS:",
                    "visual_scene_contract": "VISUAL SCENE CONTRACT RESULTS:",
                    "current_art_zoom": "CURRENT ART ZOOM RESULTS:",
                    "art_trial_battle": "ART TRIAL BATTLE RESULTS:",
                    "battle_view_reuse": "BATTLE VIEW REUSE RESULTS:",
                    "presentation_consequences": "PRESENTATION CONSEQUENCES RESULTS:",
                    "presentation_environment": "PRESENTATION ENVIRONMENT RESULTS:",
                    "battle_camera_ui": "BATTLE CAMERA UI RESULTS:",
                    "battle_execution_ui": "BATTLE EXECUTION UI RESULTS:",
                    "action_clone_worker": "ACTION FORECAST WORKER RESULTS:",
                    "action_clone_ui": "ACTION ASYNC UI RESULTS:",
                    "forecast_definition_copy": "FORECAST DEFINITION COPY RESULTS:",
                    "forecast_restore_isolation": "FORECAST RESTORE ISOLATION RESULTS:",
                    "restore_vitals": "RESTORE VITALS RESULTS:",
                }
                text = markers[label] + " 3 passed, 0 failed\n" if label in markers else "0 failed\n"
                if label == "profile_board_clone":
                    text = "BOARD CLONE PROBE RESULTS: 3 passed, 0 failed\nBOARD CLONE PROBE DONE\n"
                if label == "profile_item_graph_clone":
                    text = "ITEM GRAPH CLONE RESULTS: 3 passed, 0 failed\nITEM GRAPH CLONE DONE\n"
                    if failure_kind == "done": text = text.replace("ITEM GRAPH CLONE DONE", "")
                    if failure_kind == "diagnostic": text += "SCRIPT ERROR: probe failure\n"
                if label == "forecast_clone_probe":
                    text = "FORECAST CLONE RESULTS: 3 passed, 0 failed\nFORECAST CLONE DONE\n"
                    if failure_kind == "done": text = text.replace("FORECAST CLONE DONE", "")
                    if failure_kind == "diagnostic": text += "ERROR: probe failure\n"
                    if failure_kind == "warning": text += "WARNING: probe warning\n"
                if failure_kind == "marker" and label == failure_label: text = "no result\n"
                if failure_kind == "engine" and label == failure_label: text += "ERROR: unexpected engine error\n"
                if failure_kind == "leak" and label == failure_label: text += "WARNING: ObjectDB instances leaked at exit\n"
                if failure_kind == "count" and label == failure_label: text = "10 failed\n"
                kwargs["stdout"].write(text.encode())
                return subprocess.CompletedProcess(command, 1 if failure_kind == "exit" and label == failure_label else 0)

            output = io.StringIO()
            code = 0
            with patch.object(isolate, "__file__", str(source)), patch.object(isolate.subprocess, "check_output", return_value=b"project.godot\0"), patch.object(isolate.subprocess, "run", side_effect=fake_run), patch.object(isolate.atexit, "register"), patch("sys.argv", ["isolate", "--godot", "fake-godot", *options]), contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
                try:
                    isolate.main()
                except SystemExit as exc:
                    code = exc.code
            timings = list(repo.glob("test_reports/*/timing.json"))
            timing = json.loads(timings[0].read_text()) if timings else None
            return code, calls, timing, output.getvalue()

    def test_targeted_only_runs_selected_and_infrastructure(self):
        code, calls, timing, output = self.exercise(["--check", "--only", "battle_hud_authoring", "--only", "battle_hud_authoring"])
        self.assertEqual((code, calls), (0, ["import", "startup", "battle_hud_authoring"]))
        self.assertEqual(set(timing["checks"]), set(calls))
        self.assertGreaterEqual(timing["total_seconds"], timing["snapshot_seconds"])
        self.assertEqual(output.count(" PASS"), 3)

    def test_invalid_selection_never_starts_godot(self):
        for options in (["--check", "--only", "typo"], ["--only", "battle_hud_authoring"], ["--check", "--full", "--only", "battle_hud_authoring"]):
            with self.subTest(options=options):
                code, calls, timing, _ = self.exercise(options)
                self.assertEqual((code, calls, timing), (2, [], None))

    def test_ui_helpers_require_own_success_marker(self):
        for label in ("battle_action_descriptors", "battle_mage_presenter", "restore_vitals"):
            with self.subTest(label=label):
                options = ["--check", "--only", label]
                code, calls, _, _ = self.exercise(options)
                self.assertEqual((code, calls), (0, ["import", "startup", label]))
                code, _, timing, _ = self.exercise(options, "marker:" + label)
                self.assertEqual(code, 1)
                self.assertEqual(timing["checks"][label]["status"], "FAIL")

    def test_failures_record_status_and_never_pass(self):
        for failure in ("marker", "exit", "timeout"):
            with self.subTest(failure=failure):
                code, _, timing, output = self.exercise(["--check", "--only", "battle_hud_authoring"], failure)
                self.assertEqual(code, 1)
                self.assertEqual(timing["checks"]["battle_hud_authoring"]["status"], "TIMEOUT" if failure == "timeout" else "FAIL")
                self.assertNotIn("battle_hud_authoring PASS", output)

    def test_core_can_be_selected_without_entire_schedule(self):
        code, calls, timing, _ = self.exercise(["--check", "--only", "core"])
        self.assertEqual((code, calls), (0, ["import", "startup", "core"]))
        self.assertEqual(timing["checks"]["core"]["status"], "PASS")

    def test_independent_checks_continue_after_failure(self):
        for failure in ("marker", "exit", "timeout", "launch", "engine"):
            with self.subTest(failure=failure):
                code, calls, timing, output = self.exercise(
                    ["--check", "--only", "battle_hud_authoring", "battle_mage_presenter"], failure)
                self.assertEqual(code, 1)
                self.assertEqual(calls[-2:], ["battle_hud_authoring", "battle_mage_presenter"])
                self.assertEqual(timing["checks"]["battle_mage_presenter"]["status"], "PASS")
                self.assertEqual(timing["summary"]["failed_labels"], ["battle_hud_authoring"])
                self.assertEqual(timing["summary"]["unexecuted_requested"], [])
                self.assertIn("SUMMARY:", output)

    def test_infrastructure_failure_blocks_dependents_with_summary(self):
        for label in ("import", "startup"):
            for failure in ("exit", "timeout", "launch", "engine"):
                with self.subTest(label=label, failure=failure):
                    code, calls, timing, _ = self.exercise(
                        ["--check", "--only", "battle_hud_authoring"], failure + ":" + label)
                    self.assertEqual(code, 1)
                    self.assertNotIn("battle_hud_authoring", calls)
                    self.assertEqual(timing["summary"]["failed_labels"], [label])
                    self.assertEqual(timing["summary"]["unexecuted_requested"], ["battle_hud_authoring"])
                    self.assertIn(label, timing["summary"]["blocked"])

    def test_core_has_no_blanket_diagnostic_exemption(self):
        for failure in ("engine", "leak", "count"):
            with self.subTest(failure=failure):
                code, _, timing, _ = self.exercise(["--check", "--only", "core"], failure + ":core")
                self.assertEqual(code, 1)
                self.assertEqual(timing["summary"]["failed_labels"], ["core"])

    def test_invalid_import_cache_blocks_startup_and_requested_suite(self):
        for failure in ("cache_missing", "cache_archived"):
            with self.subTest(failure=failure):
                code, calls, timing, _ = self.exercise(
                    ["--check", "--only", "battle_hud_authoring"], failure + ":import")
                self.assertEqual((code, calls), (1, ["import"]))
                self.assertEqual(timing["summary"]["failed_labels"], ["import"])
                self.assertEqual(timing["summary"]["unexecuted_requested"], ["battle_hud_authoring"])
                self.assertIn("class cache", timing["summary"]["blocked"])

    def test_success_summary_covers_every_executed_check(self):
        code, calls, timing, _ = self.exercise(["--check", "--only", "battle_hud_authoring"])
        self.assertEqual(code, 0)
        self.assertEqual(timing["summary"], {
            "passed": len(calls), "failed": 0, "timed_out": 0,
            "failed_labels": [], "unexecuted_requested": [], "blocked": None,
        })

    def test_list_does_not_copy_or_start_godot(self):
        code, calls, timing, output = self.exercise(["--list-checks"])
        self.assertEqual((code, calls, timing), (0, [], None))
        self.assertIn("battle_hud_authoring\n", output)

    def test_board_clone_probe_is_opt_in_and_keeps_infrastructure(self):
        code, calls, timing, _ = self.exercise(["--check", "--only", "board_clone_probe"])
        self.assertEqual((code, calls), (0, ["import", "startup", "profile_board_clone"]))
        self.assertEqual(timing["checks"]["board_clone_probe"]["status"], "PASS")
        _, default_calls, _, _ = self.exercise(["--check"])
        self.assertNotIn("profile_board_clone", default_calls)

    def test_board_clone_probe_cannot_pass_without_completion_or_clean_exit(self):
        for failure in ("marker", "exit", "timeout"):
            with self.subTest(failure=failure):
                code, _, timing, _ = self.exercise(["--check", "--only", "board_clone_probe"], failure + ":profile_board_clone")
                self.assertEqual(code, 1)
                self.assertNotEqual(timing["checks"]["board_clone_probe"]["status"], "PASS")

    def test_item_graph_clone_probe_is_opt_in(self):
        code, calls, timing, _ = self.exercise(["--check", "--only", "item_graph_clone_probe"])
        self.assertEqual((code, calls), (0, ["import", "startup", "profile_item_graph_clone"]))
        self.assertEqual(timing["checks"]["item_graph_clone_probe"]["status"], "PASS")
        for mode in (["--check"], ["--check", "--full"], ["--render-check"]):
            _, default_calls, _, _ = self.exercise(mode)
            self.assertNotIn("profile_item_graph_clone", default_calls)

    def test_item_graph_clone_probe_requires_complete_clean_run(self):
        for failure in ("marker", "done", "diagnostic", "exit", "timeout"):
            with self.subTest(failure=failure):
                code, _, timing, _ = self.exercise(["--check", "--only", "item_graph_clone_probe"], failure + ":profile_item_graph_clone")
                self.assertEqual(code, 1)
                self.assertNotEqual(timing["checks"]["item_graph_clone_probe"]["status"], "PASS")

    def test_forecast_clone_probe_is_explicit_opt_in(self):
        code, calls, timing, _ = self.exercise(["--check", "--only", "forecast_clone_probe"])
        self.assertEqual((code, calls), (0, ["import", "startup", "forecast_clone_probe"]))
        self.assertEqual(timing["checks"]["forecast_clone_probe"]["status"], "PASS")
        command = self.last_commands[-1][0]
        self.assertEqual(command[command.index("--script") + 1], "tools/demo/profile_forecast_clone.gd")
        self.assertEqual(command[-2:], ["--", "--verify-only"])
        for mode in (["--check"], ["--check", "--full"], ["--render-check"]):
            _, default_calls, _, _ = self.exercise(mode)
            self.assertNotIn("forecast_clone_probe", default_calls)

    def test_forecast_clone_probe_requires_complete_clean_run(self):
        for failure in ("marker", "done", "diagnostic", "warning", "exit", "timeout"):
            with self.subTest(failure=failure):
                code, _, timing, _ = self.exercise(["--check", "--only", "forecast_clone_probe"], failure + ":forecast_clone_probe")
                self.assertEqual(code, 1)
                self.assertNotEqual(timing["checks"]["forecast_clone_probe"]["status"], "PASS")

    def test_action_clone_tests_are_explicit_opt_in(self):
        cases = (("action_clone_worker", "tests/test_action_forecast_worker.gd", "ACTION FORECAST WORKER RESULTS:"),
                 ("action_clone_ui", "tests/test_action_forecast_async_ui.gd", "ACTION ASYNC UI RESULTS:"))
        for label, script, marker in cases:
            with self.subTest(label=label):
                code, calls, timing, _ = self.exercise(["--check", "--only", label])
                self.assertEqual((code, calls), (0, ["import", "startup", label]))
                self.assertEqual(timing["checks"][label]["status"], "PASS")
                command, _, headless = self.last_commands[-1]
                self.assertEqual(command[command.index("--script") + 1], script)
                self.assertEqual(command[-2:], ["--", "--forecast-clone"])
                self.assertTrue(headless)
                for mode in (["--check"], ["--check", "--full"], ["--render-check"]):
                    _, default_calls, _, _ = self.exercise(mode)
                    self.assertNotIn(label, default_calls)
                if label == "action_clone_ui":
                    _, render_calls, _, _ = self.exercise(["--render-check", "--only", label])
                    self.assertEqual(render_calls, ["import", "startup", label])
                    self.assertFalse(self.last_commands[-1][2])

    def test_art_checks_automatically_include_all_visual_gates(self):
        code, calls, timing, _ = self.exercise(["--check", "--only", "art_trial_battle"])
        self.assertEqual(code, 0)
        self.assertEqual(calls, ["import", "startup", "environment_visual_contract", "unit_visual_contract",
                                 "defender_idle_clock", "defender_idle", "defender_buff",
                                 "defender_death", "defender_death_routes", "defender_cloth_palette", "rogue_cloth_palette",
                                 "rogue_animations", "rogue_buff", "rogue_death_routes", "archer_idle", "archer_cloth_palette",
                                 "visual_scene_contract", "art_trial_battle", "presentation_consequences",
                                 "presentation_environment", "battle_camera_ui", "battle_execution_ui"])
        self.assertEqual(timing["checks"]["visual_scene_contract"]["status"], "PASS")

    def test_archer_cloth_palette_is_an_independent_check(self):
        code, calls, timing, _ = self.exercise(["--check", "--only", "archer_cloth_palette"])
        self.assertEqual(code, 0)
        self.assertEqual(calls, ["import", "startup", "archer_cloth_palette"])
        self.assertEqual(timing["checks"]["archer_cloth_palette"]["status"], "PASS")
        _, render_calls, _, _ = self.exercise(["--render-check", "--only", "archer_cloth_palette"])
        self.assertEqual(render_calls, ["import", "startup", "archer_cloth_palette"])
        command, _, headless = self.last_commands[-1]
        self.assertFalse(headless)
        self.assertEqual(command[-2], "--")
        self.assertTrue(command[-1].startswith("--captures="))

    def test_visual_gate_requires_its_result_marker(self):
        code, calls, timing, output = self.exercise(
            ["--check", "--only", "visual_scene_contract"], "marker:visual_scene_contract")
        self.assertEqual(code, 1)
        self.assertIn("visual_scene_contract", calls)
        self.assertEqual(timing["checks"]["visual_scene_contract"]["status"], "FAIL")
        self.assertNotIn("visual_scene_contract PASS", output)

        code, calls, timing, output = self.exercise(
            ["--check", "--only", "defender_cloth_palette"], "marker:defender_cloth_palette")
        self.assertEqual(code, 1)
        self.assertIn("defender_cloth_palette", calls)
        self.assertEqual(timing["checks"]["defender_cloth_palette"]["status"], "FAIL")
        self.assertNotIn("defender_cloth_palette PASS", output)

        code, calls, timing, output = self.exercise(
            ["--check", "--only", "rogue_cloth_palette"], "marker:rogue_cloth_palette")
        self.assertEqual(code, 1)
        self.assertIn("rogue_cloth_palette", calls)
        self.assertEqual(timing["checks"]["rogue_cloth_palette"]["status"], "FAIL")
        self.assertNotIn("rogue_cloth_palette PASS", output)

        code, calls, timing, output = self.exercise(
            ["--check", "--only", "archer_cloth_palette"], "marker:archer_cloth_palette")
        self.assertEqual(code, 1)
        self.assertIn("archer_cloth_palette", calls)
        self.assertEqual(timing["checks"]["archer_cloth_palette"]["status"], "FAIL")
        self.assertNotIn("archer_cloth_palette PASS", output)

    def test_all_visual_gates_propagate_process_failures(self):
        for label in ("environment_visual_contract", "unit_visual_contract", "visual_scene_contract", "defender_idle_clock", "defender_idle", "defender_buff", "defender_death", "defender_death_routes", "defender_cloth_palette", "rogue_cloth_palette", "rogue_animations", "rogue_buff", "rogue_death_routes", "archer_idle", "archer_cloth_palette",
                      "presentation_consequences", "presentation_environment", "battle_camera_ui", "battle_execution_ui"):
            with self.subTest(label=label):
                code, calls, timing, output = self.exercise(
                    ["--check", "--only", label], "exit:" + label)
                self.assertEqual(code, 1)
                self.assertIn(label, calls)
                self.assertEqual(timing["checks"][label]["status"], "FAIL")
                self.assertNotIn(label + " PASS", output)


if __name__ == "__main__":
    unittest.main()
