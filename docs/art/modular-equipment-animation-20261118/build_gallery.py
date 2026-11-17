"""Собирает автономную галерею, встраивая PNG-листы без сетевых зависимостей."""
from __future__ import annotations

import base64
import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent
PREVIEW = ROOT / "preview"


def main() -> None:
	validation: dict[str, Any] = json.loads((PREVIEW / "validation.json").read_text(encoding="utf-8-sig"))
	if not validation.get("complete"):
		raise SystemExit("Галерея требует полный комплект: шесть still, шесть idle и шесть attack без pending или failed заданий")
	assets: dict[str, str] = {}
	clips = []
	for item in validation.get("exports", []):
		if item.get("kind") not in ("idle", "attack"):
			continue
		folder = ROOT / item["path"]
		meta = json.loads((folder / "clip.json").read_text(encoding="utf-8-sig"))
		if meta.get("key") != item["key"] or meta.get("kind") != item["kind"]:
			raise SystemExit(f"Метаданные не совпадают: {item['key']} {item['kind']}")
		sheet_path = folder / "spritesheet.png"
		assets[f"{item['key']}:{item['kind']}"] = "data:image/png;base64," + base64.b64encode(sheet_path.read_bytes()).decode("ascii")
		clips.append({"key": item["key"], "kind": item["kind"], "title": meta["title"], "frames": meta["actual_frames"], "durations": meta["durations_ms"], "edge": bool(meta["edge_frames"])})
	variants = json.loads((ROOT / "variants.json").read_text(encoding="utf-8-sig"))
	if len(variants) != 6 or len(clips) != 12 or not validation.get("overview", {}).get("ready"):
		raise SystemExit(f"Галерея требует все 12 клипов шести вариантов; сейчас доступно {len(clips)}")
	page = r'''<!doctype html><html lang="ru"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Экипировка и позы · PixelLab</title><style>
*{box-sizing:border-box}body{margin:0;background:#121820;color:#edf1f5;font:15px/1.4 system-ui,sans-serif}header{padding:14px 20px;background:#202b37;position:sticky;top:0;z-index:2}h1{margin:0 0 5px;font-size:22px}.note{color:#c2ccd6;font-size:13px}.controls{display:flex;flex-wrap:wrap;gap:9px;align-items:center}button,select{color:#fff;background:#344555;border:1px solid #73869a;border-radius:5px;padding:7px 10px}main{max-width:1500px;margin:auto;padding:16px}.grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:12px}article{background:#202b37;border:1px solid #3c4a57;border-radius:8px;padding:11px}h2{margin:0 0 8px;font-size:17px}.stages{display:grid;grid-template-columns:1fr 1fr;gap:8px}.stage{min-width:0;text-align:center;background:#252b34;padding:7px;border-radius:5px}.stage label{display:block;margin-bottom:5px;color:#c2ccd6;font-size:12px}canvas{display:block;width:256px;max-width:100%;height:auto;margin:auto;image-rendering:pixelated}.scrub{width:100%}body.large .grid{grid-template-columns:1fr}body.large canvas{width:512px;max-width:none}.grid.hide-idle .idle, .grid.hide-attack .attack{display:none}.grid.hide-idle .stages,.grid.hide-attack .stages{grid-template-columns:1fr}body.large .stages{grid-template-columns:1fr 1fr}.cell{font-size:12px;color:#c2ccd6;margin:6px 0 0}@media(max-width:900px){.grid{grid-template-columns:repeat(2,minmax(0,1fr))}}@media(max-width:560px){header{position:static}.grid{grid-template-columns:1fr}.stages{grid-template-columns:1fr 1fr}}
</style><header><h1>Экипировка и анимационные пробы</h1><div class="note">Концепт PixelLab · готовые кадры, не сборный каркас · без внедрения</div><div class="controls"><button id="toggle">Пауза</button><button id="restart">С начала</button><label>Показать <select id="view"><option value="both">Покой и атака</option><option value="idle">Только покой</option><option value="attack">Только атака</option></select></label><label>Скорость <select id="speed"><option value="0.5">0,5×</option><option selected value="1">1×</option><option value="1.5">1,5×</option></select></label><label><input id="large" type="checkbox"> Увеличить вдвое</label><label>Кадр <input id="scrub" type="range" min="0" max="0" value="0"></label></div></header><main><div class="grid" id="grid"></div></main><script>
"use strict";const ASSETS=__ASSETS__,VARIANTS=__VARIANTS__,CLIPS=__CLIPS__;const $=s=>document.querySelector(s);let players=[],playing=true,speed=1,last=0,seek=0;for(const v of VARIANTS){let card=document.createElement('article');card.innerHTML=`<h2>${v.title}</h2><div class="stages"><div class="stage idle"><label>Покой</label><canvas width="256" height="256"></canvas></div><div class="stage attack"><label>Атака</label><canvas width="256" height="256"></canvas></div></div>`;$('#grid').append(card);for(const kind of ['idle','attack']){let clip=CLIPS.find(c=>c.key===v.key&&c.kind===kind);if(!clip)continue;let p={clip,frame:0,elapsed:0,img:new Image(),canvas:card.querySelector('.'+kind+' canvas'),loaded:false};p.img.onload=()=>{p.loaded=true;draw(p)};p.img.src=ASSETS[`${v.key}:${kind}`];players.push(p)}}function draw(p){if(!p.loaded)return;let c=p.canvas.getContext('2d');c.clearRect(0,0,256,256);c.drawImage(p.img,p.frame%8*256,Math.floor(p.frame/8)*256,256,256,0,0,256,256)}function maxFrames(){return Math.max(0,...players.map(p=>p.clip.frames-1))}function seekAll(value){seek=+value;for(const p of players){p.frame=Math.min(seek,p.clip.frames-1);p.elapsed=0;draw(p)}}$('#scrub').max=String(maxFrames());$('#scrub').oninput=e=>{playing=false;$('#toggle').textContent='Играть';seekAll(e.target.value)};function tick(t){if(!last)last=t;let dt=Math.min(100,t-last);last=t;if(playing)for(const p of players){if(!p.loaded)continue;p.elapsed+=dt*speed;while(p.elapsed>=p.clip.durations[p.frame]){p.elapsed-=p.clip.durations[p.frame];p.frame=(p.frame+1)%p.clip.frames}draw(p)}$('#scrub').value=String(Math.max(0,...players.map(p=>p.frame)));requestAnimationFrame(tick)}$('#toggle').onclick=()=>{playing=!playing;$('#toggle').textContent=playing?'Пауза':'Играть'};$('#restart').onclick=()=>{seekAll(0);playing=true;$('#toggle').textContent='Пауза'};$('#speed').onchange=e=>speed=+e.target.value;$('#view').onchange=e=>$('#grid').className='grid '+(e.target.value==='idle'?'hide-attack':e.target.value==='attack'?'hide-idle':'');$('#large').onchange=e=>document.body.classList.toggle('large',e.target.checked);window.__galleryState=()=>({clips:players.length,loaded:players.every(p=>p.loaded)});requestAnimationFrame(tick);
</script></html>'''
	page = page.replace("__ASSETS__", json.dumps(assets, separators=(",", ":"))).replace("__VARIANTS__", json.dumps(variants, ensure_ascii=False, separators=(",", ":"))).replace("__CLIPS__", json.dumps(clips, ensure_ascii=False, separators=(",", ":")))
	(ROOT / "gallery.html").write_text(page, encoding="utf-8")
	print(json.dumps({"variants": len(variants), "clips": len(clips), "embedded_sheets": len(assets), "gallery_bytes": (ROOT / "gallery.html").stat().st_size, "visual_acceptance": "pending"}, ensure_ascii=False))


if __name__ == "__main__":
	main()
