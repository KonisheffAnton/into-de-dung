# Передача — 2026-10-18: отталкивание со скольжением
D:\Games\into-de-dung; main; base b68776af226817491e232bfe35b44110359510ad.
По выбору U внедрён наземный сдвиг: быстрый импульс→торможение за 0,18 с,
наклон вокруг стоп и затухающие штрихи; конец в новой клетке без возврата.
Одиночный и цепной толчок, native/fallback; resize/zoom и очистка поз проверены.
Атака/упор/падение прежние; механика и исходный арт не менялись.
Владелец: [Показ](BATTLE_PRESENTATION_REWORK.md), архитектура/TESTING обновлены.
[Отчёт](../test_reports/push-slide-20261018/README.md): import/startup PASS,
9 render-меток 3965/0, включая push 386/0, цепь 2007/0, падение 323/0,
контакт 149/0, стили 174/0, визуальные контракты и маршруты смерти; Python 28/0.
PNG осмотрены, независимый review APPROVE. Новых full/core и ручных
F5/editor/DPI/GPU-проверок нет. Следующее: U оценивает скольжение в бою.
Ранее b68776af: ножи выданы разбойнику; extra_attack суммируется по вещам,
даёт +1 последовательный удар той же цели; серия за 1 main. Детали у
[EQUIPMENT_ATTACKS](EQUIPMENT_ATTACKS.md), [отчёт](../test_reports/equipment-attacks-20261018/README.md).
Прежние equipment 175/0, core 9424/0 и worker/preview/live PASS;
ручная приёмка двух атак, показа серии и баланса ещё открыта.
Четыре [диорамы](art/hub-diorama-layered-20261018/README.md) сохранены до возврата U.
HTML не внедрён; browser playback/размещение/подсветка не приняты.
Выбор crowd02/market05/latest smith03; cleanup676d718 отклонён. Детали у [ART](ART_DIRECTION.md).
WallTrap/конечная стрелка технически проверены ранее, новый вид ждёт U.
Открыты HUD/art: поле, воин/тайлы/боковины30px, Лучница, камера/04/05, баланс яда.
Круглые тени live; направленные/2:1 и idle A/B — preview. Остаток у ART/архива.
Чужие scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/
не трогать/reset/stage/commit; SHA сцены сохранён; manifest03 устарел.
Core/preview/live/worker/queue/RNG/save/frozen сохранять; без нового баланса.
Без push/sidebar/расписаний; следующий этап только по выбору U; арт-превью не внедрять.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261018-18.md), [HISTORY](HISTORY.md).
После этапа — проверки, Conventional Commit, короткий HANDOFF; прежний побайтно
в отдельный архив+HISTORY. В финале/при блокере предложить новый чат и полный
промпт блоком: HEAD, результат, docs/artifacts, остаток, ограничения, проверки
и это же правило передачи. Чат автоматически не создавать; правило переносить.
