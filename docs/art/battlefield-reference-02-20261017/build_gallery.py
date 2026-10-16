#!/usr/bin/env python3
"""Собирает офлайн-сравнение десяти пар сцен по одному референсу."""
from __future__ import annotations

import html
import json
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
BG = (23, 25, 32)
CARD = (42, 45, 55)
FG = (239, 235, 222)
MUTED = (183, 186, 194)
REFERENCE_BRIEF = "Новый референс задаёт тёмный контур, компактные силуэты, приглушённые зелёные, фиолетовые и медные цвета. Для новых сцен используем нашу изометрию 4:3."
VIEW_LABELS = {"isometric": "Персонажи изометрические", "frontal": "F — персонажи фронтальные"}


def read_json(path: Path, default: Any) -> Any:
    return json.loads(path.read_text(encoding="utf-8")) if path.is_file() else default


def classify(item: dict[str, Any]) -> tuple[str, str, str]:
    """Классифицирует итог по result.json, не выдавая сбои за ожидание."""
    folder = ROOT / item.get("_folder", f'items/{int(item["id"]):03d}')
    result = read_json(folder / "result.json", {})
    status = str(result.get("status", "pending")).strip().lower()
    if status == "completed":
        outputs = result.get("outputs", [result["original"]] if "original" in result else [])
        image = folder / "original.png"
        if not image.is_file() or not outputs:
            return "invalid", "Завершено, PNG отсутствует", ""
        expected = str(outputs[0].get("path", outputs[0].get("relative_path", ""))).replace("\\", "/")
        if expected and Path(expected).name != image.name:
            return "invalid", "Завершено, PNG некорректен", ""
        return "complete", "Готово", (folder / "original.png").relative_to(ROOT).as_posix()
    if status in {"", "pending", "queued", "submitted", "submission_started", "running", "processing", "in_progress"}:
        return "pending", "Ожидает PNG", ""
    names = {"failed": "Ошибка", "failure": "Ошибка", "error": "Ошибка", "cancelled": "Отменено", "canceled": "Отменено", "submission_error": "Ошибка отправки", "no_encoded_png": "PNG не получен"}
    return "failed", f'{names.get(status, "Сбой")} ({status[:32]})', ""


def prompt_for(item: dict[str, Any]) -> str:
    folder = ROOT / item.get("_folder", f'items/{int(item["id"]):03d}')
    request = read_json(folder / "request.json", {})
    body = request.get("body", request) if isinstance(request, dict) else {}
    description = body.get("description") if isinstance(body, dict) else None
    description = description or item.get("request", {}).get("description", "")
    if description:
        return str(description)
    if isinstance(request.get("prompt"), str):
        return request["prompt"]
    if isinstance(item.get("prompt"), str):
        return item["prompt"]
    # У PixelLab поля сцены и стиля передаются отдельно; показываем оба без пересказа.
    return f'Сцена:\n{item.get("scene", "")}\n\nСтиль:\n{item.get("style", "")}'


def fit(source: Image.Image, width: int, height: int) -> Image.Image:
    image = source.convert("RGB")
    image.thumbnail((width, height), Image.Resampling.NEAREST)
    canvas = Image.new("RGB", (width, height), BG)
    canvas.paste(image, ((width - image.width) // 2, (height - image.height) // 2))
    return canvas


def font(size: int) -> ImageFont.ImageFont:
    for path in (Path("C:/Windows/Fonts/segoeui.ttf"), Path("C:/Windows/Fonts/arial.ttf")):
        try:
            return ImageFont.truetype(str(path), size)
        except OSError:
            pass
    return ImageFont.load_default()


def main() -> None:
    plan = read_json(ROOT / "plan.json", [])
    if len(plan) != 20:
        raise ValueError(f"Ожидалось 20 записей плана, получено {len(plan)}")
    animation = read_json(ROOT / "animation-ready-imagegen/plan.json", [])
    if len(animation) != 10:
        raise ValueError("Expected ten simplified ImageGen briefs")
    for item in animation:
        plan.append({**item, "pair": 100 + item["id"], "composition": item["id"],
                     "character_view": "isometric", "series": "animation",
                     "_folder": f'animation-ready-imagegen/items/{item["id"]:03d}'})
    trial = read_json(ROOT / "animation-friendly/brief.json", {})
    if not trial:
        raise ValueError("Missing PixelLab animation-oriented brief")
    plan.append({**trial, "pair": 101, "composition": 1, "character_view": "isometric",
                 "series": "animation", "_folder": "animation-friendly"})
    entries: list[dict[str, Any]] = []
    for item in plan:
        state, status_label, image = classify(item)
        entries.append({
            "id": int(item["id"]), "label": item["label"], "pair": int(item["pair"]),
            "composition": int(item["composition"]), "character_view": item["character_view"],
            "engine": item["engine"], "title": item["title"], "prompt": prompt_for(item),
            "view_label": "Упрощённый стиль" if item.get("series") == "animation" else VIEW_LABELS[item["character_view"]],
            "series": item.get("series", "main"),
            "state": state, "status_label": status_label, "image": image,
        })
    pairs: list[dict[str, Any]] = []
    for pair_no in range(1, 11):
        members = [entry for entry in entries if entry["pair"] == pair_no]
        gen = next((entry for entry in members if entry["engine"] == "ImageGen"), None)
        pixel = next((entry for entry in members if entry["engine"] == "PixelLab"), None)
        if not gen or not pixel:
            raise ValueError(f"Пара {pair_no} должна содержать ImageGen и PixelLab")
        if gen["composition"] != pixel["composition"] or gen["character_view"] != pixel["character_view"]:
            raise ValueError(f"Пара {pair_no} должна совпадать по композиции и виду персонажей")
        pairs.append({"number": pair_no, "composition": gen["composition"], "view": gen["character_view"], "view_label": gen["view_label"], "title": gen["title"], "items": [gen, pixel]})

    for number in range(101, 111):
        members = [entry for entry in entries if entry["pair"] == number]
        pairs.append({"number": number, "composition": number - 100, "view": "isometric",
                      "view_label": "Для будущей анимации", "title": members[0]["title"], "items": members})

    payload = json.dumps(pairs, ensure_ascii=False).replace("</", "<\\/")
    document = f'''<!doctype html><html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Сравнение сцен по референсу</title>
<style>
*{{box-sizing:border-box}}body{{margin:0;background:#171920;color:#efebde;font:15px "Segoe UI",Arial,sans-serif}}header{{padding:18px clamp(14px,4vw,48px);background:#20232c;border-bottom:1px solid #50535d}}h1{{font-size:clamp(21px,3vw,30px);margin:0 0 8px}}p{{color:#c8c9cc;margin:5px 0 12px;max-width:1000px;line-height:1.45}}.controls{{display:flex;gap:8px;flex-wrap:wrap}}input,select,button{{background:#30343f;color:#efebde;border:1px solid #747987;border-radius:6px;padding:9px;font:inherit}}input{{min-width:min(260px,100%)}}button{{cursor:pointer}}main{{padding:20px clamp(14px,4vw,48px)}}.reference{{display:grid;grid-template-columns:minmax(180px,320px) 1fr;gap:16px;align-items:center;background:#2a2d37;padding:12px;border-radius:8px;margin-bottom:18px}}.reference img{{width:100%;aspect-ratio:4/3;object-fit:contain;background:#171920;image-rendering:pixelated;cursor:zoom-in}}.reference h2{{margin:0 0 6px}}#counts{{color:#c8c9cc;margin-bottom:12px}}#pairs{{display:grid;gap:14px}}.pair{{background:#2a2d37;border-radius:8px;padding:12px;min-width:0}}.pair h2{{font-size:19px;margin:0 0 9px}}.sides{{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px}}.side{{min-width:0;background:#20232c;border-radius:6px;padding:9px}}.sidehead{{display:flex;justify-content:space-between;gap:8px;color:#d1d2d4}}.side img,.placeholder{{display:grid;width:100%;aspect-ratio:4/3;object-fit:contain;background:#171920;margin-top:7px;image-rendering:pixelated}}.side img{{cursor:zoom-in}}.placeholder{{place-items:center;color:#b7bac2}}.title{{font-size:15px;margin:7px 0}}.star{{padding:2px 8px;font-size:20px;border:0;background:transparent;color:#ffd77b;flex:none}}#modal{{display:none;position:fixed;inset:0;z-index:5;background:#000e;align-items:center;justify-content:center;padding:60px 20px}}#modal.open{{display:flex}}.modalbox{{max-width:94vw;max-height:90vh;display:flex;flex-direction:column;align-items:center;gap:8px}}#modal img{{max-width:90vw;max-height:65vh;object-fit:contain;image-rendering:pixelated}}#mtitle{{font-size:17px;text-align:center}}#mprompt{{max-width:85vw;max-height:20vh;overflow:auto;white-space:pre-wrap;overflow-wrap:anywhere;background:#20232c;padding:10px;border-radius:5px;font:12px/1.45 "Segoe UI",Arial,sans-serif}}#modal button.close{{position:absolute;right:16px;top:14px;font-size:24px}}#modal button.prev{{position:absolute;left:12px;top:50%}}#modal button.next{{position:absolute;right:12px;top:50%}}#copy-status{{color:#c8c9cc;font-size:13px}}@media(max-width:640px){{.reference{{grid-template-columns:1fr}}.reference img{{max-width:420px}}.sides{{grid-template-columns:1fr}}}}
</style></head><body><header><h1>Референс 02 · 20 основных + 11 упрощённых</h1><p>Задача серии: поле в изометрии 4:3, фигуры на отдельных тайлах без подставок. Пол и персонажи должны следовать одному изометрическому ракурсу. Ниже — 10 упрощённых ImageGen и одна проба PixelLab. Точная геометрия тайлов и устойчивость в движении ещё не проверены.</p><div class="controls"><input id="search" type="search" placeholder="Код или название сцены"><select id="series"><option value="">Все 31</option><option value="main">Основные 20</option><option value="animation">Для будущей анимации · 11</option></select><select id="provider"><option value="">Все провайдеры</option><option>ImageGen</option><option>PixelLab</option></select><button id="copy">Скопировать избранные коды</button><span id="copy-status" aria-live="polite"></span></div></header><main><section class="reference"><img src="reference.png" data-reference alt="Оригинальный референс"><div><h2>Референсный образец</h2><p>{html.escape(REFERENCE_BRIEF)}</p><p>Файл reference.png открыт в модальном окне в исходном разрешении.</p></div></section><div id="counts"></div><div id="pairs"></div></main><div id="modal" role="dialog" aria-modal="true"><button class="close" aria-label="Закрыть">×</button><button class="prev" aria-label="Предыдущее">‹</button><div class="modalbox"><img alt="Оригинал"><div id="mtitle"></div><pre id="mprompt"></pre></div><button class="next" aria-label="Следующее">›</button></div>
<script>const pairs={payload};const $=s=>document.querySelector(s),root=$('#pairs'),modal=$('#modal');let favorites=new Set();try{{const saved=JSON.parse(localStorage.getItem('battlefield-reference-02-favorites-v1')||'[]');if(Array.isArray(saved))favorites=new Set(saved.filter(label=>pairs.some(p=>p.items.some(x=>x.label===label))))}}catch{{}}let visible=[],viewables=[],at=0,showingReference=false;const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({{'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}}[c]));function save(){{try{{localStorage.setItem('battlefield-reference-02-favorites-v1',JSON.stringify([...favorites]))}}catch{{}}}}function render(){{const query=$('#search').value.trim().toLocaleLowerCase('ru'),provider=$('#provider').value,series=$('#series').value;visible=pairs.map(pair=>{{const items=pair.items.filter(x=>(!provider||x.engine===provider)&&(!series||x.series===series)&&(!query||x.label.toLowerCase()===query||x.title.toLocaleLowerCase('ru').includes(query)));return {{...pair,items}}}}).filter(pair=>pair.items.length);root.innerHTML=visible.map(pair=>`<section class="pair"><h2>Композиция ${{pair.composition}} · ${{esc(pair.view_label)}} · ${{esc(pair.title)}}</h2><div class="sides">${{pair.items.map(x=>`<div class="side"><div class="sidehead"><b>${{esc(x.label)}} · ${{esc(x.engine)}}</b><span>${{esc(x.status_label)}}</span><button class="star" data-fav="${{esc(x.label)}}" aria-label="Избранное ${{esc(x.label)}}">${{favorites.has(x.label)?'★':'☆'}}</button></div>${{x.image?`<img src="${{esc(x.image)}}" data-open="${{esc(x.label)}}" alt="${{esc(x.label+' '+x.title)}}">`:`<div class="placeholder">${{esc(x.status_label)}}</div>`}}<div class="title">${{esc(x.title)}}</div></div>`).join('')}}</div></section>`).join('');const all=pairs.flatMap(p=>p.items),count=(engine,state)=>all.filter(x=>x.engine===engine&&x.state===state).length;$('#counts').textContent=['ImageGen','PixelLab'].map(e=>`${{e}}: ${{count(e,'complete')}} готово / ${{count(e,'pending')}} ожидает / ${{count(e,'failed')}} сбой / ${{count(e,'invalid')}} некорректно`).join(' · ');viewables=visible.flatMap(p=>p.items.filter(x=>x.image));}}function show(){{if(!viewables.length)return;showingReference=false;$('.prev').style.display='block';$('.next').style.display='block';const x=viewables[(at+viewables.length)%viewables.length];$('#modal img').src=x.image;$('#mtitle').textContent=`${{x.label}} · ${{x.title}} · ${{x.view_label}} · исходный PNG`;$('#mprompt').textContent=x.prompt;modal.classList.add('open')}}function open(label){{at=viewables.findIndex(x=>x.label===label);if(at>=0)show()}}function move(n){{if(viewables.length){{at=(at+n+viewables.length)%viewables.length;show()}}}}root.addEventListener('click',e=>{{if(e.target.dataset.open)open(e.target.dataset.open);const label=e.target.dataset.fav;if(label){{favorites.has(label)?favorites.delete(label):favorites.add(label);save();render()}}}});['search','provider','series'].forEach(id=>$('#'+id).addEventListener(id==='search'?'input':'change',render));document.querySelector('.reference img').onclick=()=>{{showingReference=true;$('.prev').style.display='none';$('.next').style.display='none';$('#modal img').src='reference.png';$('#mtitle').textContent='Референсный образец · исходный PNG';$('#mprompt').textContent='{html.escape(REFERENCE_BRIEF)}';modal.classList.add('open')}};$('.close').onclick=()=>modal.classList.remove('open');$('.prev').onclick=()=>move(-1);$('.next').onclick=()=>move(1);modal.onclick=e=>{{if(e.target===modal)modal.classList.remove('open')}};document.addEventListener('keydown',e=>{{if(e.key==='Escape')modal.classList.remove('open');if(modal.classList.contains('open')&&!showingReference&&e.key==='ArrowLeft')move(-1);if(modal.classList.contains('open')&&!showingReference&&e.key==='ArrowRight')move(1)}});$('#copy').onclick=async()=>{{const text=[...favorites].sort().join(', ');try{{await navigator.clipboard.writeText(text);$('#copy-status').textContent='Скопировано: '+text}}catch{{$('#copy-status').textContent='Избранное: '+text}}}};render();</script></body></html>'''
    (ROOT / "gallery.html").write_text(document, encoding="utf-8")

    regular, small = font(20), font(14)
    overview = Image.new("RGB", (640, 530 + len(pairs) * 252), BG)
    od = ImageDraw.Draw(overview)
    if not (ROOT / "reference.png").is_file():
        raise FileNotFoundError("Обязательный референс reference.png отсутствует")
    with Image.open(ROOT / "reference.png") as reference:
        overview.paste(fit(reference, 640, 480), (0, 0))
    od.rectangle((0, 480, 639, 529), fill=CARD)
    od.text((10, 484), "Референсный образец", fill=FG, font=regular)
    od.text((10, 508), REFERENCE_BRIEF, fill=MUTED, font=small)
    for i, pair in enumerate(pairs):
        y = 530 + i * 252
        od.rectangle((0, y, 639, y + 251), fill=CARD)
        od.text((8, y + 3), f'Композиция {pair["composition"]} · {pair["view_label"]} · {pair["title"]}', fill=FG, font=small)
        for col, entry in enumerate(pair["items"]):
            x = col * 320
            if entry["image"]:
                with Image.open(ROOT / entry["image"]) as im:
                    overview.paste(fit(im, 320, 210), (x, y + 22))
            else:
                od.rectangle((x, y + 22, x + 319, y + 231), fill=BG)
                od.text((x + 8, y + 105), entry["status_label"], fill=MUTED, font=small)
            od.text((x + 6, y + 234), f'{entry["label"]} · {entry["view_label"]} · {entry["status_label"]}', fill=FG, font=small)
    overview.save(ROOT / "overview.jpg", quality=92, subsampling=0)

    for engine, filename in (("ImageGen", "imagegen-sheet.jpg"), ("PixelLab", "pixellab-sheet.jpg"), ("animation", "animation-sheet.jpg")):
        subset = [entry for entry in entries if (entry["series"] == "animation" if engine == "animation" else entry["engine"] == engine and entry["series"] == "main")]
        sheet = Image.new("RGB", (1024, ((len(subset) + 1) // 2) * 430), BG)
        sd = ImageDraw.Draw(sheet)
        for i, entry in enumerate(subset):
            x, y = (i % 2) * 512, (i // 2) * 430
            if entry["image"]:
                with Image.open(ROOT / entry["image"]) as im:
                    sheet.paste(fit(im, 512, 384), (x, y))
            else:
                sd.rectangle((x, y, x + 511, y + 383), fill=CARD)
                sd.text((x + 12, y + 170), entry["status_label"], fill=MUTED, font=regular)
            sd.rectangle((x, y + 384, x + 511, y + 429), fill=CARD)
            sd.text((x + 8, y + 385), f'{entry["label"]} · {entry["title"]} · {entry["view_label"]}', fill=FG, font=small)
            sd.text((x + 8, y + 407), entry["status_label"], fill=MUTED, font=small)
        sheet.save(ROOT / filename, quality=92, subsampling=0)

    summary: dict[str, Any] = {"total": len(entries), "engines": {}}
    for engine in ("ImageGen", "PixelLab"):
        rows = [entry for entry in entries if entry["engine"] == engine]
        summary["engines"][engine] = {state: sum(entry["state"] == state for entry in rows) for state in ("complete", "pending", "failed", "invalid")}
    (ROOT / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False))


if __name__ == "__main__":
    main()
