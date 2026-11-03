"""Строит автономную галерею с исходными PNG-листами и GIF-превью."""
from pathlib import Path
import base64
import json
import mimetypes

ROOT = Path(__file__).resolve().parent


def main() -> None:
	requests = json.loads((ROOT / "requests.json").read_text(encoding="utf-8"))
	validation = json.loads((ROOT / "pixellab-validation.json").read_text(encoding="utf-8"))
	if not requests or len(validation.get("clips", [])) != len(requests):
		raise SystemExit("Request/export clip counts differ")
	if not validation.get("complete") or validation.get("expected") != len(requests):
		raise SystemExit("PixelLab exports are incomplete")
	assets: dict[str, str] = {}

	def embed(path: Path) -> str:
		if not path.is_file():
			raise SystemExit(f"Missing gallery asset: {path}")
		key = path.relative_to(ROOT).as_posix()
		mime = mimetypes.guess_type(path.name)[0]
		if mime not in ("image/png", "image/gif"):
			raise SystemExit(f"Unexpected gallery asset: {path}")
		assets[key] = f"data:{mime};base64,{base64.b64encode(path.read_bytes()).decode('ascii')}"
		return key

	source = embed(ROOT / "model" / "source-full.png")
	initial = embed(ROOT / "model" / "input-256.png")
	clips = []
	for row in requests:
		folder = ROOT / "pixellab" / row["key"]
		meta = json.loads((folder / "clip.json").read_text(encoding="utf-8"))
		if meta["key"] != row["key"] or meta["kind"] != row["kind"]:
			raise SystemExit(f"Clip manifest mismatch: {row['key']}")
		if meta["actual_frames"] != row["expected_frames"] or len(meta["durations_ms"]) != row["expected_frames"]:
			raise SystemExit(f"Incomplete clip: {row['key']}")
		clips.append({
			"key": meta["key"], "kind": row["kind"], "variant": row["variant"],
			"name": row["name"], "count": meta["actual_frames"], "timing": meta["durations_ms"],
			"loop": row["loop"], "sheet": embed(folder / "spritesheet.png"),
			"gif": embed(folder / "preview.gif"),
			"margin": bool(meta["margin_violation_frames"]),
			"last_equal": meta["last_frame_rgba_equal"],
		})
	if len(assets) != 2 + 2 * len(requests):
		raise SystemExit("Gallery must embed two model images plus a GIF and sprite sheet per request")

	asset_count = len(assets)
	clip_count = len(clips)
	template = r'''<!doctype html><html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Маг02 · Капюшон звёзд · 15 PixelLab-проб</title><style>
*{box-sizing:border-box}body{margin:0;background:#101723;color:#e8eef5;font:16px/1.4 system-ui,sans-serif}header{padding:18px 22px;background:#1a2434;position:sticky;top:0;z-index:3}h1{margin:0 0 8px;font-size:24px}h2{margin:22px 0 10px}p{color:#bdc9d6;line-height:1.4}.controls{display:flex;gap:8px;flex-wrap:wrap;align-items:center}button,select{background:#2b3c54;border:1px solid #60718b;border-radius:6px;color:#fff;padding:7px 12px;cursor:pointer}.model{display:flex;align-items:center;gap:18px;margin-bottom:16px}.model img{width:180px;height:180px;object-fit:contain;background:#202b3d}a{color:#edbe75}.grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:13px}article{background:#1b2739;border:1px solid #34465e;border-radius:9px;padding:11px;text-align:center;min-width:0}article h3{margin:3px 0 9px}.stage{height:275px;display:grid;place-items:center;background:var(--stage,#182131)}canvas{width:256px;height:auto;max-width:100%;aspect-ratio:1;image-rendering:auto}body.game canvas{width:72px}body.zoom canvas{width:384px}body.zoom .stage{height:400px}input[type=range]{width:95%}.note{font-size:13px;color:#bac9dd}.warning{color:#ffbb88}.error{color:#ff9999}footer{padding:20px}main{max-width:1500px;margin:auto;padding:18px}@media(max-width:850px){header{position:static}.grid{grid-template-columns:repeat(2,minmax(0,1fr))}.model{align-items:flex-start}.stage{height:240px}}@media(max-width:520px){header{padding:12px}main{padding:12px}.grid{grid-template-columns:1fr;gap:9px}.model{display:block}.model img{width:140px;height:140px}.stage{height:270px}body.zoom canvas{width:min(384px,90vw)}}
</style></head><body><header><h1>Маг02 · Капюшон звёзд · 15 PixelLab-проб</h1><div class="controls"><button id="play">Пауза</button><button id="restart">Сначала</button><button id="step">+ кадр</button><select id="speed"><option value="1">Скорость 1×</option><option value="0.5">0,5×</option><option value="1.5">1,5×</option></select><select id="scale"><option value="">Размер просмотра</option><option value="game">Малый размер</option><option value="zoom">Увеличить</option></select><select id="background"><option value="#182131">Тёмный фон</option><option value="#88939c">Серый фон</option><option value="#ded4b9">Светлый фон</option></select></div></header><main><div class="model"><img id="input" alt="Подготовленный маг на прозрачном фоне"><div><p>Один образ Мага 02, по пять вариантов ожидания, смерти и заклинания. Кадры поставлены в общий холст 256×256 без ручной перерисовки. Просмотр концептов; игровой интеграции нет.</p><p><a href="#" data-open="__SOURCE__">Полный исходник</a> · <a href="#" data-open="__INITIAL__">Подготовленный вход 256×256</a></p></div></div><div id="gallery"></div><p class="note">Ожидание зациклено. Смерть и заклинание проигрываются один раз и удерживают последний кадр. Отдельные GIF-превью повторяются для сравнения. Все тайминги относятся только к просмотру. Названия описывают задумку: фактическое движение может отличаться; стыки циклов и возврат в стойку требуют просмотра.</p></main><footer id="errors" class="error"></footer><script>
"use strict";const ASSETS=__ASSETS__;const CLIPS=__CLIPS__;const LABELS={idle:'Ожидание',death:'Смерть',ability:'Заклинание'};
const $=selector=>document.querySelector(selector);let players=[],playing=true,speed=1,last=0;
function openAsset(key){const data=ASSETS[key];if(!data){$('#errors').textContent='Встроенный файл не найден: '+key;return}const [head,b64]=data.split(',');const binary=atob(b64),bytes=new Uint8Array(binary.length);for(let i=0;i<binary.length;i++)bytes[i]=binary.charCodeAt(i);const url=URL.createObjectURL(new Blob([bytes],{type:head.slice(5,-7)}));const a=document.createElement('a');a.href=url;a.target='_blank';a.rel='noopener';document.body.appendChild(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),120000)}
document.addEventListener('click',event=>{const link=event.target.closest('[data-open]');if(link){event.preventDefault();openAsset(link.dataset.open)}});$('#input').src=ASSETS['__INITIAL__'];$('#input').onerror=()=>$('#errors').textContent='Не удалось загрузить встроенный входной PNG';
for(const kind of ['idle','death','ability']){const section=CLIPS.filter(clip=>clip.kind===kind);let html=`<h2>${LABELS[kind]} · ${section.length} вариантов</h2><div class="grid">`;for(const clip of section){const index=players.length;players.push({clip,frame:0,elapsed:0,img:new Image(),loaded:false});html+=`<article><h3>${LABELS[kind]} ${clip.variant} · ${clip.name}</h3><div class="stage"><canvas width="256" height="256" data-canvas="${index}"></canvas></div><input type="range" min="0" max="${clip.count-1}" value="0" data-slider="${index}" aria-label="Кадр ${clip.key}"><p class="note">${clip.count} кадров · ${clip.loop?'цикл':'одно исполнение с удержанием конца'}${clip.margin?' · <span class="warning">проверьте край кадра</span>':''}</p><p><a href="#" data-open="${clip.gif}">GIF</a> · <a href="#" data-open="${clip.sheet}">PNG-лист</a></p><div class="error" data-error="${index}"></div></article>`}$('#gallery').insertAdjacentHTML('beforeend',html+'</div>')}
players.forEach((player,index)=>{player.canvas=document.querySelector(`[data-canvas="${index}"]`);player.slider=document.querySelector(`[data-slider="${index}"]`);player.slider.oninput=()=>{playing=false;$('#play').textContent='Играть';player.frame=+player.slider.value;player.elapsed=0;draw(player)};player.img.onload=()=>{player.loaded=true;draw(player)};player.img.onerror=()=>document.querySelector(`[data-error="${index}"]`).textContent='Не удалось загрузить встроенный PNG-лист';player.img.src=ASSETS[player.clip.sheet]});
function draw(player){if(!player.loaded)return;const context=player.canvas.getContext('2d');context.clearRect(0,0,256,256);context.drawImage(player.img,player.frame%8*256,Math.floor(player.frame/8)*256,256,256,0,0,256,256);player.slider.value=player.frame}
function tick(time){if(!last)last=time;const delta=Math.min(100,time-last);last=time;if(playing)for(const player of players){if(!player.loaded)continue;player.elapsed+=delta*speed;let duration=player.clip.timing[player.frame];while(player.elapsed>=duration){player.elapsed-=duration;if(player.frame<player.clip.count-1)player.frame++;else if(player.clip.loop)player.frame=0;else{player.elapsed=0;break}duration=player.clip.timing[player.frame]}draw(player)}requestAnimationFrame(tick)}
$('#play').onclick=()=>{playing=!playing;$('#play').textContent=playing?'Пауза':'Играть'};$('#restart').onclick=()=>{for(const player of players){player.frame=0;player.elapsed=0;draw(player)}playing=true;$('#play').textContent='Пауза'};$('#step').onclick=()=>{playing=false;$('#play').textContent='Играть';for(const player of players){player.frame=Math.min(player.frame+1,player.clip.count-1);draw(player)}};$('#speed').onchange=event=>speed=+event.target.value;$('#scale').onchange=event=>document.body.className=event.target.value;$('#background').onchange=event=>document.documentElement.style.setProperty('--stage',event.target.value);window.__galleryState=()=>({assetCount:Object.keys(ASSETS).length,clipCount:players.length,loaded:players.every(player=>player.loaded),frameIndexes:players.map(player=>player.frame),clips:CLIPS.map(clip=>({key:clip.key,kind:clip.kind,loop:clip.loop,count:clip.count,timing:clip.timing}))});window.__decodeGalleryAssets=async()=>{const outcomes=await Promise.all(Object.values(ASSETS).map(url=>new Promise(resolve=>{const image=new Image();image.onload=()=>resolve(image.naturalWidth>0&&image.naturalHeight>0);image.onerror=()=>resolve(false);image.src=url})));return{count:outcomes.length,all:outcomes.every(Boolean)}};requestAnimationFrame(tick);
</script></body></html>'''
	html = (template.replace("__ASSETS__", json.dumps(assets, separators=(",", ":")))
		.replace("__CLIPS__", json.dumps(clips, ensure_ascii=False, separators=(",", ":")))
		.replace("__SOURCE__", source).replace("__INITIAL__", initial))
	output = ROOT / "gallery.html"
	output.write_text(html, encoding="utf-8")
	print(json.dumps({"clips": clip_count, "embedded_assets": asset_count, "html_bytes": output.stat().st_size}))


if __name__ == "__main__":
	main()
