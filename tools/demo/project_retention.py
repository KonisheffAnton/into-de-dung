"""Ограниченная очистка завершённых временных копий проекта."""
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import shutil


OWNER = "intoDeDung.project-retention"
VERSION = 1
MARKER_NAME = "project-retention.json"
_RUN_NAME = re.compile(r"demo-[0-9a-f]{32}\Z")


def _is_link(path: Path) -> bool:
    try:
        info = path.lstat()
    except FileNotFoundError:
        return False
    return path.is_symlink() or bool(getattr(info, "st_file_attributes", 0) & 0x400)


def _check_chain(path: Path, boundary: Path) -> None:
    """Проверяет даже отсутствующие конечные пути: ни один существующий компонент не может быть ссылкой."""
    path = Path(os.path.abspath(path))
    boundary = Path(os.path.abspath(boundary))
    try:
        relative = path.relative_to(boundary)
    except ValueError as exc:
        raise ValueError(f"path outside allowed root: {path}") from exc
    current = boundary
    if _is_link(boundary):
        raise ValueError(f"linked boundary: {boundary}")
    for part in relative.parts:
        current /= part
        if _is_link(current):
            raise ValueError(f"linked path component: {current}")


def _atomic_json(path: Path, data: dict) -> None:
    temporary = path.with_name(path.name + ".tmp")
    _check_chain(temporary, path.parent.parent)
    temporary.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def mark_completed(repo: Path, out: Path, keep: bool = False) -> None:
    """Помечает проект завершённым; вызывающий гарантирует остановку всех дочерних процессов."""
    repo_path = Path(repo).resolve()
    output = Path(os.path.abspath(out))
    allowed = repo_path / "test_reports"
    _check_chain(output, allowed)
    if (output.parent != allowed or not _RUN_NAME.fullmatch(output.name)
            or not output.is_dir() or not (output / "project").is_dir()):
        raise ValueError("output project directory does not exist")
    marker = output / MARKER_NAME
    _check_chain(marker, allowed)
    _atomic_json(marker, {
        "owner": OWNER,
        "version": VERSION,
        "state": "complete",
        "completed_at": datetime.now(timezone.utc).isoformat(),
        "keep": bool(keep),
    })


def _acquire_lock(lock_path: Path):
    lease = lock_path.open("a+b")
    try:
        if os.name == "nt":
            import msvcrt
            if lock_path.stat().st_size == 0:
                lease.write(b"\0")
                lease.flush()
            lease.seek(0)
            msvcrt.locking(lease.fileno(), msvcrt.LK_NBLCK, 1)
        else:
            import fcntl
            fcntl.flock(lease, fcntl.LOCK_EX | fcntl.LOCK_NB)
        return lease
    except (OSError, ImportError):
        lease.close()
        raise


def _marker(project: Path, report_root: Path):
    marker = project.parent / MARKER_NAME
    _check_chain(marker, report_root)
    if not marker.is_file():
        return None, "missing completion marker"
    try:
        data = json.loads(marker.read_text(encoding="utf-8"))
        if (not isinstance(data, dict) or set(data) != {"owner", "version", "state", "completed_at", "keep"}
                or data["owner"] != OWNER or type(data["version"]) is not int or data["version"] != VERSION
                or data["state"] != "complete" or type(data["keep"]) is not bool):
            return None, "invalid completion marker schema"
        stamp = data["completed_at"]
        if not isinstance(stamp, str):
            return None, "invalid completion timestamp"
        completed = datetime.fromisoformat(stamp.replace("Z", "+00:00"))
        if completed.tzinfo is None or completed.utcoffset() is None:
            return None, "completion timestamp lacks timezone"
        completed = completed.astimezone(timezone.utc)
        if completed > datetime.now(timezone.utc):
            return None, "completion timestamp is in the future"
        return (completed, data["keep"]), None
    except (OSError, ValueError, TypeError, KeyError):
        return None, "malformed completion marker"


def _has_reparse(project: Path) -> bool:
    failures = []
    def onerror(error):
        failures.append(error)

    for root, dirs, files in os.walk(project, followlinks=False, onerror=onerror):
        base = Path(root)
        for name in dirs + files:
            if _is_link(base / name):
                return True
    if failures:
        raise failures[0]
    return False


def prune_projects(repo: Path, keep_count: int = 3) -> dict:
    """Удаляет только старые помеченные project-поддеревья; sibling-артефакты остаются нетронутыми."""
    result = {"removed": [], "skipped": [], "errors": []}
    if type(keep_count) is not int or keep_count < 0:
        result["errors"].append({"path": "test_reports", "reason": "keep_count must be a non-negative integer"})
        return result
    repo_path = Path(repo).resolve()
    report_root = repo_path / "test_reports"
    lock_path = report_root / "project-retention.lock"
    lease = None
    try:
        _check_chain(report_root, repo_path)
        if not report_root.exists():
            return result
        if not report_root.is_dir():
            raise ValueError("test_reports is not a directory")
        _check_chain(lock_path, report_root)
        lease = _acquire_lock(lock_path)
    except (OSError, ValueError) as exc:
        result["errors"].append({"path": "test_reports", "reason": str(exc)})
        return result

    try:
        eligible = []
        try:
            entries = list(report_root.iterdir())
        except OSError as exc:
            result["errors"].append({"path": "test_reports", "reason": str(exc)})
            return result
        for run in entries:
            if not _RUN_NAME.fullmatch(run.name):
                continue
            project = run / "project"
            relative = project.relative_to(repo_path).as_posix()
            try:
                _check_chain(run, report_root)
                _check_chain(project, report_root)
                if not project.exists():
                    continue
                if not project.is_dir():
                    result["skipped"].append({"path": relative, "reason": "project is not a directory"})
                    continue
                state, reason = _marker(project, report_root)
                if reason:
                    result["skipped"].append({"path": relative, "reason": reason})
                    continue
                completed, pinned = state
                if pinned:
                    result["skipped"].append({"path": relative, "reason": "pinned keep=true"})
                else:
                    eligible.append((completed, relative, project))
            except (OSError, ValueError) as exc:
                result["skipped"].append({"path": relative, "reason": str(exc)})

        eligible.sort(key=lambda item: (item[0], item[1]), reverse=True)
        for _, relative, project in eligible[keep_count:]:
            try:
                # Проверка непосредственно перед удалением защищает от подмены после сканирования.
                _check_chain(project, report_root)
                if _has_reparse(project):
                    result["skipped"].append({"path": relative, "reason": "project contains a symlink or reparse point"})
                    continue
                absolute = Path(os.path.abspath(project))
                expected = report_root / Path(relative).relative_to("test_reports")
                if absolute != expected or absolute.parent.parent != report_root or absolute.name != "project":
                    raise ValueError("project path does not match standard shape")
                shutil.rmtree(absolute)
                result["removed"].append(relative)
            except (OSError, ValueError) as exc:
                result["errors"].append({"path": relative, "reason": str(exc)})
        return result
    finally:
        if lease is not None:
            try:
                if os.name == "nt":
                    import msvcrt
                    lease.seek(0)
                    msvcrt.locking(lease.fileno(), msvcrt.LK_UNLCK, 1)
                else:
                    import fcntl
                    fcntl.flock(lease, fcntl.LOCK_UN)
            finally:
                lease.close()
