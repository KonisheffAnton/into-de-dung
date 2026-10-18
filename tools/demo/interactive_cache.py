"""Reusable source mirror for interactive play; validation snapshots stay separate."""
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import uuid


CACHE_VERSION = 1


class CacheBusyError(RuntimeError):
    pass


def _read_json(path, default=None):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return default


def _write_json(path, value):
    temporary = path.with_name(path.name + ".tmp")
    _inside(path.parent, temporary)
    temporary.write_text(json.dumps(value, indent=2), encoding="utf-8")
    temporary.replace(path)


def _hash(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _relative(name):
    path = PurePosixPath(name)
    if not name or path.is_absolute() or "\\" in name or ":" in name or any(
        part in ("", ".", "..") for part in name.split("/")
    ):
        raise ValueError("Unsafe cache source path: " + name)
    return path


def _inside(root, path):
    # Кэш никогда не следует junction/symlink: удаление допустимо только внутри своей копии.
    path.relative_to(root)
    for current in (path, *path.parents):
        if current.is_symlink() or (hasattr(current, "is_junction") and current.is_junction()):
            raise ValueError("Linked cache path is not allowed: " + str(current))
        if current == root:
            break
    path.resolve().relative_to(root.resolve())
    return path


class InteractiveCache:
    def __init__(self, repo, engine):
        self.repo = Path(repo).resolve()
        self.root = _inside(self.repo, self.repo / "test_reports/interactive-cache")
        self.engine = engine
        self.needs_import = True
        self.stats = {"copied": 0, "removed": 0, "unchanged": 0}
        self._lease = None
        self._prepared = False

    def __enter__(self):
        self.root.mkdir(parents=True, exist_ok=True)
        lock = _inside(self.root, self.root / "launcher.lock")
        self._lease = lock.open("a+b")
        try:
            if os.name == "nt":
                import msvcrt
                if lock.stat().st_size == 0:
                    self._lease.write(b"\0")
                    self._lease.flush()
                self._lease.seek(0)
                msvcrt.locking(self._lease.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(self._lease, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as exc:
            self._lease.close()
            self._lease = None
            raise CacheBusyError("Cached game is already open; close it or use --fresh.") from exc
        try:
            self._state_path = _inside(self.root, self.root / "state.json")
            state = _read_json(self._state_path, {})
            if not isinstance(state, dict):
                state = {}
            generation = state.get("generation", "")
            reusable = (
                state.get("version") == CACHE_VERSION
                and state.get("engine") == self.engine
                and isinstance(generation, str)
                and re.fullmatch(r"[0-9a-f]{32}", generation)
                and state.get("phase") in ("ready", "preparing", "prepared")
            )
            # После убийства launcher игра могла выжить. Её каталог больше не перезаписываем.
            if not reusable:
                generation = uuid.uuid4().hex
                state = {"version": CACHE_VERSION, "engine": self.engine,
                         "generation": generation, "phase": "preparing"}
            self._prior_ready = state.get("phase") == "ready"
            self._state = state
            self.generation = _inside(self.root, self.root / generation)
            self.project = _inside(self.root, self.generation / "project")
            self.project.mkdir(parents=True, exist_ok=True)
            self._manifest_path = _inside(self.root, self.generation / "manifest.json")
            self._artifacts_path = _inside(self.root, self.generation / "artifacts.json")
            self._set_phase("preparing")
            return self
        except BaseException:
            self.__exit__(None, None, None)
            raise

    def __exit__(self, *_):
        if self._lease is not None:
            try:
                if os.name == "nt":
                    import msvcrt
                    self._lease.seek(0)
                    msvcrt.locking(self._lease.fileno(), msvcrt.LK_UNLCK, 1)
                else:
                    import fcntl
                    fcntl.flock(self._lease, fcntl.LOCK_UN)
            finally:
                self._lease.close()
                self._lease = None

    def _set_phase(self, phase):
        self._state["phase"] = phase
        _write_json(self._state_path, self._state)

    def _target(self, name):
        return _inside(self.project, self.project.joinpath(*_relative(name).parts))

    def _remove(self, name):
        path = self._target(name)
        if path.is_file():
            path.unlink()
            parent = path.parent
            while parent != self.project:
                try:
                    parent.rmdir()
                except OSError:
                    break
                parent = parent.parent

    def sync(self, names):
        previous = _read_json(self._manifest_path, [])
        if not isinstance(previous, list):
            raise ValueError("Invalid interactive source manifest; use --fresh.")
        old = {}
        for item in previous:
            name = item["path"]
            _relative(name)
            if name.startswith((".godot/", "test_reports/")):
                raise ValueError("Invalid managed cache path: " + name)
            old[name] = item["sha256"]
        current = {}
        for name in sorted(set(names) - {""}):
            _relative(name)
            if name.startswith(("test_reports/", ".godot/")):
                continue
            source = self.repo.joinpath(*PurePosixPath(name).parts)
            source.resolve().relative_to(self.repo)
            if source.is_file():
                current[name] = _hash(source)
        self.stats = {"copied": 0, "removed": 0, "unchanged": 0}
        # Журнал включает новые пути ДО копирования: после обрыва не останутся чужие версии файлов.
        pending = dict(old)
        pending.update(current)
        _write_json(self._manifest_path, [{"path": name, "sha256": digest} for name, digest in pending.items()])
        for name in old.keys() - current.keys():
            self._remove(name)
            for suffix in (".import", ".uid"):
                if name + suffix not in current:
                    self._remove(name + suffix)
            self.stats["removed"] += 1
        for name, digest in current.items():
            target = self._target(name)
            if target.is_file() and _hash(target) == digest:
                self.stats["unchanged"] += 1
                continue
            # Пустой каталог после удаления последнего дочернего исходника может стать файлом.
            if target.is_dir():
                target.rmdir()
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(self.repo / name, target)
            if _hash(target) != digest:
                raise RuntimeError("Source changed during copy; retry launcher: " + name)
            self.stats["copied"] += 1
        self.needs_import = (
            not self._prior_ready or old != current or self.stats["copied"] > 0
            or not self._cache_healthy()
        )
        if old != current or self.stats["copied"] > 0:
            # Godot может пропустить изменённую текстуру с прежним mtime; пересканируем индекс,
            # сохранив дорогие импортированные ресурсы и их контрольные суммы.
            editor = self._target(".godot/editor")
            if editor.is_dir():
                for index in editor.glob("filesystem_cache*"):
                    self._remove(index.relative_to(self.project).as_posix())
        return [{"path": name, "sha256": digest} for name, digest in current.items()]

    def _artifact_paths(self):
        artifacts = {".godot/global_script_class_cache.cfg"}
        for path in self.project.rglob("*.import"):
            name = path.relative_to(self.project).as_posix()
            if name.startswith(".godot/"):
                continue
            path = self._target(name)
            artifacts.add(name)
            artifacts.update(re.findall(r'res://(\.godot/imported/[^"\r\n]+)', path.read_text(encoding="utf-8")))
        return sorted(artifacts)

    def _cache_healthy(self):
        cache = self._target(".godot/global_script_class_cache.cfg")
        if not cache.is_file() or "test_reports" in cache.read_text(encoding="utf-8", errors="replace"):
            return False
        expected = _read_json(self._artifacts_path)
        if not isinstance(expected, list) or not expected:
            return False
        return all(self._target(name).is_file() for name in set(expected) | set(self._artifact_paths()))

    def imported(self, manifest):
        _write_json(self._manifest_path, manifest)
        _write_json(self._artifacts_path, self._artifact_paths())
        self._set_phase("prepared")
        self._prepared = True

    def begin_import(self):
        # При timeout/обрыве неизвестно, остановился ли внешний процесс импорта.
        self._set_phase("importing")

    def end_import(self):
        self._set_phase("preparing")

    def begin_play(self):
        if not self._prepared:
            raise RuntimeError("Interactive source mirror is not prepared")
        self._set_phase("playing")

    def end_play(self, success=True):
        self._set_phase("ready" if success else "preparing")
