#!/usr/bin/env python3
"""Собирает автономную галерею визуальных проб поля боя."""
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


def read_json(path: Path, default: Any) -> Any:
    return json.loads(path.read_text(encoding="utf-8")) if path.is_file() else default


def classify_result(item: dict[str, Any]) -> tuple[str, str]:
    """Отделяет завершённые сбои от ещё выполняющихся запросов."""
    folder = ROOT / "items" / f'{int(item["id"]):03d}'
    result = read_json(folder / "result.json", {})
    raw_status = str(result.get("status", "pending")).strip().lower()
    if raw_status == "completed":
        original = folder / "original.png"
        outputs = result.get("outputs", [])
        if not original.is_file() or not outputs:
            return "invalid", "Завершено, но PNG отсутствует"
        expected = str(outputs[0].get("path", "")).replace("\\", "/")
        if expected and Path(expected).name != original.name:
            return "invalid", "Завершено, но PNG некорректен"
        return "complete", "Готово"
    if raw_status in {"", "pending", "queued", "submitted", "submission_started", "running", "processing", "in_progress"}:
        return "pending", "Ожидает PNG"
    known_errors = {
        "failed": "Ошибка", "failure": "Ошибка", "cancelled": "Отменено",
        "canceled": "Отменено", "error": "Ошибка", "submission_error": "Ошибка отправки",
        "no_encoded_png": "PNG не получен",
    }
    label = known_errors.get(raw_status, "Сбой")
    # Не выводим текст ошибки провайдера: там может быть длинная диагностика.
    return "failed", f"{label} ({raw_status[:32]})"


def completed_image(item: dict[str, Any], state: str) -> str:
    """Использует только ожидаемый оригинал, не пересохраняя PNG."""
    if state != "complete":
        return ""
    return f'items/{int(item["id"]):03d}/original.png'


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
        raise ValueError(f"Ожидалось 20 строк плана, получено {len(plan)}")
    entries: list[dict[str, Any]] = []
    for row in plan:
        number = int(row["id"])
        result = read_json(ROOT / "items" / f"{number:03d}" / "result.json", {})
        state, status_label = classify_result(row)
        prompt = row.get("request", {}).get("description", "")
        entries.append({
            "id": number, "label": row["label"], "title": row["title"], "era": row["era"],
            "engine": row["engine"], "prompt": prompt,
            "state": state, "status_label": status_label,
            "image": completed_image(row, state), "usage": result.get("usage"),
        })

    payload = json.dumps(entries, ensure_ascii=False).replace("</", "<\\/")
    era_options = "".join(f'<option>{html.escape(era)}</option>' for era in dict.fromkeys(str(row["era"]) for row in plan))
    document = f'''<!doctype html><html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Поле боя — стилевые пробы</title>
<style>
*{{box-sizing:border-box}}body{{margin:0;background:#171920;color:#efebde;font:15px "Segoe UI",Arial,sans-serif}}header{{position:sticky;top:0;z-index:2;padding:18px clamp(14px,4vw,48px);background:#20232c;border-bottom:1px solid #50535d}}h1{{font-size:clamp(21px,3vw,30px);margin:0 0 7px}}p{{color:#c8c9cc;margin:0 0 12px;max-width:1100px;line-height:1.45}}.tools{{display:flex;gap:8px;flex-wrap:wrap}}input,select,button{{background:#30343f;color:#efebde;border:1px solid #747987;border-radius:6px;padding:9px;font:inherit}}input{{min-width:min(270px,100%)}}button{{cursor:pointer}}main{{padding:20px clamp(14px,4vw,48px)}}#counts{{color:#c8c9cc;margin-bottom:14px}}#grid{{display:grid;grid-template-columns:repeat(auto-fill,minmax(min(260px,100%),1fr));gap:14px}}article{{background:#2a2d37;border-radius:8px;padding:11px;min-width:0}}.top{{display:flex;justify-content:space-between;align-items:center;color:#d1d2d4;margin-bottom:7px}}.thumb,.placeholder{{display:block;width:100%;aspect-ratio:4/3;object-fit:contain;background:#171920;image-rendering:pixelated}}.thumb{{cursor:zoom-in}}.placeholder{{display:grid;place-items:center;color:#b7bac2}}h2{{font-size:18px;margin:8px 0 4px}}.star{{float:right;padding:2px 8px;font-size:21px;border:0;background:transparent;color:#ffd77b}}.chips{{color:#e5d9bd;font-size:13px;margin-bottom:9px}}details{{font-size:13px;color:#e2e0da}}summary{{cursor:pointer}}pre{{font:12px/1.5 "Segoe UI",Arial,sans-serif;white-space:pre-wrap;overflow-wrap:anywhere}}#modal{{display:none;position:fixed;inset:0;z-index:5;background:#000e;align-items:center;justify-content:center}}#modal.open{{display:flex}}#modal img{{max-width:90vw;max-height:82vh;object-fit:contain;image-rendering:pixelated}}#modal button{{position:absolute;font-size:24px}}#close{{right:16px;top:14px}}#prev{{left:14px}}#next{{right:14px}}#mtitle{{position:absolute;bottom:12px;text-align:center;max-width:80vw}}#copy-status{{font-size:13px;color:#c8c9cc;padding-top:6px}}@media(max-width:480px){{header{{position:static}}#grid{{grid-template-columns:1fr}}}}
</style></head><body><header><h1>Поле боя · 20 стилевых проб</h1><p>Галерея концептов; наличие изображения не означает приёмку или внедрение. «8-bit» и «16-bit» здесь обозначают эстетические ориентиры, а не проверенные аппаратные палитры. Утверждения о числе цветов относятся только к промптам.</p><div class="tools"><input id="search" type="search" placeholder="Точный код G01/P01 или часть названия"><select id="engine"><option value="">Все движки</option><option>ImageGen</option><option>PixelLab</option></select><select id="era"><option value="">Все эстетики</option>{era_options}</select><button id="copy">Скопировать коды избранного</button></div><div id="copy-status" aria-live="polite"></div></header><main><div id="counts"></div><div id="grid"></div></main><div id="modal" role="dialog" aria-modal="true"><button id="close" aria-label="Закрыть">×</button><button id="prev" aria-label="Предыдущее изображение">‹</button><img alt="Увеличенный оригинал"><button id="next" aria-label="Следующее изображение">›</button><div id="mtitle"></div></div>
<script>const items={payload};const $=s=>document.querySelector(s),grid=$('#grid'),modal=$('#modal');let favs=new Set();try{{const a=JSON.parse(localStorage.getItem('intoDeDung-battle-style-gallery-favs-v1')||'[]');if(Array.isArray(a))favs=new Set(a.filter(v=>items.some(x=>x.label===v)))}}catch{{}}let visible=[],at=0;
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({{'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}}[c]));function save(){{try{{localStorage.setItem('intoDeDung-battle-style-gallery-favs-v1',JSON.stringify([...favs]))}}catch{{}}}}function render(){{const q=$('#search').value.trim().toLocaleLowerCase('ru'),exact=/^[gp]\\d{{2}}$/i.test(q);visible=items.filter(x=>(!$('#engine').value||x.engine===$('#engine').value)&&(!$('#era').value||x.era===$('#era').value)&&(!q&&(true)||exact&&x.label.toLowerCase()===q||!exact&&(x.label.toLowerCase().includes(q)||x.title.toLocaleLowerCase('ru').includes(q))));grid.innerHTML=visible.map(x=>`<article><div class="top"><b>${{esc(x.label)}}</b><span>${{esc(x.status_label)}}</span></div>${{x.image?`<img class="thumb" data-open="${{x.id}}" src="${{esc(x.image)}}" alt="${{esc(x.label+' '+x.title)}}">`:`<div class="placeholder">${{esc(x.status_label)}}</div>`}}<h2>${{esc(x.title)}}<button class="star" data-fav="${{esc(x.label)}}" aria-label="Избранное ${{esc(x.label)}}">${{favs.has(x.label)?'★':'☆'}}</button></h2><div class="chips">${{esc(x.era)}} · ${{esc(x.engine)}}</div><details><summary>Точный промпт</summary><pre>${{esc(x.prompt)}}</pre></details></article>`).join('');const tally=e=>{{const a=items.filter(x=>x.engine===e),count=s=>a.filter(x=>x.state===s).length;return `${{e}}: ${{count('complete')}} готово / ${{count('pending')}} ожидает / ${{count('failed')}} сбой / ${{count('invalid')}} некорректно`}};$('#counts').textContent=`${{tally('ImageGen')}} · ${{tally('PixelLab')}}`;}}function imageItems(){{return visible.filter(x=>x.image)}}function show(){{const a=imageItems();if(!a.length)return;const x=a[(at+a.length)%a.length];$('#modal img').src=x.image;$('#mtitle').textContent=`${{x.label}} · ${{x.title}}`;modal.classList.add('open')}}function openImage(id){{const a=imageItems();at=a.findIndex(x=>x.id===id);show()}}function move(n){{const a=imageItems();if(a.length){{at=(at+n+a.length)%a.length;show()}}}}
grid.addEventListener('click',e=>{{const id=e.target.dataset.open;if(id)openImage(Number(id));const label=e.target.dataset.fav;if(label){{favs.has(label)?favs.delete(label):favs.add(label);save();render()}}}});['search','engine','era'].forEach(id=>$('#'+id).addEventListener(id==='search'?'input':'change',render));$('#close').onclick=()=>modal.classList.remove('open');$('#prev').onclick=()=>move(-1);$('#next').onclick=()=>move(1);modal.onclick=e=>{{if(e.target===modal)modal.classList.remove('open')}};document.addEventListener('keydown',e=>{{if(e.key==='Escape')modal.classList.remove('open');if(modal.classList.contains('open')&&e.key==='ArrowLeft')move(-1);if(modal.classList.contains('open')&&e.key==='ArrowRight')move(1)}});$('#copy').onclick=async()=>{{const text=[...favs].sort().join(', ');try{{await navigator.clipboard.writeText(text);$('#copy-status').textContent='Скопировано: '+text}}catch{{$('#copy-status').textContent='Коды избранного: '+text}}}};render();</script></body></html>'''
    (ROOT / "gallery.html").write_text(document, encoding="utf-8")

    regular, small = font(20), font(15)
    overview = Image.new("RGB", (1280, 1440), BG)
    draw = ImageDraw.Draw(overview)
    for i, entry in enumerate(entries):
        x, y = (i % 4) * 320, (i // 4) * 288
        if entry["image"]:
            with Image.open(ROOT / entry["image"]) as im:
                overview.paste(fit(im, 320, 240), (x, y))
        else:
            draw.rectangle((x, y, x + 319, y + 239), fill=CARD)
            draw.text((x + 92, y + 103), entry["status_label"], fill=MUTED, font=regular)
        draw.rectangle((x, y + 240, x + 319, y + 287), fill=CARD)
        draw.text((x + 8, y + 241), f'{entry["label"]} · {entry["title"]}', fill=FG, font=small)
        draw.text((x + 8, y + 264), entry["status_label"], fill=MUTED, font=small)
    overview.save(ROOT / "overview.jpg", quality=92, subsampling=0)

    for engine, filename in (("ImageGen", "imagegen-sheet.jpg"), ("PixelLab", "pixellab-sheet.jpg")):
        subset = [e for e in entries if e["engine"] == engine]
        sheet = Image.new("RGB", (1024, 2150), BG)
        sd = ImageDraw.Draw(sheet)
        for i, entry in enumerate(subset):
            x, y = (i % 2) * 512, (i // 2) * 430
            if entry["image"]:
                with Image.open(ROOT / entry["image"]) as im:
                    sheet.paste(fit(im, 512, 384), (x, y))
            else:
                sd.rectangle((x, y, x + 511, y + 383), fill=CARD)
                sd.text((x + 165, y + 170), entry["status_label"], fill=MUTED, font=regular)
            sd.rectangle((x, y + 384, x + 511, y + 429), fill=CARD)
            sd.text((x + 9, y + 384), f'{entry["label"]} · {entry["title"]}', fill=FG, font=small)
            sd.text((x + 9, y + 406), entry["status_label"], fill=MUTED, font=small)
        sheet.save(ROOT / filename, quality=92, subsampling=0)

    summary: dict[str, Any] = {"total": len(entries), "engines": {}}
    for engine in ("ImageGen", "PixelLab"):
        rows = [e for e in entries if e["engine"] == engine]
        data: dict[str, Any] = {state: sum(e["state"] == state for e in rows) for state in ("complete", "pending", "failed", "invalid")}
        if engine == "PixelLab":
            known = [e["usage"] for e in rows if isinstance(e["usage"], dict)]
            numeric_keys = {k for v in known for k, value in v.items() if isinstance(value, (int, float)) and not isinstance(value, bool)}
            data["usage_known_count"] = sum(any(isinstance(value, (int, float)) and not isinstance(value, bool) for value in usage.values()) for usage in known)
            data["usage"] = {k: sum(v[k] for v in known if isinstance(v.get(k), (int, float)) and not isinstance(v.get(k), bool)) for k in sorted(numeric_keys)}
        summary["engines"][engine] = data
    (ROOT / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False))


if __name__ == "__main__":
    main()
