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
    def exercise(self, options, failure=None):
        calls = []
        with tempfile.TemporaryDirectory(prefix="into-dedung-launcher-") as directory:
            repo = Path(directory)
            source = repo / "tools/demo/isolate.py"
            source.parent.mkdir(parents=True)
            source.write_text(Path(isolate.__file__).read_text(encoding="utf-8"), encoding="utf-8")
            (repo / "project.godot").write_text("config_version=5\n", encoding="utf-8")

            def fake_run(command, **kwargs):
                project = Path(command[command.index("--path") + 1])
                label = "import" if "--import" in command else "startup"
                if "--script" in command:
                    script = command[command.index("--script") + 1]
                    label = "core" if script == "tests/run_tests.gd" else Path(script).stem.removeprefix("test_")
                calls.append(label)
                if label == "import":
                    (project / ".godot").mkdir()
                    (project / ".godot/global_script_class_cache.cfg").write_text("", encoding="utf-8")
                failure_kind, separator, failure_label = (failure or "").partition(":")
                if not separator:
                    failure_kind, failure_label = failure_kind, "battle_hud_authoring"
                if failure_kind == "timeout" and label == failure_label:
                    raise subprocess.TimeoutExpired(command, kwargs["timeout"])
                markers = {
                    "battle_hud_authoring": "BATTLE HUD AUTHORING RESULTS:",
                    "environment_visual_contract": "ENVIRONMENT VISUAL CONTRACT RESULTS:",
                    "visual_scene_contract": "VISUAL SCENE CONTRACT RESULTS:",
                    "current_art_zoom": "CURRENT ART ZOOM RESULTS:",
                    "art_trial_battle": "ART TRIAL BATTLE RESULTS:",
                    "battle_view_reuse": "BATTLE VIEW REUSE RESULTS:",
                }
                text = markers[label] + " 3 passed, 0 failed\n" if label in markers else "0 failed\n"
                if failure_kind == "marker" and label == failure_label: text = "no result\n"
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

    def test_list_does_not_copy_or_start_godot(self):
        code, calls, timing, output = self.exercise(["--list-checks"])
        self.assertEqual((code, calls, timing), (0, [], None))
        self.assertIn("battle_hud_authoring\n", output)

    def test_art_checks_automatically_include_both_visual_gates(self):
        code, calls, timing, _ = self.exercise(["--check", "--only", "art_trial_battle"])
        self.assertEqual(code, 0)
        self.assertEqual(calls, ["import", "startup", "environment_visual_contract", "visual_scene_contract", "art_trial_battle"])
        self.assertEqual(timing["checks"]["visual_scene_contract"]["status"], "PASS")

    def test_visual_gate_requires_its_result_marker(self):
        code, calls, timing, output = self.exercise(
            ["--check", "--only", "visual_scene_contract"], "marker:visual_scene_contract")
        self.assertEqual(code, 1)
        self.assertIn("visual_scene_contract", calls)
        self.assertEqual(timing["checks"]["visual_scene_contract"]["status"], "FAIL")
        self.assertNotIn("visual_scene_contract PASS", output)

    def test_both_visual_gates_propagate_process_failures(self):
        for label in ("environment_visual_contract", "visual_scene_contract"):
            with self.subTest(label=label):
                code, calls, timing, output = self.exercise(
                    ["--check", "--only", label], "exit:" + label)
                self.assertEqual(code, 1)
                self.assertIn(label, calls)
                self.assertEqual(timing["checks"][label]["status"], "FAIL")
                self.assertNotIn(label + " PASS", output)


if __name__ == "__main__":
    unittest.main()
