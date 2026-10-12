"""Measure original PNGs and build a size comparison; never rewrite source pixels."""
from pathlib import Path
from PIL import Image
import base64
import hashlib
import json

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[2]
SOURCES = {
    "defender": REPO / "assets/art_presets/trials/defender_field_v1/defender_new.png",
    "archer": ROOT / "archer-clean.png",
}
records = {}
for name, path in SOURCES.items():
    with Image.open(path) as img:
        rgba = img.convert("RGBA")
        alpha = rgba.getchannel("A")
        bbox = alpha.point(lambda v: 255 if v >= 128 else 0).getbbox()
        assert bbox and alpha.getextrema() == (0, 255)
        records[name] = {"path": path.relative_to(REPO).as_posix(),
                         "size": list(img.size), "alpha_bbox_128": list(bbox),
                         "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}

# The current Defender scene displays its 966px crop at this uniform scale.
defender_height = 966 * 0.0745342 * 0.8
records["defender"]["display_height"] = defender_height
records["archer"]["display_height"] = defender_height * 0.9
records["ratio"] = 0.9
records["measurement"] = "full silhouette height including hair; alpha >= 128; uniform scaling"
records["scope"] = "offline comparison only; no game integration; original RGBA preserved"

def figure(name, zoom):
    rec = records[name]
    left, top, right, bottom = rec["alpha_bbox_128"]
    scale = rec["display_height"] * zoom / (bottom - top)
    width, height = rec["size"]
    uri = "data:image/png;base64," + base64.b64encode(SOURCES[name].read_bytes()).decode()
    return (f'<div class="crop" style="width:{(right-left)*scale}px;height:{(bottom-top)*scale}px">'
            f'<img src="{uri}" style="width:{width*scale}px;height:{height*scale}px;'
            f'left:{-left*scale}px;top:{-top*scale}px"></div>')

panels = []
for zoom, label in [(5, "Увеличение ×5"), (1, "Условный игровой размер ×1")]:
    columns = []
    for name, title in [("defender", "Защитник · 100%"), ("archer", "Лучница · 90%")]:
        columns.append(f'<div class="column"><div class="stage" style="height:{defender_height*zoom+16}px">'
                       f'{figure(name, zoom)}</div><p>{title}</p></div>')
    panels.append(f'<section><h2>{label}</h2><div class="row">{"".join(columns)}</div></section>')
html = '''<!doctype html><html lang="ru"><meta charset="utf-8"><title>Лучница — сравнение размера</title>
<style>*{box-sizing:border-box}body{margin:0;padding:30px;background:#25292a;color:#eee9dc;
font:16px Arial,sans-serif;width:940px}h1{font-size:26px;margin:0 0 8px}h2{font-size:16px;color:#bebcae;
margin:16px 0 8px}p{margin:12px 0}.note{color:#bebcae;font-size:14px;line-height:1.5}
.row{display:flex;gap:20px}.column{width:420px;text-align:center}.stage{display:flex;align-items:flex-end;
justify-content:center;border-bottom:1px solid #8c9684;background:#343b35}.crop{position:relative;overflow:hidden;
flex-shrink:0}.crop img{position:absolute;max-width:none;image-rendering:pixelated}</style>
<h1>Лучница и текущий Защитник</h1><div class="note">Высота полного силуэта лучницы — ровно 90% высоты Защитника.
Пропорции сохранены; нижние границы выровнены для сравнения.</div>'''
html += "".join(panels)
html += ('<p class="note">Уменьшение задано только масштабом показа. Исходные PNG не перерисованы этим сравнением.'
         '<br>Это отдельная визуальная проба, не кадр Godot и не проверка посадки на клетку.</p></html>')
(ROOT / "comparison.html").write_text(html, encoding="utf-8")
(ROOT / "manifest.json").write_text(json.dumps(records, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
assert abs(records["archer"]["display_height"] / defender_height - 0.9) < 1e-12
print(json.dumps(records, ensure_ascii=False))
