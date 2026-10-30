# Передача — 2026-10-30: Воин и выбранные модели

D:\Games\into-de-dung; main; base f6bbd0b5f4d8c76d3d6dd86999aa2548ad219fa5.
По U: Щитоносец модель17, новый Воин модель11. Последняя поправка U:
обводка отключена у обеих фигур. Компактный масштаб, без изометрии персонажа.
[Правила](WARRIOR_V1.md), [ассеты](../assets/art_presets/trials/warrior_classes_v1/README.md).
Новый catalog3 добавляет fighter в резерв/найм; legacy warrior и catalog1/2
сохранены. Существующие профили не мигрируют. В F5 новый временный профиль.

Пассивка +20% получаемого исцеления/брони во всех действующих источниках;
Рассекающий удар: соседняя цель, обычный урон+1кровотечение, main1/CD1;
Пинок: база2P, балансP/4, bonus1 без отката. Пул второй активки пока singleton.
Уточнения по cap/ремонту/криту/откату принадлежат контракту, не этой передаче.
Capability/cooldown переносятся через perks codec и guards; preview/live/worker
используют один путь. Статичные модели не подменяются старыми idle/buff/death.

Проверки: import/startup; core PASS; адресные hub/save/expedition/recovery,
forecast/workers/UI PASS. Начальное падение старого shieldbearer_ui ожидало
прежний рисунок; контрактный тест обновлён и прошёл. Финальные тесты:
warrior_class67/0, warrior_recovery55/0, GPU warrior_visuals40/0,
shieldbearer_ui24/0. Независимое APPROVE; ведущий проверил критические границы.
[Свидетельства](../test_reports/warrior-class-20261030/): gate/final-gate,
журналы проверок, render models-on-tiles.png, validation/completion.json.
Полный --full не запускался. Ручные F5/движение/zoom/DPI/баланс открыты.
Авторские анимации новых моделей не создавались.

Чужие dirty scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/
сохранены; не reset/stage/commit. Без push/sidebar tasks/расписаний.
Прежние отзывы о Колоде, одиночном упоре и общей плавности остаются открыты.
Следующий шаг — ручная приёмка нового класса/моделей; новый срез не начинать.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261030.md), [HISTORY](HISTORY.md).
Завершение: проверки, локальный Conventional Commit, короткий HANDOFF;
прежний побайтно отдельным архивом+HISTORY. В финале/при блокере предложить
новый чат и полный промпт: HEAD, результат, docs/artifacts, остаток,
ограничения, проверки и это же правило. Чат автоматически не создавать.
