"""Artifact checks for the selected twenty concepts; no game import or mutation."""
from pathlib import Path
import hashlib
import json
from PIL import Image

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[2]


def read(name):
    return json.loads((ROOT / name).read_text(encoding="utf-8-sig"))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    selections = read("selection.json")
    assert set(selections) == {f"G{i}" for i in range(31, 41)} | {f"PL{i}" for i in range(39, 49)}
    rows = []
    for name, source in selections.items():
        path = ROOT / source
        im = Image.open(path)
        assert im.mode == "RGBA", name
        alpha = im.getchannel("A")
        low, high = alpha.getextrema()
        assert low == 0 and high >= 128, (name, low, high)
        bbox = alpha.point(lambda a: 255 if a >= 128 else 0).getbbox()
        assert bbox and bbox[0] > 0 and bbox[1] > 0 and bbox[2] < im.width and bbox[3] < im.height
        visible_colors = {rgb for rgb in im.getdata() if rgb[3] >= 128}
        if name.startswith("PL"):
            assert im.size == (64, 64), name
        rows.append({"id": name, "source": source, "size": list(im.size), "sha256": sha(path),
                     "alpha_extrema": [low, high], "alpha_128_bbox": bbox,
                     "visible_rgba_colors": len(visible_colors)})
    assert len({r["sha256"] for r in rows}) == 20, "Repeated selected source files"
    for row in read("imagegen-sources.json"):
        assert sha(Path(row["source"])) == sha(ROOT / row["destination"]), row["id"]
    for path, expected in read("protected-hashes.json").items():
        assert sha(REPO / path) == expected, path
    for name in ("imagegen-ten.png", "pixellab-ten.png"):
        assert Image.open(ROOT / name).size == (1400, 740)
    report = {"result": "PASS", "selected_count": 20, "unique_files": 20,
              "imagegen_original_copies_byte_exact": True, "protected_files_unchanged": True,
              "runtime_changed": False, "godot_run": False,
              "art_acceptance": "pending user choice", "assets": rows}
    (ROOT / "verification.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("PASS: twenty distinct RGBA files, transparent margins, source copies and protected hashes")


if __name__ == "__main__":
    main()
