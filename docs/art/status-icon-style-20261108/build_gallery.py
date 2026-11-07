from pathlib import Path


ROOT = Path(__file__).resolve().parent
ROWS = {
    "01": ["Кровотечение", "Горение", "Яд", "Кислота", "Оглушение", "Путы", "Заморозка", "Мокрота"],
    "02": ["Магический щит", "Поднятый щит", "Оппортунист", "Контратака", "Прикрытие", "Ожидание", "Огонь на клетке", "Лужа кислоты"],
    "03": ["Шипы", "Труп", "Обвал", "Напольная ловушка", "Настенная ловушка", "Глубокая кислота", "Провал", "Опасность"],
}


def section(sheet_id: str, labels: list[str]) -> str:
    rows = "\n".join(f'          <li>{label}</li>' for label in labels)
    return f'''    <section class="sheet" id="sheet{sheet_id}" data-sheet="{sheet_id}">
      <h2>Лист {sheet_id}</h2>
      <p class="caption">PixelLab: проба в стиле текущих спрайтов. Три варианта A/B/C; не внедрено</p>
      <div class="gallery-row">
        <ol class="row-labels" aria-label="Эффекты по строкам">
{rows}
        </ol>
        <div class="sheet-image">
          <div class="column-headings" aria-hidden="true"><span>A</span><span>B</span><span>C</span></div>
          <a href="raw/sheet{sheet_id}.png" aria-label="Открыть исходный лист {sheet_id}, 384 на 512">
            <img src="raw/sheet{sheet_id}.png" alt="Исходный лист {sheet_id}: варианты A, B и C по восьми строкам" width="384" height="512">
          </a>
          <a class="full-image" href="raw/sheet{sheet_id}.png">Открыть исходный PNG 384×512</a>
        </div>
      </div>
    </section>'''


def build() -> str:
    sections = "\n\n".join(section(sheet_id, labels) for sheet_id, labels in ROWS.items())
    return f'''<!doctype html>
<html lang="ru">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Стиль статус-иконок — листы 01–03</title>
  <style>
    :root {{ color-scheme: dark; font-family: system-ui, sans-serif; background: #303636; color: #e0ddcb; }}
    body {{ margin: 1.5rem auto; max-width: 1080px; padding: 0 20px; }}
    a {{ color: #b9cfb1; }}
    nav {{ display: flex; gap: 1rem; flex-wrap: wrap; margin-bottom: 1rem; }}
    .sheet {{ margin: 2rem 0 3rem; padding-bottom: 2rem; border-bottom: 1px solid #8888; }}
    .caption {{ margin: .25rem 0 1rem; }}
    .gallery-row {{ display: flex; align-items: flex-start; gap: 1rem; overflow-x: auto; }}
    .row-labels {{ box-sizing: border-box; flex: 0 0 13rem; height: 1024px; margin: 32px 0 0; padding: 0; list-style: none; }}
    .row-labels li {{ box-sizing: border-box; height: 128px; display: flex; align-items: center; padding-right: .5rem; }}
    .sheet-image {{ flex: 0 0 768px; width: 768px; }}
    .column-headings {{ height: 32px; display: grid; grid-template-columns: repeat(3, 1fr); text-align: center; font-weight: 700; }}
    .sheet-image img {{ display: block; width: 768px; height: 1024px; image-rendering: pixelated; }}
    .full-image {{ display: inline-block; margin-top: .5rem; }}
    body.native .row-labels {{ height: 512px; margin-top: 32px; }}
    body.native .row-labels li {{ height: 64px; }}
    body.native .sheet-image {{ flex-basis: 384px; width: 384px; }}
    body.native .column-headings {{ height: 32px; }}
    body.native .sheet-image img {{ width: 384px; height: 512px; }}
  </style>
</head>
<body>
  <h1>Проба стиля статус-иконок</h1>
  <p>Просмотр исходных листов 384×512 с увеличением в 2 раза. Перед внедрением нужно проверить фактическую читаемость каждого спрайта при размере 16×16.</p>
  <p>Референс стиля: <a href="../../../assets/art_presets/approved/character_skins_v1/grey_bastion/still.png">текущий спрайт Grey Bastion</a>. Предыдущая галерея: <a href="../status-icon-proposals-20261108/index.html">схемы и предложения</a>.</p>
  <p>Формат запросов: <a href="requests/sheet01.json">лист 01</a> · <a href="requests/sheet02.json">лист 02</a> · <a href="requests/sheet03.json">лист 03</a> · <a href="README.md">README</a></p>
  <label><input id="native-toggle" type="checkbox"> Показать в исходном размере 384×512</label>
  <nav aria-label="Листы"><a href="#sheet01">Лист 01</a><a href="#sheet02">Лист 02</a><a href="#sheet03">Лист 03</a></nav>
{sections}
  <script>
    document.getElementById('native-toggle').addEventListener('change', function () {{
      document.body.classList.toggle('native', this.checked);
    }});
  </script>
</body>
</html>
'''


if __name__ == "__main__":
    (ROOT / "index.html").write_text(build(), encoding="utf-8", newline="\n")
