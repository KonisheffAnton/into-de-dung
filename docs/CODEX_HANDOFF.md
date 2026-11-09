# Передача — 2026-11-09: выбрана навигация хаба

D:/Games/into-de-dung; main; base4803b58f1878afde941592682dfd1cb19f428988.
U выбрал вкладки и диораму «Поход» сначала, кликабельные здания позже,
как второй вход в те же разделы. Решение: docs/DESIGN_DIRECTION.md §6.1;
приоритет H0→H1→H4 и вопросы: docs/HUB_DESIGN_PLAN.md §3/§7/§8.
Точная композиция, названия, школы и материалы остаются P/Q.
Изменены только документы; хаб, код, арт и гамма не менялись.
Следующий шаг — обсуждение композиции первого экрана; реализация не начата.
H2/H3/H5 и кликабельные здания автоматически не запускать.
Контракты: docs/HUB_SCENES_V1.md, docs/HERO_HUB_H1.md.
Аудит: docs/art/hub-ux-audit-20261108/; прежние62/0 и APPROVE не повторены.

Сохранён открытый выбор предыдущего этапа: полосы HP/брони A9/10,
B8/9, C7/8 против нынешних11px/font14. Предложение — B; выбора U нет.
docs/ART_DIRECTION.md; docs/art/vital-bar-sizes-20261109/ (13 GPU PNG).
Компактный статусный C: docs/art/status-compact-c-20261109/ — тоже P.
По предыдущей передаче runtime48×11/font14, весь ряд статусов только hover;
внедрение компактного C требует отдельной работы со слоями/picking/forecast/
lifecycle. Новые пробы и внедрение автоматически не начинать.
Предыдущий отчёт: test_reports/vital-bar-sizes-20261109/validation.json.

Свежие проверки документации: diff/ссылки/объём/точный архив/чужие33 PASS;
test_reports/hub-navigation-choice-20261109/validation.json.
Godot/import/startup, прежние suites/APPROVE не повторены. Full/core,
ручные F5/движение/zoom/OS-DPI/usability/performance не запускались.
Остаток: читаемость/стыки/посадка, край стрелы4 Лучницы, performance, HUD/Колода;
presentation_foundation141/2, turn_forecast_ui26/3 не повторены.

Чужие33: scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/;
не reset/stage/commit. Core/preview/queue/RNG/save/frozen,5 классов F5,
PLAYER вправо/ENEMY влево и возврат сохранить; каталоги1–3 не мигрировать.
Один Godot runner, isolated project; без root import, служб/драйверов,
принудительного фокуса, push/sidebar tasks/расписаний.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261109-3.md), [HISTORY](HISTORY.md).
Завершение: проверки, локальный Conventional Commit только своих изменений,
короткий HANDOFF; прежний побайтно отдельно+HISTORY. В финале/при блокере
предложить новый чат и полный промпт: HEAD, результат, docs/artifacts, остаток,
ограничения, проверки и это же правило. Чат автоматически не создавать.
