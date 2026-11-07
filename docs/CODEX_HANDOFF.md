# Передача — 2026-11-07: визуал полос ресурсов

D:/Games/into-de-dung; main; base 351c91a6451c1ba91e0bdce8db88776e8b320807.
По U проработаны HP/броня/равновесие: спокойные зелёная/металлическая/янтарная
шкалы, чёрные числа и рамки, читаемый ноль/малый остаток. HP/броня48×11;
рамка и баланс устойчивы на75%. Механика, общий урон над получателем и тайминг прежние.
Владелец: BATTLE_PRESENTATION_REWORK; направление ART_DIRECTION;
ARCHITECTURE/TESTING обновлены. Кадры docs/art/unit-vitals-polish-20261107/.

Свежий isolated import/startup PASS; unit_vital_bars245/0, current_art_zoom520/0,
unit_visual45/0, visual_scene106/0, contact327/0, consequences2096/0,
environment364/0, camera111/0, execution61/0; остальные запущенные арт-gates PASS.
presentation_status84/2: только прежние две ошибки размеров поля, baseline66/2
подтверждён прошлым этапом, здесь не повторялся. Launcher24/1/0, не полный PASS.
Python launcher37 PASS; GPU кадры75/100/125, независимое ревью APPROVE.
Отчёт test_reports/unit-vitals-polish-20261107/; runner demo-48064b03e699428696bddfb05c4a6105.
Первый прогон выявил исчезающую рамку/тонкий баланс на75% и ошибку fixture;
исправлены, весь выбранный набор повторён. Full/core, ручные F5/движение/
zoom/DPI/performance не запускались; прежние проверки не считать повторёнными.

Далее — отзыв U о полосах в текущем бою; художественная приёмка открыта.
Новые срезы без запроса не начинать. Принятый огонь29 natural02-middle сохранён:
docs/art/fire29-natural-integration-20261107/, ART_DIRECTION.
Остаток: стыки/посадка/читаемость, край стрелы4 Лучницы, performance;
presentation_status84/2, presentation_foundation141/2, turn_forecast_ui26/3, HUD/Колода.
Чужие33 файла: scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/;
не reset/stage/commit. Core/preview/queue/RNG/save/frozen сохранять;
5 классов F5, PLAYER вправо/ENEMY влево и возврат; каталоги1–3 не мигрировать.
Один Godot runner, isolated project; без root import, служб/драйверов,
принудительного фокуса, push/sidebar tasks/расписаний.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261107-13.md), [HISTORY](HISTORY.md).
Завершение: проверки, локальный Conventional Commit, короткий HANDOFF;
прежний побайтно отдельно+HISTORY. В финале/при блокере предложить новый чат
и полный промпт: HEAD, результат, docs/artifacts, остаток, ограничения,
проверки и это же правило. Чат автоматически не создавать.
