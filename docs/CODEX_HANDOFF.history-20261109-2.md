# Передача — 2026-11-09: пример компактного HUD C

D:/Games/into-de-dung; main; base b642431dcb7ea2a6a3e513d2a45cc1275b82ca21.
По U показан P-макет C: нынешние горизонтальные полосы, до3 значков без чисел
и +N снизу; hover раскрывает5 со стаками/сроками на №4. Подробности — правая
карточка. Не принят и НЕ внедрён; текущий runtime по-прежнему скрывает весь
ряд без hover. Нового арта/изменения гаммы/механик нет.
Выбор: docs/ART_DIRECTION.md. Пакет docs/art/status-compact-c-20261109/:
comparison.png,8 GPU PNG, probe/исходники/manifest. Значения и1/3/5 эффектов
синтетические. Только в макете StatusHud выше тайлов/фигур; перед внедрением
нужны слои, hover/picking, overflow/приоритеты и коллизии соседних HUD.

Свежая isolated GPU-проба PASS: core/RNG и якоря100/75% неизменны;
карточка не сдвигает поле/камеру/руку и не пересекает карты при1440×900.
Временный isolated-patch восстановлен побайтно, production не менялся.
Отчёт test_reports/status-compact-c-20261109/validation.json.
Независимое APPROVE; diff/ссылки/точный архив/33 чужих файла PASS.
Import/startup, прежние runtime/hub/огонь/шипы/launcher suites и их APPROVE
не повторялись. Full/core, ручные F5/движение/zoom/OS-DPI/performance не запускались.
План docs/HUB_DESIGN_PLAN.md остаётся предложением H0–H5.
Далее — отзыв U о C; не начинать новые пробы/внедрение/хаб автоматически.
Остаток: читаемость/стыки/посадка, край стрелы4 Лучницы, performance, HUD/Колода;
presentation_foundation141/2, turn_forecast_ui26/3 не повторены.

Чужие33: scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/;
не reset/stage/commit. Сохранить core/preview/queue/RNG/save/frozen,5 классов F5,
PLAYER вправо/ENEMY влево и возврат; каталоги1–3 не мигрировать. Один Godot runner,
isolated project; без root import, служб/драйверов, фокуса, push/sidebar tasks/расписаний.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261109.md), [HISTORY](HISTORY.md).
Завершение: проверки, локальный Conventional Commit, короткий HANDOFF;
прежний побайтно отдельно+HISTORY. В финале/при блокере предложить новый чат
и полный промпт: HEAD, результат, docs/artifacts, остаток, ограничения,
проверки и это же правило. Чат автоматически не создавать.
