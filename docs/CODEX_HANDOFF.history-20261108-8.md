# Передача — 2026-11-08: числа на значках

D:/Games/into-de-dung; main; base67e4269db261f5d7a733576e543354d7e552670c.
По U меньшие числа непосредственно на значках: стаки слева сверху,
срок справа снизу; базовый шрифт12→10px, без плашек, контур/привязка к пикселям.
Значки A16 у персонажей прозрачны; дерево/железо остаётся только в панелях UI.
Новых изображений не генерировали; гамма/полосы/механики прежние.
ПКМ-карточка, область42px, неподвижные поле/рука сохранены.
Выбор: docs/ART_DIRECTION.md; показ: docs/BATTLE_PRESENTATION_REWORK.md
и docs/BATTLE_HUD_SCENES_V1.md.
Обновлённые кадры/пакет: docs/art/status-icon-frame-20261108/.
Ресурсы: assets/art_presets/approved/status_icons_a_v1/ (поле),
assets/art_presets/approved/status_icons_framed_v1/ (панели UI).
Отчёт: test_reports/status-counters-overlay-20261108/validation.json.

Свежие isolated import/startup PASS; status_counter_layout22/0,
presentation_status146/0, condition_icons412/0, unit_vital_bars278/0 =858/0.
GPU75/100%, углы/сохранённые пиксели рисунка/нулевые стаки/99+/переполнение PASS.
В H1 тестовые DTO представления, не сыгранный статусный бой; независимое APPROVE.
Diff, ссылки, архив HANDOFF и33 чужих файла PASS.
Предыдущие builders/launcher/огонь/шипы/HUD gates и APPROVE не повторены.
Full/core, ручные F5/движение/zoom/DPI/performance не запускались.
U сам закрыл интерактивную игру перед проверками; новых активных runners нет.

Далее — отзыв U о компактных числах; новые пробы/срезы без запроса не начинать.
Остаток: стыки/посадка, край стрелы4 Лучницы, performance, HUD/Колода;
foundation141/2 и turn_forecast_ui26/3 не повторены.
Чужие33: scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/;
не reset/stage/commit. Сохранить core/preview/queue/RNG/save/frozen,5 классов F5,
PLAYER вправо/ENEMY влево и возврат; каталоги1–3 не мигрировать.
Один Godot runner, isolated project; без root import, служб/драйверов,
принудительного фокуса, push/sidebar tasks/расписаний.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261108-7.md), [HISTORY](HISTORY.md).
Завершение: проверки, локальный Conventional Commit, короткий HANDOFF;
прежний побайтно отдельно+HISTORY. В финале/при блокере предложить новый чат
и полный промпт: HEAD, результат, docs/artifacts, остаток, ограничения,
проверки и это же правило. Чат автоматически не создавать.
