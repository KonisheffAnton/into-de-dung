# Боевые подписи: Monogram Extended + Jersey 10

Уточнение U 2026-10-27: вернуть цифры Jersey 10, сохранив буквы Monogram.
Исходники взяты из [сравнения пар](../../../docs/art/combat-font-pairs-preview-20261027/README.md).
`combat_feedback.tres` назначен только Label в `result_number.tscn`.
Числа и знаки `0123456789.,+-%−` — Jersey 10 Regular; остальные
символы, включая кириллицу и латинский HP, — Monogram Extended Regular.
Размер Label 24, подписи последствий 20: мелкие знаки выбранных гарнитур
компенсированы размером кегля. Содержание, цвета, outline и lifecycle прежние.

`monogram_letters.ttf` — Monogram с теми же контурами/интервалами в font units,
но em=768 вместо 1024 (масштаб 4/3). При кегле 24 шаг исходной сетки равен 2 px,
буквы не теряются рядом с цифрами. Внутреннее имя `Combat Monogram Letters`.
`jersey_numbers.ttf` — числовое подмножество Jersey 10 с прежними рисунками,
em=1400 и горизонтальными метриками. Нижнее поле строки сокращено с 375 до 280
font units, чтобы сочетание с Monogram не вытесняло верхнее лечение за кадр.
Контуры числовых знаков занимают y=-150..750; изменение поля их не обрезает.
Внутреннее имя `Combat Jersey Numbers`. Без ограничения набора Jersey
перехватывал бы латинские буквы. Исходный U+2212 сохранён.
Исходные полные TTF, URL и SHA остаются в
[provenance.json](../../../docs/art/combat-font-pairs-preview-20261027/provenance.json).
Jersey — [SIL OFL 1.1](jersey-OFL.txt). Monogram — [CC0 1.0](monogram-CC0.txt),
[декларация автора](monogram-license-source.txt). Тексты сохранены побайтно.

Воспроизведение из корня проекта с `fonttools==4.60.1`:

```powershell
python tools/art/build_combat_fonts.py
```

Скрипт сверяет исходные SHA, сохраняет timestamp шрифта и выдаёт SHA результатов.
Зависимость нужна только для пересборки; игра использует готовые файлы из assets.
Monogram runtime SHA256: `ea1d00561f89684d0c84e2fd0f87255150fa29593f945153d8896090e0c0201f`.
Jersey subset SHA256: `688f135fd30f8b3eb274d610c1b86f6150dc57a2debb5d280ebc19ed2522577c`.

Контракт поведения — [BATTLE_PRESENTATION_REWORK](../../../docs/BATTLE_PRESENTATION_REWORK.md).
Шейпинг смешанных строк и PNG — `test_presentation_contact.gd`; проверяются
действительные шрифты glyph, включая HP, знаки, крит, щит и кириллические статусы.
