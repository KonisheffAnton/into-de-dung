"""Строит contact sheets и автономную галерею исходных PNG-концептов."""
from pathlib import Path
import base64
import json

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
BG = "#182131"


def font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
	for path in (Path("C:/Windows/Fonts/arial.ttf"), Path("C:/Windows/Fonts/segoeui.ttf")):
		if path.is_file():
			return ImageFont.truetype(str(path), size=size)
	return ImageFont.load_default()


def contact_sheet(items: list[dict], scale: int, columns: int) -> Image.Image:
	cell_w = 256 * scale
	label_h = 44 * scale
	rows = (len(items) + columns - 1) // columns
	sheet = Image.new("RGB", (columns * cell_w, rows * (cell_w + label_h)), BG)
	draw = ImageDraw.Draw(sheet)
	label_font = font(18 * scale)
	for index, item in enumerate(items):
		x = index % columns * cell_w
		y = index // columns * (cell_w + label_h)
		image = Image.open(ROOT / item["file"]).convert("RGBA")
		if scale != 1:
			image = image.resize((cell_w, cell_w), Image.Resampling.NEAREST)
		background = Image.new("RGBA", image.size, BG)
		background.alpha_composite(image)
		sheet.paste(background.convert("RGB"), (x, y + label_h))
		draw.text((x + 8 * scale, y + 5 * scale), f"{item['id']:02d} · {item['name']}", fill="#f0d6a1", font=label_font)
	return sheet


def style_compare(items: list[dict], reference: dict) -> Image.Image:
	ordered = [{"id": 0, "name": "Воин 11", "file": reference["file"]}, *items]
	columns = 4
	cell_h = 286
	out = Image.new("RGB", (columns * 256, 3 * cell_h), BG)
	draw = ImageDraw.Draw(out)
	label_font = font(16)
	for index, item in enumerate(ordered):
		x = index % columns * 256
		y = index // columns * cell_h
		draw.text((x + 6, y + 5), f"{item['id']:02d} · {item['name']}", fill="#f0d6a1", font=label_font)
		image = Image.open(ROOT / item["file"]).convert("RGBA")
		background = Image.new("RGBA", (256, 256), BG)
		background.alpha_composite(image)
		out.paste(background.convert("RGB"), (x, y + 26))
	return out


def main() -> None:
	manifest = json.loads((ROOT / "sources.json").read_text(encoding="utf-8-sig"))
	if not manifest.get("complete") or len(manifest.get("variants", [])) != 10:
		raise SystemExit("Need ten completed PNG exports before building the gallery")
	items = manifest["variants"]
	reference_file = manifest["style_reference"]
	reference = {"id": 0, "name": "Воин 11", "file": reference_file}
	contact_sheet(items, scale=2, columns=5).save(ROOT / "contact-sheet.png")
	contact_sheet(items, scale=1, columns=5).save(ROOT / "contact-sheet-small.png")
	style_compare(items, reference).save(ROOT / "style-compare.png")
	assets = {}
	for item in items:
		path = ROOT / item["file"]
		assets[item["file"]] = "data:image/png;base64," + base64.b64encode(path.read_bytes()).decode("ascii")
	ref_path = ROOT / reference_file
	assets[reference_file] = "data:image/png;base64," + base64.b64encode(ref_path.read_bytes()).decode("ascii")
	cards = [{"id": item["id"], "name": item["name"], "file": item["file"]} for item in items]
	page = r'''<!doctype html><html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Десять бледных хобгоблинов</title><style>
*{box-sizing:border-box}body{margin:0;background:#111923;color:#edf2f7;font:16px/1.45 system-ui,sans-serif}header{padding:18px 22px;background:#202c3b;position:sticky;top:0;z-index:2}h1{font-size:24px;margin:0 0 6px}.controls{display:flex;gap:9px;flex-wrap:wrap;align-items:center}button,select{background:#34475d;color:#fff;border:1px solid #72859a;border-radius:5px;padding:8px 11px;cursor:pointer}main{max-width:1500px;margin:auto;padding:18px}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:14px}.card{background:#202c3b;border:1px solid #3b4d62;border-radius:8px;padding:10px}.card h2{margin:3px 0 8px;font-size:18px}.board{background:var(--tile,#182131);display:grid;place-items:center;min-height:220px;border-radius:4px}.board.check{background-color:#4e5966;background-image:conic-gradient(#303a45 25%,transparent 0 50%,#303a45 0 75%,transparent 0);background-size:24px 24px}.board.light{background:#ded4ba}.board img{width:100%;height:auto;object-fit:contain;image-rendering:pixelated;cursor:zoom-in}dialog{border:1px solid #718196;border-radius:8px;background:#101720;color:white;max-width:95vw;max-height:95vh;padding:12px}dialog::backdrop{background:#000b}dialog img{display:block;width:min(70vh,80vw,768px);height:auto;max-width:80vw;max-height:80vh;image-rendering:pixelated;object-fit:contain}dialog button{margin-top:8px}.note{color:#bdc9d6;font-size:14px}.ref{max-width:220px}.sheets{display:flex;gap:12px;flex-wrap:wrap;margin-top:22px}.sheets img{max-width:100%;height:auto;background:#182131}.sheets figure{margin:0}.sheets figcaption{margin:5px 0}@media(max-width:650px){header{position:static}main{padding:10px}.grid{grid-template-columns:repeat(2,minmax(0,1fr))}.board{min-height:170px}}@media(max-width:410px){.grid{grid-template-columns:1fr}}
</style></head><body><header><h1>Десять бледных хобгоблинов</h1><div class="controls"><label for="back">Фон:</label><select id="back"><option value="dark">Тёмный</option><option value="light">Светлый</option><option value="check">Шахматный</option></select><button id="refToggle">Показать образец стиля: Воин 11</button></div></header><main><p class="note">Десять отдельных PixelLab-концептов; игровой интеграции нет. Образец Воина используется только для сравнения пиксельного стиля. Нажмите на изображение, чтобы открыть его крупнее без обрезки.</p><div id="reference" class="card ref" hidden><h2>Воин 11 · образец стиля</h2><div class="board"><img src="__REF__" alt="Оригинальный спрайт Воина 11"></div></div><div id="grid" class="grid"></div><div class="sheets"><figure><figcaption>Контактный лист · nearest-neighbor 2×</figcaption><img src="__SHEET__" alt="Пять на два: все десять концептов с подписями"></figure><figure><figcaption>Сравнение стиля · исходный масштаб пикселей; игровая посадка не настроена</figcaption><img src="__COMPARE__" alt="Воин 11 и десять концептов в одинаковых 256×256 ячейках"></figure></div><dialog id="viewer"><img id="large" alt="Крупный вид концепта"><button id="close">Закрыть</button></dialog></main><script>
"use strict";const ASSETS=__ASSETS__,CARDS=__CARDS__;const grid=document.querySelector('#grid'),dlg=document.querySelector('#viewer'),large=document.querySelector('#large');for(const c of CARDS){grid.insertAdjacentHTML('beforeend',`<article class="card"><h2>${String(c.id).padStart(2,'0')} · ${c.name}</h2><div class="board"><img src="${ASSETS[c.file]}" alt="Хобгоблин ${c.name}, концепт ${c.id}" data-id="${c.id}"></div></article>`)}grid.addEventListener('click',e=>{const img=e.target.closest('img[data-id]');if(!img)return;large.src=img.src;large.alt=img.alt;dlg.showModal()});document.querySelector('#close').onclick=()=>dlg.close();dlg.addEventListener('click',e=>{if(e.target===dlg)dlg.close()});document.querySelector('#back').onchange=e=>document.querySelectorAll('.board').forEach(el=>el.className='board '+(e.target.value==='dark'?'':e.target.value));document.querySelector('#refToggle').onclick=()=>{const el=document.querySelector('#reference');el.hidden=!el.hidden};window.__galleryState=()=>({concepts:CARDS.length,embeddedImages:Object.keys(ASSETS).length,names:CARDS.map(c=>c.name)});
</script></body></html>'''
	page = (page.replace("__ASSETS__", json.dumps(assets, separators=(",", ":")))
		.replace("__CARDS__", json.dumps(cards, ensure_ascii=False, separators=(",", ":")))
		.replace("__REF__", assets[reference_file])
		.replace("__SHEET__", "data:image/png;base64," + base64.b64encode((ROOT / "contact-sheet.png").read_bytes()).decode("ascii"))
		.replace("__COMPARE__", "data:image/png;base64," + base64.b64encode((ROOT / "style-compare.png").read_bytes()).decode("ascii")))
	(ROOT / "gallery.html").write_text(page, encoding="utf-8")
	print(json.dumps({"concepts": len(cards), "embedded_originals": len(assets),
		"contact_sheet": [Image.open(ROOT / "contact-sheet.png").width, Image.open(ROOT / "contact-sheet.png").height],
		"html_bytes": (ROOT / "gallery.html").stat().st_size}, ensure_ascii=False))


if __name__ == "__main__":
	main()
