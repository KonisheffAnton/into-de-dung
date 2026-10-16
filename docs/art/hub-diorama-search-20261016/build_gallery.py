
#!/usr/bin/env python3
"""Offline gallery builder for the PixelLab hub concept batch."""
from __future__ import annotations

import html
import json
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parent
PLAN = ROOT / "plan.json"
OUT = ROOT
BG = (24, 25, 31)
CARD = (38, 39, 48)
FG = (238, 233, 218)
MUTED = (177, 175, 174)
CSS_BG = "rgb(24, 25, 31)"
CSS_CARD = "rgb(38, 39, 48)"
CSS_FG = "rgb(238, 233, 218)"
CSS_MUTED = "rgb(177, 175, 174)"


def contain_nearest(source: Image.Image, width: int, height: int) -> Image.Image:
    """Вписывает изображение без искажения, сохраняя поля вокруг него."""
    image = source.convert("RGB")
    image.thumbnail((width, height), Image.Resampling.NEAREST)
    canvas = Image.new("RGB", (width, height), BG)
    canvas.paste(image, ((width - image.width) // 2, (height - image.height) // 2))
    return canvas


def load_font(size: int) -> ImageFont.ImageFont:
    for font_path in (Path("C:/Windows/Fonts/segoeui.ttf"), Path("C:/Windows/Fonts/arial.ttf")):
        try:
            return ImageFont.truetype(str(font_path), size=size)
        except OSError:
            continue
    return ImageFont.load_default()


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def main() -> None:
    plan = read_json(PLAN)
    entries: list[dict[str, Any]] = []
    usage_total: dict[str, float] = {}
    for item in plan:
        number = int(item["id"])
        folder = ROOT / "items" / f"{number:03d}"
        result_path = folder / "result.json"
        result = read_json(result_path) if result_path.exists() else {}
        image_path = folder / "original.png"
        completed = result.get("status") == "completed" and image_path.is_file()
        usage = result.get("usage", {}) if completed else {}
        if not isinstance(usage, dict):
            usage = {}
        for key, value in usage.items():
            if isinstance(value, (int, float)):
                usage_total[key] = usage_total.get(key, 0) + value
        plan_request = item.get("request", {})
        if not isinstance(plan_request, dict):
            plan_request = {}
        request_path = folder / "request.json"
        request_doc = read_json(request_path) if request_path.exists() else {}
        if not isinstance(request_doc, dict):
            request_doc = {}
        request_body = request_doc.get("body", {})
        if not isinstance(request_body, dict):
            request_body = {}
        endpoint = request_doc.get("endpoint") or item.get("endpoint", "")
        description = request_body.get("description") or plan_request.get("description", "")
        entries.append({
            "id": number, "title": item.get("title", f"Эскиз {number}"),
            "family": item.get("family", ""), "family_title": item.get("family_title", ""),
            "palette": item.get("palette", ""), "mode": {"generate-image-v2": "Pro", "create-image-pixen": "Pixen", "create-image-pixflux": "Pixflux"}.get(endpoint.lstrip("/"), endpoint.lstrip("/")),
            "prompt": description, "status": "completed" if completed else "pending",
            "image": f"items/{number:03d}/original.png" if completed else "",
            "usage": usage,
        })

    families = sorted({e["family"] for e in entries})
    modes = sorted({e["mode"] for e in entries})
    payload = json.dumps(entries, ensure_ascii=False).replace("</", "<\\/")
    family_opts = "".join(f'<option value="{html.escape(f)}">{html.escape(next(e["family_title"] for e in entries if e["family"] == f))}</option>' for f in families)
    mode_opts = "".join(f'<option value="{html.escape(m)}">{html.escape(m)}</option>' for m in modes)
    document = f'''<!doctype html><html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Хаб — 100 поисковых диорам / PixelLab / пробы без внедрения</title>
<style>
*{{box-sizing:border-box}}body{{margin:0;background:{CSS_BG};color:{CSS_FG};font:15px system-ui,sans-serif}}header{{padding:22px 4vw;background:rgb(32,33,42);position:sticky;top:0;z-index:2;border-bottom:1px solid rgb(82,83,92)}}h1{{font-size:clamp(20px,3vw,30px);margin:0 0 8px}}.note{{color:rgb(205,203,202);margin:0 0 14px}}.tools{{display:flex;gap:8px;flex-wrap:wrap}}input,select,button{{background:rgb(48,49,59);color:{CSS_FG};border:1px solid rgb(120,121,130);border-radius:5px;padding:8px}}input{{min-width:220px}}main{{padding:20px 4vw}}#grid{{display:grid;grid-template-columns:repeat(auto-fill,minmax(230px,1fr));gap:14px}}article{{background:{CSS_CARD};padding:10px;border-radius:7px;min-width:0}}.thumb{{width:100%;aspect-ratio:4/3;object-fit:contain;background:rgb(21,22,27);image-rendering:pixelated;cursor:zoom-in}}.pending{{aspect-ratio:4/3;display:grid;place-items:center;background:rgb(32,33,42);color:rgb(205,203,202)}}.meta{{display:flex;justify-content:space-between;margin:7px 0;color:rgb(205,203,202)}}article h2{{font-size:17px;margin:3px 0 8px}}.chips{{font-size:12px;color:rgb(225,215,194);margin-bottom:8px}}details{{font-size:13px;color:rgb(230,228,222)}}summary{{cursor:pointer}}pre{{white-space:pre-wrap;overflow-wrap:anywhere;font:12px/1.45 system-ui}}.fav{{float:right}}#modal{{display:none;position:fixed;inset:0;z-index:5;background:rgb(0 0 0 / 92%);align-items:center;justify-content:center}}#modal.open{{display:flex}}#modal img{{max-width:92vw;max-height:82vh;object-fit:contain;image-rendering:pixelated}}#modal button{{position:absolute;font-size:22px}}#close{{right:20px;top:15px}}#prev{{left:15px}}#next{{right:15px}}#modal-title{{position:absolute;left:60px;right:60px;bottom:10px;text-align:center;color:{CSS_FG};font-size:18px}}#favlist{{color:rgb(205,203,202);font-size:12px;margin-top:8px}}
</style></head><body><header><h1>Хаб — 100 поисковых диорам / PixelLab / пробы без внедрения</h1><p class="note">Концепт-пробы для просмотра. Наличие в галерее не означает художественную приёмку или внедрение.</p><div class="tools"><input id="search" placeholder="Номер или название"><select id="family"><option value="">Все семейства</option>{family_opts}</select><select id="mode"><option value="">Все режимы</option>{mode_opts}</select><button id="export">Скопировать номера избранного</button></div><div id="favlist"></div></header><main><div id="grid"></div></main><div id="modal"><button id="close" aria-label="Закрыть">×</button><button id="prev" aria-label="Предыдущая">‹</button><img alt="Увеличенный оригинал"><div id="modal-title"></div><button id="next" aria-label="Следующая">›</button></div>
<script>const items={payload};const grid=document.querySelector('#grid'),search=document.querySelector('#search'),family=document.querySelector('#family'),mode=document.querySelector('#mode'),modal=document.querySelector('#modal');let favs=new Set();try{{const saved=JSON.parse(localStorage.getItem('hub100-favs')||'[]');if(Array.isArray(saved))favs=new Set(saved.filter(Number.isInteger))}}catch{{}}let visible=[],at=0;
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({{'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}}[c]));function persist(){{try{{localStorage.setItem('hub100-favs',JSON.stringify([...favs]))}}catch{{}}}}
function favText(){{document.querySelector('#favlist').textContent='Избранное: '+[...favs].sort((a,b)=>a-b).map(n=>String(n).padStart(3,'0')).join(', ')}}
function render(){{const q=search.value.trim().toLocaleLowerCase('ru'),numericQuery=/^\\d+$/.test(q),numericId=numericQuery?Number(q):null;visible=items.filter(x=>(!family.value||x.family===family.value)&&(!mode.value||x.mode===mode.value)&&(!q||(numericQuery?x.id===numericId:(x.title.toLocaleLowerCase('ru').includes(q)||x.family_title.toLocaleLowerCase('ru').includes(q)))));grid.innerHTML=visible.map(x=>`<article><div class="meta"><b>#${{String(x.id).padStart(3,'0')}}</b><span>${{x.status==='completed'?'готово':'ожидает'}}</span></div>${{x.image?`<img class="thumb" data-id="${{x.id}}" src="${{esc(x.image)}}" alt="${{esc(x.title)}}">`:'<div class="pending">PNG ещё не готов</div>'}}<h2>${{esc(x.title)}}<button class="fav" data-fav="${{x.id}}" title="Избранное">${{favs.has(x.id)?'★':'☆'}}</button></h2><div class="chips">${{esc(x.family_title)}} · ${{esc(x.palette)}} · ${{esc(x.mode)}}</div><details><summary>Точный промпт</summary><pre>${{esc(x.prompt)}}</pre></details></article>`).join('');favText()}}
function imageItems(){{return visible.filter(x=>x.image)}}function show(){{const imgs=imageItems();if(!imgs.length)return;const x=imgs[(at+imgs.length)%imgs.length];document.querySelector('#modal img').src=esc(x.image);document.querySelector('#modal-title').textContent=`#${{String(x.id).padStart(3,'0')}} · ${{x.title}}`;modal.classList.add('open')}}function open(id){{const imgs=imageItems();at=imgs.findIndex(x=>x.id===id);if(at>=0)show()}}function move(d){{const imgs=imageItems();if(!imgs.length)return;at=(at+d+imgs.length)%imgs.length;show()}}
grid.addEventListener('click',e=>{{if(e.target.dataset.id)open(Number(e.target.dataset.id));if(e.target.dataset.fav){{const n=Number(e.target.dataset.fav);favs.has(n)?favs.delete(n):favs.add(n);persist();render()}}}});[search,family,mode].forEach(x=>x.addEventListener('input',render));document.querySelector('#close').onclick=()=>modal.classList.remove('open');document.querySelector('#prev').onclick=()=>move(-1);document.querySelector('#next').onclick=()=>move(1);modal.onclick=e=>{{if(e.target===modal)modal.classList.remove('open')}};document.addEventListener('keydown',e=>{{if(e.key==='Escape')modal.classList.remove('open');if(modal.classList.contains('open')&&e.key==='ArrowLeft')move(-1);if(modal.classList.contains('open')&&e.key==='ArrowRight')move(1)}});document.querySelector('#export').onclick=async()=>{{const t=[...favs].sort((a,b)=>a-b).map(n=>String(n).padStart(3,'0')).join(', ');try{{await navigator.clipboard.writeText(t)}}catch{{}}document.querySelector('#favlist').textContent='Избранное: '+t}};render();</script></body></html>'''
    (OUT / "gallery.html").write_text(document, encoding="utf-8")

    font = load_font(22)
    small_font = load_font(18)
    contact_dir = OUT / "contact-sheets"
    contact_dir.mkdir(exist_ok=True)
    for sheet in range(10):
        canvas = Image.new("RGB", (1056, 2200), BG)
        draw = ImageDraw.Draw(canvas)
        for slot, entry in enumerate(entries[sheet * 10:(sheet + 1) * 10]):
            col, row = slot % 2, slot // 2
            x, y = col * 528, row * 440
            draw.rectangle((x, y, x + 511, y + 439), fill=CARD)
            if entry["image"]:
                with Image.open(ROOT / entry["image"]) as im:
                    canvas.paste(contain_nearest(im, 512, 384), (x + 8, y + 8))
            else:
                draw.text((x + 18, y + 160), "Ожидает PNG", fill=FG, font=font)
            draw.text((x + 10, y + 397), f'{entry["id"]:03d}  {entry["title"]}', fill=FG, font=font)
            draw.text((x + 10, y + 420), entry["family_title"], fill=MUTED, font=small_font)
        canvas.save(contact_dir / f"{sheet + 1:02d}.jpg", quality=90, subsampling=0)

    overview = Image.new("RGB", (1680, 1480), BG)
    draw = ImageDraw.Draw(overview)
    for i, entry in enumerate(entries):
        col, row = i % 10, i // 10
        x, y = col * 168, row * 148
        if entry["image"]:
            with Image.open(ROOT / entry["image"]) as im:
                overview.paste(contain_nearest(im, 160, 120), (x + 4, y + 2))
        else:
            draw.rectangle((x + 4, y + 2, x + 163, y + 121), fill=CARD)
            draw.text((x + 35, y + 48), "Ожидает", fill=MUTED, font=small_font)
        draw.text((x + 4, y + 124), f'{entry["id"]:03d}', fill=FG, font=small_font)
    overview.save(OUT / "overview.jpg", quality=90, subsampling=0)
    counts = {"total": len(entries), "completed": sum(e["status"] == "completed" for e in entries), "pending": sum(e["status"] != "completed" for e in entries)}
    (OUT / "summary.json").write_text(json.dumps({"counts": counts, "usage": usage_total, "items": [{"id": e["id"], "status": e["status"], "usage": e["usage"]} for e in entries]}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"counts": counts, "usage": usage_total, "gallery": str(OUT / "gallery.html"), "contact_sheets": 10}, ensure_ascii=False))


if __name__ == "__main__":
    main()
