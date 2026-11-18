"""Собирает автономную галерею, встраивая актуальные слои и общий renderer."""
from __future__ import annotations

import base64
import hashlib
import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent
REFERENCE = ROOT.parent / "modular-equipment-animation-20261118" / "preview" / "clips" / "light-sword" / "attack"


def main() -> None:
    manifest_path = ROOT / "assets" / "manifest.json"
    manifest: dict[str, Any] = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    parts = manifest.get("parts")
    if not isinstance(parts, dict) or not parts:
        raise SystemExit("assets/manifest.json должен содержать непустой parts")
    images: dict[str, str] = {}
    for key, part in parts.items():
        if not isinstance(key, str) or not isinstance(part, dict):
            raise SystemExit(f"Некорректное определение слоя: {key!r}")
        for field in ("file", "width", "height", "pivot", "flip_x", "sha256"):
            if field not in part:
                raise SystemExit(f"У слоя {key} отсутствует {field}")
        path = (ROOT / part["file"]).resolve()
        if not path.is_relative_to(ROOT.resolve()) or not path.is_file():
            raise SystemExit(f"Файл слоя {key} отсутствует или выходит за каталог assets: {path}")
        if not isinstance(part["width"], int) or not isinstance(part["height"], int) or min(part["width"], part["height"]) <= 0:
            raise SystemExit(f"Некорректный размер слоя {key}")
        pivot = part["pivot"]
        if not isinstance(pivot, list) or len(pivot) != 2 or not all(isinstance(v, (int, float)) for v in pivot):
            raise SystemExit(f"Некорректный pivot слоя {key}")
        if not isinstance(part["flip_x"], bool):
            raise SystemExit(f"Некорректный flip_x слоя {key}")
        payload = path.read_bytes()
        if hashlib.sha256(payload).hexdigest() != part["sha256"]:
            raise SystemExit(f"SHA-256 слоя {key} не совпадает с manifest")
        images[key] = "data:image/png;base64," + base64.b64encode(payload).decode("ascii")
    renderer = ROOT / "motion.js"
    if not renderer.is_file():
        raise SystemExit("Ожидается assets и motion.js от ведущего")
    ref_png = REFERENCE / "spritesheet.png"
    clip = json.loads((REFERENCE / "clip.json").read_text(encoding="utf-8"))
    if not ref_png.is_file() or len(clip.get("durations_ms", [])) < 24:
        raise SystemExit("Не найден PixelLab spritesheet или данные длительности клипа")
    ref = "data:image/png;base64," + base64.b64encode(ref_png.read_bytes()).decode("ascii")
    template = r'''<!doctype html><html lang="ru"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Natural layered character · preview</title><style>
*{box-sizing:border-box}body{margin:0;background:#151b22;color:#e9edf1;font:14px/1.45 system-ui,sans-serif}header{padding:14px 18px;background:#222c36;position:sticky;top:0;z-index:2}h1{font-size:21px;margin:0 0 4px}.sub{color:#b8c4ce;font-size:12px;margin-bottom:10px}.controls{display:flex;align-items:center;flex-wrap:wrap;gap:8px}button,select{background:#334453;color:#fff;border:1px solid #687b89;border-radius:5px;padding:6px 9px}main{max-width:1280px;margin:auto;padding:14px}.top{display:grid;grid-template-columns:1.15fr 1fr;gap:12px}article{padding:11px;background:#202a34;border:1px solid #394753;border-radius:7px}h2{font-size:15px;margin:0 0 7px}.pair{display:grid;grid-template-columns:1fr 1fr;gap:10px}.pair canvas{width:100%;height:auto;aspect-ratio:1}.cards{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:10px;margin-top:12px}.card{text-align:center}.card canvas{width:100%;height:auto;aspect-ratio:1}canvas{display:block;image-rendering:pixelated;background:radial-gradient(ellipse,#303943,#202a34 70%)}.scrub{width:min(230px,35vw)}.time{min-width:70px;color:#b8c4ce}.label{color:#c2ccd4;font-size:12px}.refbox{overflow:hidden}.refsheet{display:none}.reference{position:relative}.refindex{position:absolute;left:8px;top:8px;background:#151b22d9;padding:3px 7px;border-radius:4px}@media(max-width:760px){header{position:static}.top{grid-template-columns:1fr}.cards{grid-template-columns:repeat(2,minmax(0,1fr))}}
</style><header><h1>Сборный персонаж · движение и экипировка</h1><div class="sub">Послойный прототип движения: выбор брони меняет весь комплект — корпус, руки и ноги. Перчатки и сапоги отдельно не экипируются; справа показан ориентир PixelLab в той же фазе.</div><div class="controls"><label>Оружие <select id="weapon"><option value="sword">Меч</option><option value="axe">Топор</option></select></label><label>Броня · весь комплект <select id="armor"><option value="none">Без брони</option><option value="light" selected>Лёгкий комплект</option><option value="heavy">Тяжёлый комплект</option></select></label><label>Шлем <select id="helmet"><option value="none">Без шлема</option><option value="steel">Стальной</option></select></label><label>Режим <select id="mode"><option value="auto">Цикл 4 с</option><option value="breath">Дыхание</option><option value="strike">Удар 2 с</option></select></label><button id="pause">Пауза</button><button id="restart">Сначала</button><label>Время <input class="scrub" id="scrub" type="range" min="0" max="4000" step="10" value="0"></label><span class="time" id="time">0 мс</span><label>Скорость <select id="speed"><option value="0.5">0,5×</option><option selected value="1">1×</option></select></label><label><input id="joints" type="checkbox"> Суставы</label></div></header><img id="refsheet" class="refsheet" alt=""><main><div class="top"><article><h2>Новый персонаж · текущая экипировка</h2><canvas id="hero" width="256" height="256"></canvas></article><article class="refbox"><h2>Готовая анимация PixelLab · примерная фаза</h2><div class="pair"><div><canvas id="referenceFrame" width="256" height="256"></canvas><div class="label">PixelLab · кадр <span id="refindex">1 / 25</span></div></div><div><canvas id="refpose" width="256" height="256"></canvas><div class="label">Новая поза на том же времени</div></div></div><div class="label">Обе стороны показывают фазу по времени действия; позы могут отличаться.</div></article></div><section class="cards"><article class="card"><h2>Без брони · меч</h2><canvas width="256" height="256" data-card data-armor="none" data-weapon="sword" data-helmet="none"></canvas></article><article class="card"><h2>Лёгкая · меч</h2><canvas width="256" height="256" data-card data-armor="light" data-weapon="sword" data-helmet="none"></canvas></article><article class="card"><h2>Тяжёлая · топор</h2><canvas width="256" height="256" data-card data-armor="heavy" data-weapon="axe" data-helmet="none"></canvas></article><article class="card"><h2>Стальной шлем</h2><canvas width="256" height="256" data-card data-armor="light" data-weapon="sword" data-helmet="steel"></canvas></article></section><p><a href="../layered-character-rig-20261118/gallery.html" style="color:#a9c9ff">Предыдущая версия галереи</a></p></main><script>
"use strict";window.__naturalAssets={manifest:__MANIFEST__,images:{}};const A=window.__naturalAssets;let pending=Object.keys(__IMAGE_URLS__).length;function ready(){if(--pending===0){window.__naturalReady=true;draw()}}for(const [k,url]of Object.entries(__IMAGE_URLS__)){const i=new Image();A.images[k]=i;i.onload=ready;i.onerror=()=>{console.error("Не загружен слой",k);ready()};i.src=url}document.getElementById("refsheet").src="__REFERENCE__";(0,eval)(__MOTION__);
const $=id=>document.getElementById(id),hero=$("hero"),refpose=$("refpose"),referenceFrame=$("referenceFrame"),cards=[...document.querySelectorAll("canvas[data-card]")];let time=0,last=0,playing=true,speed=1;function options(extra={}){return{mode:$("mode").value,weapon:$("weapon").value,armor:$("armor").value,helmet:$("helmet").value,joints:$("joints").checked,...extra}}function render(c,t,o){const x=c.getContext("2d");x.clearRect(0,0,256,256);return window.NaturalRig.render(x,A.manifest,A.images,t,o)}window.renderPreview=(t,o={})=>render(hero,t,options(o));function draw(){if(!window.NaturalRig)return;const heroResult=render(hero,time,options());render(refpose,time,options());const action=Math.max(0,Math.min(2000,heroResult.pose.actionTimeMs||0));const index=Math.max(0,Math.min(24,Math.floor(action/70)));$("refindex").textContent=`${index+1} / 25`;const sheet=$("refsheet"),cols=8,sw=sheet.naturalWidth/cols,sh=256,cx=referenceFrame.getContext("2d");cx.clearRect(0,0,256,256);if(sheet.complete&&sheet.naturalWidth)cx.drawImage(sheet,(index%cols)*sw,Math.floor(index/cols)*sh,sw,sh,0,0,256,256);for(const c of cards)render(c,time,options({armor:c.dataset.armor,weapon:c.dataset.weapon,helmet:c.dataset.helmet}));$("scrub").value=String(time%4000);$("time").textContent=Math.round(time)+" мс"}function tick(now){if(!last)last=now;const dt=Math.min(100,now-last);last=now;if(playing){time+=dt*speed;if(time>=4000&&$("mode").value==="auto")time%=4000}draw();requestAnimationFrame(tick)}$("pause").onclick=()=>{playing=!playing;$("pause").textContent=playing?"Пауза":"Продолжить"};$("restart").onclick=()=>{time=0;playing=true;$("pause").textContent="Пауза";draw()};$("scrub").oninput=e=>{time=+e.target.value;playing=false;$("pause").textContent="Продолжить";draw()};$("speed").onchange=e=>speed=+e.target.value;for(const id of ["weapon","armor","helmet","mode","joints"])$(id).addEventListener("input",draw);window.__naturalState=()=>({time,playing,...options()});requestAnimationFrame(tick);
</script></html>'''
    page = template.replace("__MANIFEST__", json.dumps(manifest, ensure_ascii=False, separators=(",", ":")))
    page = page.replace("__IMAGE_URLS__", json.dumps(images, separators=(",", ":")))
    page = page.replace("__REFERENCE__", ref)
    page = page.replace("__MOTION__", json.dumps(renderer.read_text(encoding="utf-8")))
    target = ROOT / "gallery.html"
    target.write_text(page, encoding="utf-8", newline="\n")
    print(json.dumps({"parts": len(images), "gallery_bytes": target.stat().st_size, "offline": True}, ensure_ascii=False))


if __name__ == "__main__":
    main()
