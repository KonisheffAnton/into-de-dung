# Передача — 2026-11-22: видимость полоски брони

D:/Games/into-de-dung; main; база435f11a3d6f67c7cbd4b3ddc51dce8071536a0b0.
U поручил: без исходной брони нет полоски; временная/магическая показывает
её до фактического0, затем скрывает. Пустая штатная броня остаётся.
Внедрено в BattleUnitVitalsPainter; maximum=штатная ёмкость,
current=текущий запас с выдачами. HP/равновесие и core прежние.
Положительный остаток<0.1 отображается как <0.1; прогноз видимость не меняет.
[Владелец правила](BATTLE_PRESENTATION_REWORK.md), [пакет/кадры](art/armor-bar-visibility-20261122/README.md).

Изолированный import/startup + unit_vital_bars/presentation_status/
unit_visual_contract/visual_scene_contract PASS, 1884/0, независимое ревью APPROVE.
Отчёт test_reports/demo-025837fc8f5d423896a864f0d40207c1.
Первый import упал на Godot teardown Button disconnect; чистый повтор PASS.
Full/core, ручной F5/DPI/плейтест/performance не заявлены.

Параллельно U выбрал K1 и поручил альбиноса с немного болезненно-кровавыми
акцентами и по3 ожидания/смерти/усиления через PixelLab. Арт вне Git:
D:/Codex/home/visualizations/2026/11/22/01a202d0-455a-7d51-b346-7485f6101462/
k1-albino-animations-v12-20261122/. Владелец арт-статуса — HANDOFF того workspace.
В игру K1 не интегрирован. Выбор анимаций/художественная приёмка открыты.

Прежняя игровая проба2:1 с кнопкой возврата4:3 остаётся:
[контракт](BATTLE_VISUAL_SCENE_CONTRACT.md), [пакет](art/projection-2x1-runtime-20261122/README.md).
Ручная приёмка боя/перекрытий открыта. Прежние лица — только рот у людей,
лица монстров не менять этим старым срезом; персонажи/анимации игры прежние.
Вселение/карты — дизайн без реализации, новые атаки хобгоблина без U не делать.
Core/preview/queue/RNG/save/frozen сохранять; инициативы нет, 5 классов F5 прежние.
Чужие scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/
не reset/stage/commit. Только свои локальные коммиты, без push.
Один isolated runner; без root import, sidebar tasks и расписаний.

[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261122-3.md) + HISTORY.
После этапа/при блокере предложить новый чат и полный самодостаточный промпт:
HEAD, результат, docs/artifacts, остаток, ограничения, проверки и это правило.
Прежний HANDOFF сохранить побайтно отдельно со ссылкой из HISTORY;
чат автоматически не создавать.