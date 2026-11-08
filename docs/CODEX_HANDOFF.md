# Передача — 2026-11-08: рамки только в интерфейсе

D:/Games/into-de-dung; main; base970f2a961fe7b6cb7ea5122b50db1b2b19c4ede0.
Уточнение U: у персонажей рамки не нужны. Ряд на поле использует прозрачные
значки A16 без дерева/железа; в карточке и нижнем осмотре UI рамки сохранены.
Стаки сверху, срок снизу и +N по-прежнему без чёрных плашек.
Новых изображений не генерировали; гамма/полосы/механики прежние.
ПКМ-карточка, область42px, неподвижные поле/рука сохранены.
Выбор: docs/ART_DIRECTION.md; показ: docs/BATTLE_HUD_SCENES_V1.md
и docs/BATTLE_PRESENTATION_REWORK.md.
Обновлённые кадры/пакет: docs/art/status-icon-frame-20261108/.
Ресурсы: assets/art_presets/approved/status_icons_a_v1/ (поле),
assets/art_presets/approved/status_icons_framed_v1/ (панели UI).
Отчёт: test_reports/status-world-icons-20261108/validation.json.

Свежие isolated import/startup PASS; status_counter_layout19/0,
presentation_status146/0, condition_icons412/0 =577/0. GPU75/100%:
в H1 тестовые DTO представления, не сыгранный статусный бой.
Независимое ревью APPROVE; diff, ссылки, архив HANDOFF и33 чужих файла PASS.
Предыдущие builders/vital/launcher/огонь/шипы/HUD gates и APPROVE не повторены.
Full/core, ручные F5/движение/zoom/DPI/performance не запускались.

Далее — отзыв U о текущем показе; новые пробы/срезы без запроса не начинать.
Остаток: стыки/посадка, край стрелы4 Лучницы, performance, HUD/Колода;
foundation141/2 и turn_forecast_ui26/3 не повторены.
Чужие33: scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/;
не reset/stage/commit. Сохранить core/preview/queue/RNG/save/frozen,5 классов F5,
PLAYER вправо/ENEMY влево и возврат; каталоги1–3 не мигрировать.
Один Godot runner, isolated project; без root import, служб/драйверов,
принудительного фокуса, push/sidebar tasks/расписаний.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261108-6.md), [HISTORY](HISTORY.md).
Завершение: проверки, локальный Conventional Commit, короткий HANDOFF;
прежний побайтно отдельно+HISTORY. В финале/при блокере предложить новый чат
и полный промпт: HEAD, результат, docs/artifacts, остаток, ограничения,
проверки и это же правило. Чат автоматически не создавать.
