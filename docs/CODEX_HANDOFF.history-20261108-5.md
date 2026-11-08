# Передача — 2026-11-08: значки A в бою

D:/Games/into-de-dung; main; base87a981caf12f11224795184f4531a1a6bcff9cee.
U выбрал A для всех24 значков; подготовлены48 PNG16/32 и подключены к показу.
20 мотивов — исходные пиксели; края4 восстановлены PixelLab (24 generations).
Ряд у ног/компактный осмотр фигуры16px; карточка и осмотр клетки32px.
Труп, кислота, ловушки и прочие клетки читаются из опубликованного Board.
Область42px постоянна, поле/рука не сдвигаются; карточка остаётся только по ПКМ.
Гамма, core и утверждённые сцены опасностей не менялись.
Выбор: docs/ART_DIRECTION.md; поведение: docs/BATTLE_HUD_SCENES_V1.md,
нижний ряд: docs/BATTLE_PRESENTATION_REWORK.md.
Пакет/кадры: docs/art/status-icons-a-20261108/.
Ресурсы: assets/art_presets/approved/status_icons_a_v1/.
Отчёт: test_reports/status-icons-a-20261108/validation.json.

Свежие: builder24/48 и48 import sidecar PASS; isolated import/startup PASS.
condition_icons268/0, presentation_status146/0, camera112/0, hud_input163/0,
character_card119/0, execution_ui61/0 =869/0. GPU:48 текстур равны PNG по RGBA;
кадры H1 при75/100%, native16/32. Статусы в кадрах — тестовые DTO, не сыгранный бой.
Независимое ревью APPROVE; замечания о ловушках исправлены. Старое сравнение текста адаптировано к inline image.
PASS diff,1305 ссылок, архив HANDOFF и33 чужих файла; launcher37/0.
Full/core, ручные F5/движение/zoom/DPI/performance не запускались.
Прежние проверки огня/шипов/HUD и APPROVE не считать повторёнными.

Далее — отзыв U о читаемости выбранного A в текущем бою; новые пробы/срезы
без запроса не начинать. Остаток: стыки/посадка, край стрелы4 Лучницы,
performance, HUD/Колода; foundation141/2 и turn_forecast_ui26/3 не повторены.
Чужие33: scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/;
не reset/stage/commit. Сохранить core/preview/queue/RNG/save/frozen,5 классов F5,
PLAYER вправо/ENEMY влево и возврат; каталоги1–3 не мигрировать.
Один Godot runner, isolated project; без root import, служб/драйверов,
принудительного фокуса, push/sidebar tasks/расписаний.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261108-4.md), [HISTORY](HISTORY.md).
Завершение: проверки, локальный Conventional Commit, короткий HANDOFF;
прежний побайтно отдельно+HISTORY. В финале/при блокере предложить новый чат
и полный промпт: HEAD, результат, docs/artifacts, остаток, ограничения,
проверки и это же правило. Чат автоматически не создавать.
