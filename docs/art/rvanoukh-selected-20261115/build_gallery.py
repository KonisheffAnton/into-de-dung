"""Build an offline gallery for the three user-selected animation clips."""
from pathlib import Path
import base64
import hashlib
import json
import mimetypes

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[2]
SOURCE = REPO / "docs/art/rvanoukh-animation-20261115"
BG = (24, 33, 49, 255)
CLIP_SPECS = [
	{"key": "idle-3", "kind": "idle", "name": "Основное ожидание №3", "role": "Основное ожидание", "folder": "idle-3", "loop": True},
	{"key": "idle-2", "kind": "idle", "name": "Редкое ожидание №2", "role": "Редкое ожидание · частота не задана", "folder": "idle-2", "loop": True},
	{"key": "death-1-closed-eyes", "kind": "death", "name": "Смерть №1 — закрытые глаза", "role": "Смерть · закрытые глаза", "folder": "death-1-closed-eyes", "loop": False},
]


def sha(data: bytes) -> str:
	return hashlib.sha256(data).hexdigest()


def json_sha(path: Path) -> str:
	value = json.loads(path.read_text(encoding="utf-8-sig"))
	return sha(json.dumps(value, sort_keys=True, separators=(",", ":")).encode("utf-8"))


def font(size: int):
	for path in (Path("C:/Windows/Fonts/arial.ttf"), Path("C:/Windows/Fonts/segoeui.ttf")):
		if path.is_file():
			return ImageFont.truetype(str(path), size=size)
	return ImageFont.load_default()


def frame_from_sheet(path: Path, index: int) -> Image.Image:
	with Image.open(path) as sheet:
		return sheet.crop(((index % 8) * 256, (index // 8) * 256,
			(index % 8 + 1) * 256, (index // 8 + 1) * 256)).convert("RGBA")


def create_overview(rows: list[dict]) -> None:
	canvas = Image.new("RGBA", (1536, 190), BG)
	draw = ImageDraw.Draw(canvas)
	for column, clip in enumerate(rows):
		x = column * 512
		draw.text((x + 10, 7), clip["name"], font=font(18), fill="#f4d18e")
		for sample_col, frame_index in enumerate((0, 8, 16, 24, 32)):
			sheet_root = SOURCE if clip["kind"] == "idle" else ROOT
			frame = frame_from_sheet(sheet_root / clip["sheet_file"], frame_index)
			frame = frame.resize((128, 128), Image.Resampling.NEAREST)
			canvas.alpha_composite(frame, (x + 8 + sample_col * 98, 42))
	canvas.convert("RGB").save(ROOT / "overview.png")


def composite_preview(rows: list[dict]) -> None:
	# Объединяем временные границы, чтобы у каждого клипа сохранился собственный шаг.
	boundaries = {0}
	death_durations = rows[2]["timing"]
	total = sum(death_durations)
	boundaries.update(range(90, total, 90))
	clock = 0
	for duration in death_durations:
		clock += duration
		if clock < total:
			boundaries.add(clock)
	times = sorted(boundaries)
	images, durations = [], []
	for pos, start in enumerate(times):
		end = times[pos + 1] if pos + 1 < len(times) else total
		panels = []
		for clip in rows:
			if clip["loop"]:
				frame_index = (start // clip["timing"][0]) % clip["count"]
			else:
				elapsed = 0
				frame_index = clip["count"] - 1
				for i, duration in enumerate(clip["timing"]):
					if start < elapsed + duration:
						frame_index = i
						break
					elapsed += duration
			sheet_root = SOURCE if clip["kind"] == "idle" else ROOT
			panels.append(frame_from_sheet(sheet_root / clip["sheet_file"], frame_index))
		frame = Image.new("RGBA", (768, 256), BG)
		for i, panel in enumerate(panels):
			frame.alpha_composite(panel, (i * 256, 0))
		images.append(frame.convert("RGB").resize((1536, 512), Image.Resampling.NEAREST))
		durations.append(end - start)
	images[0].save(ROOT / "preview.gif", save_all=True, append_images=images[1:], duration=durations,
		loop=0, disposal=2, optimize=False)


def main() -> None:
	selected = json.loads((ROOT / "selection.json").read_text(encoding="utf-8-sig"))
	assets: dict[str, str] = {}

	def embed(key: str, path: Path) -> str:
		if not path.is_file():
			raise SystemExit(f"Missing selected gallery asset: {path}")
		mime = mimetypes.guess_type(path.name)[0]
		if mime not in ("image/png", "image/gif"):
			raise SystemExit(f"Unsupported gallery asset type: {path}")
		assets[key] = f"data:{mime};base64," + base64.b64encode(path.read_bytes()).decode("ascii")
		return key

	rows = []
	for spec in CLIP_SPECS:
		if spec["key"] == "idle-3":
			selection = selected["main_idle"]
		elif spec["key"] == "idle-2":
			selection = selected["rare_idle"]
		else:
			selection = selected["death"]
		folder = SOURCE / "pixellab" / spec["folder"] if spec["kind"] == "idle" else ROOT / "death-1-closed-eyes"
		base_folder = SOURCE / "pixellab/death-1" if spec["kind"] == "death" else folder
		meta = json.loads((folder / "clip.json").read_text(encoding="utf-8-sig"))
		if spec["kind"] == "death":
			base_meta = json.loads((base_folder / "clip.json").read_text(encoding="utf-8-sig"))
			source_sheet = embed("source/death-1/spritesheet.png", base_folder / "spritesheet.png")
		else:
			base_meta = meta
			source_sheet = None
		sheet_path = folder / meta["spritesheet"]["file"].split("/")[-1] if spec["kind"] == "idle" else ROOT / meta["spritesheet"]["file"]
		sheet_file = embed(f"selected/{spec['key']}/spritesheet.png", sheet_path)
		rows.append({**spec, "variant": meta["variant"], "count": meta["actual_frames"],
			"timing": meta["durations_ms"], "source_timing": base_meta["durations_ms"],
			"sheet": sheet_file, "sheet_file": sheet_path.relative_to(ROOT).as_posix() if spec["kind"] == "death" else sheet_path.relative_to(SOURCE).as_posix(),
			"sourceSheet": source_sheet, "sourceFolder": selection["source"],
			"sourceClipSha256": json_sha(folder / "clip.json"),
			"loop": spec["loop"], "anchor": meta["anchor"]})
	create_overview(rows)
	composite_preview(rows)
	overview = embed("overview.png", ROOT / "overview.png")
	preview = embed("preview.gif", ROOT / "preview.gif")
	data = {"clips": rows, "assets": sorted(assets), "embedded_asset_count": len(assets),
		"selected": selected, "preview": preview, "overview": overview, "runtime_integration": False}
	(ROOT / "gallery-data.json").write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
	template = r'''<!doctype html><html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Рваноух · выбранные клипы</title><style>
*{box-sizing:border-box}body{margin:0;background:#101723;color:#e8eef5;font:15px/1.4 system-ui,sans-serif}header{padding:14px 18px;background:#1a2434;position:sticky;top:0;z-index:2}h1{margin:0 0 8px;font-size:22px}.controls{display:flex;gap:8px;align-items:center;flex-wrap:wrap}button,select{background:#2b3c54;border:1px solid #60718b;border-radius:5px;color:#fff;padding:7px 11px;cursor:pointer}main{max-width:1320px;margin:auto;padding:14px}.grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:12px}.card{background:#1b2739;border:1px solid #34465e;border-radius:7px;padding:10px;text-align:center;min-width:0}.card h2{font-size:17px;margin:1px 0 3px}.role{font-size:12px;color:#bac9dd;min-height:20px}.stage{height:282px;display:grid;place-items:center;background:var(--stage,#182131);margin:7px 0;border-radius:4px}.stage canvas{width:256px;height:256px;image-rendering:pixelated}.stage.small canvas{width:128px;height:128px}.stage.large{height:402px}.stage.large canvas{width:384px;max-width:100%;height:auto;aspect-ratio:1}input[type=range]{width:96%}.links{font-size:13px;min-height:22px}.links button{font-size:12px;padding:4px 8px}.note{font-size:12px;color:#bac9dd}.overview{max-width:100%;height:auto;image-rendering:pixelated}.gif{max-width:min(100%,768px);height:auto;image-rendering:pixelated}.bar{display:flex;gap:6px;justify-content:center;flex-wrap:wrap}@media(max-width:900px){header{position:static}.grid{grid-template-columns:1fr 1fr}}@media(max-width:580px){main{padding:8px}.grid{grid-template-columns:1fr}}
</style></head><body><header><h1>Рваноух · выбранные анимации</h1><div class="controls"><button id="play">Пауза</button><button id="restart">Сначала</button><button id="step">+ кадр</button><label>Скорость <select id="speed"><option value="1">1×</option><option value="0.5">0,5×</option><option value="1.5">1,5×</option></select></label><label>Масштаб <select id="scale"><option value="native">256px</option><option value="small">0,5×</option><option value="large">1,5×</option></select></label><label>Фон <select id="background"><option value="#182131">Тёмный</option><option value="#727d89">Серый</option><option value="#ded4b9">Светлый</option></select></label></div></header><main><p class="note">Редкое ожидание — выбранная вариация; игровая частота не задана. Атаки не включены в эту подборку. Холст 256×256; сохранены исходные движения и тайминги.</p><section class="grid" id="gallery"></section><h2>Обзор поз</h2><img class="overview" src="__OVERVIEW__" alt="Статичный обзор трёх клипов"><h2>Три клипа вместе · GIF-превью</h2><img class="gif" src="__PREVIEW__" alt="Три выбранных клипа с исходными интервалами кадров"></main><script>
"use strict";const ASSETS=__ASSETS__,CLIPS=__CLIPS__;let players=[],playing=true,speed=1,lastTime=0;const $=s=>document.querySelector(s);const labels={idle:'Ожидание',death:'Смерть'};for(const clip of CLIPS){const i=players.length;players.push({clip,frame:0,elapsed:0,images:{},loaded:false,showSource:false});const before=clip.sourceSheet?`<button data-source="${i}">Исходник</button>`:'';$('#gallery').insertAdjacentHTML('beforeend',`<article class="card"><h2>${clip.name}</h2><div class="role">${clip.role}</div><div class="stage"><canvas width="256" height="256" data-canvas="${i}"></canvas></div><input type="range" min="0" max="32" value="0" data-slider="${i}" aria-label="Кадр ${clip.key}"><div class="links bar">${before}</div><p class="note">33 кадра · ${clip.loop?'цикл ожидания':'удержание последнего кадра'}</p></article>`)}function draw(p){if(!p.loaded)return;const c=p.canvas.getContext('2d'),sheet=p.showSource&&p.clip.sourceSheet?p.images.source:p.images.selected;if(!sheet)return;c.clearRect(0,0,256,256);c.drawImage(sheet,(p.frame%8)*256,Math.floor(p.frame/8)*256,256,256,0,0,256,256);p.slider.value=p.frame}players.forEach((p,i)=>{p.canvas=document.querySelector(`[data-canvas="${i}"]`);p.slider=document.querySelector(`[data-slider="${i}"]`);p.slider.oninput=()=>{playing=false;$('#play').textContent='Играть';p.frame=Number(p.slider.value);p.elapsed=0;draw(p)};for(const [type,key] of [['selected',p.clip.sheet],['source',p.clip.sourceSheet]])if(key){const image=new Image();image.onload=()=>{p.images[type]=image;if(p.images.selected&&(!p.clip.sourceSheet||p.images.source))p.loaded=true;draw(p)};image.src=ASSETS[key]} });document.querySelectorAll('[data-source]').forEach(b=>b.onclick=()=>{const p=players[Number(b.dataset.source)];p.showSource=!p.showSource;b.textContent=p.showSource?'С закрытыми глазами':'Исходник';draw(p)});function tick(now){if(!lastTime)lastTime=now;const dt=Math.min(100,now-lastTime);lastTime=now;if(playing)for(const p of players){if(!p.loaded)continue;p.elapsed+=dt*speed;let d=p.clip.timing[p.frame];while(p.elapsed>=d){p.elapsed-=d;if(p.frame<p.clip.count-1)p.frame++;else if(p.clip.loop)p.frame=0;else{p.elapsed=0;break}d=p.clip.timing[p.frame]}draw(p)}requestAnimationFrame(tick)}$('#play').onclick=()=>{playing=!playing;$('#play').textContent=playing?'Пауза':'Играть'};$('#restart').onclick=()=>{for(const p of players){p.frame=0;p.elapsed=0;draw(p)}playing=true;$('#play').textContent='Пауза'};$('#step').onclick=()=>{playing=false;$('#play').textContent='Играть';for(const p of players){p.frame=Math.min(p.frame+1,p.clip.count-1);draw(p)}};$('#speed').onchange=e=>speed=Number(e.target.value);$('#scale').onchange=e=>document.querySelectorAll('.stage').forEach(el=>el.className='stage '+(e.target.value==='small'?'small':e.target.value==='large'?'large':''));$('#background').onchange=e=>document.documentElement.style.setProperty('--stage',e.target.value);window.__galleryState=()=>({assets:Object.keys(ASSETS).length,clips:players.length,loaded:players.every(p=>p.loaded)});requestAnimationFrame(tick);
</script></body></html>'''
	html = (template.replace("__ASSETS__", json.dumps(assets, separators=(",", ":")))
		.replace("__CLIPS__", json.dumps(rows, ensure_ascii=False, separators=(",", ":")))
		.replace("__OVERVIEW__", assets[overview]).replace("__PREVIEW__", assets[preview]))
	(ROOT / "gallery.html").write_text(html, encoding="utf-8")
	print(json.dumps({"clips": len(rows), "assets": len(assets), "gallery_bytes": len(html.encode("utf-8")),
		"preview_gif": "preview.gif", "overview": "overview.png"}, ensure_ascii=False))


if __name__ == "__main__":
	main()
