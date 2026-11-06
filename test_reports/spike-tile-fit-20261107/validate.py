"""Read-only checks for the bounded tile-fit correction; writes one report."""
from pathlib import Path
import hashlib
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
REPORT = Path(__file__).resolve().parent
BASE = "328fb508e7a9924772f64c71ad4d4303307fdffd"
GPU = ROOT / "test_reports/demo-2dcbef2290f9480fa180f6ab8af2e070"
CHANGED = {
    "assets/shaders/spike_trap_surface.gdshader",
    "scenes/demo/visuals/hazards/floor_trap.tscn",
    "tests/test_environment_visual_contract.gd",
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git_bytes(path):
    return subprocess.check_output(["git", "show", f"{BASE}:{path}"], cwd=ROOT)


baseline = json.loads((REPORT / "baseline.json").read_text(encoding="utf-8"))
actual_changes = {item["path"] for item in baseline["files"]
                  if sha(ROOT / item["path"]) != item["sha256"]}
assert actual_changes == CHANGED, actual_changes
protected = [item for item in baseline["files"]
             if item["path"] == "scenes/demo/main_menu.tscn"
             or item["path"].startswith("docs/art/battlefield-reference-03-20261017/")]
assert len(protected) == 33
assert all(sha(ROOT / p["path"]) == p["sha256"] for p in protected)

archive = ROOT / "docs/CODEX_HANDOFF.history-20261107.md"
assert archive.read_bytes() == (REPORT / "previous-handoff.bytes").read_bytes()
assert archive.read_text(encoding="utf-8") == git_bytes("docs/CODEX_HANDOFF.md").decode("utf-8").replace("\r\n", "\n")
history = (ROOT / "docs/HISTORY.md").read_text(encoding="utf-8")
assert "(CODEX_HANDOFF.history-20261107.md)" in history

entry_docs = {"AGENTS.md": 5000, "docs/CODEX_HANDOFF.md": 2500,
              "docs/PROJECT_CONTEXT.md": 3500, "docs/CODEX_WORKFLOW.md": 4500}
volumes = {}
for name, limit in entry_docs.items():
    before = git_bytes(name).decode("utf-8").replace("\r\n", "\n")
    after = (ROOT / name).read_text(encoding="utf-8")
    volumes[name] = {"before_lf_chars": len(before), "after_lf_chars": len(after), "limit": limit}
    if len(after) > limit:
        assert after == before
        volumes[name]["reason"] = "Pre-existing excess; unchanged routing document, no scope expansion."
    assert len(after) <= len(before) * 1.1
    if name != "docs/CODEX_HANDOFF.md":
        assert after == before

art_name = "docs/ART_DIRECTION.md"
style_header = "## Зафиксированная стилистика персонажей — 2026-11-03"
def style(text):
    return text.split(style_header, 1)[1].split("\n## ", 1)[0]
assert style((ROOT / art_name).read_text(encoding="utf-8")) == style(git_bytes(art_name).decode("utf-8").replace("\r\n", "\n"))

handoff = (ROOT / "docs/CODEX_HANDOFF.md").read_text(encoding="utf-8")
for rule in ["core/preview/queue/RNG/save/frozen", "5 классов F5", "каталоги1–3",
             "PLAYER вправо/ENEMY влево", "не reset/stage/commit", "root import",
             "служб/драйверов", "принудительного фокуса", "push/sidebar tasks/расписаний",
             "побайтно отдельно+HISTORY", "полный промпт", "Чат автоматически не создавать",
             "presentation_foundation141/2", "turn_forecast_ui26/3", "HUD/Колода"]:
    assert rule in handoff, rule

link_sources = {
    ROOT / "docs/CODEX_HANDOFF.md": handoff,
    ROOT / "docs/HISTORY.md": history.split("## Резкие шипы в игре", 1)[0],
    ROOT / "docs/art/spike-tile-fit-20261107/README.md": (ROOT / "docs/art/spike-tile-fit-20261107/README.md").read_text(encoding="utf-8"),
}
links = []
for path, content in link_sources.items():
    for target in re.findall(r"\]\(([^)]+)\)", content):
        if "://" in target:
            continue
        target_path, _, anchor = target.partition("#")
        resolved = (path.parent / target_path).resolve()
        if resolved != REPORT / "validation.json":
            assert resolved.exists(), (path, target)
        if anchor:
            headings = re.findall(r"^#+ (.+)$", resolved.read_text(encoding="utf-8"), re.M)
            slugs = [re.sub(r"[^\w\- ]", "", h.lower()).replace(" ", "-") for h in headings]
            assert anchor in slugs, (target, slugs)
        links.append({"from": path.relative_to(ROOT).as_posix(), "target": target})

review = json.loads((REPORT / "review.json").read_text(encoding="utf-8"))
assert review["verdict"] == "APPROVE"
manifest = {item["path"]: item["sha256"] for item in json.loads((GPU / "manifest.json").read_text(encoding="utf-8"))}
for name in CHANGED:
    assert sha(ROOT / name) == review["files"][name]
    assert sha(ROOT / name) == manifest[name], name
timing = json.loads((GPU / "timing.json").read_text(encoding="utf-8"))
assert timing["summary"]["failed"] == 0
assert timing["summary"]["passed"] == 4
assert "56 passed, 0 failed" in (GPU / "environment_visual_contract.log").read_text(encoding="utf-8")
assert "118 passed, 0 failed" in (GPU / "hazards_ui.log").read_text(encoding="utf-8")
subprocess.run(["git", "diff", "--check"], cwd=ROOT, check=True)
result = {
    "status": "PASS", "base": BASE, "baseline_files": len(baseline["files"]),
    "preserved_files": len(baseline["files"]) - len(actual_changes),
    "intentional_changes": sorted(actual_changes), "protected_files": len(protected),
    "archive_sha256": sha(archive), "entry_docs": volumes,
    "links": links, "character_style_preserved": True, "handoff_rules_preserved": True,
    "isolated_source_hashes_match": True, "gpu_report": GPU.relative_to(ROOT).as_posix(),
    "tests": {"environment_visual_contract": "56/0", "hazards_ui": "118/0"},
    "review": review["verdict"], "full_core_manual_repeated": False,
}
(REPORT / "validation.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
assert all((ROOT / item["from"]).parent.joinpath(item["target"].split("#", 1)[0]).exists() for item in links)
print(f"PASS: {result['preserved_files']} preserved, {len(protected)} protected, {len(links)} links, byte-exact archive")
