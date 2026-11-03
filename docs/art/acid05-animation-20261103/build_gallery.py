"""Собирает автономную галерею десяти циклов с вшитыми исходными кадрами."""
from pathlib import Path
import base64
import json
import mimetypes

ROOT = Path(__file__).resolve().parent


def main() -> None:
	requests = json.loads((ROOT / "requests.json").read_text(encoding="utf-8"))
	validation = json.loads((ROOT / "pixellab-validation.json").read_text(encoding="utf-8"))
	keys = [f"acid-{index:02d}" for index in range(1, 11)]
	if len(requests) != 10 or [row.get("key") for row in requests] != keys:
		raise SystemExit("Галерея требует ровно десять запросов acid-01…acid-10")
	if validation.get("expected") != 10 or validation.get("completed") != 10 or not validation.get("complete"):
		raise SystemExit("Экспорт PixelLab должен содержать все десять клипов")
	assets: dict[str, str] = {}

	def embed(path: Path) -> str:
		if not path.is_file():
			raise SystemExit(f"Отсутствует файл галереи: {path}")
		key = path.relative_to(ROOT).as_posix()
		mime = mimetypes.guess_type(path.name)[0]
		if mime not in ("image/png", "image/gif"):
			raise SystemExit(f"Неожиданный файл галереи: {path}")
		assets[key] = f"data:{mime};base64,{base64.b64encode(path.read_bytes()).decode('ascii')}"
		return key

	source = embed(ROOT / "model" / "source-original.png")
	initial = embed(ROOT / "model" / "input-256.png")
	clips = []
	for row in requests:
		if row.get("kind") != "acid" or row.get("frame_count") != 32 or row.get("expected_frames") != 33:
			raise SystemExit(f"Некорректный запрос галереи: {row['key']}")
		folder = ROOT / "pixellab" / row["key"]
		meta = json.loads((folder / "clip.json").read_text(encoding="utf-8"))
		if meta.get("key") != row["key"] or meta.get("kind") != "acid":
			raise SystemExit(f"Manifest не совпадает с запросом: {row['key']}")
		if meta.get("actual_frames") != 33 or len(meta.get("durations_ms", [])) != 33 or not meta.get("loop"):
			raise SystemExit(f"Клип неполный или не циклический: {row['key']}")
		clips.append({
			"key": meta["key"], "variant": row["variant"], "name": row["name"],
			"count": meta["actual_frames"],
			"timing": meta["durations_ms"], "loop": True,
			"sheet": embed(folder / "sheet.png"), "gif": embed(folder / "preview.gif"),
			"edge": bool(meta["edge_frames"]),
			"endpoint_equal": meta["endpoint_frame_rgba_equal"],
		})
	if len(assets) != 2 + 2 * len(requests):
		raise SystemExit("Галерея должна встраивать два исходных изображения, GIF и лист каждого клипа")

	template = r'''<!doctype html><html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Кислота 05 · 10 вариантов анимации</title><style>
*{box-sizing:border-box}body{margin:0;background:#101723;color:#e8eef5;font:16px/1.45 system-ui,sans-serif}header{padding:16px 22px;background:#1a2434;position:sticky;top:0;z-index:3}h1{margin:0 0 9px;font-size:24px}.controls{display:flex;gap:8px;flex-wrap:wrap;align-items:center}button,select{background:#2b3c54;border:1px solid #60718b;border-radius:6px;color:#fff;padding:7px 12px;cursor:pointer}main{max-width:1500px;margin:auto;padding:18px}.source{display:flex;gap:18px;align-items:center;margin-bottom:20px}.source img{width:180px;height:180px;object-fit:contain;background-color:#202b3d;background-image:linear-gradient(45deg,#586273 25%,transparent 25%),linear-gradient(-45deg,#586273 25%,transparent 25%),linear-gradient(45deg,transparent 75%,#586273 75%),linear-gradient(-45deg,transparent 75%,#586273 75%);background-size:20px 20px;background-position:0 0,0 10px,10px -10px,-10px 0}p{color:#bdc9d6}.grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:13px}article{background:#1b2739;border:1px solid #34465e;border-radius:9px;padding:11px;min-width:0}article h2{font-size:18px;margin:3px 0 8px}.stage{height:275px;display:grid;place-items:center;background-color:var(--stage,#182131);background-image:var(--check,none)}canvas{width:256px;height:auto;aspect-ratio:1;max-width:100%}input[type=range]{width:100%}.note{font-size:13px;color:#bac9dd}.warning{color:#ffbb88}a{color:#edbe75}body.small canvas{width:96px}body.large canvas{width:384px}body.large .stage{height:400px}footer{padding:18px;color:#bbc7d5}@media(max-width:850px){header{position:static}.grid{grid-template-columns:repeat(2,minmax(0,1fr))}.stage{height:240px}}@media(max-width:540px){main{padding:12px}.grid{grid-template-columns:1fr}.source{align-items:flex-start}.source img{width:120px;height:120px}.stage{height:270px}body.large canvas{width:min(384px,90vw)}}
</style></head><body><header><h1>Кислота 05 · 10 PixelLab-вариантов</h1><div class="controls"><button id="play">Пауза</button><button id="restart">Сначала</button><button id="step">+ кадр</button><select id="speed"><option value="1">Скорость 1×</option><option value="0.5">0,5×</option><option value="1.5">1,5×</option><option value="2">2×</option></select><select id="size"><option value="">Размер</option><option value="small">Малый</option><option value="large">Увеличенный</option></select><select id="background"><option value="dark">Тёмный фон</option><option value="checker">Шахматный фон</option></select></div></header><main><section class="source"><img id="input" alt="Входное изображение кислоты 05"><div><p>Десять концептуальных циклов из одного подготовленного входа 256×256. Просмотр воспроизводит возвращённые кадры; тайминг задан только для этой галереи.</p><p><a href="#" data-open="__SOURCE__">Исходное изображение</a> · <a href="#" data-open="__INITIAL__">Вход 256×256</a></p></div></section><div id="gallery" class="grid"></div></main><footer>Для каждого клипа доступны исходный PNG-лист и GIF-превью. Шахматная подложка помогает видеть прозрачность. Метки описывают задумку варианта; оцените движение, стык и возврат в исходную позу визуально. В игровую интеграцию не включено.</footer><script>
"use strict";const ASSETS=__ASSETS__,CLIPS=__CLIPS__;const $=s=>document.querySelector(s);let players=[],playing=true,speed=1,last=0;
function openAsset(key){const data=ASSETS[key];if(!data)return;const [head,b64]=data.split(','),binary=atob(b64),bytes=new Uint8Array(binary.length);for(let i=0;i<binary.length;i++)bytes[i]=binary.charCodeAt(i);const url=URL.createObjectURL(new Blob([bytes],{type:head.slice(5,-7)})),a=document.createElement('a');a.href=url;a.target='_blank';a.rel='noopener';document.body.appendChild(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),120000)}document.addEventListener('click',e=>{const a=e.target.closest('[data-open]');if(a){e.preventDefault();openAsset(a.dataset.open)}});$('#input').src=ASSETS['__INITIAL__'];
$('#gallery').innerHTML=CLIPS.map((clip,index)=>`<article><h2>Вариант ${clip.variant} · ${clip.name}</h2><div class="stage"><canvas width="256" height="256" data-canvas="${index}"></canvas></div><input type="range" min="0" max="${clip.count-1}" value="0" data-slider="${index}" aria-label="Кадр ${clip.variant}"><p class="note" data-counter="${index}">Кадр 1 / ${clip.count}</p><p class="note">Цикл · ${clip.count} кадров${clip.endpoint_equal?' · последний кадр совпадает с исходным':''}${clip.edge?' · <span class="warning">кадр касается края холста</span>':''}</p><p><a href="#" data-open="${clip.gif}">GIF-превью</a> · <a href="#" data-open="${clip.sheet}">PNG-лист</a></p></article>`).join('');
players=CLIPS.map((clip,index)=>{const player={clip,frame:0,elapsed:0,img:new Image(),canvas:document.querySelector(`[data-canvas="${index}"]`),slider:document.querySelector(`[data-slider="${index}"]`),counter:document.querySelector(`[data-counter="${index}"]`),loaded:false};player.slider.oninput=()=>{playing=false;$('#play').textContent='Играть';player.frame=+player.slider.value;player.elapsed=0;draw(player)};player.img.onload=()=>{player.loaded=true;draw(player)};player.img.src=ASSETS[clip.sheet];return player});function draw(p){if(!p.loaded)return;const c=p.canvas.getContext('2d');c.clearRect(0,0,256,256);c.drawImage(p.img,p.frame%8*256,Math.floor(p.frame/8)*256,256,256,0,0,256,256);p.slider.value=p.frame;p.counter.textContent=`Кадр ${p.frame+1} / ${p.clip.count}`}function tick(time){if(!last)last=time;const delta=Math.min(100,time-last);last=time;if(playing)for(const p of players){if(!p.loaded)continue;p.elapsed+=delta*speed;while(p.elapsed>=p.clip.timing[p.frame]){p.elapsed-=p.clip.timing[p.frame];p.frame=(p.frame+1)%p.clip.count}draw(p)}requestAnimationFrame(tick)}$('#play').onclick=()=>{playing=!playing;$('#play').textContent=playing?'Пауза':'Играть'};$('#restart').onclick=()=>{players.forEach(p=>{p.frame=0;p.elapsed=0;draw(p)});playing=true;$('#play').textContent='Пауза'};$('#step').onclick=()=>{playing=false;$('#play').textContent='Играть';players.forEach(p=>{p.frame=(p.frame+1)%p.clip.count;draw(p)})};$('#speed').onchange=e=>speed=+e.target.value;$('#size').onchange=e=>document.body.className=e.target.value;$('#background').onchange=e=>{const checker=e.target.value==='checker';document.documentElement.style.setProperty('--stage',checker?'#c8c8c8':'#182131');document.documentElement.style.setProperty('--check',checker?'linear-gradient(45deg,#66717f 25%,transparent 25%,transparent 75%,#66717f 75%),linear-gradient(45deg,#66717f 25%,transparent 25%,transparent 75%,#66717f 75%)':'none');document.querySelectorAll('.stage').forEach(stage=>stage.style.backgroundSize=checker?'20px 20px':'auto');document.querySelectorAll('.stage').forEach(stage=>stage.style.backgroundPosition=checker?'0 0,10px 10px':'0 0')};window.__galleryState=()=>({assetCount:Object.keys(ASSETS).length,clipCount:players.length,loaded:players.every(p=>p.loaded),frames:players.map(p=>p.frame)});requestAnimationFrame(tick);
</script></body></html>'''
	encoded_assets = json.dumps(assets, separators=(",", ":")).replace("<", "\\u003c")
	encoded_clips = json.dumps(clips, ensure_ascii=False, separators=(",", ":")).replace("<", "\\u003c")
	html = (template.replace("__ASSETS__", encoded_assets).replace("__CLIPS__", encoded_clips)
		.replace("__SOURCE__", source).replace("__INITIAL__", initial))
	output = ROOT / "gallery.html"
	output.write_text(html, encoding="utf-8")
	print(json.dumps({"clips": len(clips), "embedded_assets": len(assets), "html_bytes": output.stat().st_size}))


if __name__ == "__main__":
	main()
