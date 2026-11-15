"""Собирает автономную галерею пяти проб способностей и их общий GIF."""
from __future__ import annotations

import base64
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
LABELS = ("Рык", "Прикрыться", "Взять след", "Чутьё земли", "Стряхнуть")
BG = (24, 33, 49, 255)
DESCRIPTIONS = (
	"Вдыхает, рычит и возвращается в низкую стойку; дубина остаётся при нём.",
	"Прикрывает лицо свободной рукой, удерживая дубину у живота.",
	"Опускает морду, принюхивается и медленно ведёт её вдоль следа.",
	"Прижимает ладонь к земле и прислушивается к колебаниям.",
	"Коротко встряхивается, стряхивая пыль, и возвращается в исходную позу.",
)


def font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
	for path in (Path("C:/Windows/Fonts/arial.ttf"), Path("C:/Windows/Fonts/segoeui.ttf")):
		if path.is_file():
			return ImageFont.truetype(str(path), size=size)
	return ImageFont.load_default()


def load_frame(path: Path) -> Image.Image:
	with Image.open(path) as image:
		if image.size != (256, 256):
			raise SystemExit(f"Frame must be 256x256: {path}")
		return image.convert("RGBA")


def read_clips() -> tuple[list[dict], list[list[Image.Image]]]:
	requests = json.loads((ROOT / "requests.json").read_text(encoding="utf-8-sig"))
	if not isinstance(requests, list) or len(requests) != 5:
		raise SystemExit("Expected five ability rows in requests.json")
	clips: list[dict] = []
	frames: list[list[Image.Image]] = []
	for index, row in enumerate(requests, start=1):
		key = f"ability-{index}"
		if row.get("key") != key or row.get("kind") != "ability" or row.get("variant") != index:
			raise SystemExit(f"Unexpected ability identity at row {index}")
		if row.get("title") != LABELS[index - 1]:
			raise SystemExit(f"Unexpected Russian title for {key}")
		folder = ROOT / "pixellab" / key
		meta_path = folder / "clip.json"
		if not meta_path.is_file():
			raise SystemExit(f"Source not ready: missing {meta_path}")
		meta = json.loads(meta_path.read_text(encoding="utf-8-sig"))
		if meta.get("key") != key or meta.get("kind") != "ability" or meta.get("variant") != index:
			raise SystemExit(f"Clip identity mismatch: {key}")
		if meta.get("actual_frames") != 33 or meta.get("durations_ms") != [70] * 32 + [500]:
			raise SystemExit(f"Expected 33 frames with 70ms cadence and 500ms ending: {key}")
		if meta.get("loop") is not False:
			raise SystemExit(f"Ability must be one-shot: {key}")
		sequence = [load_frame(folder / "frames" / f"frame-{frame:02d}.png") for frame in range(33)]
		sheet_path = folder / "spritesheet.png"
		with Image.open(sheet_path) as sheet:
			if sheet.size != (2048, 1280):
				raise SystemExit(f"Expected 2048x1280 spritesheet: {key}")
			for frame_index, frame in enumerate(sequence):
				x, y = (frame_index % 8) * 256, (frame_index // 8) * 256
				if sheet.crop((x, y, x + 256, y + 256)).convert("RGBA").tobytes() != frame.tobytes():
					raise SystemExit(f"Spritesheet does not match source frames: {key} frame {frame_index}")
		clips.append({"key": key, "kind": "ability", "variant": index, "title": row["title"],
			"description": DESCRIPTIONS[index - 1], "count": 33, "timing": [70] * 32 + [500], "loop": False,
			"sheet": f"pixellab/{key}/spritesheet.png"})
		frames.append(sequence)
	return clips, frames


def create_overview(frames: list[list[Image.Image]]) -> None:
	# Пять крупных кадров показывают ключевые позы без уменьшения до нечитаемых точек.
	samples, cell, label_h = (0, 8, 16, 24, 32), 256, 30
	width, height = len(samples) * cell, 5 * (label_h + cell)
	canvas = Image.new("RGBA", (width, height), BG)
	draw = ImageDraw.Draw(canvas)
	for index, sequence in enumerate(frames):
		y = index * (label_h + cell)
		draw.text((6, y + 5), f"{index + 1}. {LABELS[index]}", font=font(18), fill="#f4d18e")
		for col, frame_index in enumerate(samples):
			canvas.alpha_composite(sequence[frame_index], (col * cell, y + label_h))
	canvas.convert("RGB").save(ROOT / "overview.png")


def create_composite(frames: list[list[Image.Image]]) -> None:
	cell, header, gap = 512, 38, 4
	width, height = cell * 3 + gap * 4, (cell + header) * 2 + gap * 3
	output: list[Image.Image] = []
	for frame_index in range(33):
		canvas = Image.new("RGBA", (width, height), BG)
		draw = ImageDraw.Draw(canvas)
		for index, sequence in enumerate(frames):
			row, col = divmod(index, 3)
			x, y = gap + col * (cell + gap), gap + row * (cell + header + gap)
			draw.text((x + 8, y + 7), f"{index + 1}. {LABELS[index]}", font=font(20), fill="#f4d18e")
			canvas.alpha_composite(sequence[frame_index].resize((cell, cell), Image.Resampling.NEAREST), (x, y + header))
		output.append(canvas.convert("RGB"))
	# GIF последнего кадра держится столько же, сколько в клипах.
	durations = [70] * 32 + [500]
	output[0].save(ROOT / "preview.gif", save_all=True, append_images=output[1:], duration=durations,
		loop=0, disposal=2, optimize=False)


def main() -> None:
	clips, frames = read_clips()
	input_path = ROOT / "model" / "input-256.png"
	if not input_path.is_file():
		raise SystemExit(f"Source not ready: missing {input_path}")
	with Image.open(input_path) as source:
		if source.size != (256, 256):
			raise SystemExit("Expected 256x256 model/input-256.png")
		input_bytes = input_path.read_bytes()
	assets: dict[str, str] = {}
	for clip in clips:
		path = ROOT / clip["sheet"]
		assets[clip["sheet"]] = "data:image/png;base64," + base64.b64encode(path.read_bytes()).decode("ascii")
	assets["model/input-256.png"] = "data:image/png;base64," + base64.b64encode(input_bytes).decode("ascii")
	create_overview(frames)
	create_composite(frames)
	assets["overview.png"] = "data:image/png;base64," + base64.b64encode((ROOT / "overview.png").read_bytes()).decode("ascii")
	data = {"clips": clips, "input_sha256": hashlib.sha256(input_bytes).hexdigest(),
		"overview": "overview.png", "runtime_integration": False, "embedded_asset_count": len(assets)}
	(ROOT / "gallery-data.json").write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
	assets_json = json.dumps(assets, ensure_ascii=False, separators=(",", ":"))
	clips_json = json.dumps(clips, ensure_ascii=False, separators=(",", ":"))
	template = r'''<!doctype html><html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Рваноух · варианты способностей</title><style>
*{box-sizing:border-box}body{margin:0;background:#101723;color:#e8eef5;font:15px/1.4 system-ui,sans-serif}header{padding:14px 18px;background:#1a2434;position:sticky;top:0;z-index:2}h1{font-size:22px;margin:0 0 6px}h2{font-size:18px}main{max-width:1600px;margin:auto;padding:14px}.controls{display:flex;gap:8px;align-items:center;flex-wrap:wrap}button,select{background:#2b3c54;border:1px solid #60718b;border-radius:5px;color:white;padding:7px 10px;cursor:pointer}.grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:10px}.card{min-width:0;background:#1b2739;border:1px solid #34465e;border-radius:7px;padding:9px}.card h2{margin:0 0 7px}.stage{position:relative;width:100%;aspect-ratio:1;display:block;background:var(--stage,#182131);border-radius:4px;overflow:hidden}.stage canvas{position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);width:100%;height:auto;aspect-ratio:1;image-rendering:pixelated}.card input[type=range]{width:100%}.prompt{font-size:12px;color:#bdc9d6;min-height:4.5em}.refs{display:flex;gap:14px;align-items:center}.refs img{width:128px;height:128px;object-fit:contain;image-rendering:pixelated;background:#202b3d}.overview{max-width:100%;height:auto;image-rendering:pixelated}footer{color:#bdc9d6;padding:14px}@media(max-width:900px){header{position:static}.grid{grid-template-columns:repeat(2,minmax(0,1fr))}}@media(max-width:560px){main{padding:8px}.grid{grid-template-columns:1fr}}</style></head><body><header><h1>Пять вариантов способностей · без атак</h1><div class="controls"><button id="play">Пауза всех</button><button id="restart">Сначала все</button><button id="step">+ кадр всем</button><label>Скорость <select id="speed"><option value="1">1×</option><option value="0.5">0,5×</option><option value="1.5">1,5×</option></select></label><label>Масштаб <select id="zoom"><option value="1">Вписать</option><option value="0.75">75%</option><option value="1.25">125%</option></select></label><label>Фон <select id="bg"><option value="#182131">Тёмный</option><option value="#727d89">Серый</option><option value="#ded4b9">Светлый</option></select></label></div></header><main><div class="refs"><img src="__INPUT__" alt="Исходный холст Рваноуха"><p>Рваноух · подготовленный холст 256×256. Это концепт-кандидаты анимации; они не задают игровые механики и не являются атаками.</p></div><h2>Варианты</h2><section class="grid" id="gallery"></section><details><summary>Пять ключевых поз каждого варианта</summary><img class="overview" src="__OVERVIEW__" alt="Пять покадровых плёнок способностей"></details></main><footer>Кадры и тайминг встроены в этот файл. Однократный просмотр удерживает последний кадр; повтор включается отдельно для сравнения.</footer><script>
"use strict";const ASSETS=__ASSETS__,CLIPS=__CLIPS__;const players=[];let playing=true,speed=1,last=0;const $=s=>document.querySelector(s);CLIPS.forEach((clip,i)=>{const card=document.createElement('article');card.className='card';card.innerHTML=`<h2>${i+1}. ${clip.title}</h2><div class="stage"><canvas width="256" height="256" aria-label="Кадры способности ${clip.title}"></canvas></div><input type="range" min="0" max="32" value="0" aria-label="Кадр способности ${clip.title}"><p class="prompt">${clip.description}</p><label><input type="checkbox" class="repeat"> Повторять для сравнения</label> <button class="toggle">Пауза</button> <button class="restart">Сначала</button> <button class="step">+ кадр</button>`;$('#gallery').append(card);const canvas=card.querySelector('canvas'),ctx=canvas.getContext('2d'),slider=card.querySelector('input[type=range]'),image=new Image(),p={clip,card,canvas,ctx,slider,image,frame:0,elapsed:0,playing:true,repeat:false};players.push(p);image.onload=()=>draw(p);image.src=ASSETS[clip.sheet];slider.oninput=()=>{p.playing=false;p.frame=Number(slider.value);p.elapsed=0;card.querySelector('.toggle').textContent='Играть';draw(p)};card.querySelector('.repeat').onchange=e=>p.repeat=e.target.checked;card.querySelector('.toggle').onclick=e=>{p.playing=!p.playing;e.target.textContent=p.playing?'Пауза':'Играть'};card.querySelector('.restart').onclick=()=>{p.frame=0;p.elapsed=0;draw(p);p.playing=true;card.querySelector('.toggle').textContent='Пауза'};card.querySelector('.step').onclick=()=>{p.playing=false;p.elapsed=0;p.frame=Math.min(32,p.frame+1);card.querySelector('.toggle').textContent='Играть';draw(p)}});function draw(p){if(!p.image.complete)return;p.ctx.clearRect(0,0,256,256);p.ctx.drawImage(p.image,(p.frame%8)*256,Math.floor(p.frame/8)*256,256,256,0,0,256,256);p.slider.value=p.frame}function tick(now){const dt=last?Math.min(now-last,100):0;last=now;if(playing)for(const p of players)if(p.playing&&p.image.complete){p.elapsed+=dt*speed;while(p.elapsed>=p.clip.timing[p.frame]){p.elapsed-=p.clip.timing[p.frame];if(p.frame<32)p.frame++;else if(p.repeat)p.frame=0;else{p.elapsed=0;p.playing=false;p.card.querySelector('.toggle').textContent='Играть';break}}draw(p)}requestAnimationFrame(tick)}$('#play').onclick=()=>{playing=!playing;if(playing)for(const p of players){if(p.frame===32&&!p.repeat){p.frame=0;p.elapsed=0;draw(p)}p.playing=true;p.card.querySelector('.toggle').textContent='Пауза'}$('#play').textContent=playing?'Пауза всех':'Играть все'};$('#restart').onclick=()=>{playing=true;$('#play').textContent='Пауза всех';players.forEach(p=>{p.frame=0;p.elapsed=0;p.playing=true;p.card.querySelector('.toggle').textContent='Пауза';draw(p)})};$('#step').onclick=()=>players.forEach(p=>{p.playing=false;p.elapsed=0;p.frame=Math.min(32,p.frame+1);p.card.querySelector('.toggle').textContent='Играть';draw(p)});$('#speed').onchange=e=>speed=Number(e.target.value);$('#zoom').onchange=e=>document.querySelectorAll('.stage canvas').forEach(c=>{c.style.width=(Number(e.target.value)*100)+'%';c.style.height='auto'});$('#bg').onchange=e=>document.documentElement.style.setProperty('--stage',e.target.value);window.__galleryState=()=>({clips:players.length,loaded:players.every(p=>p.image.complete),labels:CLIPS.map(c=>c.title)});requestAnimationFrame(tick);
</script></body></html>'''
	html = template.replace("__ASSETS__", assets_json).replace("__CLIPS__", clips_json)
	html = html.replace("__INPUT__", assets["model/input-256.png"]).replace("__OVERVIEW__", assets["overview.png"])
	(ROOT / "gallery.html").write_text(html, encoding="utf-8")
	print(json.dumps({"clips": len(clips), "embedded_assets": len(assets), "html_bytes": len(html.encode("utf-8")),
		"gif_size": (ROOT / "preview.gif").stat().st_size, "overview_size": (ROOT / "overview.png").stat().st_size}))


if __name__ == "__main__":
	main()
