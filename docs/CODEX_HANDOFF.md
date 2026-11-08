# Передача — 2026-11-09: примеры тонких HP/брони

D:/Games/into-de-dung; main; base f291819da3a80c18e16cadf2e80b2fa33e3f5ebf.
По U показано сравнение: нынешние полосы11px/кегль14; A9/10, B8/9, C7/8.
Ширина48, цвета, Jersey20, чёрные цифры/рамки прежние. Новые примеры
центрируют цифры по GPU-растру и уменьшают до внутренней высоты. C при75%
даёт растр3px и плохо читается; предложение ведущего — B8px. Выбора U нет.
Это P, НЕ внедрено: runtime сохраняет48×11/font14 и весь ряд статусов
только при hover. Компактный статусный C на картинках тоже остаётся P.
Арт, гамма и механики не менялись.
Выбор docs/ART_DIRECTION.md; пакет docs/art/vital-bar-sizes-20261109/:
comparison.png,13 GPU PNG, probe/исходники/manifest. Значения синтетические.
В макете StatusHud выше рельефа; нужна отдельная реализация слоёв/picking/
forecast/lifecycle и геометрии при выборе. Прежний C: docs/art/status-compact-c-20261109/.

Свежая isolated GPU-проба PASS: кадры100/75%, core/RNG/верхние якоря
неизменны; измерены глифы. Временный isolated-patch восстановлен побайтно.
Отчёт test_reports/vital-bar-sizes-20261109/validation.json.
Независимое APPROVE; SHA/diff/ссылки/точный архив/чужие33 PASS.
Import/startup, прежние suites/APPROVE не повторены. Full/core,
ручные F5/движение/zoom/OS-DPI/performance не запускались.
Далее — отзыв/выбор U; новые пробы/внедрение автоматически не начинать.
План docs/HUB_DESIGN_PLAN.md — P H0–H5, не реализация.
Остаток: читаемость/стыки/посадка, край стрелы4 Лучницы, performance, HUD/Колода;
presentation_foundation141/2, turn_forecast_ui26/3 не повторены.

Чужие33: scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/;
не reset/stage/commit. Сохранить core/preview/queue/RNG/save/frozen,5 классов F5,
PLAYER вправо/ENEMY влево и возврат; каталоги1–3 не мигрировать. Один Godot runner,
isolated project; без root import, служб/драйверов, фокуса, push/sidebar tasks/расписаний.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261109-2.md), [HISTORY](HISTORY.md).
Завершение: проверки, локальный Conventional Commit, короткий HANDOFF;
прежний побайтно отдельно+HISTORY. В финале/при блокере предложить новый чат
и полный промпт: HEAD, результат, docs/artifacts, остаток, ограничения,
проверки и это же правило. Чат автоматически не создавать.
