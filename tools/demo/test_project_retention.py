"""Проверки безопасной очистки копий тестового проекта."""
from datetime import datetime, timedelta, timezone
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

from project_retention import MARKER_NAME, OWNER, VERSION, mark_completed, prune_projects


class ProjectRetentionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="into-dedung-retention-")
        self.repo = Path(self.temp.name)
        (self.repo / "test_reports").mkdir()

    def tearDown(self):
        self.temp.cleanup()

    def make_project(self, index, stamp=None, keep=False):
        run = self.repo / "test_reports" / f"demo-{index:032x}"
        project = run / "project"
        project.mkdir(parents=True)
        (project / "scene.tscn").write_bytes(f"project-{index}".encode())
        (run / "logs").mkdir()
        (run / "logs/output.log").write_bytes(b"keep log")
        for name in ("screenshots", "profile", "manifest.json", "timing.json"):
            artifact = run / name
            if name in ("screenshots", "profile"):
                artifact.mkdir()
                (artifact / "data.bin").write_bytes(name.encode())
            else:
                artifact.write_bytes(name.encode())
        if stamp is not None:
            self.write_marker(run, stamp, keep)
        return run, project

    @staticmethod
    def write_marker(run, stamp, keep=False, **overrides):
        value = {"owner": OWNER, "version": VERSION, "state": "complete",
                 "completed_at": stamp.isoformat(), "keep": keep}
        value.update(overrides)
        (run / MARKER_NAME).write_text(json.dumps(value), encoding="utf-8")

    def test_keep_three_newest_and_preserve_sibling_artifacts(self):
        base = datetime(2026, 1, 1, tzinfo=timezone.utc)
        runs = [self.make_project(i, base + timedelta(days=i)) for i in range(5)]
        marker_bytes = [(run / MARKER_NAME).read_bytes() for run, _ in runs]
        result = prune_projects(self.repo)
        self.assertEqual(len(result["removed"]), 2)
        self.assertTrue(all(not project.exists() for _, project in runs[:2]))
        self.assertTrue(all(project.exists() for _, project in runs[2:]))
        for index, (run, _) in enumerate(runs):
            self.assertEqual((run / MARKER_NAME).read_bytes(), marker_bytes[index])
            self.assertEqual((run / "logs/output.log").read_bytes(), b"keep log")
            self.assertEqual((run / "screenshots/data.bin").read_bytes(), b"screenshots")
            self.assertEqual((run / "profile/data.bin").read_bytes(), b"profile")
            self.assertEqual((run / "manifest.json").read_bytes(), b"manifest.json")
            self.assertEqual((run / "timing.json").read_bytes(), b"timing.json")

    def test_keep_zero_and_mark_completed_schema(self):
        run, project = self.make_project(1)
        mark_completed(self.repo, run, keep=True)
        marker = json.loads((run / MARKER_NAME).read_text(encoding="utf-8"))
        self.assertEqual(set(marker), {"owner", "version", "state", "completed_at", "keep"})
        self.assertTrue(marker["keep"])
        result = prune_projects(self.repo, keep_count=0)
        self.assertTrue(project.exists())
        self.assertEqual(result["removed"], [])
        self.assertTrue(any(x["path"].endswith("/project") for x in result["skipped"]))
        self.assertTrue((run / "logs/output.log").exists())

    def test_incomplete_legacy_malformed_future_nan_and_unrecognized_are_preserved(self):
        past = datetime(2026, 1, 1, tzinfo=timezone.utc)
        cases = [self.make_project(i, past) for i in range(4)]
        # Для проверки схемы каждому каталогу задаём отличающийся неподходящий маркер.
        self.write_marker(cases[0][0], past, state="running")
        (cases[1][0] / MARKER_NAME).unlink()
        self.write_marker(cases[2][0], datetime.now(timezone.utc) + timedelta(days=2))
        self.write_marker(cases[3][0], past, completed_at="NaN")
        for i, (_, project) in enumerate(cases):
            self.assertTrue(project.exists())
        result = prune_projects(self.repo, 0)
        self.assertEqual(result["removed"], [])
        self.assertEqual(len(result["skipped"]), 4)

    def test_exact_run_directory_pattern_only(self):
        run = self.repo / "test_reports/demo-ABCDEF"
        project = run / "project"
        project.mkdir(parents=True)
        self.write_marker(run, datetime(2020, 1, 1, tzinfo=timezone.utc))
        result = prune_projects(self.repo, 0)
        self.assertTrue(project.exists())
        self.assertEqual(result["removed"], [])

    def test_nested_symlink_preserves_whole_project(self):
        _, project = self.make_project(1, datetime(2020, 1, 1, tzinfo=timezone.utc))
        outside = self.repo / "outside"
        outside.mkdir()
        try:
            (project / "linked").symlink_to(outside, target_is_directory=True)
        except (OSError, NotImplementedError):
            self.skipTest("directory symlink creation is unavailable")
        result = prune_projects(self.repo, 0)
        self.assertTrue(project.exists())
        self.assertEqual(result["removed"], [])
        self.assertTrue(outside.exists())

    def test_marker_symlink_escape_is_preserved(self):
        _, project = self.make_project(1)
        outside = self.repo / "external-marker.json"
        self.write_marker(project.parent, datetime(2020, 1, 1, tzinfo=timezone.utc))
        outside.write_text((project.parent / MARKER_NAME).read_text(encoding="utf-8"), encoding="utf-8")
        (project.parent / MARKER_NAME).unlink()
        try:
            (project.parent / MARKER_NAME).symlink_to(outside)
        except (OSError, NotImplementedError):
            self.skipTest("file symlink creation is unavailable")
        result = prune_projects(self.repo, 0)
        self.assertTrue(project.exists())
        self.assertEqual(result["removed"], [])

    def test_mark_completed_rejects_wrong_or_nested_run(self):
        run, _ = self.make_project(1)
        for invalid in (run / "project", self.repo / "test_reports/demo-invalid"):
            with self.assertRaises(ValueError):
                mark_completed(self.repo, invalid)

    def test_pinned_project_does_not_consume_newest_three_slots(self):
        base = datetime(2026, 1, 1, tzinfo=timezone.utc)
        runs = [self.make_project(i, base + timedelta(days=i), keep=(i == 0)) for i in range(5)]
        result = prune_projects(self.repo, 3)
        self.assertTrue(runs[0][1].exists())
        self.assertTrue(runs[2][1].exists())
        self.assertTrue(runs[3][1].exists())
        self.assertTrue(runs[4][1].exists())
        self.assertFalse(runs[1][1].exists())
        self.assertTrue((runs[1][0] / MARKER_NAME).exists())
        self.assertEqual(len(result["removed"]), 1)

    @unittest.skipUnless(os.name == "nt", "Windows junction test")
    def test_windows_junctions_are_never_followed_or_removed(self):
        def junction(link, target):
            result = subprocess.run(["cmd", "/c", "mklink", "/J", str(link), str(target)],
                                    capture_output=True, text=True)
            if result.returncode:
                self.skipTest("junction creation unavailable: " + result.stderr.strip())

        # Внешняя цель гарантирует, что успешная очистка ссылки сама по себе не затрагивает цель.
        external = self.repo / "external"
        external.mkdir()
        (external / "sentinel").write_bytes(b"safe")
        run, project = self.make_project(9, datetime(2020, 1, 1, tzinfo=timezone.utc))
        nested = project / "junction"
        junction(nested, external)
        result = prune_projects(self.repo, 0)
        self.assertTrue(project.exists())
        self.assertTrue((external / "sentinel").exists())
        self.assertEqual(result["removed"], [])

    @unittest.skipUnless(os.name == "nt", "Windows junction test")
    def test_windows_junction_report_root_and_project_are_preserved(self):
        # Реальный test_reports размещён отдельно, чтобы подменённый корень мог ссылаться на него.
        actual = self.repo / "actual-reports"
        actual.mkdir()
        run = actual / ("demo-" + "a" * 32)
        (run / "project").mkdir(parents=True)
        self.write_marker(run, datetime(2020, 1, 1, tzinfo=timezone.utc))
        reports = self.repo / "test_reports"
        reports.rmdir()
        created = subprocess.run(["cmd", "/c", "mklink", "/J", str(reports), str(actual)],
                                 capture_output=True, text=True)
        if created.returncode:
            self.skipTest("junction creation unavailable: " + created.stderr.strip())
        result = prune_projects(self.repo, 0)
        self.assertTrue((run / "project").exists())
        self.assertTrue(result["errors"])

    @unittest.skipUnless(os.name == "nt", "Windows junction test")
    def test_windows_junction_run_is_preserved(self):
        external = self.repo / "external-run"
        run_target = external / ("demo-" + "b" * 32)
        (run_target / "project").mkdir(parents=True)
        (run_target / "project/asset.bin").write_bytes(b"safe")
        self.write_marker(run_target, datetime(2020, 1, 1, tzinfo=timezone.utc))
        run_link = self.repo / "test_reports" / run_target.name
        created = subprocess.run(["cmd", "/c", "mklink", "/J", str(run_link), str(run_target)],
                                 capture_output=True, text=True)
        if created.returncode:
            self.skipTest("junction creation unavailable: " + created.stderr.strip())
        result = prune_projects(self.repo, 0)
        self.assertTrue((run_target / "project/asset.bin").exists())
        self.assertEqual(result["removed"], [])
        self.assertTrue(result["skipped"])

    def test_lock_contention_reports_error_and_retry_succeeds(self):
        _, project = self.make_project(1, datetime(2020, 1, 1, tzinfo=timezone.utc))
        lock = (self.repo / "test_reports/project-retention.lock").open("a+b")
        try:
            if os.name == "nt":
                import msvcrt
                lock.write(b"\0")
                lock.flush()
                lock.seek(0)
                msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            result = prune_projects(self.repo, 0)
            self.assertTrue(result["errors"])
            self.assertTrue(project.exists())
        finally:
            lock.close()
        result = prune_projects(self.repo, 0)
        self.assertEqual(result["removed"], ["test_reports/demo-00000000000000000000000000000001/project"])

    def test_deletion_failure_is_reported_and_retry_succeeds(self):
        _, project = self.make_project(1, datetime(2020, 1, 1, tzinfo=timezone.utc))
        with mock.patch("project_retention.shutil.rmtree", side_effect=PermissionError("denied")):
            result = prune_projects(self.repo, 0)
        self.assertTrue(result["errors"])
        self.assertTrue(project.exists())
        result = prune_projects(self.repo, 0)
        self.assertEqual(result["removed"], ["test_reports/demo-00000000000000000000000000000001/project"])
        self.assertFalse(project.exists())


if __name__ == "__main__":
    unittest.main()
