"""Собирает переносимую HTML-галерею из локальных результатов концепта."""
import html
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parent
EXPECTED = [*(f"G{i:02d}" for i in range(1, 11)), "M01", "M02"]


def read_json(name):
    path = ROOT / name
    if not path.is_file():
        raise SystemExit(f"Не найден обязательный файл: {path}")
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise SystemExit(f"Не удалось прочитать {path}: {error}") from error


def esc(value):
    return html.escape(str(value), quote=True)


def main():
    manifest, ratings = read_json("manifest.json"), read_json("ratings.json")
    items = {item.get("id"): item for item in manifest.get("items", [])}
    rated = {item.get("id"): item for item in ratings.get("items", [])}
    missing = [key for key in EXPECTED if key not in items or key not in rated]
    if missing:
        raise SystemExit("В manifest.json или ratings.json отсутствуют: " + ", ".join(missing))
    benchmark = ratings.get("benchmark")
    if not isinstance(benchmark, dict):
        raise SystemExit("В ratings.json отсутствует объект benchmark")

    cards = []
    for key in EXPECTED:
        item, rating = items[key], rated[key]
        view = item.get("view", "")
        category = "iso" if view == "iso" else "front"
        label = "Задан изометрический ракурс" if category == "iso" else "Фронтальные фигуры"
        request = item.get("request", {})
        prompt = request.get("prompt", "") if isinstance(request, dict) else str(request)
        cards.append(f'''<article class="card" data-view="{category}" data-code="{key}" data-score="{esc(rating.get('score', 0))}">
<a class="image" href="{key}.png"><img src="{key}.png" alt="{esc(item.get('title', key))}"></a>
<div class="caption"><div><strong>{key} · {esc(item.get('title', ''))}</strong><span>{label}</span></div>
<b class="score">Оценка: {esc(rating.get('score', '—'))}/10</b><p>{esc(rating.get('reason', ''))}</p>
<details><summary>Точный промпт</summary><pre>{esc(prompt)}</pre></details></div></article>''')

    reason = esc(benchmark.get("reason", ""))
    bench = f'''<article class="card benchmark" data-view="iso">
<a class="image" href="defender-benchmark.png"><img src="defender-benchmark.png" alt="Эталон Defender"></a>
<div class="caption"><div><strong>Эталон · Defender</strong><span>Изометрический эталон</span></div>
<b class="score">Оценка: {esc(benchmark.get('score', '—'))}/10</b><p>{reason}</p></div></article>'''
    document = f'''<!doctype html><html lang="ru"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Battlefield reference 04</title><style>
*{{box-sizing:border-box}}body{{margin:0;background:#15191d;color:#e9ecef;font:16px/1.5 system-ui,sans-serif}}main{{max-width:1200px;margin:auto;padding:28px}}h1{{margin:0 0 8px}}.note{{color:#c1c8ce;max-width:900px}}nav{{display:flex;gap:10px;align-items:center;flex-wrap:wrap;margin:22px 0}}button,select{{background:#293138;color:#fff;border:1px solid #53606a;border-radius:6px;padding:8px 12px}}.grid{{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:18px}}.card{{background:#20262b;border:1px solid #39434a;border-radius:10px;overflow:hidden}}.image{{display:block;background:#111}}img{{display:block;width:100%;height:auto}}.caption{{padding:14px}}.caption>div{{display:flex;justify-content:space-between;gap:8px;flex-wrap:wrap}}.caption span{{color:#a8c4b4}}.score{{display:block;margin-top:8px;color:#f1c879}}p{{margin:7px 0 12px;color:#d0d5d9}}details pre{{white-space:pre-wrap;overflow-wrap:anywhere;color:#c5cbd0}}a{{color:inherit}}.benchmark-wrap{{max-width:580px;margin:20px 0}}@media(max-width:650px){{main{{padding:16px}}.grid{{grid-template-columns:1fr}}}}
</style><main><h1>10 сцен и 2 монстра</h1><p class="note">Оценки эвристические: 1 = проще, 10 = сложнее. Это предположение о сохранении формы при анимации, а не результат теста. Геометрия и размещение — концепт, игровые опорные точки не измерялись. Подпись ракурса показывает, что было задано; она не подтверждает, что изображение точно ему соответствует.</p>
<p><a href="reference.png">Открыть исходный style reference</a> · <a href="manifest.json">Открыть manifest.json</a></p>
<h2>Эталон Defender</h2><section class="benchmark-wrap">{bench}</section>
<nav><button data-filter="all">Все</button><button data-filter="iso">Задан изометрический ракурс</button><button data-filter="front">Фронтальные фигуры</button><label>Порядок <select id="sort"><option value="code">Код G01–G10, M01–M02</option><option value="asc">Оценка: по возрастанию</option><option value="desc">Оценка: по убыванию</option></select></label></nav>
<section class="grid">{''.join(cards)}</section></main><script>
const grid=document.querySelector('.grid');let filter='all';function update(){{const cards=[...grid.children];cards.forEach(c=>c.hidden=filter!=='all'&&c.dataset.view!==filter);const mode=document.querySelector('#sort').value;cards.sort((a,b)=>mode==='code'?a.dataset.code.localeCompare(b.dataset.code):((mode==='asc'?1:-1)*(Number(a.dataset.score)-Number(b.dataset.score))||a.dataset.code.localeCompare(b.dataset.code)));cards.forEach(c=>grid.append(c))}}document.querySelectorAll('[data-filter]').forEach(b=>b.onclick=()=>{{filter=b.dataset.filter;update()}});document.querySelector('#sort').onchange=update;update();
</script></html>'''
    output = ROOT / "gallery.html"
    output.write_text(document, encoding="utf-8")
    print(f"Создано: {output}")


if __name__ == "__main__":
    main()
