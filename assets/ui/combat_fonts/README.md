# Боевые подписи: Jersey 20 + Play Bold

По U 2026-10-27 внедрён вариант 02 [последнего сравнения](../../../docs/art/jersey20-letters-preview-20261027/README.md).
Общий Label в `result_number.tscn` получает `combat_feedback.tres`:
основной `jersey20_numbers.ttf` содержит `0123456789.,+-%−`, а полный
`combat_letters.ttf` из Play Bold подключён как fallback для кириллицы,
латинского HP и прочих букв/знаков. Размеры 24/20, строки, цвета, outline
и lifecycle прежние; синтетическая жирность не применяется.

Jersey 20 и его OFL побайтно сохранены. Это статический Regular400,
внутреннее имя `Combat Jersey 20 Numbers`, исходные em=1292 и метрики.
Высота цифр 760 units — около 14,12 px при кегле 24. Отсутствие букв
в числовом подмножестве обеспечивает выбор Play также для HP.

Play — статический Bold700. Производный файл сохраняет все исходные контуры,
cmap, интервалы, hinting и метрики строки; em=1113 вместо 1000 даёт высоту
H/К 649 units — около 14 px при кегле 24. Строчные сохраняют свои пропорции.
Внутреннее имя `Combat Lettering`/Bold не использует Reserved Font Names
Play/Playtype/Playtype Sans; copyright и лицензионные записи исходника сохранены.
Нужные кириллица А–я/Ёё, HP и знаки ·×—:()/ присутствуют без системной подмены.
Стрелки в исходном Play отсутствуют; текущие боевые подписи их не используют.

Источники, точные URL и SHA — [provenance.json](../../../docs/art/jersey20-letters-preview-20261027/provenance.json).
Оригинальные TTF и все шесть превью сохранены. Лицензии SIL OFL1.1:
[Jersey 20](jersey20-OFL.txt), [Play](play-OFL.txt), обе побайтные копии.
Прежний Pixeloid удалён только из runtime; исходники остаются в превью.

Воспроизведение из корня с `fonttools==4.60.1`:

```powershell
python tools/art/build_combat_fonts.py
```

Сборщик проверяет SHA исходников и наличие нужных glyph, сохраняет timestamp.
Зависимость нужна только для пересборки; игра использует готовые assets без docs.
Runtime SHA256:

- Jersey 20: `ce65411785a3a5632cbf4447dcba78de9ce52285a0c19b17dd778cb2c818f7ea`.
- Буквы Play: `2d12eb5cadaaaa135352a0ab82544768f08e8e415b65f07f77c8acf3be8cdbaa`.

Контракт — [BATTLE_PRESENTATION_REWORK](../../../docs/BATTLE_PRESENTATION_REWORK.md).
`test_presentation_contact.gd` проверяет реальную гарнитуру каждого glyph в
числах/крите/лечении/щите, HP, кириллических статусах, многострочных последствиях,
всём числовом подмножестве и знаках ·×—:/; системная подмена отвергается.
