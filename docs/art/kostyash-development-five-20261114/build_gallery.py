"""Строит автономную галерею развития Костяша и сравнительные листы."""
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


def composite(path: Path) -> Image.Image:
	with Image.open(path) as source:
		image = source.convert("RGBA")
	background = Image.new("RGBA", image.size, BG)
	background.alpha_composite(image)
	return background.convert("RGB")


def labeled_row(items: list[dict], scale: int) -> Image.Image:
	cell, label = 256 * scale, 34 * scale
	out = Image.new("RGB", (cell * len(items), cell + label), BG)
	draw = ImageDraw.Draw(out)
	label_font = font(16 * scale)
	for index, item in enumerate(items):
		image = composite(ROOT / item["file"])
		if scale > 1:
			image = image.resize((cell, cell), Image.Resampling.NEAREST)
		x = index * cell
		draw.text((x + 7 * scale, 5 * scale), item["label"], fill="#f0d6a1", font=label_font)
		out.paste(image, (x, label))
	return out


def before_after_sheet(source: dict, variants: list[dict]) -> Image.Image:
	label, cell, columns = 30, 256, len(variants)
	out = Image.new("RGB", (columns * cell * 2, cell + label), BG)
	draw = ImageDraw.Draw(out)
	label_font = font(15)
	for index, item in enumerate(variants):
		x = index * cell * 2
		draw.text((x + 5, 5), f"{item['id']:02d} · {item['name']} · {item['native_height']}px", fill="#f0d6a1", font=label_font)
		out.paste(composite(ROOT / source["file"]), (x, label))
		out.paste(composite(ROOT / item["file"]), (x + cell, label))
	return out


def compare_grid(items: list[dict]) -> Image.Image:
	cell, label, columns, rows = 256, 30, 3, 2
	out = Image.new("RGB", (columns * cell, rows * (cell + label)), BG)
	draw = ImageDraw.Draw(out)
	label_font = font(14)
	for index, item in enumerate(items):
		x, y = index % columns * cell, index // columns * (cell + label)
		draw.text((x + 5, y + 5), item["label"], fill="#f0d6a1", font=label_font)
		out.paste(composite(ROOT / item["file"]), (x, y + label))
	return out


def main() -> None:
	manifest = json.loads((ROOT / "sources.json").read_text(encoding="utf-8-sig"))
	if not manifest.get("complete") or len(manifest.get("variants", [])) != 5:
		raise SystemExit("Need five completed PixelLab variants before building gallery")
	variants = manifest["variants"]
	source = {"file": manifest["input_source"]["file"], "label": "Костяш · исходник"}
	warrior = {"file": manifest["input_source"]["warrior_file"], "label": "Воин 11"}
	rows = [{"file": item["file"], "label": f"{item['id']:02d} · {item['name']} · {item['native_height']}px"} for item in variants]
	labeled_row(rows, 1).save(ROOT / "contact-sheet.png")
	before_after_sheet(source, variants).save(ROOT / "before-after-sheet.png")
	compare_grid([source, *rows]).save(ROOT / "development-compare.png")
	labeled_row([source, warrior, *rows], 1).save(ROOT / "reference-strip.png")
	assets: dict[str, str] = {}
	for item in [source, warrior, *[{"file": v["file"]} for v in variants]]:
		path = ROOT / item["file"]
		assets[item["file"]] = "data:image/png;base64," + base64.b64encode(path.read_bytes()).decode("ascii")
	cards = [{"id": item["id"], "name": item["name"], "focus": item.get("focus", ""),
		"file": item["file"], "native_height": item["native_height"], "geometry_pass": item["geometry_pass"],
		"needs_review": item["needs_review"]} for item in variants]
	template = r'''<!doctype html><html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Костяш · пять вариантов развития</title><style>
*{box-sizing:border-box}body{margin:0;background:#111923;color:#edf2f7;font:16px/1.45 system-ui,sans-serif}header{padding:17px 22px;background:#202c3b;position:sticky;top:0;z-index:2}h1{font-size:23px;margin:0 0 8px}.controls{display:flex;gap:8px;align-items:center;flex-wrap:wrap}button,select{background:#34475d;color:white;border:1px solid #72859a;border-radius:5px;padding:8px 11px;cursor:pointer}main{max-width:1420px;margin:auto;padding:18px}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:14px}.card,.reference{background:#202c3b;border:1px solid #3b4d62;border-radius:8px;padding:10px}.card h2,.reference h2{font-size:18px;margin:3px 0 6px}.focus{font-size:14px;color:#d8c9a8;margin:0 0 8px}.board{background:var(--tile,#182131);display:grid;place-items:center;min-height:230px;border-radius:4px}.board.light{background:#ded4ba}.board.check{background-color:#4e5966;background-image:conic-gradient(#303a45 25%,transparent 0 50%,#303a45 0 75%,transparent 0);background-size:24px 24px}.board img{display:block;width:100%;height:auto;aspect-ratio:1;object-fit:contain;image-rendering:pixelated;cursor:zoom-in}.actions{display:flex;gap:8px;flex-wrap:wrap;margin-top:9px}.actions a{color:#f0d6a1;font-size:14px}details{margin:12px 0}details .board{max-width:280px}.sheets{display:flex;gap:14px;flex-wrap:wrap;margin-top:20px}.sheets figure{margin:0}.sheets img{max-width:100%;height:auto;background:#182131}.sheets figcaption{margin:4px 0}.note{color:#bdc9d6;font-size:14px}dialog{border:1px solid #718196;border-radius:8px;background:#101720;color:white;max-width:95vw;max-height:95vh;padding:12px}dialog::backdrop{background:#000b}dialog img{display:block;width:min(70vh,80vw,768px);height:auto;aspect-ratio:1;max-width:80vw;max-height:80vh;image-rendering:pixelated;object-fit:contain}dialog button{margin-top:8px}@media(max-width:650px){header{position:static}main{padding:10px}.grid{grid-template-columns:repeat(2,minmax(0,1fr))}}@media(max-width:420px){.grid{grid-template-columns:1fr}}
</style></head><body><header><h1>Костяш · пять вариантов развития</h1><div class="controls"><button id="allToggle">Показать: исходники</button><label for="background">Фон</label><select id="background"><option value="dark">Тёмный</option><option value="light">Светлый</option><option value="check">Шахматный</option></select></div></header><main><p class="note">Пять близких версий выбранного Костяша: костяная морда, наросты, болезненная кожа, грубое снаряжение и старый сутулый облик. Его поза, короткие ноги и дубинка сохранены. Исходник — 135 пикселей высотой, новые варианты — 135–137. Переключайте исходник и вариант, чтобы увидеть изменения.</p><details><summary>Костяш · исходник</summary><div class="board"><img src="__SOURCE__" alt="Костяш до развития"></div><p>Исходный силуэт · __SOURCE_HEIGHT__ px</p></details><details><summary>Воин 11 · сравнение стиля</summary><div class="board"><img src="__WARRIOR__" alt="Воин 11"></div></details><div id="grid" class="grid"></div><div class="sheets"><figure><figcaption>Пять вариантов · масштаб 1×</figcaption><img src="__SHEET__" alt="Контактный лист пяти вариантов"></figure><figure><figcaption>До/после · исходник и пять вариантов в нативных пикселях</figcaption><img src="__PAIRS__" alt="Сравнение исходника с каждым вариантом"></figure><figure><figcaption>Развитие · исходник и пять вариантов, 2×3</figcaption><img src="__COMPARE__" alt="Исходный Костяш и пять вариантов"></figure><figure><figcaption>Образец стиля отдельно · Костяш, Воин 11 и варианты</figcaption><img src="__STRIP__" alt="Костяш, Воин и пять результатов"></figure></div><dialog id="viewer"><img id="large" alt="Вариант Костяша"><button id="close">Закрыть</button></dialog></main><script>
"use strict";const ASSETS=__ASSETS__,CARDS=__CARDS__;let showVariant=true;const individual={};const grid=document.querySelector('#grid'),dialog=document.querySelector('#viewer'),large=document.querySelector('#large');function update(c,img,button){const state=individual[c.id]??showVariant;img.src=state?ASSETS[c.file]:sourceUrl();img.alt=state?`Костяш · ${c.name}`:'Костяш · исходник';button.textContent=state?'Исходник':'Вариант'}for(const c of CARDS){grid.insertAdjacentHTML('beforeend',`<article class="card"><h2>${String(c.id).padStart(2,'0')} · ${c.name}</h2><p class="focus">${c.focus}<br>Высота силуэта: ${c.native_height}px${c.needs_review?' · требует проверки':''}</p><div class="board"><img src="${ASSETS[c.file]}" data-id="${c.id}" alt="Костяш · ${c.name}"></div><div class="actions"><button data-toggle="${c.id}">Исходник</button><a href="${ASSETS[c.file]}" download="kostyash-${String(c.id).padStart(2,'0')}.png">Скачать PNG</a></div></article>`)}function sourceUrl(){return ASSETS['__SOURCE_KEY__']}for(const c of CARDS){const img=document.querySelector(`[data-id="${c.id}"]`),button=document.querySelector(`[data-toggle="${c.id}"]`);button.onclick=()=>{individual[c.id]=!(individual[c.id]??showVariant);update(c,img,button)}}document.querySelector('#allToggle').onclick=()=>{showVariant=!showVariant;for(const c of CARDS){individual[c.id]=showVariant;const img=document.querySelector(`[data-id="${c.id}"]`),button=document.querySelector(`[data-toggle="${c.id}"]`);update(c,img,button)}document.querySelector('#allToggle').textContent=showVariant?'Показать: исходники':'Показать: варианты'};grid.addEventListener('click',e=>{const img=e.target.closest('img[data-id]');if(!img)return;large.src=img.src;large.alt=img.alt;dialog.showModal()});document.querySelector('#close').onclick=()=>dialog.close();dialog.addEventListener('click',e=>{if(e.target===dialog)dialog.close()});document.querySelector('#background').onchange=e=>document.querySelectorAll('.board').forEach(el=>el.className='board '+(e.target.value==='dark'?'':e.target.value));window.__galleryState=()=>({cards:CARDS.length,embeddedImages:Object.keys(ASSETS).length,variant:showVariant});
</script></body></html>'''
	page = (template.replace("__ASSETS__", json.dumps(assets, separators=(",", ":")))
		.replace("__CARDS__", json.dumps(cards, ensure_ascii=False, separators=(",", ":")))
		.replace("__SOURCE__", assets[source["file"]]).replace("__SOURCE_KEY__", source["file"])
		.replace("__SOURCE_HEIGHT__", str(manifest["input_source"]["height"]))
		.replace("__WARRIOR__", assets[warrior["file"]])
		.replace("__SHEET__", "data:image/png;base64," + base64.b64encode((ROOT / "contact-sheet.png").read_bytes()).decode("ascii"))
		.replace("__PAIRS__", "data:image/png;base64," + base64.b64encode((ROOT / "before-after-sheet.png").read_bytes()).decode("ascii"))
		.replace("__COMPARE__", "data:image/png;base64," + base64.b64encode((ROOT / "development-compare.png").read_bytes()).decode("ascii"))
		.replace("__STRIP__", "data:image/png;base64," + base64.b64encode((ROOT / "reference-strip.png").read_bytes()).decode("ascii")))
	(ROOT / "gallery.html").write_text(page, encoding="utf-8")
	print(json.dumps({"variants": len(cards), "embedded_source_images": len(assets), "html_bytes": (ROOT / "gallery.html").stat().st_size}))


if __name__ == "__main__":
	main()
