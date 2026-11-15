"""Сравнение готовых Кривозуба и Тяжёлого лба с Воином без перерисовки."""
from pathlib import Path
import hashlib
import json
import runpy

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT.parent / "kostyash05-imagegen-five-20261115"
helpers = runpy.run_path(str(SOURCE / "build_comparison.py"))
manifest = json.loads((SOURCE / "generations.json").read_text(encoding="utf-8-sig"))
refs = json.loads((SOURCE / "references.json").read_text(encoding="utf-8-sig"))
variants = {v["id"]: v for v in manifest["variants"]}
warrior = next(v for v in refs if v["file"] == "references/warrior11.png")
entries = [
    ({**variants[5], "label": "05 · Кривозуб"}, 304),
    ({**warrior, "name": "Воин 11", "label": "Воин 11"}, 456),
    ({**variants[1], "label": "01 · Тяжёлый лоб"}, 304),
]
sheet = Image.new("RGBA", (1320, 640), helpers["BG"])
draw = ImageDraw.Draw(sheet)
draw.line((18, 550, 1302, 550), fill="#4e6179", width=2)
records = []
for column, (entry, height) in enumerate(entries):
    source = SOURCE / entry["file"]
    assert hashlib.sha256(source.read_bytes()).hexdigest() == entry["sha256"], source
    helpers["draw_cell"](sheet, draw, entry, column * 440, 0, 440, 550, height,
                         entry["label"], 22, helpers["font"](22), helpers["font"](15), records)
draw.text((30, 596), "Костяши — ⅔ роста воина", font=helpers["font"](24), fill="#f4d18e")
assert [r["display_visible_height"] for r in records] == [304, 456, 304]
assert all(r["display_baseline"] == 550 and not r["flags"] for r in records)
sheet.convert("RGB").save(ROOT / "comparison.png")
report = {"result": "PASS", "generation": False, "retouch": False,
          "source_package": SOURCE.name, "hero_to_kostyash_ratio": 1.5,
          "size": [1320, 640], "records": records,
          "scope": "Existing images, nearest-neighbor presentation only; alpha>=8 body height; no native or runtime scale claim."}
(ROOT / "validation.json").write_bytes((json.dumps(report, ensure_ascii=False, indent=2) + "\n").encode())
print("PASS: existing source SHA; heights304/456/304; common baseline550; no edge flags")
