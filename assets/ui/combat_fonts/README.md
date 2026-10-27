# Боевые подписи: Tiny5 + Jersey 10

Выбран U 2026-10-27: вариант 03 из
[сравнения пар](../../../docs/art/combat-font-pairs-preview-20261027/README.md).
`combat_feedback.tres` назначен только Label в `result_number.tscn`.
Числа и знаки `0123456789.,+-%−` — Jersey 10 Regular; остальные символы,
включая кириллицу и латинский HP, — Tiny5 Regular с исходными осями по умолчанию.
Размер Label 24, подписи последствий 20: мелкие знаки выбранных гарнитур
компенсированы размером кегля без роста высоты основной строки относительно
прежнего шрифта. Содержание, цвета, outline и lifecycle прежние.

`tiny5.ttf` — побайтный оригинал выбранного превью.
`jersey_numbers.ttf` — подмножество Jersey без букв, с неизменёнными рисунками
и метриками включённых знаков; внутреннее имя `Combat Jersey Numbers`.
Без ограничения набора Jersey перехватывал бы также латинские буквы.
Исходные полные TTF, URL и SHA остаются в
[provenance.json](../../../docs/art/combat-font-pairs-preview-20261027/provenance.json).
Оба шрифта распространяются под SIL OFL 1.1; оригиналы лицензий приложены
побайтно: [Tiny5](tiny5-OFL.txt), [Jersey](jersey-OFL.txt).

Воспроизведение из корня проекта с `fonttools==4.60.1`:

```powershell
python tools/art/build_combat_fonts.py
```

Скрипт сверяет исходные SHA, сохраняет timestamp шрифта и выдаёт SHA результатов.
Зависимость нужна только для пересборки; игра использует готовые файлы из assets.
Tiny5 SHA256: `588626f2c1b164f55927c0d8123f4bc134651aad7d257da68fc19b0824b0d8fa`.
Jersey subset SHA256: `345d405f613d3a8a73398c53449345de806a2f736b99edb7e25bfafcb37acd05`.

Контракт поведения — [BATTLE_PRESENTATION_REWORK](../../../docs/BATTLE_PRESENTATION_REWORK.md).
Шейпинг смешанных строк и PNG — `test_presentation_contact.gd`; проверяются
действительные шрифты glyph, включая HP, знаки, крит, щит и кириллические статусы.
