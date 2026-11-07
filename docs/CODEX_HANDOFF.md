# Передача — 2026-11-07: общий урон сразу, ловушки видимы

D:/Games/into-de-dung; main; base92cae65dedab2fc30934c0c9a51c31805e2e847b.
U исправил прежний показ: одно число общего урона, цифру сразу, убрать
лишнее ожидание после удара; урон ловушек показывать. Реализовано:
actual HP+расход брони+поглощение щитом одним «−N.N» у атакующего;
cell-источник — в origin_cell ловушки/опасности. Лечение отдельно.
Убраны задержка цифры50мс, hit-stop35мс, hold шипов700мс.
Выдвижение40мс, втягивание100мс, возврат и смерть сохранены.
Цифра при контакте/до status pulse; упор строго связывает следующий
готовый push_damage/collision_damage. After/очередь не объединяются,
дедуп по ключу результата. Core/preview/queue/RNG/save не менялись.
Контракты: BATTLE_PRESENTATION_REWORK, ENVIRONMENT_HAZARDS_V1;
ARCHITECTURE, BATTLE_VISUAL_SCENE_CONTRACT и TESTING синхронизированы.

Свежий isolated import/startup PASS; damage_feedback63/0, contact324/0,
attack_styles601/0, consequences2096/0, environment364/0, ranged238/0,
mage343/0, reactions1426/0, owned64/0, hazards_ui118/0; launcher12/0/0.
Python launcher37 PASS; независимое ревью финального патча APPROVE.
GPU общий удар/ловушка просмотрены. Отчёт test_reports/total-damage-feedback-20261107/;
runner demo-ef0b43bcd98c4d44ac99466c2c74550e. Промежуточные ошибки
и исправления — в отчёте. Full/core, ручные F5/движение/zoom/DPI/
performance не запускались. Огонь29/HUD отдельно не перепроверялись.

Далее — отзыв U об общей цифре и темпе в текущем бою; новые срезы без
запроса не начинать. Огонь29 natural02-middle остаётся внедрённым:
docs/art/fire29-natural-integration-20261107/, ART_DIRECTION.
Остаток: стыки/посадка/читаемость, край стрелы4 Лучницы, performance;
presentation_foundation141/2, turn_forecast_ui26/3, HUD/Колода.
Чужие scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/
не reset/stage/commit. Сохранить core/preview/queue/RNG/save/frozen,
5 классов F5, PLAYER вправо/ENEMY влево и возврат; каталоги1–3 не мигрировать.
Один Godot runner, isolated project; без root import, служб/драйверов,
принудительного фокуса, push/sidebar tasks/расписаний.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261107-10.md), [HISTORY](HISTORY.md).
Завершение: проверки, локальный Conventional Commit, короткий HANDOFF;
прежний побайтно отдельно+HISTORY. В финале/при блокере предложить новый чат
и полный промпт: HEAD, результат, docs/artifacts, остаток, ограничения,
проверки и это же правило. Чат автоматически не создавать.
