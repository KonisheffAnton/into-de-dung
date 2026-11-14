"""Собирает до/после-превью из исходных кадров без изменения поз и PNG-байтов."""
from pathlib import Path
import base64
import hashlib
import io
import json

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent


def read_json(path: Path) -> dict | list:
	return json.loads(path.read_text(encoding="utf-8-sig"))


def sha(data: bytes) -> str:
	return hashlib.sha256(data).hexdigest()


def load_rgba(path: Path) -> Image.Image:
	with Image.open(path) as image:
		if image.size != (256, 256):
			raise SystemExit(f"Expected a 256x256 frame: {path}")
		return image.convert("RGBA")


def pack_sheet(images: list[Image.Image]) -> Image.Image:
	sheet = Image.new("RGBA", (256 * 8, 256 * ((len(images) + 7) // 8)))
	for index, image in enumerate(images):
		sheet.paste(image, ((index % 8) * 256, (index // 8) * 256))
	return sheet


def main() -> None:
	edit = read_json(ROOT / "edit.json")
	if not isinstance(edit, dict):
		raise SystemExit("edit.json must contain one edit object")
	indices = edit.get("frame_order")
	durations = edit.get("durations_ms")
	if not isinstance(indices, list) or not indices or any(type(index) is not int or index < 0 or index > 32 for index in indices):
		raise SystemExit("frame_order must be a non-empty list of source indices from 0 through 32")
	if len(set(indices)) != len(indices) or any(a >= b for a, b in zip(indices, indices[1:])):
		raise SystemExit("frame_order indices must be unique and strictly ascending")
	if not isinstance(durations, list) or len(durations) != len(indices) or any(type(ms) is not int or ms <= 0 or ms % 10 for ms in durations):
		raise SystemExit("durations_ms must match frame_order and contain positive multiples of 10")
	impact = edit.get("impact_source_frame")
	if type(impact) is not int or impact not in indices:
		raise SystemExit("impact_source_frame must appear in frame_order")
	title = edit.get("title")
	if not isinstance(title, str) or not title.strip():
		raise SystemExit("title must be non-empty")
	source_dir_value = edit.get("source_directory")
	if not isinstance(source_dir_value, str):
		raise SystemExit("source_directory must be a repository-relative path")
	source_dir = (ROOT.parents[2] / source_dir_value).resolve()
	# Путь остаётся в репозитории, чтобы монтаж не мог случайно читать внешние артефакты.
	repo_root = ROOT.parents[2].resolve()
	if repo_root not in source_dir.parents:
		raise SystemExit("source_directory must resolve inside the repository")
	source_meta = read_json(source_dir / "clip.json")
	if source_meta.get("actual_frames") != 33 or source_meta.get("kind") != "attack":
		raise SystemExit("Source must be a 33-frame attack clip")
	if source_meta.get("durations_ms") != [50] * 32 + [700]:
		raise SystemExit("Unexpected source timing; expected 32x50ms plus final 700ms")
	source_paths = [source_dir / "frames" / f"frame-{index:02d}.png" for index in range(33)]
	source_raw = [path.read_bytes() for path in source_paths]
	if [sha(raw) for raw in source_raw] != source_meta.get("frame_sha256"):
		raise SystemExit("Source PNG hashes do not match the recorded PixelLab clip")
	source_images = [load_rgba(path) for path in source_paths]
	chosen_raw = [source_raw[index] for index in indices]
	chosen_images = [source_images[index] for index in indices]
	preview_dir = ROOT / "preview"
	frames_dir = preview_dir / "frames"
	frames_dir.mkdir(parents=True, exist_ok=True)
	for index, raw in enumerate(chosen_raw):
		(frames_dir / f"frame-{index:02d}.png").write_bytes(raw)
	sheet = pack_sheet(chosen_images)
	sheet.save(preview_dir / "spritesheet.png")
	gif_frames: list[Image.Image] = []
	for frame in chosen_images:
		background = Image.new("RGBA", (256, 256), "#182131")
		background.alpha_composite(frame)
		gif_frames.append(background.convert("RGB").resize((512, 512), Image.Resampling.NEAREST))
	gif_frames[0].save(preview_dir / "preview.gif", save_all=True, append_images=gif_frames[1:],
		duration=durations, loop=0, disposal=2)
	impact_position = indices.index(impact)
	film_positions = [0, max(0, impact_position - 2), max(0, impact_position - 1), impact_position, min(len(indices) - 1, impact_position + 1), len(indices) - 1]
	film_positions = list(dict.fromkeys(film_positions))
	filmstrip = Image.new("RGB", (256 * len(film_positions), 256), "#182131")
	for column, frame_index in enumerate(film_positions):
		filmstrip.paste(chosen_images[frame_index], (column * 256, 0), chosen_images[frame_index])
	filmstrip.save(preview_dir / "filmstrip.png")
	boxes = [image.getchannel("A").getbbox() for image in chosen_images]
	solid_boxes = [image.getchannel("A").point(lambda alpha: 255 if alpha >= 128 else 0).getbbox() for image in chosen_images]
	manifest = {
		"key": "warrior-attack-single", "kind": "attack", "title": title,
		"source_directory": source_dir_value, "source_key": source_meta.get("key"),
		"actual_frames": len(indices), "source_frame_indices": indices,
		"durations_ms": durations, "timing_origin": "Выбор и длительности заданы монтажом; исходные позы не изменялись.",
		"impact_source_frame": impact, "impact_preview_frame": impact_position,
		"frame_sha256": [sha(raw) for raw in chosen_raw],
		"edge_frames": [i for i, box in enumerate(solid_boxes) if box and (box[0] == 0 or box[1] == 0 or box[2] == 256 or box[3] == 256)],
		"margin_violation_frames": [i for i, box in enumerate(boxes) if box and (box[0] < 8 or box[1] < 8 or box[2] > 248 or box[3] > 248)],
		"last_frame_rgba_equal_first": chosen_images[-1].tobytes() == chosen_images[0].tobytes(),
		"raw_pixels_modified": False, "integration": False,
	}
	(preview_dir / "clip.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
	validation = validate(source_dir, source_raw, chosen_raw, chosen_images, indices, manifest)
	(ROOT / "validation.json").write_text(json.dumps(validation, ensure_ascii=False, indent=2), encoding="utf-8")
	build_gallery(title, source_images, source_meta, chosen_images, manifest, durations)
	print(json.dumps({"source_frames": 33, "preview_frames": len(indices), "duration_ms": sum(durations),
		"validation": validation["complete"], "gallery": "gallery.html"}, ensure_ascii=False))


def validate(source_dir: Path, source_raw: list[bytes], chosen_raw: list[bytes],
		chosen_images: list[Image.Image], indices: list[int], manifest: dict) -> dict:
	issues = []
	for out_index, source_index in enumerate(indices):
		data = (ROOT / "preview" / "frames" / f"frame-{out_index:02d}.png").read_bytes()
		if data != source_raw[source_index] or sha(data) != manifest["frame_sha256"][out_index]:
			raise SystemExit(f"Montaged raw PNG differs from source frame {source_index}")
	with Image.open(ROOT / "preview/spritesheet.png") as sheet:
		if sheet.mode != "RGBA" or sheet.width != 2048 or sheet.height != 256 * ((len(indices) + 7) // 8):
			raise SystemExit("Preview spritesheet has unexpected dimensions or mode")
		for index, frame in enumerate(chosen_images):
			cell = sheet.crop(((index % 8) * 256, (index // 8) * 256,
				(index % 8 + 1) * 256, (index // 8 + 1) * 256))
			if cell.tobytes() != frame.tobytes():
				raise SystemExit(f"Spritesheet cell differs from raw frame {index}")
	for index, image in enumerate(chosen_images):
		alpha = np.asarray(image.getchannel("A"))
		if not np.any(alpha > 0) or not np.any(alpha == 0):
			issues.append(f"Preview frame {index} must be nonempty with transparency")
	if issues:
		raise SystemExit("; ".join(issues))
	with Image.open(ROOT / "preview/preview.gif") as gif:
		gif_total = 0
		for frame in range(gif.n_frames):
			gif.seek(frame)
			gif_total += gif.info.get("duration", 0)
	if gif_total != sum(manifest["durations_ms"]):
		raise SystemExit(f"GIF total duration mismatch: {gif_total}")
	return {"complete": True, "source_png_bytes_match": True,
		"spritesheet_cells_rgba_match": True, "transparent_nonempty_frames": True,
		"gif_display_frames_after_merge": Image.open(ROOT / "preview/preview.gif").n_frames,
		"gif_merged_frame_timing_allowed": True, "gif_total_duration_ms": gif_total,
		"diagnostics": {"edge_frames": manifest["edge_frames"],
		"margin_violation_frames": manifest["margin_violation_frames"],
		"last_frame_rgba_equal_first": manifest["last_frame_rgba_equal_first"]}}


def build_gallery(title: str, source_images: list[Image.Image], source_meta: dict,
		preview_images: list[Image.Image], preview_meta: dict, preview_durations: list[int]) -> None:
	assets: dict[str, str] = {}
	for key, full in (("before", ROOT.parents[2] / preview_meta["source_directory"] / "spritesheet.png"),
		("after", ROOT / "preview/spritesheet.png")):
		assets[key] = "data:image/png;base64," + base64.b64encode(full.read_bytes()).decode("ascii")
	before_count = source_meta["actual_frames"]
	before_timing = source_meta["durations_ms"]
	clips = [
		{"key": "before", "label": "До монтажа · исходная проба", "count": before_count,
			"timing": before_timing, "impact": -1, "sheet": "before"},
		{"key": "after", "label": "После монтажа · " + title, "count": len(preview_images),
			"timing": preview_durations, "impact": preview_meta["impact_preview_frame"], "sheet": "after"},
	]
	template = r'''<!doctype html><html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Атака воина — монтаж кадров</title><style>
*{box-sizing:border-box}body{margin:0;background:#111923;color:#edf2f7;font:16px/1.45 system-ui,sans-serif}header{padding:16px 22px;background:#202c3b;position:sticky;top:0;z-index:2}h1{font-size:23px;margin:0 0 8px}.controls{display:flex;gap:8px;flex-wrap:wrap}button,select{background:#34475d;color:#fff;border:1px solid #72859a;border-radius:5px;padding:7px 10px}main{max-width:1000px;margin:auto;padding:18px}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(290px,1fr));gap:16px}article{background:#202c3b;border:1px solid #3b4d62;border-radius:8px;padding:12px;text-align:center}.stage{height:300px;display:grid;place-items:center;background:#182131;position:relative}canvas{width:256px;height:auto;max-width:100%;image-rendering:pixelated}body.game canvas{width:102px;height:auto}body.zoom canvas{width:384px;height:auto}body.zoom .grid{grid-template-columns:repeat(auto-fit,minmax(min(100%,410px),1fr))}body.zoom .stage{height:420px}.impact{color:#ffd47e;font-weight:bold;min-height:24px}.scrub{width:100%}.note{color:#bdc9d6;font-size:13px}@media(max-width:600px){header{position:static}.stage{height:270px}}
</style></head><body><header><h1>Воин 11 · один удар</h1><div class="controls"><button id="toggle">Пауза</button><button id="replay">Повторить</button><button id="step">Следующий кадр</button><select id="speed"><option value="1">Скорость 1×</option><option value=".5">0,5×</option><option value="1.5">1,5×</option></select><select id="scale"><option value="">Размер просмотра</option><option value="game">Игровой 0,4×</option><option value="zoom">Увеличить</option></select></div></header><main><p>Сравнение исходной PixelLab-пробы с монтажом выбранных исходных кадров. Монтаж исходных кадров: изображения не перерисованы и их PNG-байты сохранены.</p><div id="gallery" class="grid"></div><p class="note">Кадр каждой дорожки можно выбрать отдельно; кнопки воспроизведения общие. Маркер показывает выбранный кадр удара; циклический повтор нужен только для сравнения. Длительности относятся к этому превью.</p><div id="error"></div></main><script>
"use strict";const ASSETS=__ASSETS__,CLIPS=__CLIPS__;let players=[],playing=true,speed=1,last=0;const $=s=>document.querySelector(s);for(const c of CLIPS){let i=players.length;$('#gallery').insertAdjacentHTML('beforeend',`<article><h2>${c.label}</h2><div class="stage"><canvas width="256" height="256" data-c="${i}"></canvas></div><p class="impact" data-impact="${i}"></p><input class="scrub" type="range" min="0" max="${c.count-1}" value="0" data-s="${i}" aria-label="Кадр ${c.label}"><p class="note">${c.count} кадров · ${c.timing.reduce((a,b)=>a+b,0)} мс</p></article>`);players.push({clip:c,frame:0,elapsed:0,loaded:false,img:new Image(),canvas:document.querySelector(`[data-c="${i}"]`),slider:document.querySelector(`[data-s="${i}"]`),marker:document.querySelector(`[data-impact="${i}"]`)})}function draw(p){if(!p.loaded)return;let x=p.canvas.getContext('2d');x.clearRect(0,0,256,256);x.drawImage(p.img,p.frame%8*256,Math.floor(p.frame/8)*256,256,256,0,0,256,256);p.slider.value=p.frame;p.marker.textContent=p.frame===p.clip.impact?'◆ КАДР УДАРА':''}players.forEach(p=>{p.slider.oninput=()=>{playing=false;$('#toggle').textContent='Играть';p.frame=+p.slider.value;p.elapsed=0;draw(p)};p.img.onload=()=>{p.loaded=true;draw(p)};p.img.onerror=()=>$('#error').textContent='Ошибка встроенного PNG-листа';p.img.src=ASSETS[p.clip.sheet]});function tick(t){if(!last)last=t;let dt=Math.min(100,t-last);last=t;if(playing)for(const p of players){if(!p.loaded)continue;p.elapsed+=dt*speed;while(p.elapsed>=p.clip.timing[p.frame]){p.elapsed-=p.clip.timing[p.frame];p.frame=(p.frame+1)%p.clip.count}draw(p)}requestAnimationFrame(tick)}$('#toggle').onclick=()=>{playing=!playing;$('#toggle').textContent=playing?'Пауза':'Играть'};$('#replay').onclick=()=>{players.forEach(p=>{p.frame=0;p.elapsed=0;draw(p)});playing=true;$('#toggle').textContent='Пауза'};$('#step').onclick=()=>{playing=false;$('#toggle').textContent='Играть';players.forEach(p=>{p.frame=(p.frame+1)%p.clip.count;p.elapsed=0;draw(p)})};$('#speed').onchange=e=>speed=+e.target.value;$('#scale').onchange=e=>document.body.className=e.target.value;window.__galleryState=()=>({clipCount:players.length,loaded:players.every(p=>p.loaded),frameIndexes:players.map(p=>p.frame)});requestAnimationFrame(tick);
</script></body></html>'''
	page = template.replace("__ASSETS__", json.dumps(assets, separators=(",", ":"))).replace("__CLIPS__", json.dumps(clips, ensure_ascii=False, separators=(",", ":")))
	(ROOT / "gallery.html").write_text(page, encoding="utf-8")


if __name__ == "__main__":
	main()
