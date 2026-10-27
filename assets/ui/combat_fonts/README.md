# Боевые подписи: единый Pixeloid Sans Bold

По уточнению U 2026-10-27 цифры приведены к выбранным буквам Pixeloid Sans Bold.
`combat_feedback.tres` назначен только Label в `result_number.tscn` и использует
один полный `pixeloid.ttf`, без отдельного числового шрифта/fallback-гарнитуры.
Кириллица, латинский HP, цифры и знаки `0123456789.,+-%−` имеют один рисунок.
Размер Label 24, подписи последствий 20; содержание, цвета, outline и lifecycle прежние.

`pixeloid.ttf` — статический Bold (usWeightClass=700), без синтетической жирности.
Контуры, cmap, интервалы и метрики строки исходные; em=2448 вместо 1836 (масштаб 3/4).
При кегле 24 исходная сетка 204 units равна 2 px; заглавные и цифры высотой 14 px.
Настройка букв сохранена с прошлого этапа. Строчные а/о высотой 10 px,
нижние элементы р/у уходят на 4 px под baseline. Метрики строки их покрывают.
Внутреннее имя `Combat Pixeloid`, стиль Bold. U+2212 взят из самого Pixeloid;
пунктуация не подменяется чужим шрифтом. Jersey удалён только из runtime.

Исходный TTF, URL и SHA — в [provenance.json](../../../docs/art/jersey-cyrillic-preview-20261027/provenance.json)
предыдущего сравнения. Это тот же Pixeloid Sans Bold; прежние preview-пакеты сохранены.
[Лицензия SIL OFL 1.1](pixeloid-OFL.txt) скопирована побайтно.

Воспроизведение из корня проекта с `fonttools==4.60.1`:

```powershell
python tools/art/build_combat_fonts.py
```

Скрипт сверяет исходные SHA и числовые glyph, сохраняет timestamp шрифта.
Зависимость нужна только для пересборки; игра использует готовый файл из assets.
Runtime SHA256: `b480114afeb881a93eacaa6f2887cd4592df418a1f5adff844531c2f5bbb7328`.

Контракт — [BATTLE_PRESENTATION_REWORK](../../../docs/BATTLE_PRESENTATION_REWORK.md).
`test_presentation_contact.gd` проверяет фактический Pixeloid для каждого glyph
в строках урона/крита/лечения/щита, HP, статусах и многострочных последствиях.
