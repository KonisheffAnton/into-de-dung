"""Строит обзор движений и автономную 3×3 галерею без перекодирования кадров."""
from pathlib import Path
import base64
import json
import mimetypes

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[2]
WARRIOR_SOURCE = REPO / "assets/art_presets/approved/character_skins_v1/red_bastion/still.png"
KINDS = ("idle", "ability", "death")
KIND_RU = {"idle": "Ожидание", "ability": "Атака", "death": "Смерть"}
BG = "#182131"


def font(size: int):
	for path in (Path("C:/Windows/Fonts/arial.ttf"), Path("C:/Windows/Fonts/segoeui.ttf")):
		if path.is_file():
			return ImageFont.truetype(str(path), size=size)
	return ImageFont.load_default()


def create_overview(clips: list[dict]) -> None:
	width, cell_w, cell_h, label_h = 1536, 512, 180, 28
	canvas = Image.new("RGBA", (width, cell_h * 3), BG)
	draw = ImageDraw.Draw(canvas)
	for variant in range(1, 4):
		for col, kind in enumerate(KINDS):
			clip = next(c for c in clips if c["variant"] == variant and c["kind"] == kind)
			cell_x, cell_y = col * cell_w, (variant - 1) * cell_h
			draw.text((cell_x + 10, cell_y + 5), f"{KIND_RU[kind]} · вариант {variant} · {clip['name']}", font=font(16), fill="#f4d18e")
			if not clip.get("available"):
				draw.text((cell_x + 18, cell_y + 78), "Ожидает генерацию", font=font(16), fill="#c8d2dd")
				continue
			if not clip.get("available"):
				draw.text((cell_x + 18, cell_y + 78), "Ожидает генерацию", font=font(16), fill="#c8d2dd")
				continue
			sheet_path = ROOT / "pixellab" / clip["key"] / "spritesheet.png"
			with Image.open(sheet_path) as source:
				sprite = source.convert("RGBA")
			for sample_col, frame_index in enumerate((0, 8, 16, 24, 32)):
				x0, y0 = (frame_index % 8) * 256, (frame_index // 8) * 256
				frame = sprite.crop((x0, y0, x0 + 256, y0 + 256)).resize((94, 94), Image.Resampling.NEAREST)
				background = Image.new("RGBA", frame.size, BG)
				background.alpha_composite(frame)
				canvas.alpha_composite(background, (cell_x + 10 + sample_col * 98, cell_y + label_h))
	canvas.convert("RGB").save(ROOT / "overview.png")


def main() -> None:
	requests_path = ROOT / "requests.json"
	requests = json.loads(requests_path.read_text(encoding="utf-8-sig"))
	validation = json.loads((ROOT / "pixellab-validation.json").read_text(encoding="utf-8-sig"))
	if not isinstance(requests, list) or len(requests) != 9 or len(validation.get("clips", [])) != validation.get("completed"):
		raise SystemExit("Need a consistent partial export manifest")
	assets: dict[str, str] = {}

	def embed(relative: str) -> str:
		path = ROOT / relative
		if not path.is_file():
			raise SystemExit(f"Missing gallery asset: {relative}")
		mime = mimetypes.guess_type(path.name)[0]
		if mime not in ("image/png", "image/gif"):
			raise SystemExit(f"Unsupported embedded asset type: {relative}")
		key = Path(relative).as_posix()
		assets[key] = f"data:{mime};base64," + base64.b64encode(path.read_bytes()).decode("ascii")
		return key

	def embed_file(key: str, path: Path) -> str:
		if not path.is_file():
			raise SystemExit(f"Missing reference asset: {path}")
		assets[key] = "data:image/png;base64," + base64.b64encode(path.read_bytes()).decode("ascii")
		return key

	model_source = embed("model/source-full.png")
	model_input = embed("model/input-256.png")
	warrior = embed_file("runtime/red_bastion/still.png", WARRIOR_SOURCE)
	clips = []
	for row in requests:
		folder = ROOT / "pixellab" / row["key"]
		clip_path = folder / "clip.json"
		if not clip_path.is_file():
			clips.append({"key": row["key"], "kind": row["kind"], "variant": row["variant"], "name": row["name"],
				"available": False, "count": row["expected_frames"], "timing": [], "loop": row["loop"],
				"sheet": None, "gif": None, "edgeFrames": [], "quarantined": False})
			continue
		meta = json.loads(clip_path.read_text(encoding="utf-8-sig"))
		if meta.get("key") != row["key"] or meta.get("kind") != row["kind"] or meta.get("variant") != row["variant"]:
			raise SystemExit(f"Clip identity mismatch: {row['key']}")
		if meta.get("actual_frames") != 33 or len(meta.get("durations_ms", [])) != 33:
			raise SystemExit(f"Expected exactly 33 frames: {row['key']}")
		clips.append({"key": row["key"], "kind": row["kind"], "variant": row["variant"], "name": row["name"],
			"available": True, "count": meta["actual_frames"], "timing": meta["durations_ms"], "loop": row["loop"],
			"spritesheet_file": meta["spritesheet"]["file"], "sheet": embed(meta["spritesheet"]["file"]), "gif": embed(meta["preview_gif"]["file"]),
			"edgeFrames": meta["raw_alpha_edge_frames"], "quarantined": bool(meta["raw_alpha_edge_frames"]),
			"firstConsistency": meta["first_frame_consistency"], "lastConsistency": meta["last_frame_consistency"]})
	completed = sum(bool(clip["available"]) for clip in clips)
	if len(assets) != 3 + 2 * completed:
		raise SystemExit(f"Expected two assets per completed clip; got {len(assets)} assets for {completed} clips")
	create_overview(clips)
	overview = embed("overview.png")
	input_meta = json.loads((ROOT / "model/input-manifest.json").read_text(encoding="utf-8-sig"))
	data = {"assets": sorted(assets), "clips": clips, "model_input_sha256": input_meta["input_sha256"],
		"model_transform_sha256": input_meta["transform_sha256"], "warrior_reference": warrior,
		"overview": overview, "embedded_asset_count": len(assets), "completed_clips": completed, "runtime_integration": False}
	(ROOT / "gallery-data.json").write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
	template = r'''<!doctype html><html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Рваноух · PixelLab анимационные пробы</title><style>
*{box-sizing:border-box}body{margin:0;background:#101723;color:#e8eef5;font:15px/1.4 system-ui,sans-serif}header{padding:16px 20px;background:#1a2434;position:sticky;top:0;z-index:3}h1{margin:0 0 8px;font-size:23px}h2{font-size:18px;margin:20px 0 9px}.controls{display:flex;gap:8px;align-items:center;flex-wrap:wrap}button,select{background:#2b3c54;border:1px solid #60718b;border-radius:5px;color:white;padding:7px 11px;cursor:pointer}main{max-width:1440px;margin:auto;padding:15px}.refs{display:flex;gap:24px;align-items:flex-start;flex-wrap:wrap}.ref{display:flex;gap:10px;align-items:center;background:#1b2739;padding:10px;border-radius:6px}.ref img{width:256px;height:256px;object-fit:contain;image-rendering:pixelated;background:#202b3d}.ref p{max-width:260px;color:#bdc9d6}.grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:10px}.card{min-width:0;background:#1b2739;border:1px solid #34465e;border-radius:7px;padding:9px;text-align:center}.card h3{font-size:15px;min-height:38px;margin:2px 0 6px}.stage{height:275px;display:grid;place-items:center;background:var(--stage,#182131);border-radius:4px}.stage canvas{width:256px;height:256px;image-rendering:pixelated}.stage.small canvas{width:102px;height:102px}.stage.large canvas{width:384px;height:384px;max-height:270px;max-width:100%}input[type=range]{width:96%}.note{font-size:12px;color:#bac9dd;min-height:32px}a{color:#f0ca81}.overview{max-width:100%;height:auto;image-rendering:pixelated}footer{padding:16px;color:#becbd9}.warning{color:#ffb680}@media(max-width:920px){header{position:static}.grid{grid-template-columns:repeat(2,minmax(0,1fr))}}@media(max-width:560px){main{padding:9px}.grid{grid-template-columns:1fr}.refs{display:block}.ref{margin-bottom:8px}.ref img{width:150px;height:150px}}
</style></head><body><header><h1>Рваноух · девять PixelLab-проб анимации</h1><div class="controls"><button id="play">Пауза</button><button id="restart">Сначала</button><button id="step">+ кадр</button><label>Скорость <select id="speed"><option value="1">1×</option><option value="0.5">0,5×</option><option value="1.5">1,5×</option></select></label><label>Масштаб <select id="scale"><option value="native">256px</option><option value="small">0,4×</option><option value="large">1,5×</option></select></label><label>Фон <select id="background"><option value="#182131">Тёмный</option><option value="#727d89">Серый</option><option value="#ded4b9">Светлый</option></select></label></div></header><main><section class="refs"><div class="ref"><img src="__INPUT__" alt="Рваноух, подготовленный холст 256 на 256"><p><b>Рваноух</b><br>Холст 256×256, видимая высота 101px. <a href="#" data-open="__SOURCE__">Полный исходник</a></p></div><div class="ref"><img src="__WARRIOR__" alt="Воин 11 в нативном размере 256 на 256"><p><b>Воин 11 · статичный эталон</b><br>Тот же холст 256×256, видимая высота 152px; сравнение без нормализации.</p></div></section><h2>Обзор кадров</h2><img class="overview" src="__OVERVIEW__" alt="Подписанный обзор девяти анимаций"><div id="gallery" class="grid"></div><p class="note">Ожидание зациклено. Атака и смерть проигрываются один раз и удерживают последний кадр. GIF-файлы повторяются только для просмотра. Тайминги заданы для концепт-превью, не для runtime.</p></main><footer id="errors"></footer><script>
"use strict";const ASSETS=__ASSETS__,CLIPS=__CLIPS__;let players=[],playing=true,speed=1,lastTime=0;const $=s=>document.querySelector(s);function openAsset(key){const data=ASSETS[key];if(!data)return;const [head,b64]=data.split(','),bin=atob(b64),bytes=new Uint8Array(bin.length);for(let i=0;i<bin.length;i++)bytes[i]=bin.charCodeAt(i);const url=URL.createObjectURL(new Blob([bytes],{type:head.slice(5,-7)})),a=document.createElement('a');a.href=url;a.target='_blank';a.rel='noopener';a.click();setTimeout(()=>URL.revokeObjectURL(url),60000)}document.addEventListener('click',e=>{const a=e.target.closest('[data-open]');if(a){e.preventDefault();openAsset(a.dataset.open)}});
const labels={idle:'Ожидание',ability:'Атака',death:'Смерть'};for(let variant=1;variant<=3;variant++)for(const kind of ['idle','ability','death']){const clip=CLIPS.find(c=>c.variant===variant&&c.kind===kind);if(!clip)throw Error('Не найден клип '+variant+'/'+kind);const index=players.length;players.push({clip,frame:0,elapsed:0,image:new Image(),loaded:false});$('#gallery').insertAdjacentHTML('beforeend',`<article class="card"><h3>${labels[kind]} ${variant} · ${clip.name}</h3><div class="stage"><canvas width="256" height="256" data-canvas="${index}"></canvas></div><input type="range" min="0" max="32" value="0" data-slider="${index}" aria-label="Кадр ${clip.key}"><p class="note">33 кадра · ${clip.loop?'цикл':'однократный просмотр с удержанием конца'}${clip.edgeFrames.length?' · <span class="warning">край кадра требует проверки</span>':''}${clip.quarantined?' · <span class="warning">Артефакт в углу — не выбирать</span>':''}</p><p><a href="#" data-open="${clip.gif}">GIF-превью</a> · <a href="#" data-open="${clip.sheet}">PNG-лист</a></p></article>`)}players.forEach((p,i)=>{p.canvas=document.querySelector(`[data-canvas="${i}"]`);p.slider=document.querySelector(`[data-slider="${i}"]`);p.slider.oninput=()=>{playing=false;$('#play').textContent='Играть';p.frame=Number(p.slider.value);p.elapsed=0;draw(p)};p.image.onload=()=>{p.loaded=true;draw(p)};p.image.src=ASSETS[p.clip.sheet]});function draw(p){if(!p.loaded)return;const c=p.canvas.getContext('2d');c.clearRect(0,0,256,256);c.drawImage(p.image,(p.frame%8)*256,Math.floor(p.frame/8)*256,256,256,0,0,256,256);p.slider.value=p.frame}function tick(now){if(!lastTime)lastTime=now;const delta=Math.min(100,now-lastTime);lastTime=now;if(playing)for(const p of players){if(!p.loaded)continue;p.elapsed+=delta*speed;let duration=p.clip.timing[p.frame];while(p.elapsed>=duration){p.elapsed-=duration;if(p.frame<p.clip.count-1)p.frame++;else if(p.clip.loop)p.frame=0;else{p.elapsed=0;break}duration=p.clip.timing[p.frame]}draw(p)}requestAnimationFrame(tick)}$('#play').onclick=()=>{playing=!playing;$('#play').textContent=playing?'Пауза':'Играть'};$('#restart').onclick=()=>{for(const p of players){p.frame=0;p.elapsed=0;draw(p)}playing=true;$('#play').textContent='Пауза'};$('#step').onclick=()=>{playing=false;$('#play').textContent='Играть';for(const p of players){p.frame=Math.min(p.frame+1,p.clip.count-1);draw(p)}};$('#speed').onchange=e=>speed=Number(e.target.value);$('#scale').onchange=e=>document.querySelectorAll('.stage').forEach(el=>el.className='stage '+(e.target.value==='small'?'small':e.target.value==='large'?'large':''));$('#background').onchange=e=>document.documentElement.style.setProperty('--stage',e.target.value);window.__galleryState=()=>({assets:Object.keys(ASSETS).length,clips:players.length,loaded:players.every(p=>p.loaded),clipsData:CLIPS.map(c=>({key:c.key,count:c.count,loop:c.loop,timing:c.timing}))});requestAnimationFrame(tick);
</script></body></html>'''
	template = template.replace(
		".stage.large canvas{width:384px;height:384px;max-height:270px;max-width:100%}",
		".stage.large{height:403px}.stage.large canvas{width:384px;max-width:100%;height:auto;aspect-ratio:1}")
	template = template.replace(
		"if(!clip)throw Error('Не найден клип '+variant+'/'+kind);const index=players.length;",
		"if(!clip)throw Error('Не найден клип '+variant+'/'+kind);if(!clip.available){$('#gallery').insertAdjacentHTML('beforeend',`<article class=\"card\"><h3>${labels[kind]} ${variant} · ${clip.name}</h3><div class=\"stage\"><p class=\"note\">Клип ещё генерируется</p></div></article>`);continue}const index=players.length;")
	template = template.replace("clip.edgeFrames.length?' · <span class=\"warning\">край кадра требует проверки</span>':''",
		"!clip.quarantined&&clip.edgeFrames.length?' · <span class=\"warning\">Край кадра требует проверки</span>':''")
	html = (template.replace("__ASSETS__", json.dumps(assets, separators=(",", ":")))
		.replace("__CLIPS__", json.dumps(clips, ensure_ascii=False, separators=(",", ":")))
		.replace("__INPUT__", assets[model_input]).replace("__SOURCE__", model_source)
		.replace("__WARRIOR__", assets[warrior]).replace("__OVERVIEW__", assets[overview]))
	(ROOT / "gallery.html").write_text(html, encoding="utf-8")
	print(json.dumps({"clips": len(clips), "embedded_assets": len(assets), "html_bytes": len(html.encode("utf-8"))}))


if __name__ == "__main__":
	main()
