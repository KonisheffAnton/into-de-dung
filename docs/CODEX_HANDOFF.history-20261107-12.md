# Передача — 2026-11-07: урон над целью, читаемые полосы

D:/Games/into-de-dung; main; baseab78ddbad1b259126d4e155d75014cbf47c7ea76.
По U общий урон перенесён над получателем: target для атаки, контратаки,
ловушки, DOT, self и внешнего мага, независимо от наличия/смерти автора.
Сумма actual HP+расход брони+щит, контакт без задержки, after и очередь прежние.
Полосы48×12: броня металлическая, HP зелёное; текущие числа Jersey20 внутри,
включая дробь/ноль. Прогноз/равновесие ниже; данные только опубликованные.
Контракт: BATTLE_PRESENTATION_REWORK; ARCHITECTURE,
BATTLE_VISUAL_SCENE_CONTRACT, ENVIRONMENT_HAZARDS_V1 и TESTING обновлены.

Свежий isolated import/startup PASS; contact327/0, mage353/0,
damage_feedback63/0, ranged238/0, attack_styles601/0, consequences2096/0,
environment364/0, reactions1426/0, owned64/0, hazards_ui118/0,
unit_visual_contract45/0, visual_scene_contract106/0.
presentation_status76/2: обе ошибки размеров поля воспроизведены на base66/2;
10 новых проверок полос PASS. Launcher14/1/0, не полный PASS.
GPU цифры/полосы просмотрены; независимое ревью APPROVE.
Отчёт test_reports/recipient-vitals-20261107/; runner demo-4f39a64ee7b841d5b5f5999f5676e7d4.
Первый импорт остановился на TTF preload; lazy runtime load исправлен,
чистый импорт повторён. Full/core, ручные F5/движение/zoom/DPI/performance
не запускались. Прежние огонь29/шипы/HUD APPROVE не считать повторёнными.

Далее — отзыв U о цифре над целью и полосах в текущем бою; новые срезы
без запроса не начинать. Принятый огонь29 natural02-middle сохранён:
docs/art/fire29-natural-integration-20261107/, ART_DIRECTION.
Остаток: стыки/посадка/читаемость, край стрелы4 Лучницы, performance;
presentation_status76/2, presentation_foundation141/2, turn_forecast_ui26/3, HUD/Колода.
Чужие33 файла: scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/;
не reset/stage/commit. Core/preview/queue/RNG/save/frozen сохранять;
5 классов F5, PLAYER вправо/ENEMY влево и возврат; каталоги1–3 не мигрировать.
Один Godot runner, isolated project; без root import, служб/драйверов,
принудительного фокуса, push/sidebar tasks/расписаний.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261107-11.md), [HISTORY](HISTORY.md).
Завершение: проверки, локальный Conventional Commit, короткий HANDOFF;
прежний побайтно отдельно+HISTORY. В финале/при блокере предложить новый чат
и полный промпт: HEAD, результат, docs/artifacts, остаток, ограничения,
проверки и это же правило. Чат автоматически не создавать.
