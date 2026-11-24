"""Prepare numbered layouts from unchanged provider outputs; no sprite retouching."""
from pathlib import Path
import json
import shutil

ROOT = Path(__file__).resolve().parent
PREVIOUS = ROOT.parent / "bones-twenty-next-20261123"

def main():
    source_rows = json.loads((ROOT / "imagegen-sources.json").read_text(encoding="utf-8-sig"))
    correction = json.loads((ROOT / "g46-regeneration.json").read_text(encoding="utf-8"))
    shutil.copyfile(correction["cleanup_source"], ROOT / "imagegen/G46-cleanup-attempt.png")
    shutil.copyfile(correction["replacement_source"], ROOT / "imagegen/G46-final.png")
    for row in source_rows:
        if row["id"] == "G46" and "initial_source" not in row:
            row["initial_source"] = row["source"]
            row["initial_destination"] = row["destination"]
            row["source"] = correction["replacement_source"]
            row["destination"] = "imagegen/G46-final.png"
    (ROOT / "imagegen-sources.json").write_text(json.dumps(source_rows, indent=2) + "\n", encoding="utf-8")
    selection = {r["id"]: r["destination"] for r in source_rows}
    indices = [0, 1, 2, 3, 5, 7, 9, 10, 12, 14]
    for number, index in enumerate(indices, 49):
        filename = f"image-{index}.png" if index else "image.png"
        selection[f"PL{number}"] = "pixellab/ribs-skull/" + filename
    (ROOT / "selection.json").write_text(json.dumps(selection, indent=2) + "\n", encoding="utf-8")
    for filename in ("build_preview.py",):
        text = (PREVIOUS / filename).read_text(encoding="utf-8")
        text = text.replace("PL39–PL48", "PL49–PL58").replace("G31–G40", "G41–G50")
        text = text.replace("index + 39", "index + 49").replace("index + 31", "index + 41")
        text = text.replace("range(31, 41)", "range(41, 51)").replace("range(39, 49)", "range(49, 59)")
        text = text.replace("Разные мелкие кости внутри каждой кучки · без черепов", "Мелкие кости · элементы рёбер · едва заметный фрагмент черепа")
        text = text.replace('"runtime_changed": False, "godot_run": False,', '"production_runtime_changed_by_this_task": False, "godot_evidence": "runtime-check.json and capture-all.json",')
        (ROOT / filename).write_text(text, encoding="utf-8")

if __name__ == "__main__":
    main()
