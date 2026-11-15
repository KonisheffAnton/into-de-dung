"""Показ готового редактирования одежды; исходные PNG не меняются."""
from pathlib import Path
import hashlib
import json
import runpy

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent
helpers = runpy.run_path(str(ROOT.parent / "kostyash-warrior-style-two-20261115/build_comparison.py"))
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
generation = json.loads((ROOT / "generation.json").read_text(encoding="utf-8-sig"))
references = json.loads((ROOT / "references.json").read_text(encoding="utf-8-sig"))
expected = {r["file"]: r["sha256"] for r in references}
expected[generation["file"]] = generation["sha256"]
for file, digest in expected.items():
    assert sha(ROOT / file) == digest, file
assert hashlib.sha256((ROOT / generation["prompt_file"]).read_text(encoding="utf-8-sig").encode()).hexdigest() == generation["prompt_sha256"]
entries = [("references/original.png", "Рваноух · раньше", 304),
           ("references/warrior11.png", "Воин 11", 456),
           (generation["file"], "Рваноух · рваная одежда", 304)]
sheet = Image.new("RGBA", (1320, 640), helpers["BG"])
draw = ImageDraw.Draw(sheet)
draw.line((18, 550, 1302, 550), fill="#4e6179", width=2)
records = []
for index, (file, label, height) in enumerate(entries):
    image = helpers["load_png"](ROOT / file)
    _, native = helpers["bounds"](image)
    rendered, box, native_height = helpers["fit"](image, height)
    left = index * 440 + (440 - (box[2] - box[0])) // 2
    assert left >= index * 440 and left + box[2] - box[0] <= (index + 1) * 440
    assert box[3] - box[1] == height
    sheet.alpha_composite(rendered, (left - box[0], 550 - box[3]))
    draw.text((index * 440 + 220, 23), label, font=helpers["font"](21), fill="#f4d18e", anchor="mt")
    draw.text((index * 440 + 220, 49), "Эталон" if height == 456 else "⅔ роста воина",
              font=helpers["font"](15), fill="#c8d2dd", anchor="mt")
    records.append({"file": file, "sha256": sha(ROOT / file), "visible_native_height": native_height,
                    "display_height": height, "display_bottom": 550, "visible_bbox": native})
draw.text((28, 596), "Выбранный Рваноух · до и после изменения одежды", font=helpers["font"](23), fill="#f4d18e")
sheet.convert("RGB").save(ROOT / "comparison.png")
for file, digest in expected.items():
    assert sha(ROOT / file) == digest, file
report = {"result": "PASS", "records": records, "hero_to_kostyash_ratio": 1.5,
          "source_pngs_unchanged": True, "presentation_only": True,
          "scope": "NN presentation, alpha>=8 height; warrior silhouette includes sword; no native/runtime claim."}
(ROOT / "validation.json").write_bytes((json.dumps(report, ensure_ascii=False, indent=2) + "\n").encode())
print("PASS: SHA, prompt, visible heights304/456/304, exact source preservation")
