# Выбранный разбойник: три idle и три смерти PixelLab

U2026-10-23 приложил зелёного разбойника с поднятым правым по картинке кинжалом
и поручил анимации PixelLab, также по три варианта. Base main
`b44ad76995c67f15ce34972552311406e9042b9a`; integration=false.

[Открыть галерею шести клипов](C:/Users/Aston/.codex/generated_images/rogue-selected-pixellab-20261023/gallery.html).

| Тип | Вариант1 | Вариант2 | Вариант3 |
|---|---|---|---|
| Idle | [GIF1](C:/Users/Aston/.codex/generated_images/rogue-selected-pixellab-20261023/previews/idle-1.gif) | [GIF2](C:/Users/Aston/.codex/generated_images/rogue-selected-pixellab-20261023/previews/idle-2.gif) | [GIF3](C:/Users/Aston/.codex/generated_images/rogue-selected-pixellab-20261023/previews/idle-3.gif) |
| Смерть | [GIF1](C:/Users/Aston/.codex/generated_images/rogue-selected-pixellab-20261023/previews/death-1.gif) | [GIF2](C:/Users/Aston/.codex/generated_images/rogue-selected-pixellab-20261023/previews/death-2.gif) | [GIF3](C:/Users/Aston/.codex/generated_images/rogue-selected-pixellab-20261023/previews/death-3.gif) |

## Исходник и подготовка

[source.png](source.png) — побайтная копия нового вложения U. Рисунок визуально
соответствует выбранному варианту с открытой стойкой, но его байты/RGBA не равны
прежнему variant-02; в API передан именно новый файл после подготовки.
PixelLab unzoom и remove-background, затем кадрирование по alpha и равномерный
nearest resize дали [input-transparent.png](input-transparent.png):128² RGBA,
фигура66×72 в(31,20). Опора около(64,92) — ориентир входа, не игровая посадка.
[Подготовка](source-preparation.json), [происхождение/SHA](provenance.json),
[сравнение с воином](style-comparison.png). Обе фигуры имеют видимую высоту72px.
Новый дизайн не генерировался, исходники и полученные позы не ретушировались.

Владелец стиля — [ART_DIRECTION](../../ART_DIRECTION.md), эталон —
[warrior_format_v1](../../../assets/art_presets/approved/warrior_format_v1/README.md).
Правая сторона по картинке дальняя, левая ближняя; правый кинжал вверх обычным
хватом, левый вверх-влево, глаз маленький чёрный без белка/блика.

## Запросы и выдача

Точные задания — [idle1](prompts/idle-1.txt), [idle2](prompts/idle-2.txt),
[idle3](prompts/idle-3.txt), [смерть1](prompts/death-1.txt),
[смерть2](prompts/death-2.txt), [смерть3](prompts/death-3.txt).
По актуальной [схеме PixelLab](https://api.pixellab.ai/v2/openapi.json) отправлены
шесть animate-with-text-v3: frame_count=16, no_background=true,
enhance_prompt=false, seeds2026102390–2026102395. У idle last_frame равен входу;
у смерти отсутствует. Все6 jobs completed, каждый вернул17 PNG128².

Полный пакет вне Git:
`C:/Users/Aston/.codex/generated_images/rogue-selected-pixellab-20261023/`.
Там сохранены source-prep, schema, точные request/prompt, admission, окончательные
job-latest,102 оригинальных PNG, metadata, manifest, contact-sheets, previews,
галерея и скрипты подготовки/сборки/проверки. Ответы API и секреты в Git не включены.
Авторский шаг просмотра150мс, не тайминг API. Idle повторяется; смерть идёт один
раз, GIF держит финал дополнительные900мс, галерея остаётся на последнем кадре.

## Проверки и ограничения

[Проверки завершения](closeout-checks.json), [независимое ревью](review.txt):
APPROVE только для внешней выдачи с указанными ограничениями.
102/102 PNG побайтно равны API,128² RGBA с прозрачностью, касаний края нет.
Первые кадры6/6 RGBA-равны входу. Галерея:6 canvases/17кадров,12 локальных ссылок,
пауза/повтор во время паузы/продолжение/скорость/финальный кадр смерти PASS.
Ведущий и reviewer просмотрели все6 контактных листов. Python/JS запуск PASS.

- Idle1 спокойнее; idle2 заметнее наклоняет корпус/кисти; idle3 меняет голову
  и левый нож. Руки/углы клинков/местами лицо не полностью стабильны.
- При переходе последнего кадра к первому видимые RGBA-различия составляют
  279/357/239 пикселей. Бесшовность не подтверждена.
- Все три смерти фактически падают вперёд-вправо. Задания на ближний бок
  влево и назад на спину не выполнены. Отдельная ясная остановка на колене
  в death1 не подтверждена. В лежачих позах ножи местами заслонены.
- Названия в галерее нейтральные; задания сохранены отдельно. Художественный
  выбор U, игровой размер/посадка, тайминг и переходы требуют отдельной приёмки.

Расход25,1 генерации:24 за6 клипов,0,1 unzoom и1 remove-background;
баланс2172,4→2147,3, USD0. [Учёт](costs.json); повторных неопределённых POST нет.
Игровые код/ассеты, воин idle-1/death-2 и другие классы прежние.
Godot/full/core/F5/editor/DPI/GPU не запускались. Следующий шаг — отзыв/выбор U;
новые серии, правки и интеграцию автоматически не начинать.
