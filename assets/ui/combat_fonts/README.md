# Боевые подписи: Jersey 20 + Pixeloid Sans Bold

По U 2026-10-27 внедрён вариант 03 из [сравнения](../../../docs/art/pixeloid-numerals-preview-20261027/README.md).
`combat_feedback.tres` назначен только Label в `result_number.tscn`: основной
`jersey20_numbers.ttf` содержит `0123456789.,+-%−`, полный `pixeloid.ttf` подключён
как fallback для кириллицы, латинского HP и прочих знаков/слов.
Размер Label 24, подписи последствий 20; содержание, цвета, outline и lifecycle прежние.

Jersey 20 — статический Regular400. Подмножество сохраняет исходные контуры,
em=1292, интервалы и вертикальные метрики; меняются только состав и внутренние
имена: `Combat Jersey 20 Numbers`. Цифры высотой 760 units, около 14,12px при
кегле24. Запятая опускается до −114 units при descent −266, не обрезается.
Настоящий U+2212 взят из Jersey 20; латинские буквы в подмножестве отсутствуют,
поэтому HP тоже рисуется Pixeloid. Синтетическое утолщение не применяется.

`pixeloid.ttf` и его OFL сохранены побайтно с прошлого этапа. Это статический
Bold700, внутреннее имя `Combat Pixeloid`, em=2448 вместо исходного1836.
Сетка204units=2px при кегле24, заглавные14px, строчные а/о10px;
контуры, cmap, интервалы и метрики строки прежние.

Исходники, точные URL и SHA — [provenance.json](../../../docs/art/pixeloid-numerals-preview-20261027/provenance.json).
Лицензии SIL OFL1.1: [Jersey20](jersey20-OFL.txt), [Pixeloid](pixeloid-OFL.txt).
Оригинальные файлы и все прежние preview-пакеты сохранены.

Воспроизведение из корня проекта с `fonttools==4.60.1`:

```powershell
python tools/art/build_combat_fonts.py
```

Скрипт сверяет исходные SHA и наличие числовых glyph, сохраняет timestamp шрифта.
Зависимость нужна только для пересборки; игра использует готовые assets без docs.
Runtime SHA256:

- Jersey20: `ce65411785a3a5632cbf4447dcba78de9ce52285a0c19b17dd778cb2c818f7ea`.
- Pixeloid: `b480114afeb881a93eacaa6f2887cd4592df418a1f5adff844531c2f5bbb7328`.

Контракт — [BATTLE_PRESENTATION_REWORK](../../../docs/BATTLE_PRESENTATION_REWORK.md).
`test_presentation_contact.gd` проверяет фактическую гарнитуру каждого glyph
в уроне/крите/лечении/щите, HP, кириллических статусах, многострочных последствиях
и всём числовом подмножестве; системная подмена используемых знаков отвергается.
