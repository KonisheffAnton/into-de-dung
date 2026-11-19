"""Собирает автономное сравнение двух полнотелых покадровых анимаций."""
from __future__ import annotations

import base64
import hashlib
import json
import struct
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent
ASSETS = ROOT / "assets"
LEGACY = ROOT.parent / "whole-body-weighted-strike-20261118"


def _size(payload: bytes, label: str) -> tuple[int, int]:
    if len(payload) < 24 or payload[:8] != b"\x89PNG\r\n\x1a\n" or payload[12:16] != b"IHDR":
        raise ValueError(f"{label}: повреждённый PNG")
    return struct.unpack(">II", payload[16:24])


def _embedded(manifest_path: Path, root: Path) -> tuple[dict[str, Any], dict[str, str]]:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    paths: set[str] = set()
    for body in manifest["bodies"].values():
        for frames in body.values():
            paths.update(frames)
    paths.update(item["file"] for item in manifest["equipment"].values())
    urls: dict[str, str] = {}
    expected = manifest.get("files_sha256", {})
    for relative in sorted(paths):
        path = (root / relative).resolve()
        if not path.is_relative_to((root / "assets").resolve()) or not path.is_file():
            raise ValueError(f"Файл отсутствует или выходит за assets: {relative}")
        data = path.read_bytes()
        width, height = _size(data, relative)
        if relative.startswith("assets/body/") and (width, height) != (256, 256):
            raise ValueError(f"Полнотелый кадр {relative} должен быть 256×256")
        if relative in expected and hashlib.sha256(data).hexdigest() != expected[relative]:
            raise ValueError(f"SHA-256 не совпадает: {relative}")
        urls[relative] = "data:image/png;base64," + base64.b64encode(data).decode("ascii")
    return manifest, urls


def main() -> None:
    target_manifest = ASSETS / "manifest.json"
    if not target_manifest.is_file():
        raise SystemExit("Ожидается assets/manifest.json от ведущего")
    old_manifest = LEGACY / "assets" / "manifest.json"
    if not old_manifest.is_file():
        raise SystemExit(f"Не найден предыдущий manifest: {old_manifest}")
    current, current_urls = _embedded(target_manifest, ROOT)
    previous, previous_urls = _embedded(old_manifest, LEGACY)
    renderer = ROOT / "renderer.js"
    if not renderer.is_file():
        raise SystemExit("Не найден renderer.js")
    page = r'''<!doctype html>
<html lang="ru"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Плавный переход в ударе</title><style>
*{box-sizing:border-box}body{margin:0;background:#151b22;color:#e9edf1;font:14px/1.45 system-ui,sans-serif}
header{padding:14px 18px;background:#222c36;position:sticky;top:0;z-index:2}h1{font-size:21px;margin:0 0 4px}
.sub{color:#b8c4ce;font-size:12px;margin-bottom:10px}.controls{display:flex;align-items:center;flex-wrap:wrap;gap:8px}
button,select{background:#334453;color:#fff;border:1px solid #687b89;border-radius:5px;padding:6px 9px}
main{max-width:1180px;margin:auto;padding:14px;display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px}
article{padding:11px;background:#202a34;border:1px solid #394753;border-radius:7px;text-align:center}h2{font-size:15px;margin:0 0 7px}
canvas{display:block;width:100%;height:auto;image-rendering:pixelated;background:#202a34}.scrub{width:min(230px,35vw)}
.time{min-width:100px;color:#b8c4ce}.label{color:#c2ccd4;font-size:12px}.error{color:#ff9a8f;white-space:pre-wrap}
@media(max-width:760px){header{position:static}main{grid-template-columns:1fr}}
</style><header><h1>Плавный переход в ударе</h1>
<div class="sub">Сравните плавность замаха и возврата; оружие и шлем следуют одним и тем же точкам крепления.</div>
<div class="controls"><label>Оружие <select id="weapon"><option value="none">Нет</option><option value="sword">Меч</option><option value="axe">Топор</option></select></label>
<label>Шлем <select id="helmet"><option value="none">Без шлема</option><option value="steel">Сталь и кожа</option></select></label>
<label>Режим <select id="mode"><option value="auto">Дыхание + удар</option><option value="idle">Дыхание</option><option value="attack">Удар</option></select></label>
<button id="pause">Пауза</button><label>Время <input class="scrub" id="scrub" type="range" min="0" max="1" step="1" value="0"></label>
<span class="time" id="time">0 мс</span><label>Скорость <select id="speed"><option value="0.5">0,5×</option><option selected value="1">1×</option><option value="2">2×</option></select></label></div>
<div id="error" class="error" hidden></div></header><main>
<article><h2>Предыдущая версия · свой цикл 1×</h2><canvas id="legacy" width="256" height="256"></canvas></article>
<article><h2>Плавные переходы · свой цикл 1×</h2><canvas id="hero" width="256" height="256"></canvas></article></main>
<script>
"use strict";
window.__legacyAssets={manifest:__OLD_MANIFEST__,images:{}};
window.__wholeAssets={manifest:__NEW_MANIFEST__,images:{}};
window.__legacyReady=false;window.__wholeReady=false;
function loadImages(asset,urls,markReady){let remaining=Object.keys(urls).length;
  const ready=()=>{remaining--;if(remaining===0)markReady()};
  for(const[path,url]of Object.entries(urls)){const img=new Image();asset.images[path]=img;
    img.onload=ready;img.onerror=()=>{const e=document.getElementById("error");e.hidden=false;e.textContent="Не загружено изображение: "+path;ready()};img.src=url;}}
loadImages(window.__legacyAssets,__OLD_URLS__,()=>window.__legacyReady=true);
loadImages(window.__wholeAssets,__NEW_URLS__,()=>window.__wholeReady=true);
(0,eval)(__RENDERER__);
const $=id=>document.getElementById(id),oldCanvas=$("legacy"),newCanvas=$("hero");
let time=0,last=0,playing=true,speed=1;
function duration(manifest,mode){const names=mode==="auto"?["idle","attack"]:[mode];return names.reduce((sum,n)=>sum+(manifest.clips[n]?.durations||[]).reduce((a,b)=>a+b,0),0)}
function render(canvas,asset,t){const ctx=canvas.getContext("2d");ctx.clearRect(0,0,256,256);
  return FrameRig.render(ctx,asset.manifest,asset.images,t,{body:Object.keys(asset.manifest.bodies)[0],weapon:$("weapon").value,helmet:$("helmet").value,mode:$("mode").value});}
window.renderPreview=(t,options={})=>{const a=window.__wholeAssets,ctx=newCanvas.getContext("2d");ctx.clearRect(0,0,256,256);return FrameRig.render(ctx,a.manifest,a.images,t,{body:Object.keys(a.manifest.bodies)[0],weapon:$("weapon").value,helmet:$("helmet").value,mode:$("mode").value,...options});};
window.__renderAtForQA=t=>{window.__setTimeForQA(t);const old=render(oldCanvas,window.__legacyAssets,t),current=render(newCanvas,window.__wholeAssets,t);return{old,current}};
function draw(){if(!window.FrameRig||!window.__legacyReady||!window.__wholeReady)return;try{
  const old=render(oldCanvas,window.__legacyAssets,time),current=render(newCanvas,window.__wholeAssets,time);
  const max=duration(window.__wholeAssets.manifest,$("mode").value);$("scrub").max=String(max);$("scrub").value=String(time%max);
  $("time").textContent=Math.round(time)+" мс";
  oldCanvas.dataset.frame=old.sample.clip+":"+old.sample.index;newCanvas.dataset.frame=current.sample.clip+":"+current.sample.index;
}catch(e){$("error").hidden=false;$("error").textContent=String(e)}}
function tick(now){if(!last)last=now;const dt=Math.min(100,now-last);last=now;
  if(playing)time+=dt*speed;draw();requestAnimationFrame(tick)}
$("pause").onclick=()=>{playing=!playing;$("pause").textContent=playing?"Пауза":"Продолжить"};
$("scrub").oninput=e=>{const d=duration(window.__wholeAssets.manifest,$("mode").value);time=d>0?(+e.target.value)%d:0;playing=false;$("pause").textContent="Продолжить";draw()};
$("speed").onchange=e=>speed=+e.target.value;
$("mode").onchange=()=>{const d=duration(window.__wholeAssets.manifest,$("mode").value);time=d>0?time%d:0;draw()};
for(const id of ["weapon","helmet","mode"])$(id).addEventListener("input",draw);
window.__wholeState=()=>({time,playing,weapon:$("weapon").value,helmet:$("helmet").value,mode:$("mode").value,speed});
window.__setTimeForQA=t=>{time=t;last=performance.now();return last};window.__tickForQA=now=>tick(now);
requestAnimationFrame(tick);
</script></html>'''
    replacements = {
        "__OLD_MANIFEST__": json.dumps(previous, ensure_ascii=False, separators=(",", ":")),
        "__NEW_MANIFEST__": json.dumps(current, ensure_ascii=False, separators=(",", ":")),
        "__OLD_URLS__": json.dumps(previous_urls, separators=(",", ":")),
        "__NEW_URLS__": json.dumps(current_urls, separators=(",", ":")),
        "__RENDERER__": json.dumps(renderer.read_text(encoding="utf-8")),
    }
    for marker, value in replacements.items():
        page = page.replace(marker, value)
    output = ROOT / "gallery.html"
    output.write_text(page, encoding="utf-8", newline="\n")
    print(json.dumps({"images": {"legacy": len(previous_urls), "new": len(current_urls)}, "gallery_bytes": output.stat().st_size, "offline": True}, ensure_ascii=False))


if __name__ == "__main__":
    main()
