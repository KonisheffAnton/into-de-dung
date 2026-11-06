"""Validate source preservation, scoped GPU evidence and closeout documents."""
from pathlib import Path
import hashlib
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
BASE = "f948431d9d2fe61ba6a1c053a93ce828937d3f6a"
RUNS = [ROOT / "test_reports/demo-8c114d2156bf48e2b049f71d2dea6dd7",
        ROOT / "test_reports/demo-30d91f2cd58e4e44b203f82c436f24b8"]
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
def read(path):
    return json.loads(path.read_text(encoding="utf-8"))
def before(name):
    return subprocess.check_output(["git", "show", f"{BASE}:{name}"], cwd=ROOT).decode("utf-8").replace("\r\n", "\n")

review = read(HERE / "review.json")
assert review["verdict"] == "APPROVE"
for path, expected in review["files"].items():
    assert sha(ROOT / path) == expected, path
baseline = read(HERE / "baseline.json")["files"]
changed = [item["path"] for item in baseline if sha(ROOT / item["path"]) != item["sha256"]]
assert len(changed) == 8 and set(changed) <= set(review["files"]), changed
protected = [item for item in baseline if item["path"] == "scenes/demo/main_menu.tscn"
             or item["path"].startswith("docs/art/battlefield-reference-03-20261017/")]
assert len(protected) == 33
assert all(sha(ROOT / item["path"]) == item["sha256"] for item in protected)
archive = ROOT / "docs/CODEX_HANDOFF.history-20261107-2.md"
assert archive.read_bytes() == (HERE / "previous-handoff.bytes").read_bytes()
assert archive.read_text(encoding="utf-8") == before("docs/CODEX_HANDOFF.md")

manifests = [{row["path"]: row["sha256"] for row in read(run / "manifest.json")} for run in RUNS]
for name, expected in review["files"].items():
    index = 1 if name == "tests/test_dungeon_room_comparison.gd" else 0
    assert manifests[index][name] == expected, name
checks = {}
for run in RUNS:
    for name, value in read(run / "timing.json")["checks"].items():
        checks[name] = value["status"]
assert set(checks.values()) == {"PASS"}, checks
assert len(checks) == 8
imported = RUNS[1] / "project/assets/art_presets/approved/fire29_selected_v1"
imports = list(imported.glob("fire29_atlas_*.png.import"))
assert len(imports) == 6 and all("mipmaps/generate=false" in p.read_text(encoding="utf-8") for p in imports)

volumes = {}
for name, limit in {"AGENTS.md": 5000, "docs/CODEX_HANDOFF.md": 2500,
                    "docs/PROJECT_CONTEXT.md": 3500, "docs/CODEX_WORKFLOW.md": 4500}.items():
    old, new = before(name), (ROOT / name).read_text(encoding="utf-8")
    volumes[name] = {"before_lf_chars": len(old), "after_lf_chars": len(new), "limit": limit}
    assert len(new) <= len(old) * 1.1
    if name != "docs/CODEX_HANDOFF.md": assert new == old
    if len(new) > limit:
        assert new == old
        volumes[name]["reason"] = "Existing unchanged routing document exceeds guideline."
style = "## Зафиксированная стилистика персонажей — 2026-11-03"
old_style = before("docs/ART_DIRECTION.md").split(style)[1].split("\n## ")[0]
new_style = (ROOT / "docs/ART_DIRECTION.md").read_text(encoding="utf-8").split(style)[1].split("\n## ")[0]
assert old_style == new_style
handoff = (ROOT / "docs/CODEX_HANDOFF.md").read_text(encoding="utf-8")
for rule in ["core/preview/queue/RNG/save/frozen", "5 классов F5", "каталоги1–3", "не reset/stage/commit",
             "PLAYER вправо/ENEMY влево", "root import", "служб/драйверов", "принудительного фокуса",
             "push/sidebar tasks/расписаний", "побайтно отдельно+HISTORY", "полный промпт",
             "Чат автоматически не создавать", "presentation_foundation141/2", "turn_forecast_ui26/3", "HUD/Колода"]:
    assert rule in handoff, rule
links = []
for name in ["docs/CODEX_HANDOFF.md", "docs/art/spike-flush-20261107/README.md", "docs/art/fire29-integration-20261107/README.md"]:
    path = ROOT / name
    for link in re.findall(r"\]\(([^)]+)\)", path.read_text(encoding="utf-8")):
        target, _, anchor = link.partition("#")
        resolved = (path.parent / target).resolve()
        if resolved != HERE / "validation.json": assert resolved.exists(), (name, link)
        if anchor:
            headings = re.findall(r"^#+ (.+)$", resolved.read_text(encoding="utf-8"), re.M)
            assert anchor in [re.sub(r"[^\w\- ]", "", h.lower()).replace(" ", "-") for h in headings]
        links.append({"from": name, "target": link})
assert "(CODEX_HANDOFF.history-20261107-2.md)" in (ROOT / "docs/HISTORY.md").read_text(encoding="utf-8")
subprocess.run(["git", "diff", "--check"], cwd=ROOT, check=True)
result = {"status": "PASS", "base": BASE, "preserved_files": len(baseline)-len(changed),
          "intentional_baseline_changes": changed, "protected_files": len(protected), "reviewed_files": review["files"],
          "archive_sha256": sha(archive), "entry_docs": volumes, "links": links,
          "character_style_preserved": True, "handoff_rules_preserved": True,
          "latest_scoped_gpu_checks": checks, "six_atlas_mipmaps_disabled": True,
          "no_full_core_manual_or_stable_fps_claim": True}
(HERE / "validation.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"PASS: preserved{result['preserved_files']}, protected33, links{len(links)}, exact archive, eight scoped GPU gates")
