"""Строит автономную галерею пяти вариантов атаки без предположений о циклах."""
from pathlib import Path
import base64
import json

ROOT = Path(__file__).resolve().parent


def main() -> None:
	rows = json.loads((ROOT / "requests.json").read_text(encoding="utf-8-sig"))
	validation = json.loads((ROOT / "pixellab-validation.json").read_text(encoding="utf-8-sig"))
	if len(rows) != 5 or len(validation.get("clips", [])) != 5 or not validation.get("complete"):
		raise SystemExit("Expected five completed attack exports")
	assets: dict[str, str] = {}
	clips = []
	for row in rows:
		folder = ROOT / "pixellab" / row["key"]
		meta = json.loads((folder / "clip.json").read_text(encoding="utf-8-sig"))
		if meta.get("key") != row["key"] or meta.get("kind") != "attack" or meta.get("actual_frames") != 33:
			raise SystemExit(f"Clip manifest mismatch: {row['key']}")
		for filename in ("spritesheet.png", "preview.gif"):
			path = folder / filename
			assets[path.relative_to(ROOT).as_posix()] = "data:" + ("image/gif" if filename.endswith("gif") else "image/png") + ";base64," + base64.b64encode(path.read_bytes()).decode("ascii")
		clips.append({"key": row["key"], "variant": row["variant"], "name": row["name"],
			"prompt": row["prompt"], "count": 33, "timing": meta["durations_ms"], "sheet": (folder / "spritesheet.png").relative_to(ROOT).as_posix(),
			"gif": (folder / "preview.gif").relative_to(ROOT).as_posix(), "edge": bool(meta["edge_frames"]),
			"margin": bool(meta["margin_violation_frames"]), "first_match": meta["first_frame_alpha_equal"] and meta["first_frame_visible_differing_pixels"] == 0, "last_match": meta["last_frame_rgba_equal"]})
	if len(assets) != 10:
		raise SystemExit("Gallery must embed exactly two assets per attack")
	page = r'''<!doctype html><html lang="ru"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Воин 11 — гиперболизированные атаки</title><style>
*{box-sizing:border-box}body{margin:0;background:#111923;color:#edf2f7;font:16px/1.45 system-ui,sans-serif}header{padding:16px 22px;background:#202c3b;position:sticky;top:0;z-index:2}h1{margin:0 0 8px;font-size:24px}.controls{display:flex;gap:8px;flex-wrap:wrap}button,select{background:#34475d;color:white;border:1px solid #72859a;border-radius:5px;padding:7px 10px}main{max-width:1400px;margin:auto;padding:18px}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(250px,1fr));gap:14px}article{background:#202c3b;border:1px solid #3b4d62;border-radius:8px;padding:12px}.stage{height:280px;display:grid;place-items:center;background:var(--back,#182131)}canvas{width:256px;height:auto;max-width:100%;image-rendering:pixelated}body.game canvas{width:102px;height:auto}body.zoom canvas{width:384px;height:auto}body.zoom .grid{grid-template-columns:repeat(auto-fit,minmax(min(100%,408px),1fr))}body.zoom .stage{height:408px}.scrub{width:100%}.note{font-size:13px;color:#bdc9d6}a{color:#f2c77f}.warning{color:#ffc18d}@media(max-width:550px){header{position:static}main{padding:10px}.stage{height:260px}}
</style><header><h1>Воин 11 · мощный замах и след меча</h1><div class="controls"><button id="toggle">Пауза</button><button id="replay">Повторить</button><button id="step">Следующий кадр</button><select id="speed"><option value="1">Скорость 1×</option><option value=".5">0,5×</option><option value="1.5">1,5×</option></select><select id="scale"><option value="">Размер просмотра</option><option value="game">Игровой 0,4×</option><option value="zoom">Увеличить</option></select><select id="back"><option value="#182131">Тёмный фон</option><option value="#87939d">Серый фон</option><option value="#ded4ba">Светлый фон</option><option value="transparent">Шахматный фон</option></select></div></header><main><p>Пять новых проб: утрированный замах, широкая дуга и акцент на ударе. Тайминг задан локально: первые 32 кадра по 50 мс, последний — 700 мс. Это автономная художественная галерея; интеграции в игру нет.</p><div class="grid" id="grid"></div><p class="note">Просматривайте крайние кадры, поля и возврат к исходной стойке. Предупреждения геометрии показывают места для оценки, сами изображения не изменены.</p><div id="error" class="warning"></div></main><script>
"use strict";const ASSETS=__ASSETS__,CLIPS=__CLIPS__;let players=[],playing=true,speed=1,last=0;const $=s=>document.querySelector(s);for(const c of CLIPS){const i=players.length;$('#grid').insertAdjacentHTML('beforeend',`<article><h2>Атака ${c.variant} · ${c.name}</h2><details class="note"><summary>Задание PixelLab</summary><p>${c.prompt}</p></details><div class="stage"><canvas width="256" height="256" data-c="${i}"></canvas></div><input class="scrub" type="range" min="0" max="32" value="0" data-s="${i}" aria-label="Кадр атаки ${c.variant}"><p class="note">33 кадра · ${c.first_match?'первый видимый кадр совпадает с входом':'<span class="warning">проверьте первый кадр'}${c.last_match?' · возврат совпадает':' · конечная поза отличается'}${c.edge?' · край холста':''}${c.margin?' · отступ меньше 8 px':''}</span></p><a href="#" data-open="${c.gif}">GIF</a> · <a href="#" data-open="${c.sheet}">PNG-лист</a></article>`);players.push({clip:c,frame:0,elapsed:0,loaded:false,img:new Image(),canvas:document.querySelector(`[data-c="${i}"]`),slider:document.querySelector(`[data-s="${i}"]`)})}function draw(p){if(!p.loaded)return;let x=p.canvas.getContext('2d');x.clearRect(0,0,256,256);x.drawImage(p.img,p.frame%8*256,Math.floor(p.frame/8)*256,256,256,0,0,256,256);p.slider.value=p.frame}players.forEach(p=>{p.slider.oninput=()=>{playing=false;$('#toggle').textContent='Играть';p.frame=+p.slider.value;p.elapsed=0;draw(p)};p.img.onload=()=>{p.loaded=true;draw(p)};p.img.onerror=()=>$('#error').textContent='Ошибка встроенного изображения';p.img.src=ASSETS[p.clip.sheet]});function tick(t){if(!last)last=t;let dt=Math.min(100,t-last);last=t;if(playing)for(const p of players){if(!p.loaded)continue;p.elapsed+=dt*speed;while(p.elapsed>=p.clip.timing[p.frame]){p.elapsed-=p.clip.timing[p.frame];if(p.frame===32){p.frame=0}else p.frame++}draw(p)}requestAnimationFrame(tick)}$('#toggle').onclick=()=>{playing=!playing;$('#toggle').textContent=playing?'Пауза':'Играть'};$('#replay').onclick=()=>{players.forEach(p=>{p.frame=0;p.elapsed=0;draw(p)});playing=true;$('#toggle').textContent='Пауза'};$('#step').onclick=()=>{playing=false;$('#toggle').textContent='Играть';players.forEach(p=>{p.frame=(p.frame+1)%33;p.elapsed=0;draw(p)})};$('#speed').onchange=e=>speed=+e.target.value;$('#scale').onchange=e=>document.body.className=e.target.value;$('#back').onchange=e=>document.documentElement.style.setProperty('--back',e.target.value==='transparent'?'conic-gradient(#59616b 25%,#343c46 0 50%,#59616b 0 75%,#343c46 0) 0/24px 24px':e.target.value);document.addEventListener('click',e=>{let a=e.target.closest('[data-open]');if(!a)return;e.preventDefault();let url=URL.createObjectURL(awaitBlob(ASSETS[a.dataset.open]));window.open(url,'_blank','noopener');setTimeout(()=>URL.revokeObjectURL(url),60000)});function awaitBlob(data){let [h,b]=data.split(',');let s=atob(b),u=new Uint8Array(s.length);for(let i=0;i<s.length;i++)u[i]=s.charCodeAt(i);return new Blob([u],{type:h.slice(5,-7)})}window.__galleryState=()=>({assetCount:Object.keys(ASSETS).length,clipCount:players.length,loaded:players.every(p=>p.loaded)});requestAnimationFrame(tick);
</script></html>'''
	page = page.replace("__ASSETS__", json.dumps(assets, separators=(",", ":"))).replace("__CLIPS__", json.dumps(clips, ensure_ascii=False, separators=(",", ":")))
	(ROOT / "gallery.html").write_text(page, encoding="utf-8")
	print(json.dumps({"clips": len(clips), "embedded_assets": len(assets), "html_bytes": (ROOT / "gallery.html").stat().st_size}))


if __name__ == "__main__":
	main()
