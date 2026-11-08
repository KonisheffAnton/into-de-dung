# Передача — 2026-11-08: подложки значков и числа

D:/Games/into-de-dung; main; base e025abf93837acc575241677d8eb34daa3c3d402.
По U под24 значками A дерево с железной рамкой;48 PNG16/32 сохраняют пиксели A.
PixelLab:10 generations. Стаки сверху, срок снизу, +N без чёрных плашек;
только контур глифов, привязка к экранным пикселям. Гамма/полосы/механики прежние.
ПКМ-карточка, постоянная область42px, неподвижные поле/рука сохранены.
Выбор: docs/ART_DIRECTION.md; показ: docs/BATTLE_HUD_SCENES_V1.md,
счётчики: docs/BATTLE_PRESENTATION_REWORK.md.
Пакет/кадры: docs/art/status-icon-frame-20261108/.
Ресурсы: assets/art_presets/approved/status_icons_framed_v1/; исходные status_icons_a_v1 сохранены.
Отчёт: test_reports/status-counters-no-panel-20261108/validation.json.

Свежие: builders A24/48 и frame48+2,50 sidecars PASS; isolated import/startup PASS.
condition_icons412/0, presentation_status146/0, unit_vital_bars278/0,
status_counter_layout19/0; launcher37/0. GPU: RGBA48 композиций точно равны
A поверх панели, кадры75/100%; тестовые DTO на H1, не сыгранный статусный бой.
Независимое ревью APPROVE. PASS diff, ссылки, архив HANDOFF и33 чужих файла.
Full/core, ручные F5/движение/zoom/DPI/performance не запускались.
Прежние огонь/шипы/HUD gates и APPROVE не считать повторёнными.

Далее — отзыв U о подложках/числах в текущем бою; новые пробы/срезы без запроса
не начинать. Остаток: стыки/посадка, край стрелы4 Лучницы, performance,
HUD/Колода; foundation141/2 и turn_forecast_ui26/3 не повторены.
Чужие33: scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/;
не reset/stage/commit. Сохранить core/preview/queue/RNG/save/frozen,5 классов F5,
PLAYER вправо/ENEMY влево и возврат; каталоги1–3 не мигрировать.
Один Godot runner, isolated project; без root import, служб/драйверов,
принудительного фокуса, push/sidebar tasks/расписаний.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261108-5.md), [HISTORY](HISTORY.md).
Завершение: проверки, локальный Conventional Commit, короткий HANDOFF;
прежний побайтно отдельно+HISTORY. В финале/при блокере предложить новый чат
и полный промпт: HEAD, результат, docs/artifacts, остаток, ограничения,
проверки и это же правило. Чат автоматически не создавать.
