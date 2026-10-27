# Боевые подписи: Monogram Extended + Pixelify Sans Bold

Уточнение U 2026-10-27: буквы Monogram, цифры Pixelify — вариант 02 из
[сравнения пар](../../../docs/art/combat-font-pairs-preview-20261027/README.md).
`combat_feedback.tres` назначен только Label в `result_number.tscn`.
Числа и знаки `0123456789.,+-%−` — Pixelify Sans Bold (wght=700); остальные
символы, включая кириллицу и латинский HP, — Monogram Extended Regular.
Размер Label 24, подписи последствий 20: мелкие знаки выбранных гарнитур
компенсированы размером кегля. Содержание, цвета, outline и lifecycle прежние.

`monogram_letters.ttf` — Monogram с теми же контурами/интервалами в font units,
но em=768 вместо 1024 (масштаб 4/3). При кегле 24 шаг исходной сетки равен 2 px,
буквы не теряются рядом с цифрами. Внутреннее имя `Combat Monogram Letters`.
`pixelify_numbers.ttf` — статический Bold из variable Pixelify Sans, подмножество
без букв с неизменёнными рисунками и горизонтальными метриками при wght=700;
внутреннее имя `Combat Pixelify Numbers`. Без ограничения набора цифры и буквы
получали бы Pixelify. Исходный U+2212 присутствует; подмена на дефис не нужна.
Вертикальные метрики числового подмножества 800/-200, lineGap=0:
поля полного алфавита убраны, видимые контуры помещаются целиком.
Исходные полные TTF, URL и SHA остаются в
[provenance.json](../../../docs/art/combat-font-pairs-preview-20261027/provenance.json).
Pixelify — [SIL OFL 1.1](pixelify-OFL.txt). Monogram — [CC0 1.0](monogram-CC0.txt),
[декларация автора](monogram-license-source.txt). Тексты сохранены побайтно.

Воспроизведение из корня проекта с `fonttools==4.60.1`:

```powershell
python tools/art/build_combat_fonts.py
```

Скрипт сверяет исходные SHA, сохраняет timestamp шрифта и выдаёт SHA результатов.
Зависимость нужна только для пересборки; игра использует готовые файлы из assets.
Monogram runtime SHA256: `ea1d00561f89684d0c84e2fd0f87255150fa29593f945153d8896090e0c0201f`.
Pixelify subset SHA256: `9a40b5dc7622a858ef8509b9f35836025a935873fec3e19665123efc0dc9045d`.

Контракт поведения — [BATTLE_PRESENTATION_REWORK](../../../docs/BATTLE_PRESENTATION_REWORK.md).
Шейпинг смешанных строк и PNG — `test_presentation_contact.gd`; проверяются
действительные шрифты glyph, включая HP, знаки, крит, щит и кириллические статусы.
