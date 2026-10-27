# Боевые подписи: Pixeloid Sans Bold + Jersey 10

По U 2026-10-27 внедрены буквы Pixeloid Sans Bold, вариант 03 из
[сравнения кириллицы](../../../docs/art/jersey-cyrillic-preview-20261027/README.md).
Числовой файл Jersey сохранён побайтно.
`combat_feedback.tres` назначен только Label в `result_number.tscn`.
Числа и знаки `0123456789.,+-%−` — Jersey 10 Regular; остальные
символы, включая кириллицу и латинский HP, — Pixeloid Sans Bold.
Размер Label 24, подписи последствий 20: мелкие знаки выбранных гарнитур
компенсированы размером кегля. Содержание, цвета, outline и lifecycle прежние.

`pixeloid_letters.ttf` — статический Bold (usWeightClass=700), без синтетической
жирности. Контуры и интервалы в font units сохранены; em=2448 вместо 1836
(масштаб 3/4). При кегле 24 шаг исходной сетки 204 units равен 2 px, а высота
основных заглавных 14 px — как у прежнего Monogram. Метрики строки исходные;
строчные а/о высотой 10 px, нижние элементы р/у уходят на 4 px под baseline.
Буквы шире прежнего Monogram; длинные последствия проверяются в рендере.
Внутреннее имя `Combat Pixeloid Letters`, стиль Bold.
`jersey_numbers.ttf` — числовое подмножество Jersey 10 с прежними рисунками,
em=1400 и горизонтальными метриками. Нижнее поле строки сокращено с 375 до 280
font units; эта прежняя настройка удерживает верхнее лечение в кадре.
Контуры числовых знаков занимают y=-150..750; изменение поля их не обрезает.
Внутреннее имя `Combat Jersey Numbers`. Без ограничения набора Jersey
перехватывал бы латинские буквы. Исходный U+2212 сохранён.
Исходные полные TTF, URL и SHA остаются в
[provenance.json](../../../docs/art/jersey-cyrillic-preview-20261027/provenance.json).
Jersey — [SIL OFL 1.1](jersey-OFL.txt), Pixeloid — [SIL OFL 1.1](pixeloid-OFL.txt).
Тексты лицензий сохранены побайтно. Старый Monogram удалён только из runtime;
все прежние preview-пакеты сохранены.

Воспроизведение из корня проекта с `fonttools==4.60.1`:

```powershell
python tools/art/build_combat_fonts.py
```

Скрипт сверяет исходные SHA, сохраняет timestamp шрифта и выдаёт SHA результатов.
Зависимость нужна только для пересборки; игра использует готовые файлы из assets.
Pixeloid runtime SHA256: `e114ace31270494a016392dc1afcc9516a43586bba81dfa16854edbc49c47b5c`.
Jersey subset SHA256: `688f135fd30f8b3eb274d610c1b86f6150dc57a2debb5d280ebc19ed2522577c`.

Контракт поведения — [BATTLE_PRESENTATION_REWORK](../../../docs/BATTLE_PRESENTATION_REWORK.md).
Шейпинг смешанных строк и PNG — `test_presentation_contact.gd`; проверяются
действительные шрифты glyph, включая HP, знаки, крит, щит и кириллические статусы.
