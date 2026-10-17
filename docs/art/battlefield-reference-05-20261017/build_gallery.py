"""Собирает переносимую галерею компактных героев из локальных файлов."""
import html
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parent
EXPECTED = [f"G{i:02d}" for i in range(1, 11)]


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
    if not isinstance(ratings.get("benchmark"), dict):
        raise SystemExit("В ratings.json отсутствует объект benchmark")

    cards = []
    for key in EXPECTED:
        item, rating = items[key], rated[key]
        view = item.get("view", "")
        category = "iso" if view == "iso" else "front"
        label = "Задан изометрический ракурс" if category == "iso" else "Задан фронтальный ракурс"
        request = item.get("request", {})
        prompt = request.get("prompt", "") if isinstance(request, dict) else str(request)
        monsters = rating.get("monsters", [])
        monster_rows = "".join(
            f'<li><strong>{esc(monster.get("name", "Монстр"))}</strong> '
            f'({"крупный" if monster.get("size") == "large" else "маленький"}, визуальное предложение): '
            f'{esc(monster.get("score", "—"))}/10 · {esc(monster.get("reason", ""))}</li>'
            for monster in monsters
        )
        cards.append(f'''<article class="card" data-view="{category}" data-code="{key}" data-score="{esc(rating.get('score', 0))}">
<a class="image" href="{key}.png"><img src="{key}.png" alt="{esc(item.get('title', key))}"></a>
<div class="caption"><div><strong>{key} · {esc(item.get('title', ''))}</strong><span>{label}</span></div>
<b class="score">Максимальная сложность фигур: {esc(rating.get('score', '—'))}/10</b>
<p>{esc(rating.get('reason', ''))}</p><p>Герои: {esc(rating.get('heroes_score', '—'))}/10</p>
<ul class="monster-scores">{monster_rows}</ul>
<details><summary>Точный промпт</summary><pre>{esc(prompt)}</pre></details></div></article>''')

    benchmark = ratings["benchmark"]
    bench = f'''<article class="card benchmark">
<a class="image" href="defender-benchmark.png"><img src="defender-benchmark.png" alt="Эталон Defender"></a>
<div class="caption"><div><strong>Эталон · Defender</strong><span>Сравнительный образ героя</span></div>
<b class="score">Оценка: {esc(benchmark.get('score', '—'))}/10</b><p>{esc(benchmark.get('reason', ''))}</p></div></article>'''
    document = f'''<!doctype html><html lang="ru"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>10 вариантов · компактные герои</title><style>
*{{box-sizing:border-box}}body{{margin:0;background:#15191d;color:#e9ecef;font:16px/1.5 system-ui,sans-serif}}main{{max-width:1200px;margin:auto;padding:28px}}h1{{margin:0 0 8px}}.note{{color:#c1c8ce;max-width:950px}}nav{{display:flex;gap:10px;align-items:center;flex-wrap:wrap;margin:22px 0}}button,select{{background:#293138;color:#fff;border:1px solid #53606a;border-radius:6px;padding:8px 12px}}.grid,.references{{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:18px}}.references{{grid-template-columns:repeat(4,minmax(0,1fr));margin:18px 0 26px}}.card{{background:#20262b;border:1px solid #39434a;border-radius:10px;overflow:hidden}}.image{{display:block;background:#111}}img{{display:block;width:100%;height:auto}}.caption{{padding:14px}}.caption>div{{display:flex;justify-content:space-between;gap:8px;flex-wrap:wrap}}.caption span{{color:#a8c4b4}}.score{{display:block;margin-top:8px;color:#f1c879}}p{{margin:7px 0 12px;color:#d0d5d9}}.monster-scores{{padding-left:22px;color:#d0d5d9}}details pre{{white-space:pre-wrap;overflow-wrap:anywhere;color:#c5cbd0}}a{{color:inherit}}.benchmark-wrap{{max-width:580px;margin:18px 0 26px}}.references .card{{padding:12px}}.references a{{display:block;margin-top:4px;color:#bcd9c8}}@media(max-width:720px){{main{{padding:16px}}.grid,.references{{grid-template-columns:1fr}}}}
</style><main><h1>10 вариантов · компактные герои</h1><p class="note">Оценки эвристические: 1 = проще, 10 = сложнее; тест анимации не выполнялся. Оценка сцены — максимум сложности среди фигур, а не оценка анимации всей сцены. Подписи ракурса описывают задание для генерации и не подтверждают точность изображения. Геометрия пола показана как концепт; игровые опорные точки не измерялись. Размеры монстров — визуальные предложения, не игровые занимаемые клетки.</p>
<h2>Визуальные ориентиры</h2><section class="references"><article class="card"><a href="reference.png"><img src="reference.png" alt="Style reference — компактные герои"></a><a href="reference.png">Style reference · лист компактных героев</a></article><article class="card"><a href="palette-reference.png"><img src="palette-reference.png" alt="Палитра пользователя"></a><a href="palette-reference.png">Палитра пользователя</a></article><article class="card"><a href="projection-reference.png"><img src="projection-reference.png" alt="Проекция пола"></a><a href="projection-reference.png">Геометрия проекции пола</a></article><article class="card"><a href="monster-reference.png"><img src="monster-reference.png" alt="Референс монстров"></a><a href="monster-reference.png">Референс монстров</a></article></section>
<p><a href="manifest.json">manifest.json</a> · <a href="ratings.json">ratings.json</a></p><h2>Эталон Defender</h2><section class="benchmark-wrap">{bench}</section>
<nav><button data-filter="all">Все</button><button data-filter="iso">Задан изометрический ракурс</button><button data-filter="front">Задан фронтальный ракурс</button><label>Порядок <select id="sort"><option value="code">Код G01–G10</option><option value="asc">Оценка: по возрастанию</option><option value="desc">Оценка: по убыванию</option></select></label></nav>
<section class="grid">{''.join(cards)}</section></main><script>
const grid=document.querySelector('.grid');let filter='all';function update(){{const cards=[...grid.children];cards.forEach(c=>c.hidden=filter!=='all'&&c.dataset.view!==filter);const mode=document.querySelector('#sort').value;cards.sort((a,b)=>mode==='code'?a.dataset.code.localeCompare(b.dataset.code):((mode==='asc'?1:-1)*(Number(a.dataset.score)-Number(b.dataset.score))||a.dataset.code.localeCompare(b.dataset.code)));cards.forEach(c=>grid.append(c))}}document.querySelectorAll('[data-filter]').forEach(b=>b.onclick=()=>{{filter=b.dataset.filter;update()}});document.querySelector('#sort').onchange=update;update();
</script></html>'''
    output = ROOT / "gallery.html"
    output.write_text(document, encoding="utf-8")
    print(f"Создано: {output}")


if __name__ == "__main__":
    main()
