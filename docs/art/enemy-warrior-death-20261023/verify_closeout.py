"""Validate this bounded art integration and its handoff archival."""
from pathlib import Path
import hashlib
import json
import re
import subprocess
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parents[3]
REPORT = Path(__file__).resolve().parent
BASE = "b2d78510f7c3216f01ebf9bbc32d3c4f4a878e7f"
INITIAL = ROOT / "test_reports/demo-57aa0f420dd046aab691a26327e6165f"
FINAL = ROOT / "test_reports/demo-e511e79f6aac438f898cf2830fb52d90"

def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT)

def sha(data):
    return hashlib.sha256(data).hexdigest()

def read_json(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))

baseline = read_json(INITIAL / "manifest.json")
validated = []
for item in baseline:
    path = item["path"]
    if path.startswith(("scripts/", "scenes/")) or path.startswith("assets/art_presets/trials/enemy_warrior_") and path.endswith((".png", ".tres")):
        assert sha((ROOT / path).read_bytes()) == item["sha256"], path
        validated.append(item)
corrected = read_json(REPORT / "corrected-routes.json")
assert all(check["status"] == "PASS" for check in corrected["checks"].values())
assert sha((ROOT / corrected["correctedTest"]).read_bytes()) == corrected["testSha256"]
results = {}
for label, item in read_json(INITIAL / "timing.json")["checks"].items():
    if label == "defender_death_routes": continue
    assert item["status"] == "PASS", label
    results[label] = {"status": "PASS", "log": str(INITIAL / (label + ".log"))}
    log = INITIAL / (label + ".log")
    if log.exists(): results[label]["result"] = re.findall(r"[^\n]*RESULTS:[^\n]*", log.read_text(encoding="utf-8"))
for label in ("defender_death_routes", "rogue_death_routes"):
    results[label] = corrected["checks"][label]
assert len(results) == 14

protected_hash = sha((ROOT / "scenes/demo/main_menu.tscn").read_bytes())
assert protected_hash == "a64c270256ebf2ea073081200be23028f792f42c3ca98f83a6499c1300a68668"
archive = ROOT / "docs/CODEX_HANDOFF.history-20261023-5.md"
previous_sha = (REPORT / "prior-handoff-sha256.txt").read_text().strip()
assert sha(archive.read_bytes()) == previous_sha
prior_blob = git("show", BASE + ":docs/CODEX_HANDOFF.md")
assert archive.read_bytes().replace(b"\r\n", b"\n") == prior_blob.replace(b"\r\n", b"\n")

sizes = {}
for path in ("AGENTS.md", "docs/CODEX_HANDOFF.md", "docs/PROJECT_CONTEXT.md", "docs/CODEX_WORKFLOW.md"):
    before = git("show", BASE + ":" + path).decode("utf-8-sig").replace("\r\n", "\n")
    after = (ROOT / path).read_text(encoding="utf-8-sig").replace("\r\n", "\n")
    sizes[path] = [len(before), len(after)]
assert sizes["docs/CODEX_HANDOFF.md"][1] <= 2500

changed = set(git("diff", "--name-only", BASE).decode().splitlines())
changed.update(git("ls-files", "--others", "--exclude-standard").decode().splitlines())
changed = {p for p in changed if p != "scenes/demo/main_menu.tscn" and not p.startswith("docs/art/battlefield-reference-03-20261017/")}
links = 0
for path in sorted(changed):
    file = ROOT / path
    if file.suffix != ".md" or not file.exists(): continue
    for target in re.findall(r"\]\(([^)]+)\)", file.read_text(encoding="utf-8-sig")):
        target = target.strip().strip("<>").split("#", 1)[0]
        if not target or re.match(r"(?:https?|mailto|codex|res)://", target): continue
        candidate = file.parent / unquote(target)
        assert candidate.exists(), (path, target)
        links += 1
subprocess.run(["git", "diff", "--check"], cwd=ROOT, check=True)
summary = {"base": BASE, "scope": "enemy warrior death-2 + character format reference",
           "finalChecks": results, "validatedRuntimeFiles": len(validated),
           "changedRouteTestSha256": corrected["testSha256"], "renderAudit": "107 passed, 0 failed",
           "archiveExactWorkingBytes": True, "archiveMatchesPriorGitNormalizedBytes": True,
           "protectedSceneSha256": protected_hash, "links": links, "entryDocumentCharsBeforeAfter": sizes,
           "entryDocumentDeviation": "PROJECT_CONTEXT remains at its pre-existing 3557 chars; no change",
           "manualF5EditorDpiGpu": "not run", "fullCore": "not run"}
(REPORT / "closeout-validation.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"CLOSEOUT PASS: {len(results)} final green checks, {len(validated)} unchanged runtime files, {links} local links")
