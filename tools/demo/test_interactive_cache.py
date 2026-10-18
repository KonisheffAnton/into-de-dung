"""Regression checks for the reusable interactive project cache."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from interactive_cache import CacheBusyError, InteractiveCache


class InteractiveCacheTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="into-dedung-interactive-cache-")
        self.repo = Path(self.temp.name)
        self.engine = {"path": "fake-godot", "version": "4.7.test"}

    def tearDown(self):
        self.temp.cleanup()

    def source(self, relative, data):
        path = self.repo / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return path

    def prepare_imported(self, cache):
        godot = cache.project / ".godot"
        godot.mkdir(parents=True, exist_ok=True)
        (godot / "global_script_class_cache.cfg").write_text("class cache\n", encoding="utf-8")
        imported = cache.project / ".godot/imported/hero.ctex"
        imported.parent.mkdir(parents=True, exist_ok=True)
        imported.write_bytes(b"texture")
        sidecar = cache.project / "assets/hero.png.import"
        sidecar.parent.mkdir(parents=True, exist_ok=True)
        sidecar.write_text(
            "[remap]\npath=\"res://.godot/imported/hero.ctex\"\n", encoding="utf-8")

    def make_ready(self, names):
        with InteractiveCache(self.repo, self.engine) as cache:
            manifest = cache.sync(names)
            self.prepare_imported(cache)
            cache.imported(manifest)
            cache.end_play()
            return cache.project

    def test_cold_then_warm_sync_preserves_unchanged_mtime(self):
        self.source("scripts/a.gd", b"extends RefCounted\n")
        with InteractiveCache(self.repo, self.engine) as cache:
            self.assertTrue(cache.needs_import)
            manifest = cache.sync(["scripts/a.gd"])
            self.assertEqual(cache.stats["copied"], 1)
            self.prepare_imported(cache)
            cache.imported(manifest)
            cache.end_play()
            target = cache.project / "scripts/a.gd"
            before = target.stat().st_mtime_ns
        with InteractiveCache(self.repo, self.engine) as cache:
            manifest = cache.sync(["scripts/a.gd"])
            self.assertFalse(cache.needs_import)
            self.assertEqual(cache.stats["unchanged"], 1)
            self.assertEqual((cache.project / "scripts/a.gd").stat().st_mtime_ns, before)
            cache.imported(manifest)

    def test_content_hash_detects_same_size_same_mtime_edit(self):
        source = self.source("scripts/a.gd", b"extends A\n")
        project = self.make_ready(["scripts/a.gd"])
        target = project / "scripts/a.gd"
        original_stat = source.stat()
        source.write_bytes(b"extends B\n")
        os.utime(source, ns=(original_stat.st_atime_ns, original_stat.st_mtime_ns))
        with InteractiveCache(self.repo, self.engine) as cache:
            self.assertEqual(cache.project, project)
            manifest = cache.sync(["scripts/a.gd"])
            self.assertEqual(target.read_bytes(), b"extends B\n")
            self.assertTrue(cache.needs_import)
            self.assertEqual(cache.stats["copied"], 1)
            self.assertNotEqual(manifest[0]["sha256"], "")

    def test_add_delete_rename_removes_managed_import_sidecars(self):
        self.source("scripts/old.gd", b"old")
        with InteractiveCache(self.repo, self.engine) as cache:
            manifest = cache.sync(["scripts/old.gd"])
            self.prepare_imported(cache)
            (cache.project / "scripts/old.gd.import").write_text("sidecar", encoding="utf-8")
            (cache.project / "scripts/old.gd.uid").write_text("uid", encoding="utf-8")
            cache.imported(manifest)
            (self.repo / "scripts/old.gd").unlink()
            self.source("scripts/new.gd", b"new")
            manifest = cache.sync(["scripts/new.gd"])
            self.assertTrue(cache.needs_import)
            self.assertFalse((cache.project / "scripts/old.gd").exists())
            self.assertFalse((cache.project / "scripts/old.gd.import").exists())
            self.assertFalse((cache.project / "scripts/old.gd.uid").exists())
            self.assertTrue((cache.project / "scripts/new.gd").exists())
            self.assertEqual({entry["path"] for entry in manifest}, {"scripts/new.gd"})

    def test_missing_global_or_imported_resource_requires_import(self):
        self.source("assets/hero.png", b"png")
        project = self.make_ready(["assets/hero.png"])
        (project / ".godot/global_script_class_cache.cfg").unlink()
        with InteractiveCache(self.repo, self.engine) as cache:
            self.assertEqual(cache.project, project)
            cache.sync(["assets/hero.png"])
            self.assertTrue(cache.needs_import)
        project = self.make_ready(["assets/hero.png"])
        (project / ".godot/imported/hero.ctex").unlink()
        with InteractiveCache(self.repo, self.engine) as cache:
            self.assertEqual(cache.project, project)
            cache.sync(["assets/hero.png"])
            self.assertTrue(cache.needs_import)

    def test_preparing_generation_is_reused_and_imported_again(self):
        self.source("scripts/a.gd", b"a")
        with InteractiveCache(self.repo, self.engine) as cache:
            first_project = cache.project
            cache.sync(["scripts/a.gd"])
        with InteractiveCache(self.repo, self.engine) as cache:
            self.assertEqual(cache.project, first_project)
            self.assertTrue(cache.needs_import)

    def test_interrupted_playing_uses_new_generation_and_preserves_old(self):
        self.source("scripts/a.gd", b"a")
        with InteractiveCache(self.repo, self.engine) as cache:
            old = cache.project
            manifest = cache.sync(["scripts/a.gd"])
            self.prepare_imported(cache)
            cache.imported(manifest)
            cache.begin_play()
        sentinel = old / "still-running-copy.marker"
        sentinel.write_text("keep", encoding="utf-8")
        with InteractiveCache(self.repo, self.engine) as cache:
            self.assertNotEqual(cache.project, old)
            self.assertTrue(sentinel.is_file())
            self.assertTrue(cache.needs_import)

    def test_engine_change_uses_new_generation(self):
        self.source("scripts/a.gd", b"a")
        with InteractiveCache(self.repo, self.engine) as cache:
            old = cache.project
            manifest = cache.sync(["scripts/a.gd"])
            self.prepare_imported(cache)
            cache.imported(manifest)
            cache.end_play()
        changed_engine = {"path": "fake-godot", "version": "4.8.test"}
        with InteractiveCache(self.repo, changed_engine) as cache:
            self.assertNotEqual(cache.project, old)
            self.assertTrue(cache.needs_import)

    def test_busy_lease_fails_without_mutating_sources_or_cache(self):
        self.source("scripts/a.gd", b"a")
        with InteractiveCache(self.repo, self.engine) as owner:
            owner.sync(["scripts/a.gd"])
            project = owner.project
            before = (self.repo / "scripts/a.gd").read_bytes()
            with self.assertRaises(CacheBusyError):
                with InteractiveCache(self.repo, self.engine):
                    self.fail("second owner unexpectedly acquired the lease")
            self.assertEqual((self.repo / "scripts/a.gd").read_bytes(), before)
            self.assertTrue(project.is_dir())

    def test_rejects_traversal_and_destination_symlink(self):
        self.source("linked/file.gd", b"source")
        outside = self.repo / "outside"
        outside.mkdir()
        with InteractiveCache(self.repo, self.engine) as cache:
            link = cache.project / "linked"
            junction_created = False
            try:
                link.symlink_to(outside, target_is_directory=True)
            except (OSError, NotImplementedError):
                junction_created = self._create_directory_junction(link, outside)
            try:
                if link.exists():
                    with self.assertRaises((ValueError, OSError)):
                        cache.sync(["linked/file.gd"])
                elif not junction_created:
                    self.skipTest("directory symlink/junction creation unavailable")
                self.assertTrue(outside.is_dir())
            finally:
                if junction_created:
                    cleanup = f"Remove-Item -LiteralPath '{self._ps_quote(link)}' -Force"
                    subprocess.run(
                        ["powershell", "-NoProfile", "-NonInteractive", "-Command", cleanup],
                        capture_output=True, text=True, check=False)

    @staticmethod
    def _ps_quote(value):
        return str(value).replace("'", "''")

    def _create_directory_junction(self, link, target):
        command = (
            "$ErrorActionPreference='Stop'; "
            f"New-Item -ItemType Junction -Path '{self._ps_quote(link)}' -Target '{self._ps_quote(target)}' | Out-Null"
        )
        result = subprocess.run(
            ["powershell", "-NoProfile", "-NonInteractive", "-Command", command],
            capture_output=True, text=True, check=False)
        if result.returncode != 0:
            return False
        return True

    def test_traversal_paths_are_rejected_independently(self):
        with InteractiveCache(self.repo, self.engine) as cache:
            for invalid in ("../outside.gd", "/absolute.gd", "scripts/../outside.gd"):
                with self.subTest(path=invalid):
                    with self.assertRaises((ValueError, OSError)):
                        cache.sync([invalid])

    def test_interrupted_sync_removes_stale_pending_source(self):
        self.source("scripts/old.gd", b"old")
        with InteractiveCache(self.repo, self.engine) as cache:
            cache.sync(["scripts/old.gd"])
            old_project = cache.project
            self.assertTrue((old_project / "scripts/old.gd").is_file())
        (self.repo / "scripts/old.gd").unlink()
        self.source("scripts/new.gd", b"new")
        with InteractiveCache(self.repo, self.engine) as cache:
            self.assertEqual(cache.project, old_project)
            manifest = cache.sync(["scripts/new.gd"])
            self.assertFalse((cache.project / "scripts/old.gd").exists())
            self.assertTrue((cache.project / "scripts/new.gd").is_file())
            self.assertEqual([entry["path"] for entry in manifest], ["scripts/new.gd"])

    def test_file_directory_transitions_are_applied(self):
        self.source("node", b"file")
        with InteractiveCache(self.repo, self.engine) as cache:
            cache.sync(["node"])
            self.assertTrue((cache.project / "node").is_file())
        (self.repo / "node").unlink()
        self.source("node/child.gd", b"child")
        with InteractiveCache(self.repo, self.engine) as cache:
            cache.sync(["node/child.gd"])
            self.assertTrue((cache.project / "node/child.gd").is_file())
        (self.repo / "node/child.gd").unlink()
        (self.repo / "node").rmdir()
        self.source("node", b"file again")
        with InteractiveCache(self.repo, self.engine) as cache:
            cache.sync(["node"])
            self.assertEqual((cache.project / "node").read_bytes(), b"file again")

    def test_damaged_mirror_is_repaired_and_requires_import(self):
        self.source("scripts/a.gd", b"source")
        project = self.make_ready(["scripts/a.gd"])
        target = project / "scripts/a.gd"
        target.write_bytes(b"damaged")
        with InteractiveCache(self.repo, self.engine) as cache:
            cache.sync(["scripts/a.gd"])
            self.assertEqual(target.read_bytes(), b"source")
            self.assertTrue(cache.needs_import)

    def test_svg_change_invalidates_discovery_index_but_keeps_imported_resource(self):
        source = self.source("assets/hero.svg", b"<svg>8px</svg>")
        project = self.make_ready(["assets/hero.svg"])
        index = project / ".godot/editor/filesystem_cache10"
        index.parent.mkdir(parents=True, exist_ok=True)
        index.write_bytes(b"discovery index")
        imported = project / ".godot/imported/hero.ctex"
        self.assertTrue(imported.is_file())

        with InteractiveCache(self.repo, self.engine) as cache:
            cache.sync(["assets/hero.svg"])
            self.assertTrue(index.is_file())
            self.assertTrue(imported.is_file())

        before = source.stat()
        source.write_bytes(b"<svg>9px</svg>")
        os.utime(source, ns=(before.st_atime_ns, before.st_mtime_ns))
        with InteractiveCache(self.repo, self.engine) as cache:
            cache.sync(["assets/hero.svg"])
            self.assertTrue(cache.needs_import)
            self.assertFalse(index.exists())
            self.assertTrue(imported.is_file())

    def test_excludes_cache_outputs_and_does_not_touch_repo_sources(self):
        self.source("scripts/a.gd", b"a")
        self.source("test_reports/ignored.txt", b"report")
        self.source(".godot/ignored.cfg", b"cache")
        original = (self.repo / "scripts/a.gd").read_bytes()
        with InteractiveCache(self.repo, self.engine) as cache:
            manifest = cache.sync(["scripts/a.gd", "test_reports/ignored.txt", ".godot/ignored.cfg"])
            self.assertEqual([entry["path"] for entry in manifest], ["scripts/a.gd"])
            self.assertFalse((cache.project / "test_reports/ignored.txt").exists())
            self.assertFalse((cache.project / ".godot/ignored.cfg").exists())
            self.assertEqual((self.repo / "scripts/a.gd").read_bytes(), original)


if __name__ == "__main__":
    unittest.main()
