# Передача — 2026-10-21: темп отталкивания
D:\Games\into-de-dung; main; base 9340019a3151210c70aa4dc491e9570626181c37.
По U одиночный ровный и терминальный цепной сдвиг замедлены с 0,18 до 0,24 с.
Резкий старт, торможение, наклон и штрихи прежние; атака/упор/падение,
core и исходный арт не менялись. [Показ](BATTLE_PRESENTATION_REWORK.md),
[архитектура](ARCHITECTURE.md), [отчёт](../test_reports/push-slide-tempo-20261021/README.md).
Import/startup PASS; render push 386/0, consequences 2007/0, environment 323/0,
всего 2716/0. PNG середины осмотрен; независимый review APPROVE.
Новых full/core/Python и ручных F5/editor/DPI/GPU нет; темп в бою ждёт U.
U: пока только отталкивание. Эффекты ударов/выбор стиля отложены;
предложение PNG-анимаций не внедрено, ассеты не создавались.
Следующий этап только по выбору U.
Ранее b68776af: ножи разбойника; extra_attack суммируется по вещам,
даёт +1 последовательный удар той же цели; серия за 1 main.
[EQUIPMENT_ATTACKS](EQUIPMENT_ATTACKS.md), [отчёт](../test_reports/equipment-attacks-20261018/README.md).
Прежние equipment 175/0, core 9424/0, worker/preview/live PASS;
ручная приёмка серии и баланса открыта.
Четыре [диорамы](art/hub-diorama-layered-20261018/README.md) сохранены.
HTML не внедрять; browser playback/размещение/подсветка не приняты.
Crowd02/market05/latest smith03 выбраны; cleanup676d718 отклонён.
WallTrap/конечная стрелка ждут U; HUD/art, поле, воин/тайлы/боковины30px,
Лучница, камера/04/05 и баланс яда — остаток у [ART](ART_DIRECTION.md).
Круглые тени live; направленные/2:1 и idle A/B — preview.
Чужие scenes/demo/main_menu.tscn (dirty) и docs/art/battlefield-reference-03-20261017/
(untracked) не трогать/reset/stage/commit; SHA сцены в отчёте, manifest03 устарел.
Core/preview/live/worker/queue/RNG/save/frozen сохранять; без нового баланса.
Без push/sidebar/расписаний; арт-превью не внедрять.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261021.md), [HISTORY](HISTORY.md).
После этапа — проверки, Conventional Commit, короткий HANDOFF; прежний побайтно
в отдельный архив+HISTORY. В финале/при блокере предложить новый чат и полный
промпт блоком: HEAD, результат, docs/artifacts, остаток, ограничения, проверки
и это же правило передачи. Чат автоматически не создавать; правило переносить.
