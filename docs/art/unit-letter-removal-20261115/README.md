# Убраны буквы на персонажах — 2026-11-15

По U удалена первая буква имени, которая рисовалась поверх тела в
`BattleDemoIsoVisual._draw_unit`. Изменение касается обычных персонажей,
процедурных фигур и временных силуэтов перемещения.
Имена в карточках/подсказках, полосы и статусы остаются прежними.
Поле `transient_label` и его очистка сохранены для совместимости API.

Ветка main, база `d27f0c8ceb5234664906f313bc74ebf0f0834ff3`.
Production diff — удаление двух строк отрисовки; в тесте скинов обновлён комментарий.
Новых тестов для этой малой визуальной правки нет; использованы существующие.
Контракт — [BATTLE_VISUAL_SCENE_CONTRACT](../../BATTLE_VISUAL_SCENE_CONTRACT.md).

Проверка: `python tools/demo/isolate.py --render-check --only
unit_visual_contract class_showcase_ui --screen 0` с явным `--godot`.
Отчёт: `test_reports/demo-92777eb228ef47ec9d245fca1db36273/`.
Итоговые счётчики, независимое ревью, SHA и сохранность чужих файлов —
в `validation.json`. [Игровое поле после удаления букв](class-roster-facing.png).
Import/startup PASS; unit_visual_contract45/0, class_showcase_ui54/0;
независимое ревью APPROVE. Игровой GPU-кадр просмотрен: буквы на телах убраны.
Это целевая проверка, не новый full/core или ручная F5/DPI/performance-приёмка.

Чужие `scenes/demo/main_menu.tscn` и `docs/art/battlefield-reference-03-20261017/`
сохранены;33 SHA сверены с аудитом предыдущего этапа. Без push.
[Прежняя передача побайтно](../../CODEX_HANDOFF.history-20261115-21.md).
Входные AGENTS/PROJECT_CONTEXT/WORKFLOW не менялись; исходное превышение
PROJECT_CONTEXT3652 символа не относится к этой правке.
