"""Собирает автономный просмотрщик цельных кадров тела и двух предметов."""
from __future__ import annotations

import base64
import hashlib
import json
import math
import struct
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent
ASSETS = ROOT / "assets"
LEGACY_GALLERY = ROOT.parent / "whole-body-layered-20261118" / "gallery.html"


def _png_size(payload: bytes, label: str) -> tuple[int, int]:
    if len(payload) < 24 or payload[:8] != b"\x89PNG\r\n\x1a\n" or payload[12:16] != b"IHDR":
        raise ValueError(f"{label}: повреждённый PNG")
    return struct.unpack(">II", payload[16:24])


def _validate_manifest(manifest: dict[str, Any]) -> dict[str, str]:
    if manifest.get("canvas") != 256 or manifest.get("slots") != ["body", "weapon", "helmet"]:
        raise ValueError("manifest должен задавать canvas=256 и слоты body/weapon/helmet")
    clips = manifest.get("clips")
    bodies = manifest.get("bodies")
    equipment = manifest.get("equipment")
    if not isinstance(clips, dict) or not isinstance(bodies, dict) or not isinstance(equipment, dict):
        raise ValueError("manifest должен содержать clips, bodies и equipment")
    body_names = list(bodies)
    if not 1 <= len(body_names) <= 2:
        raise ValueError("Для просмотра поддерживается один или два цельных варианта тела")
    for clip_name, clip in clips.items():
        durations, sockets = clip.get("durations"), clip.get("sockets")
        if not isinstance(durations, list) or not durations or not isinstance(sockets, list) or len(durations) != len(sockets):
            raise ValueError(f"{clip_name}: число длительностей и sockets должно совпадать")
        if any(not isinstance(d, (int, float)) or d <= 0 for d in durations):
            raise ValueError(f"{clip_name}: длительности должны быть положительными")
        for body_name in body_names:
            frames = bodies.get(body_name, {}).get(clip_name)
            if not isinstance(frames, list) or len(frames) != len(durations):
                raise ValueError(f"{body_name}/{clip_name}: число полнотелых кадров не совпадает с клипом")
        for index, socket in enumerate(sockets):
            root = socket.get("root", [0, 0])
            if not isinstance(root, list) or len(root) != 2 or any(not isinstance(v, (int, float)) or isinstance(v, bool) or not math.isfinite(v) for v in root):
                raise ValueError(f"{clip_name}/{index}: socket.root должен содержать конечные dx/dy")
            if any(not (-256 <= v <= 256) for v in root):
                raise ValueError(f"{clip_name}/{index}: socket.root выходит за диапазон canvas")
            for key in ("hand", "head"):
                point = socket.get(key)
                if not isinstance(point, list) or len(point) != 2 or any(not isinstance(v, (int, float)) for v in point):
                    raise ValueError(f"{clip_name}/{index}: socket.{key} должен содержать координаты x/y")
            for key in ("weaponAngle", "headAngle", "headScale", "gripRadius"):
                if not isinstance(socket.get(key), (int, float)):
                    raise ValueError(f"{clip_name}/{index}: отсутствует числовой socket.{key}")
            if socket["headScale"] <= 0 or socket["gripRadius"] < 0 or not isinstance(socket.get("weaponBehind"), bool):
                raise ValueError(f"{clip_name}/{index}: некорректны параметры socket")
            if socket.get("helmetVariant") not in ("front", "profile"):
                raise ValueError(f"{clip_name}/{index}: helmetVariant должен быть front или profile")
    if "idle" not in clips:
        raise ValueError("Для автопроигрывания требуется clips.idle")
    paths: set[str] = set()
    for variants in bodies.values():
        for frames in variants.values():
            paths.update(frames)
    for item in equipment.values():
        if not isinstance(item, dict) or "file" not in item:
            raise ValueError("Каждый элемент equipment должен задавать file")
        for key in ("width", "height"):
            if not isinstance(item.get(key), int) or item[key] <= 0:
                raise ValueError(f"У equipment {item.get('file')} некорректен {key}")
        pivot = item.get("pivot")
        if not isinstance(pivot, list) or len(pivot) != 2 or any(not isinstance(v, (int, float)) for v in pivot):
            raise ValueError(f"У equipment {item['file']} некорректен pivot")
        paths.add(item["file"])
    result: dict[str, str] = {}
    expected_hashes = manifest.get("files_sha256", {})
    for relative in sorted(paths):
        path = (ROOT / relative).resolve()
        if not path.is_relative_to(ASSETS.resolve()) or not path.is_file():
            raise ValueError(f"Файл отсутствует или выходит за assets: {relative}")
        payload = path.read_bytes()
        width, height = _png_size(payload, relative)
        body_paths = {f for body in bodies.values() for clip in body.values() for f in clip}
        if relative in body_paths and (width, height) != (256, 256):
            raise ValueError(f"Кадр тела {relative} должен быть 256×256, получен {width}×{height}")
        for item in equipment.values():
            if item["file"] == relative and (width, height) != (item["width"], item["height"]):
                raise ValueError(f"Размер {relative}: {width}×{height}, ожидался {item['width']}×{item['height']}")
        if relative in expected_hashes and hashlib.sha256(payload).hexdigest() != expected_hashes[relative]:
            raise ValueError(f"SHA-256 не совпадает: {relative}")
        result[relative] = "data:image/png;base64," + base64.b64encode(payload).decode("ascii")
    return result


def main() -> None:
    manifest_path = ASSETS / "manifest.json"
    if not manifest_path.is_file():
        raise SystemExit("Ожидается assets/manifest.json от ведущего")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    image_urls = _validate_manifest(manifest)
    renderer_path = ROOT / "renderer.js"
    if not renderer_path.is_file():
        raise SystemExit("Не найден renderer.js")
    template = r'''<!doctype html><html lang="ru"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Разворот и перенос веса</title><style>
*{box-sizing:border-box}body{margin:0;background:#151b22;color:#e9edf1;font:14px/1.45 system-ui,sans-serif}header{padding:14px 18px;background:#222c36;position:sticky;top:0;z-index:2}h1{font-size:21px;margin:0 0 4px}.sub{color:#b8c4ce;font-size:12px;margin-bottom:10px}.controls{display:flex;align-items:center;flex-wrap:wrap;gap:8px}button,select{background:#334453;color:#fff;border:1px solid #687b89;border-radius:5px;padding:6px 9px}main{max-width:1180px;margin:auto;padding:14px}article{padding:11px;background:#202a34;border:1px solid #394753;border-radius:7px}h2{font-size:15px;margin:0 0 7px}.hero{max-width:520px;margin:auto}.cards{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:10px;margin-top:12px}.card{text-align:center}.card canvas{width:100%;height:auto;aspect-ratio:1}canvas{display:block;width:100%;height:auto;image-rendering:pixelated;background:#202a34}.scrub{width:min(230px,35vw)}.time{min-width:100px;color:#b8c4ce}.label{color:#c2ccd4;font-size:12px}.error{color:#ff9a8f;white-space:pre-wrap}@media(max-width:760px){header{position:static}.cards{grid-template-columns:repeat(2,minmax(0,1fr))}}
 </style><header><h1>Разворот и перенос веса</h1><div class="sub">Цельные покадровые позы; оружие и шлем следуют общим точкам крепления.</div><div class="controls"><label>Тело <select id="body"></select></label><label>Оружие <select id="weapon"><option value="sword">Меч</option><option value="axe">Топор</option><option value="none">Нет</option></select></label><label>Шлем <select id="helmet"><option value="none">Без шлема</option><option value="steel">Шлем</option></select></label><label>Режим <select id="mode"><option value="auto">Авто</option><option value="idle">Покой</option><option value="attack">Атака</option></select></label><button id="pause">Пауза</button><button id="restart">Сначала</button><label>Время <input class="scrub" id="scrub" type="range" min="0" max="1" step="1" value="0"></label><span class="time" id="time">0 мс</span><label>Скорость <select id="speed"><option value="0.5">0,5×</option><option selected value="1">1×</option><option value="2">2×</option></select></label><label><input id="show-body" type="checkbox" checked> Тело</label><label><input id="show-weapon" type="checkbox" checked> Оружие</label><label><input id="show-helmet" type="checkbox" checked> Шлем</label></div><div id="error" class="error" hidden></div></header><main><article class="hero"><h2>Разворот и перенос веса</h2><canvas id="hero" width="256" height="256"></canvas><div class="label" id="frame-label"></div></article><section class="cards" id="cards"></section></main><script>"use strict";window.__wholeAssets={manifest:__MANIFEST__,images:{}};const A=window.__wholeAssets;let waiting=Object.keys(__IMAGE_URLS__).length;function ready(){if(--waiting===0){window.__wholeReady=true;draw()}}for(const [path,url]of Object.entries(__IMAGE_URLS__)){const img=new Image();A.images[path]=img;img.onload=ready;img.onerror=()=>{document.getElementById("error").hidden=false;document.getElementById("error").textContent="Не загружено изображение: "+path;ready()};img.src=url}(0,eval)(__RENDERER__);const $=id=>document.getElementById(id),hero=$("hero"),bodyNames=Object.keys(A.manifest.bodies);const bodyLabels={light:"Сталь и кожа",heavy:"Стальной комплект"};for(const name of bodyNames){const option=document.createElement("option");option.value=name;option.textContent=bodyLabels[name]||name;$("body").append(option)}const cardConfigs=bodyNames.length===1?[[bodyNames[0],"sword","none"],[bodyNames[0],"sword","steel"],[bodyNames[0],"axe","none"],[bodyNames[0],"axe","steel"]]:[[bodyNames[0],"sword","none"],[bodyNames[0],"axe","steel"],[bodyNames[1],"sword","steel"],[bodyNames[1],"axe","none"]];for(const [body,weapon,helmet]of cardConfigs){const article=document.createElement("article");article.className="card";const heading=document.createElement("h2");heading.textContent=`${bodyLabels[body]||body} · ${weapon==="sword"?"Меч":"Топор"} · ${helmet==="steel"?"Шлем":"Без шлема"}`;const card=document.createElement("canvas");card.width=card.height=256;card.dataset.card="";card.dataset.body=body;card.dataset.weapon=weapon;card.dataset.helmet=helmet;article.append(heading,card);$("cards").append(article)}let time=0,last=0,playing=true,speed=1;function opts(extra={}){return{body:$("body").value,weapon:$("weapon").value,helmet:$("helmet").value,mode:$("mode").value,visible:{body:$("show-body").checked,weapon:$("show-weapon").checked,helmet:$("show-helmet").checked},...extra}}function render(c,t,o){const ctx=c.getContext("2d");ctx.clearRect(0,0,256,256);return FrameRig.render(ctx,A.manifest,A.images,t,o)}window.renderPreview=(t,o={})=>render(hero,t,{...opts(),...o});function windowDuration(mode){const names=mode==="auto"?["idle","attack"]:[mode];return names.reduce((sum,name)=>sum+(A.manifest.clips[name]?.durations||[]).reduce((a,b)=>a+b,0),0)}function draw(){if(!window.FrameRig||!window.__wholeReady)return;try{const max=windowDuration($("mode").value);$("scrub").max=String(max);const r=render(hero,time,opts());for(const c of document.querySelectorAll("canvas[data-card]"))render(c,time,opts({body:c.dataset.body,weapon:c.dataset.weapon,helmet:c.dataset.helmet}));$("frame-label").textContent=`${r.sample.clip} · кадр ${r.sample.index+1} · цикл ${r.sample.cycle}`;$("scrub").value=String(Math.min(max,time));$("time").textContent=Math.round(time)+" мс"}catch(e){$("error").hidden=false;$("error").textContent=String(e)}}function tick(now){if(!last)last=now;const dt=Math.min(100,now-last);last=now;if(playing){const duration=windowDuration($("mode").value);time=duration>0?(time+dt*speed)%duration:0}draw();requestAnimationFrame(tick)}$("pause").onclick=()=>{playing=!playing;$("pause").textContent=playing?"Пауза":"Продолжить"};$("restart").onclick=()=>{time=0;playing=true;$("pause").textContent="Пауза";draw()};$("scrub").oninput=e=>{const duration=windowDuration($("mode").value);time=duration>0?(+e.target.value)%duration:0;playing=false;$("pause").textContent="Продолжить";draw()};$("speed").onchange=e=>speed=+e.target.value;$("mode").onchange=()=>{const duration=windowDuration($("mode").value);time=duration>0?time%duration:0;draw()};for(const id of ["body","weapon","helmet","mode","show-body","show-weapon","show-helmet"])$(id).addEventListener("input",draw);window.__wholeState=()=>({time,playing,...opts()});requestAnimationFrame(tick);</script></html>'''
    page = template.replace("__MANIFEST__", json.dumps(manifest, ensure_ascii=False, separators=(",", ":")))
    page = page.replace("__IMAGE_URLS__", json.dumps(image_urls, separators=(",", ":")))
    page = page.replace("__RENDERER__", json.dumps(renderer_path.read_text(encoding="utf-8")))
    if not LEGACY_GALLERY.is_file():
        raise SystemExit(f"Не найден автономный старый просмотр: {LEGACY_GALLERY}")
    legacy_html = LEGACY_GALLERY.read_text(encoding="utf-8")
    # Встроенная строка лежит внутри script; экранируем закрывающий тег, чтобы
    # разборщик HTML не обрезал автономный документ legacy-просмотра.
    legacy_srcdoc = json.dumps(legacy_html, ensure_ascii=False).replace("</", "<\\/")
    page = page.replace(
        "<main><article class=\"hero\">",
        "<main><article class=\"hero\"><h2>Новое цельное тело</h2>",
    )
    page = page.replace(
        "</section></main><script>",
        "</section><article class=\"legacy\"><h2>Предыдущий пакет · собственный цикл 1×</h2>"
        "<iframe id=\"legacy-view\" title=\"Предыдущая версия анимации\"></iframe></article></main><script>",
    )
    page = page.replace(
        "*{box-sizing:border-box}body{",
        "*{box-sizing:border-box}.legacy iframe{width:100%;height:620px;border:0;background:#151b22}"
        "main{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px}"
        "@media(max-width:760px){main{grid-template-columns:1fr}}body{",
    )
    page = page.replace(
        '"use strict";window.__wholeAssets=',
        '"use strict";document.getElementById("legacy-view").srcdoc=' + legacy_srcdoc + ';window.__wholeAssets=',
    )
    output = ROOT / "gallery.html"
    output.write_text(page, encoding="utf-8", newline="\n")
    print(json.dumps({"images": len(image_urls), "gallery_bytes": output.stat().st_size, "offline": True}, ensure_ascii=False))


if __name__ == "__main__":
    main()
