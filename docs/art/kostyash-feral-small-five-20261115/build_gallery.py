"""Собирает автономный просмотр пяти пар PNG без изменения исходников."""
from pathlib import Path
import base64
import json

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
BG = "#182131"


def font(size: int):
	for path in (Path("C:/Windows/Fonts/arial.ttf"), Path("C:/Windows/Fonts/segoeui.ttf")):
		if path.is_file():
			return ImageFont.truetype(str(path), size=size)
	return ImageFont.load_default()


def composite(path: Path) -> Image.Image:
	with Image.open(path) as im:
		image = im.convert("RGBA")
	background = Image.new("RGBA", image.size, BG)
	background.alpha_composite(image)
	return background.convert("RGB")


def sheet(items: list[dict], columns: int, cell: int = 256, label_h: int = 34) -> Image.Image:
	rows = (len(items) + columns - 1) // columns
	out = Image.new("RGB", (columns * cell, rows * (cell + label_h)), BG)
	draw = ImageDraw.Draw(out)
	for index, item in enumerate(items):
		x, y = index % columns * cell, index // columns * (cell + label_h)
		draw.text((x + 6, y + 6), item["label"], fill="#f0d6a1", font=font(15))
		out.paste(composite(ROOT / item["file"]), (x, y + label_h))
	return out


def paired_sheet(items: list[dict]) -> Image.Image:
	cell, label_h, columns = 256, 30, len(items)
	out = Image.new("RGB", (columns * cell, label_h + 26 + 2 * cell), BG)
	draw = ImageDraw.Draw(out)
	draw.text((8, 7), "ИСТОЧНИКИ: верхний ряд · новые варианты: нижний ряд", fill="#f0d6a1", font=font(16))
	for i, item in enumerate(items):
		x = i * cell
		draw.text((x + 5, label_h + 4), f"{i+1:02d} · {item['name']} · −{item['shrink_percent']}%", fill="#f0d6a1", font=font(13))
		out.paste(composite(ROOT / item["source_file"]), (x, label_h + 26))
		out.paste(composite(ROOT / item["file"]), (x, label_h + cell + 26))
	return out


def raw_showcase(items: list[dict]) -> Image.Image:
	cell_w, cell_h, label_h = 320, 256, 34
	out = Image.new("RGB", (cell_w * len(items), cell_h + label_h), BG)
	draw = ImageDraw.Draw(out)
	for index, item in enumerate(items):
		draw.text((index * cell_w + 6, 7), f"{item['id']:02d} · {item['name']} · {item['native_height']}px · 2×", fill="#f0d6a1", font=font(14))
		with Image.open(ROOT / item["file"]) as raw:
			image = raw.convert("RGBA").resize((cell_w, cell_h), Image.Resampling.NEAREST)
		background = Image.new("RGBA", image.size, BG)
		background.alpha_composite(image)
		out.paste(background.convert("RGB"), (index * cell_w, label_h))
	return out


def main() -> None:
	manifest = json.loads((ROOT / "sources.json").read_text(encoding="utf-8-sig"))
	if not manifest.get("complete") or len(manifest.get("variants", [])) != 5:
		raise SystemExit("Need five exported variants before building gallery")
	inputs, variants = manifest["input_sources"], manifest["variants"]
	warrior = {"file": inputs["warrior_file"], "label": "Воин 11 · 152px"}
	new = [{"file": v["preview_file"], "label": f"{v['id']:02d} · {v['name']} · {v['native_height']}px"} for v in variants]
	sheet(new, 5).save(ROOT / "contact-sheet.png")
	pairs = [{**v, "file": v["preview_file"]} for v in variants]
	paired_sheet(pairs).save(ROOT / "before-after-sheet.png")
	sheet([warrior, *new], 6).save(ROOT / "reference-strip.png")
	raw_showcase(variants).save(ROOT / "showcase.png")
	assets: dict[str, str] = {}
	for path in [*(s["file"] for s in inputs["sources"]), *(v["preview_file"] for v in variants), inputs["warrior_file"]]:
		assets[path] = "data:image/png;base64," + base64.b64encode((ROOT / path).read_bytes()).decode("ascii")
	raw_assets = {v["file"]: "data:image/png;base64," + base64.b64encode((ROOT / v["file"]).read_bytes()).decode("ascii") for v in variants}
	cards = [{k: v[k] for k in ("id", "name", "focus", "file", "preview_file", "source_file", "source_height", "native_height", "height_delta", "shrink_percent", "needs_review", "geometry_flags")} for v in variants]
	source_names = {s["file"]: s["source_package"] for s in inputs["sources"]}
	template = r'''<!doctype html><html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Костяш · пять меньших звериных вариантов</title><style>
*{box-sizing:border-box}body{margin:0;background:#111923;color:#edf2f7;font:16px/1.45 system-ui,sans-serif}header{padding:17px 22px;background:#202c3b;position:sticky;top:0;z-index:2}h1{font-size:23px;margin:0 0 8px}.controls,.actions{display:flex;gap:8px;align-items:center;flex-wrap:wrap}button,select{background:#34475d;color:white;border:1px solid #72859a;border-radius:5px;padding:8px 11px;cursor:pointer}main{max-width:1420px;margin:auto;padding:18px}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:14px}.card,.reference{background:#202c3b;border:1px solid #3b4d62;border-radius:8px;padding:10px}.card h2{font-size:18px;margin:3px 0 6px}.focus,.note{font-size:14px;color:#d8c9a8}.board{background:#182131;display:grid;place-items:center;min-height:230px;border-radius:4px}.board.light{background:#ded4ba}.board.check{background-color:#4e5966;background-image:conic-gradient(#303a45 25%,transparent 0 50%,#303a45 0 75%,transparent 0);background-size:24px 24px}.board img{display:block;width:100%;height:auto;aspect-ratio:1;object-fit:contain;image-rendering:pixelated;cursor:zoom-in}.actions{margin-top:9px}.actions a{color:#f0d6a1;font-size:14px}.sheets{display:flex;gap:14px;flex-wrap:wrap;margin-top:20px}.sheets figure{margin:0}.sheets img{width:100%;max-width:100%;height:auto;background:#182131}details{margin:12px 0}details img{width:256px;height:256px;image-rendering:pixelated}dialog{border:1px solid #718196;border-radius:8px;background:#101720;color:white;max-width:95vw;max-height:95vh;padding:12px}dialog::backdrop{background:#000b}dialog img{display:block;width:min(70vh,80vw,768px);height:auto;aspect-ratio:1;max-width:80vw;max-height:80vh;image-rendering:pixelated;object-fit:contain}@media(max-width:650px){header{position:static}main{padding:10px}.grid{grid-template-columns:repeat(2,minmax(0,1fr))}}@media(max-width:420px){.grid{grid-template-columns:1fr}}
</style></head><body><header><h1>Костяш · пять меньших звериных вариантов</h1><div class="controls"><button id="allToggle">Показать: новые варианты</button><label for="background">Фон</label><select id="background"><option value="dark">Тёмный</option><option value="light">Светлый</option><option value="check">Шахматный</option></select></div></header><main><p class="note">Каждый результат показан рядом со своим исходником. Указана фактическая высота видимого силуэта и её изменение относительно соответствующего исходника; листы собраны в нативном масштабе 1×.</p><details><summary>Образец стиля · Воин 11</summary><img src="__WARRIOR__" alt="Воин 11, 152 пикселя высотой"></details><details><summary>Сравнительные листы</summary><div class="sheets"><figure><figcaption>Пять новых вариантов · 1×</figcaption><img src="__CONTACT__" alt="Пять вариантов"></figure><figure><figcaption>Исходники сверху · результаты снизу</figcaption><img src="__PAIRS__" alt="Пять индивидуальных сравнений"></figure><figure><figcaption>Воин 11 и новые варианты · 1×</figcaption><img src="__STRIP__" alt="Сравнение масштаба персонажей"></figure></div></details><div id="grid" class="grid"></div><dialog id="viewer"><img id="large" alt="Костяш"><button id="close">Закрыть</button></dialog></main><script>
"use strict";const ASSETS=__ASSETS__,RAW=__RAW__,CARDS=__CARDS__,SOURCES=__SOURCES__,WARRIOR="__WARRIOR_KEY__";let globalAfter=true;const local={};const grid=document.querySelector('#grid');function imgFor(c){return ASSETS[(local[c.id]??globalAfter)?c.preview_file:c.source_file]}for(const c of CARDS){grid.insertAdjacentHTML('beforeend',`<article class="card"><h2>${String(c.id).padStart(2,'0')} · ${c.name}</h2><p class="focus">${c.focus}<br>Высота силуэта: ${c.native_height}px (было ${c.source_height}px), изменение ${c.height_delta}px / ${c.shrink_percent}%${c.needs_review?(c.native_height<90&&c.geometry_flags.every(f=>f==='height_outside_target_90_110')?' · ниже ориентира 90px':' · требуется проверка контуров'):''}</p><div class="board"><img data-id="${c.id}" src="${imgFor(c)}" alt="Костяш · ${c.name}"></div><div class="actions"><button data-toggle="${c.id}">Показать ${globalAfter?'исходник':'результат'}</button><a href="${RAW[c.file]}" download="kostyash-${String(c.id).padStart(2,'0')}-raw-224.png">Скачать PNG</a></div></article>`)}function update(c){const state=local[c.id]??globalAfter;document.querySelector(`[data-id="${c.id}"]`).src=ASSETS[state?c.preview_file:c.source_file];document.querySelector(`[data-toggle="${c.id}"]`).textContent=`Показать ${state?'исходник':'результат'}`}for(const c of CARDS)document.querySelector(`[data-toggle="${c.id}"]`).onclick=()=>{local[c.id]=!(local[c.id]??globalAfter);update(c)};document.querySelector('#allToggle').onclick=()=>{globalAfter=!globalAfter;for(const c of CARDS){local[c.id]=globalAfter;update(c)}document.querySelector('#allToggle').textContent=`Показать: ${globalAfter?'исходники':'новые варианты'}`};document.querySelector('#background').onchange=e=>document.querySelectorAll('.board').forEach(el=>el.className='board '+(e.target.value==='dark'?'':e.target.value));const dialog=document.querySelector('#viewer'),large=document.querySelector('#large');grid.addEventListener('click',e=>{const im=e.target.closest('img[data-id]');if(im){large.src=im.src;large.alt=im.alt;dialog.showModal()}});document.querySelector('#close').onclick=()=>dialog.close();dialog.addEventListener('click',e=>{if(e.target===dialog)dialog.close()});window.__galleryState=()=>({cards:CARDS.length,embeddedImages:Object.keys(ASSETS).length,rawDownloads:Object.keys(RAW).length});

</script></body></html>'''
	template = template.replace("пять меньших звериных вариантов", "пять низких звериных вариантов")
	template = template.replace("Показать: новые варианты", "Показать: исходники")
	template = template.replace("raw 224×224", "raw 160×128")
	template = template.replace("-raw-224.png", "-raw-160x128.png")
	template = template.replace("Каждый результат показан рядом со своим исходником. Указана фактическая высота видимого силуэта и её изменение относительно соответствующего исходника; листы собраны в нативном масштабе 1×.", "Новые Костяши ниже прежних на 29–38%. У каждого варианта можно включить его исходник; масштаб сравнения одинаковый. Длинные лапы, короткие ноги и низкая посадка сильнее всего выражены у №2 и №4.")
	template = template.replace("alt=\"Сравнение масштаба персонажей\"></figure></div></details>", "alt=\"Сравнение масштаба персонажей\"></figure><figure><figcaption>Пять вариантов · увеличение 2× без сглаживания</figcaption><img src=\"__SHOWCASE__\" alt=\"Пять вариантов в масштабе 2×\"></figure></div></details>")
	page = (template.replace("__ASSETS__", json.dumps(assets, separators=(",", ":")))
		.replace("__RAW__", json.dumps(raw_assets, separators=(",", ":")))
		.replace("__CARDS__", json.dumps(cards, ensure_ascii=False, separators=(",", ":")))
		.replace("__SOURCES__", json.dumps(source_names, ensure_ascii=False, separators=(",", ":")))
		.replace("__WARRIOR__", assets[inputs["warrior_file"]]).replace("__WARRIOR_KEY__", inputs["warrior_file"])
		.replace("__CONTACT__", "data:image/png;base64," + base64.b64encode((ROOT / "contact-sheet.png").read_bytes()).decode("ascii"))
		.replace("__PAIRS__", "data:image/png;base64," + base64.b64encode((ROOT / "before-after-sheet.png").read_bytes()).decode("ascii"))
		.replace("__STRIP__", "data:image/png;base64," + base64.b64encode((ROOT / "reference-strip.png").read_bytes()).decode("ascii"))
		.replace("__SHOWCASE__", "data:image/png;base64," + base64.b64encode((ROOT / "showcase.png").read_bytes()).decode("ascii")))
	(ROOT / "gallery.html").write_text(page, encoding="utf-8")
	print(json.dumps({"variants": len(cards), "embedded_source_images": len(assets), "html_bytes": len(page.encode("utf-8"))}, ensure_ascii=False))


if __name__ == "__main__":
	main()
