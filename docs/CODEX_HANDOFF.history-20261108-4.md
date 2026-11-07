# Передача — 2026-11-08: значки в стиле игры

D:/Games/into-de-dung; main; base47605034978ec9140a63423bc5d7f6ed8a58cd67.
U попросил переделать прежние SVG-схемы в стиле игры. Получены3 растровых листа
PixelLab generate-image-v2, по24 мотива:24 семейства×3 варианта, всего72.
Референс — approved character_skins_v1/grey_bastion/still.png; контур,
пиксельные плоскости, объём и материалы. Статусы/реакции/клетки, включая труп.
Это P для выбора, без runtime-интеграции. Владелец выбора docs/ART_DIRECTION.md.
Пакет docs/art/status-icon-style-20261108/: index.html, preview01–03.png,
raw/sheet01–03.png, requests/, README.md, build_gallery.py.
Отчёт test_reports/status-icon-style-20261108/.

Свежие:3 jobs completed; PNG384×512 RGBA/alpha и побайтное равенство API PASS;
наблюдены72 мотива; HTML/локальные ссылки/повторная сборка PASS; листы просмотрены.
Фактический usage75 generations. Независимое ревью APPROVE как концепты.
ВАЖНО: сетка смещена; все листы касаются нижнего края,03 также верхнего.
Возможна обрезка крайних мотивов. Не нарезать автоматически по128×64;
после выбора нужны отдельные спрайты с прозрачным запасом и проверкой16px/75%.
Godot/full/core/ручные F5/движение/zoom/DPI/performance здесь не запускались.
Прежние1123/0 относятся к UI commitd0832d08 и не повторены: компактный HUD,
карточка только коротким ПКМ, ЛКМ — выбор/обычная атака, drag камеры сохранён.
UI — BATTLE_HUD_SCENES_V1/TACTICAL_BATTLE. Старые SVG — схемы смыслов.

Далее — отзыв U о стиле и выбор A/B/C; без запроса не внедрять и не начинать
новые серии. Остаток: стыки/посадка/читаемость, край стрелы4 Лучницы,
performance, HUD/Колода; прежние foundation141/2 и turn_forecast_ui26/3 не повторены.
Огонь29 принят: docs/art/fire29-natural-integration-20261107/.
Чужие33: scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/;
не reset/stage/commit. Сохранить core/preview/queue/RNG/save/frozen,5 классов F5,
PLAYER вправо/ENEMY влево и возврат; каталоги1–3 не мигрировать.
Один Godot runner, isolated project; без root import, служб/драйверов,
принудительного фокуса, push/sidebar tasks/расписаний.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261108-3.md), [HISTORY](HISTORY.md).
Завершение: проверки, локальный Conventional Commit, короткий HANDOFF;
прежний побайтно отдельно+HISTORY. В финале/при блокере предложить новый чат
и полный промпт: HEAD, результат, docs/artifacts, остаток, ограничения,
проверки и это же правило. Чат автоматически не создавать.
