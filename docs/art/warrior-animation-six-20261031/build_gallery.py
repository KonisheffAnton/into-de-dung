#!/usr/bin/env python3
"""Собирает автономную галерею с PNG/GIF, встроенными в один HTML-файл."""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import mimetypes
from pathlib import Path
from typing import Any

from PIL import Image

ROOT = Path(__file__).resolve().parent
WARRIORS = {
    "02": "Щит дозора",
    "05": "Тяжёлый страж",
    "11": "Красный бастион",
    "12": "Синий щитоносец",
    "17": "Седой бастион",
    "18": "Лазурный мечник",
}
KINDS = ("idle", "death", "ability")
VARIANTS = (1, 2, 3)


class PackageError(RuntimeError):
    pass


def read_image(path: Path) -> bytes:
    if not path.is_file():
        raise PackageError(f"missing asset: {path.relative_to(ROOT).as_posix()}")
    payload = path.read_bytes()
    if not payload:
        raise PackageError(f"empty asset: {path.relative_to(ROOT).as_posix()}")
    try:
        with Image.open(path) as im:
            im.verify()
    except Exception as exc:  # Pillow decoder gives a useful source-specific failure.
        raise PackageError(f"invalid image: {path.relative_to(ROOT).as_posix()}: {exc}") from exc
    return payload


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "gallery.html",
                        help="HTML output path (default: package gallery.html)")
    args = parser.parse_args()

    assets: dict[str, dict[str, Any]] = {}

    def embed(path: Path) -> str:
        key = path.relative_to(ROOT).as_posix()
        if key in assets:
            raise PackageError(f"duplicate asset key: {key}")
        payload = read_image(path)
        mime = mimetypes.guess_type(path.name)[0]
        if mime not in ("image/png", "image/gif"):
            raise PackageError(f"unexpected image type for {key}: {mime}")
        assets[key] = {
            "mime": mime,
            "bytes": len(payload),
            "sha256": hashlib.sha256(payload).hexdigest(),
            "base64": base64.b64encode(payload).decode("ascii"),
        }
        return key

    models: list[dict[str, Any]] = []
    for warrior, name in WARRIORS.items():
        model_dir = ROOT / "models" / f"warrior-{warrior}"
        input_key = embed(model_dir / "input-256.png")
        source_key = embed(model_dir / "source-full.png")
        clips: list[dict[str, Any]] = []
        for kind in KINDS:
            specs = [("pixellab", variant) for variant in VARIANTS] + [("local", 1)]
            for provider, variant in specs:
                folder = (ROOT / "pixellab" / f"{warrior}-{kind}-{variant}"
                          if provider == "pixellab" else ROOT / "local" / warrior / kind)
                metadata_path = folder / "clip.json"
                if not metadata_path.is_file():
                    raise PackageError(f"missing clip metadata: {metadata_path.relative_to(ROOT).as_posix()}")
                try:
                    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
                except Exception as exc:
                    raise PackageError(f"invalid clip metadata: {metadata_path.relative_to(ROOT).as_posix()}: {exc}") from exc
                count = metadata.get("actual_frames", metadata.get("frame_count"))
                durations = metadata.get("durations_ms")
                if not isinstance(count, int) or count < 1:
                    raise PackageError(f"invalid actual_frames in {metadata_path.relative_to(ROOT).as_posix()}")
                if not isinstance(durations, list) or len(durations) != count or any(
                    not isinstance(d, int) or d <= 0 for d in durations
                ):
                    raise PackageError(f"invalid durations_ms in {metadata_path.relative_to(ROOT).as_posix()}")
                if not isinstance(metadata.get("loop"), bool):
                    raise PackageError(f"invalid loop flag in {metadata_path.relative_to(ROOT).as_posix()}")

                sheet_path = folder / "spritesheet.png"
                gif_path = folder / "preview.gif"
                sheet_key = embed(sheet_path)
                gif_key = embed(gif_path)
                with Image.open(sheet_path) as sheet:
                    if sheet.width != 2048 or sheet.height % 256 != 0 or sheet.height < 256:
                        raise PackageError(
                            f"sheet must use 8 columns of 256px: {sheet_path.relative_to(ROOT).as_posix()} {sheet.size}"
                        )
                    if count > (sheet.height // 256) * 8:
                        raise PackageError(f"sheet has too few cells: {sheet_path.relative_to(ROOT).as_posix()}")
                clips.append({
                    "kind": kind,
                    "provider": provider,
                    "variant": variant,
                    "actual_frames": count,
                    "durations_ms": durations,
                    "loop": metadata["loop"],
                    "ability_title": metadata.get("ability_title"),
                    "edge_frames": metadata.get("edge_frames"),
                    "margin_violation_frames": metadata.get("margin_violation_frames"),
                    "sheet": sheet_key,
                    "gif": gif_key,
                })
        if len(clips) != 12:
            raise PackageError(f"warrior {warrior} has {len(clips)} clips; expected 12")
        models.append({"id": warrior, "name": name, "input": input_key,
                       "source_full": source_key, "clips": clips})

    expected_assets = {"spritesheet PNG": 72, "preview GIF": 72,
                       "input PNG": 6, "source-full PNG": 6}
    actual_assets = {
        "spritesheet PNG": sum(k.endswith("/spritesheet.png") for k in assets),
        "preview GIF": sum(k.endswith("/preview.gif") for k in assets),
        "input PNG": sum(k.endswith("/input-256.png") for k in assets),
        "source-full PNG": sum(k.endswith("/source-full.png") for k in assets),
    }
    if actual_assets != expected_assets or len(models) != 6 or sum(len(m["clips"]) for m in models) != 72:
        raise PackageError(f"incomplete gallery package: {actual_assets}, models={len(models)}")

    asset_json = json.dumps(assets, ensure_ascii=False, separators=(",", ":"))
    model_json = json.dumps(models, ensure_ascii=False, separators=(",", ":"))
    template = r'''<!doctype html>
<html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Шесть воинов — автономная галерея</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#101723;color:#e8eef5;font:16px system-ui}header{padding:24px 32px;background:#1a2434;position:sticky;top:0;z-index:2}h1{font-size:25px;margin:0 0 10px}p{color:#b5c3d5;line-height:1.5}button,select{background:#2b3c54;border:1px solid #546a87;border-radius:7px;color:white;padding:8px 13px;margin:3px;cursor:pointer}button.active{background:#795831;border-color:#efba66}main{max-width:1500px;margin:auto;padding:24px}.models{display:flex;align-items:center;gap:24px}.models img{width:220px;height:220px;object-fit:contain;background:#1b2739}.models a{color:#eabe75}.row{display:grid;grid-template-columns:repeat(4,minmax(150px,1fr));gap:14px}article{background:#1b2739;border:1px solid #34465e;border-radius:10px;overflow:hidden;text-align:center}article h3{font-size:15px}.stage{height:280px;display:flex;align-items:center;justify-content:center;background:var(--bg,#182131);position:relative}canvas{width:256px;height:auto;max-width:100%;image-rendering:pixelated}body.game canvas{width:102.4px;height:102.4px}body.zoom canvas{width:384px;height:auto}body.zoom .row{grid-template-columns:repeat(2,minmax(150px,1fr))}body.zoom .stage{height:400px}a{color:#eabe75}.muted{font-size:13px;color:#9fb0c6}.warning{color:#ffb577}.asset-error{color:#ff9a9a;background:#351f29;border:1px solid #88414d;border-radius:6px;padding:8px;margin:8px;font-size:13px}input[type=range]{width:90%}@media(max-width:800px){.row{grid-template-columns:repeat(2,1fr)}body.zoom .row{grid-template-columns:1fr}header{position:static}main{padding:12px}}
</style></head><body><header><h1>Шесть воинов · автономная галерея</h1><nav id="tabs"></nav><div><button id="play">Пауза</button><button id="restart">Сначала</button><button id="step">+ Кадр</button><select id="scale"><option value="">Масштаб 1×</option><option value="game">Игровой размер (~61 px)</option><option value="zoom">Масштаб 1,5×</option></select><select id="speed"><option value="1">Скорость 1×</option><option value="0.5">0,5×</option><option value="1.5">1,5×</option></select><select id="background"><option value="#182131">Тёмный фон</option><option value="#88939c">Серый фон</option><option value="#ded4b9">Светлый фон</option></select></div></header>
<main><div id="model"></div><p>Три варианта PixelLab и одна локальная проба на каждый тип. Смерть и способность проигрываются один раз и удерживают последний кадр; «Сначала» повторяет. Локальные пробы — движение вырезанных частей исходника. У PixelLab возврат к исходной позе может отличаться; плавность стыка idle ещё требует выбора и проверки. В игру не подключено.</p><div id="clips"></div></main>
<script>
"use strict";
const ASSETS=__ASSETS__;
const DATA=__DATA__;
let current='02',playing=true,speed=1,last=0,players=[];
const labels={idle:'Ожидание',death:'Смерть',ability:'Способность'},dataUrls=new Map();
function dataUrl(key){const asset=ASSETS[key];if(!asset)throw new Error('Нет встроенного файла: '+key);let url=dataUrls.get(key);if(!url){url='data:'+asset.mime+';base64,'+asset.base64;dataUrls.set(key,url)}return url}
function visibleError(node,message){node.hidden=false;node.textContent=message}
function openAsset(key,download){const asset=ASSETS[key];if(!asset){alert('Файл не найден внутри HTML: '+key);return}const binary=atob(asset.base64),bytes=new Uint8Array(binary.length);for(let i=0;i<binary.length;i++)bytes[i]=binary.charCodeAt(i);const url=URL.createObjectURL(new Blob([bytes],{type:asset.mime}));const link=document.createElement('a');link.href=url;link.rel='noopener';if(download){link.download=key.split('/').pop();}else{link.target='_blank'}document.body.appendChild(link);link.click();link.remove();setTimeout(()=>URL.revokeObjectURL(url),120000)}
document.addEventListener('click',event=>{const link=event.target.closest('[data-open-asset]');if(!link)return;event.preventDefault();openAsset(link.dataset.openAsset,link.dataset.download==='true')});
function render(){players=[];document.querySelector('#tabs').innerHTML=DATA.map(m=>`<button class="${m.id===current?'active':''}" data-id="${m.id}">${m.id} · ${m.name}</button>`).join('');document.querySelectorAll('[data-id]').forEach(b=>b.onclick=()=>{current=b.dataset.id;render()});const m=DATA.find(x=>x.id===current);document.querySelector('#model').innerHTML=`<div class="models"><img id="model-input" alt="Модель ${m.id}"><div><h2>${m.id} · ${m.name}</h2><p>Прозрачная модель · холст 256×256 · опора (128,200)</p><a href="#" data-open-asset="${m.source_full}">Открыть полноразмерную модель</a><div id="model-error" class="asset-error" hidden></div></div></div>`;const modelImage=document.querySelector('#model-input');modelImage.onerror=()=>visibleError(document.querySelector('#model-error'),'Не удалось загрузить встроенную модель '+m.input);modelImage.src=dataUrl(m.input);let html='';for(const kind of ['idle','death','ability']){html+=`<h2>${labels[kind]}</h2><div class="row">`;for(const provider of ['pixellab','local'])for(const n of provider==='pixellab'?[1,2,3]:[1]){const c=m.clips.find(c=>c.kind===kind&&c.provider===provider&&c.variant===n);if(!c)throw new Error(`Неполная галерея: ${m.id}/${kind}/${provider}/${n}`);const index=players.length;players.push({c,frame:0,time:0,img:new Image(),loaded:false,failed:false});html+=`<article><h3>${provider==='local'?'Локальная проба':'PixelLab · '+n}</h3><div class="stage"><canvas width="256" height="256" data-player="${index}"></canvas></div><input type="range" min="0" max="${c.actual_frames-1}" value="0" data-slider="${index}"><p class="muted">${c.actual_frames} кадров · ${c.loop?'цикл':'одно исполнение'}</p>${(c.edge_frames?.length||c.margin_violation_frames?.length)?'<p class="warning">Есть пиксели в зоне отступа у края</p>':''}<div class="asset-error" data-error="${index}" hidden></div><p><a href="#" data-open-asset="${c.gif}">GIF</a> · <a href="#" data-open-asset="${c.sheet}">PNG-лист</a></p></article>`}html+='</div>'}document.querySelector('#clips').innerHTML=html;players.forEach((p,i)=>{p.canvas=document.querySelector(`[data-player="${i}"]`);p.slider=document.querySelector(`[data-slider="${i}"]`);p.slider.oninput=()=>{playing=false;document.querySelector('#play').textContent='Играть';p.frame=+p.slider.value;p.time=0;draw(p)};p.img.onload=()=>{p.loaded=true;draw(p)};p.img.onerror=()=>{p.failed=true;visibleError(document.querySelector(`[data-error="${i}"]`),'Не удалось загрузить встроенный лист '+p.c.sheet);draw(p)};p.img.src=dataUrl(p.c.sheet)});last=0}
function draw(p){if(!p.canvas)return;const ctx=p.canvas.getContext('2d');ctx.clearRect(0,0,256,256);if(p.failed){ctx.fillStyle='#351f29';ctx.fillRect(0,0,256,256);ctx.fillStyle='#ff9a9a';ctx.font='14px system-ui';ctx.textAlign='center';ctx.fillText('Изображение недоступно',128,128);return}if(!p.loaded)return;ctx.drawImage(p.img,(p.frame%8)*256,Math.floor(p.frame/8)*256,256,256,0,0,256,256);p.slider.value=p.frame}
function tick(t){if(!last)last=t;const dt=Math.min(100,t-last);last=t;if(playing)players.forEach(p=>{if(!p.loaded||p.failed)return;p.time+=dt*speed;let duration=p.c.durations_ms[p.frame]||90;while(p.time>=duration){p.time-=duration;if(p.frame<p.c.actual_frames-1)p.frame++;else if(p.c.loop)p.frame=0;else{p.time=0;break}duration=p.c.durations_ms[p.frame]||90}draw(p)});requestAnimationFrame(tick)}
document.querySelector('#play').onclick=()=>{playing=!playing;document.querySelector('#play').textContent=playing?'Пауза':'Играть'};document.querySelector('#restart').onclick=()=>{players.forEach(p=>{p.frame=0;p.time=0;draw(p)});playing=true;document.querySelector('#play').textContent='Пауза'};document.querySelector('#step').onclick=()=>{playing=false;document.querySelector('#play').textContent='Играть';players.forEach(p=>{p.frame=Math.min(p.frame+1,p.c.actual_frames-1);draw(p)})};document.querySelector('#scale').onchange=e=>document.body.className=e.target.value;document.querySelector('#speed').onchange=e=>speed=+e.target.value;document.querySelector('#background').onchange=e=>document.documentElement.style.setProperty('--bg',e.target.value);render();requestAnimationFrame(tick);
</script></body></html>'''
    output = template.replace("__ASSETS__", asset_json).replace("__DATA__", model_json)
    output_path = args.output if args.output.is_absolute() else (Path.cwd() / args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(output, encoding="utf-8")
    raw_bytes = sum(item["bytes"] for item in assets.values())
    print(json.dumps({"output": str(output_path), "models": len(models),
                      "clips": sum(len(m["clips"]) for m in models),
                      "assets": actual_assets, "asset_count": len(assets),
                      "embedded_raw_bytes": raw_bytes, "html_bytes": output_path.stat().st_size},
                     ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except PackageError as exc:
        raise SystemExit(f"BUILD FAILED: {exc}") from exc
