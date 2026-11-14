"""Строит контактные листы и галерею до/после из исходных PNG ремонта."""
from pathlib import Path
import base64
import json

from PIL import Image, ImageDraw, ImageFont
from selected_outputs import resolve_selected

ROOT = Path(__file__).resolve().parent
BG = "#182131"


def font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
	for path in (Path("C:/Windows/Fonts/arial.ttf"), Path("C:/Windows/Fonts/segoeui.ttf")):
		if path.is_file():
			return ImageFont.truetype(str(path), size=size)
	return ImageFont.load_default()


def render(image_path: Path) -> Image.Image:
	with Image.open(image_path) as source:
		image = source.convert("RGBA")
	background = Image.new("RGBA", image.size, BG)
	background.alpha_composite(image)
	return background.convert("RGB")


def contact_sheet(items: list[dict], scale: int) -> Image.Image:
	columns, rows = 5, 2
	cell, label = 256 * scale, 42 * scale
	out = Image.new("RGB", (columns * cell, rows * (cell + label)), BG)
	draw = ImageDraw.Draw(out)
	label_font = font(18 * scale)
	for index, item in enumerate(items):
		x, y = index % columns * cell, index // columns * (cell + label)
		image = render(ROOT / item["file"])
		if scale != 1:
			image = image.resize((cell, cell), Image.Resampling.NEAREST)
		draw.text((x + 8 * scale, y + 5 * scale), f"{item['id']:02d} · {item['name']} · {item['final_height']}px",
			fill="#f0d6a1", font=label_font)
		out.paste(image, (x, y + label))
	return out


def before_after_sheet(items: list[dict]) -> Image.Image:
	# Пять пар на ряд; оба изображения остаются в исходных пикселях 256×256.
	columns, rows, label_height = 5, 2, 30
	out = Image.new("RGB", (columns * 512, rows * (256 + label_height)), BG)
	draw = ImageDraw.Draw(out)
	label_font = font(15)
	for index, item in enumerate(items):
		x, y = index % columns * 512, index // columns * (256 + label_height)
		draw.text((x + 5, y + 5), f"{item['id']:02d} · {item['name']} · {item.get('before_height', item['source_height'])}→{item['final_height']}px",
			fill="#f0d6a1", font=label_font)
		out.paste(render(ROOT / item["before_file"]), (x, y + label_height))
		out.paste(render(ROOT / item["file"]), (x + 256, y + label_height))
	return out


def style_compare(items: list[dict], reference_file: str) -> Image.Image:
	# Ref warrior and all repaired variants share the same 256×256 canvas scale.
	ordered = [{"id": 0, "name": "Воин 11", "file": reference_file, "height": 152}, *items]
	columns, cell_h = 4, 286
	out = Image.new("RGB", (columns * 256, 3 * cell_h), BG)
	draw = ImageDraw.Draw(out)
	label_font = font(15)
	for index, item in enumerate(ordered):
		x, y = index % columns * 256, index // columns * cell_h
		height = item.get("final_height", item.get("height", 0))
		draw.text((x + 5, y + 4), f"{item['id']:02d} · {item['name']} · {height}px", fill="#f0d6a1", font=label_font)
		out.paste(render(ROOT / item["file"]), (x, y + 26))
	return out


def main() -> None:
	manifest = json.loads((ROOT / "sources.json").read_text(encoding="utf-8-sig"))
	if not manifest.get("complete") or len(manifest.get("variants", [])) != 10:
		raise SystemExit("Need ten completed repairs before building gallery")
	items = resolve_selected(manifest, ROOT)
	for item in items:
		item["before_file"] = item["input_file"]
		item["before_height"] = item["source_height"]
	contact_sheet(items, 2).save(ROOT / "contact-sheet.png")
	contact_sheet(items, 1).save(ROOT / "contact-sheet-small.png")
	before_after_sheet(items).save(ROOT / "before-after-sheet.png")
	style_compare(items, "references/warrior11.png").save(ROOT / "style-compare.png")
	assets: dict[str, str] = {}
	for item in items:
		for key in ("before_file", "file"):
			path = ROOT / item[key]
			assets[item[key]] = "data:image/png;base64," + base64.b64encode(path.read_bytes()).decode("ascii")
	ref = "references/warrior11.png"
	assets[ref] = "data:image/png;base64," + base64.b64encode((ROOT / ref).read_bytes()).decode("ascii")
	cards = [{"id": item["id"], "name": item["name"], "before": item["before_file"], "after": item["file"],
		"source_height": item["before_height"], "final_height": item["final_height"],
		"additional_style_pass": item.get("additional_style_pass", False)} for item in items]
	template = r'''<!doctype html><html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Ремонт десяти хобгоблинов · до и после</title><style>
*{box-sizing:border-box}body{margin:0;background:#111923;color:#edf2f7;font:16px/1.45 system-ui,sans-serif}header{padding:18px 22px;background:#202c3b;position:sticky;top:0;z-index:2}h1{font-size:24px;margin:0 0 8px}.controls{display:flex;gap:9px;flex-wrap:wrap;align-items:center}button,select{background:#34475d;color:#fff;border:1px solid #72859a;border-radius:5px;padding:8px 11px;cursor:pointer}main{max-width:1500px;margin:auto;padding:18px}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(230px,1fr));gap:14px}.card{background:#202c3b;border:1px solid #3b4d62;border-radius:8px;padding:10px}.card h2{margin:3px 0 6px;font-size:18px}.metric{font-size:13px;color:#d8c9a8;margin:0 0 8px}.board{background:var(--tile,#182131);display:grid;place-items:center;min-height:240px;border-radius:4px}.board.check{background-color:#4e5966;background-image:conic-gradient(#303a45 25%,transparent 0 50%,#303a45 0 75%,transparent 0);background-size:24px 24px}.board.light{background:#ded4ba}.board img{width:100%;height:auto;object-fit:contain;image-rendering:pixelated;cursor:zoom-in}.actions{display:flex;gap:8px;flex-wrap:wrap}.actions a{color:#f0d6a1;font-size:13px}dialog{border:1px solid #718196;border-radius:8px;background:#101720;color:white;max-width:95vw;max-height:95vh;padding:12px}dialog::backdrop{background:#000b}dialog img{display:block;width:min(70vh,80vw,768px);height:auto;max-width:80vw;max-height:80vh;image-rendering:pixelated;object-fit:contain}dialog button{margin-top:8px}#reference{max-width:280px}.note{color:#bdc9d6;font-size:14px}.sheets{display:flex;gap:12px;flex-wrap:wrap;margin-top:22px}.sheets figure{margin:0}.sheets img{max-width:100%;height:auto;background:#182131}.sheets figcaption{margin:5px 0}@media(max-width:650px){header{position:static}main{padding:10px}.grid{grid-template-columns:repeat(2,minmax(0,1fr))}.board{min-height:190px}}@media(max-width:410px){.grid{grid-template-columns:1fr}}
</style></head><body><header><h1>Ремонт десяти хобгоблинов · до и после</h1><div class="controls"><button id="globalToggle">Показать: до</button><label for="back">Фон:</label><select id="back"><option value="dark">Тёмный</option><option value="light">Светлый</option><option value="check">Шахматный</option></select><button id="refToggle">Образец стиля · Воин 11</button></div></header><main><p class="note">PixelLab дополнил головы и ступни, добавил крупные волдыри и более звериные черты. Сгорбленный облик сохранён. Новые контуры прибавили 4–8 пикселей высоты без масштабирования. У №8 чище прорисовка и более глубокое приседание. Переключайте «до / после», чтобы сравнить с прежней десяткой.</p><div id="reference" class="card" hidden><h2>Воин 11 · образец стиля</h2><div class="board"><img src="__REF__" alt="Воин 11, образец стиля"></div></div><div id="grid" class="grid"></div><div class="sheets"><figure><figcaption>Результаты · увеличение 2×</figcaption><img src="__SHEET__" alt="Десять результатов ремонта"></figure><figure><figcaption>Результаты · масштаб 1×</figcaption><img src="__SMALL__" alt="Десять результатов при масштабе 1×"></figure><figure><figcaption>До/после · каждая пара использует нативные PNG 256×256</figcaption><img src="__PAIRS__" alt="Пары исходник и результат"></figure><figure><figcaption>Стиль · Воин 11 и десять результатов в одинаковом масштабе 256×256</figcaption><img src="__COMPARE__" alt="Сравнение пиксельного стиля в нативных холстах"></figure></div><dialog id="viewer"><img id="large" alt="Увеличенное изображение"><button id="close">Закрыть</button></dialog></main><script>
"use strict";const ASSETS=__ASSETS__,CARDS=__CARDS__;let showAfter=true;const individual={};const grid=document.querySelector('#grid'),dlg=document.querySelector('#viewer'),large=document.querySelector('#large');function update(c,img,button){const state=individual[c.id]??showAfter;const path=state?c.after:c.before;img.src=ASSETS[path];img.alt=`${state?'После':'До'} · ${c.name}`;button.textContent=state?'До':'После'}for(const c of CARDS){grid.insertAdjacentHTML('beforeend',`<article class="card"><h2>${String(c.id).padStart(2,'0')} · ${c.name}</h2><p class="metric" data-metric="${c.id}"></p><div class="board"><img data-img="${c.id}" data-id="${c.id}" alt=""></div><div class="actions"><button data-toggle="${c.id}">До</button><a href="${ASSETS[c.before]}" download="hobgoblin-${String(c.id).padStart(2,'0')}-before.png">Исходник</a><a href="${ASSETS[c.after]}" download="hobgoblin-${String(c.id).padStart(2,'0')}-after.png">Результат</a></div></article>`)}for(const c of CARDS){let img=document.querySelector(`[data-img="${c.id}"]`),btn=document.querySelector(`[data-toggle="${c.id}"]`);document.querySelector(`[data-metric="${c.id}"]`).textContent=`До ${c.source_height}px → после ${c.final_height}px${c.additional_style_pass?" · обновлённая прорисовка":""}`;update(c,img,btn);btn.onclick=()=>{individual[c.id]=!(individual[c.id]??showAfter);update(c,img,btn)}}document.querySelector('#globalToggle').onclick=()=>{showAfter=!showAfter;for(const c of CARDS){individual[c.id]=showAfter;update(c,document.querySelector(`[data-img="${c.id}"]`),document.querySelector(`[data-toggle="${c.id}"]`))};document.querySelector('#globalToggle').textContent=showAfter?'Показать: до':'Показать: после'};grid.addEventListener('click',e=>{const img=e.target.closest('img[data-id]');if(!img)return;large.src=img.src;large.alt=img.alt;dlg.showModal()});document.querySelector('#close').onclick=()=>dlg.close();dlg.addEventListener('click',e=>{if(e.target===dlg)dlg.close()});document.querySelector('#back').onchange=e=>document.querySelectorAll('.board').forEach(el=>el.className='board '+(e.target.value==='dark'?'':e.target.value));document.querySelector('#refToggle').onclick=()=>{let e=document.querySelector('#reference');e.hidden=!e.hidden};window.__galleryState=()=>({cards:CARDS.length,embeddedImages:Object.keys(ASSETS).length,after:showAfter});
</script></body></html>'''
	page = (template.replace("__ASSETS__", json.dumps(assets, separators=(",", ":")))
		.replace("__CARDS__", json.dumps(cards, ensure_ascii=False, separators=(",", ":")))
		.replace("__REF__", assets[ref])
		.replace("__SHEET__", "data:image/png;base64," + base64.b64encode((ROOT / "contact-sheet.png").read_bytes()).decode("ascii"))
		.replace("__SMALL__", "data:image/png;base64," + base64.b64encode((ROOT / "contact-sheet-small.png").read_bytes()).decode("ascii"))
		.replace("__PAIRS__", "data:image/png;base64," + base64.b64encode((ROOT / "before-after-sheet.png").read_bytes()).decode("ascii"))
		.replace("__COMPARE__", "data:image/png;base64," + base64.b64encode((ROOT / "style-compare.png").read_bytes()).decode("ascii")))
	(ROOT / "gallery.html").write_text(page, encoding="utf-8")
	print(json.dumps({"cards": len(cards), "embedded_before_after_reference": len(assets), "html_bytes": (ROOT / "gallery.html").stat().st_size}))


if __name__ == "__main__":
	main()
