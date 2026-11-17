"""Собирает автономный HTML предпросмотр из слоёв и общего rig.js."""
from __future__ import annotations

import base64
import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent


def main() -> None:
    manifest_path = ROOT / "assets" / "manifest.json"
    manifest: dict[str, Any] = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    required = {
        "head", "torso", "pelvis", "upper_arm", "forearm", "hand", "leg_left", "leg_right",
        "armor_light", "armor_heavy", "shoulder_light", "shoulder_heavy", "sword", "axe",
        "bracer_light", "bracer_heavy",
    }
    if set(manifest.get("parts", {})) != required:
        raise SystemExit("manifest.json должен содержать ровно все 16 определённых слоёв")
    embedded: dict[str, str] = {}
    for name, part in manifest["parts"].items():
        image_path = ROOT / part["file"]
        if not image_path.is_file():
            raise SystemExit(f"Не найден слой {name}: {image_path}")
        if len(part.get("pivot", [])) != 2 or not all(isinstance(v, (int, float)) for v in part["pivot"]):
            raise SystemExit(f"Некорректный pivot слоя {name}")
        part["width"], part["height"] = int(part["width"]), int(part["height"])
        embedded[name] = "data:image/png;base64," + base64.b64encode(image_path.read_bytes()).decode("ascii")
    js = (ROOT / "rig.js").read_text(encoding="utf-8")
    page = r'''<!doctype html><html lang="ru"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Сборная оснастка персонажа</title><style>
*{box-sizing:border-box}body{margin:0;background:#151b22;color:#e9edf1;font:14px/1.45 system-ui,sans-serif}header{padding:14px 18px;background:#222c36;position:sticky;top:0;z-index:2}h1{font-size:21px;margin:0 0 7px}.sub{color:#b8c4ce;font-size:12px;margin-bottom:10px}.controls{display:flex;align-items:center;flex-wrap:wrap;gap:8px}button,select{background:#334453;color:#fff;border:1px solid #687b89;border-radius:5px;padding:6px 9px}input[type=range]{vertical-align:middle}.time{min-width:70px;color:#b8c4ce}main{max-width:1200px;margin:auto;padding:14px}.layout{display:grid;grid-template-columns:minmax(290px,1.15fr) minmax(300px,1fr);gap:12px}article{padding:11px;background:#202a34;border:1px solid #394753;border-radius:7px}h2{font-size:15px;margin:0 0 7px}canvas{display:block;width:256px;height:256px;max-width:100%;margin:auto;image-rendering:pixelated;background:radial-gradient(ellipse,#303943,#202a34 70%)}.main canvas{width:min(100%,420px);height:auto;aspect-ratio:1}.cards{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px}.card{text-align:center}.card canvas{width:100%;height:auto;aspect-ratio:1}.checks{display:flex;flex-wrap:wrap;gap:10px;margin-top:9px;color:#c1cbd3;font-size:12px}.scrub{width:min(230px,35vw)}@media(max-width:760px){header{position:static}.layout{grid-template-columns:1fr}.main canvas{width:320px}}
</style><header><h1>Послойная оснастка · общий цикл движения</h1><div class="sub">Офлайн прототип: персонаж, броня и оружие — отдельные изображения; одна математическая поза для всех комплектов.</div><div class="controls"><label>Броня <select id="armor"><option value="light">Лёгкая</option><option value="heavy">Тяжёлая</option></select></label><label>Оружие <select id="weapon"><option value="sword">Меч</option><option value="axe">Топор</option></select></label><label>Режим <select id="mode"><option value="auto">Цикл</option><option value="breath">Дыхание</option><option value="strike">Удар</option></select></label><button id="pause">Пауза</button><button id="restart">Сначала</button><label>Время <input class="scrub" id="scrub" type="range" min="0" max="5000" step="10" value="0"></label><span class="time" id="time">0 мс</span><label>Скорость <select id="speed"><option value="0.5">0,5×</option><option selected value="1">1×</option><option value="1.5">1,5×</option><option value="2">2×</option></select></label></div><div class="checks"><label><input id="joints" type="checkbox"> Суставы</label><label>Разобрать на слои <input id="explode" type="range" min="0" max="16" value="0"></label><label><input id="showArmor" type="checkbox" checked> Броня</label><label><input id="showWeapon" type="checkbox" checked> Оружие</label></div></header><main><div class="layout"><article class="main"><h2>Выбранный комплект</h2><canvas id="hero" width="256" height="256" data-rig data-armor="light" data-weapon="sword"></canvas></article><section class="cards"><article class="card"><h2>Лёгкая · меч</h2><canvas width="256" height="256" data-rig data-armor="light" data-weapon="sword"></canvas></article><article class="card"><h2>Лёгкая · топор</h2><canvas width="256" height="256" data-rig data-armor="light" data-weapon="axe"></canvas></article><article class="card"><h2>Тяжёлая · меч</h2><canvas width="256" height="256" data-rig data-armor="heavy" data-weapon="sword"></canvas></article><article class="card"><h2>Тяжёлая · топор</h2><canvas width="256" height="256" data-rig data-armor="heavy" data-weapon="axe"></canvas></article></section></div></main><script>
"use strict";window.__rigAssets={manifest:__MANIFEST__,images:{}};const data=window.__rigAssets;let pending=0;for(const [key,url] of Object.entries(__IMAGE_URLS__)){const img=new Image();pending++;img.onload=()=>{if(!--pending)draw()};img.onerror=()=>console.error("Не загрузился слой",key);img.src=url;data.images[key]=img}window.__rigReady=Promise.all(Object.values(data.images).map(img=>img.decode()));__RIG__
const $=id=>document.getElementById(id),canvases=[...document.querySelectorAll("canvas[data-rig]")];let time=0,last=0,playing=true,speed=1;function state(){return{mode:$("mode").value,armor:$("armor").value,weapon:$("weapon").value,joints:$("joints").checked,explode:+$("explode").value,showArmor:$("showArmor").checked,showWeapon:$("showWeapon").checked,canvases}}function draw(){for(const c of canvases){const ctx=c.getContext("2d");ctx.clearRect(0,0,c.width,c.height)}window.renderPreview(time,state());$("scrub").value=String(time%5000);$("time").textContent=Math.round(time)+" мс"}function tick(now){if(!last)last=now;const dt=Math.min(100,now-last);last=now;if(playing){time+=dt*speed;if(time>=5000&&$("mode").value==="auto")time%=5000}draw();requestAnimationFrame(tick)}$("pause").onclick=()=>{playing=!playing;$("pause").textContent=playing?"Пауза":"Продолжить"};$("restart").onclick=()=>{time=0;playing=true;$("pause").textContent="Пауза";draw()};$("scrub").oninput=e=>{time=+e.target.value;playing=false;$("pause").textContent="Продолжить";draw()};$("speed").onchange=e=>speed=+e.target.value;for(const id of ["armor","weapon","mode","joints","explode","showArmor","showWeapon"])$(id).addEventListener("input",draw);window.__rigState=()=>({time,playing,...state()});requestAnimationFrame(tick);
</script></html>'''
    page = page.replace("__MANIFEST__", json.dumps(manifest, ensure_ascii=False, separators=(",", ":")))
    page = page.replace("__IMAGE_URLS__", json.dumps(embedded, separators=(",", ":")))
    page = page.replace("__RIG__", js)
    target = ROOT / "gallery.html"
    target.write_text(page, encoding="utf-8")
    print(json.dumps({"layers": len(embedded), "embedded_pngs": len(embedded), "gallery_bytes": target.stat().st_size, "offline": True}, ensure_ascii=False))


if __name__ == "__main__":
    main()
