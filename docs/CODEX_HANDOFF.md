# Передача — 2026-11-08: компактный HUD, ПКМ и предложения значков

D:/Games/into-de-dung; main; basead8cf7c349705231d74fa488ac856b0348da6adc.
UI commitd0832d083556ca89bf2c157387ac74694059b550: пустой слот Status44px убран
из раскладки; сообщения поверх поля слева от открытой карточки. Статусы не двигают
Board/камеру/руку. Карточка только коротким ПКМ; drag камеры/отмена пустым ПКМ
сохранены. ЛКМ выбирает союзника либо выполняет прежний click_attack по врагу.
Владельцы BATTLE_HUD_SCENES_V1/TACTICAL_BATTLE; ARCHITECTURE/TESTING обновлены.
Кадры docs/art/compact-hud-rmb-20261108/;
отчёт test_reports/compact-hud-rmb-20261108/.

По U составлен инвентарь и72 SVG-эскиза:24 семейства×3, включая труп, разные
кислоты/ловушки, реакции/ожидание. docs/art/status-icon-proposals-20261108/:
index.html, characters.png, tiles.png, inventory.md, build.py, icons/.
Это P для выбора символа, не финальный пиксельный арт и не runtime-интеграция.
ART_DIRECTION содержит ссылку; текущий базовый значок16px,32/64 — увеличение.

Свежие isolated import/startup PASS; status146/0, card119/0, camera112/0,
authoring370/0, input163/0, execution61/0, click_attack152/0: всего1123/0.
После ревью исправлено перекрытие сообщения карточкой и повторены затронутые
наборы; независимое APPROVE. Full/core и ручные F5/движение/zoom/DPI/performance
не запускались; прежние foundation141/2, turn_forecast_ui26/3 не повторены.
Отзыв U и проверка символов в настоящем бою ещё нужны.

Далее — выбор U вариантов значков и отзыв о HUD; без запроса не внедрять и
не запускать новые серии. Остаток: стыки/посадка/читаемость, край стрелы4 Лучницы,
performance, HUD/Колода. Огонь29 принят: docs/art/fire29-natural-integration-20261107/.
Чужие33: scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/;
не reset/stage/commit. Сохранить core/preview/queue/RNG/save/frozen,5 классов F5,
PLAYER вправо/ENEMY влево и возврат; каталоги1–3 не мигрировать.
Один Godot runner, isolated project; без root import, служб/драйверов,
принудительного фокуса, push/sidebar tasks/расписаний.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261108-2.md), [HISTORY](HISTORY.md).
Завершение: проверки, локальный Conventional Commit, короткий HANDOFF;
прежний побайтно отдельно+HISTORY. В финале/при блокере предложить новый чат
и полный промпт: HEAD, результат, docs/artifacts, остаток, ограничения,
проверки и это же правило. Чат автоматически не создавать.
