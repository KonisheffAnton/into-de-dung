# Передача — 2026-10-27: Monogram + Jersey 10 в бою

D:\Games\into-de-dung; main; base a4beebee6315c902616515a1f5665a20ea8d42dc.
По U возвращён Jersey 10 Regular для цифр/числовых знаков; буквы Monogram
сохранены побайтно. Кегли 24/20 прежние. У Jersey исходные рисунок, em и интервалы;
нижнее поле строки уменьшено с 375 до 280 units, чтобы верхнее лечение не обрезалось.
Runtime-сцены/скрипты, тексты, цвета и lifecycle не менялись.
[Контракт](BATTLE_PRESENTATION_REWORK.md), [ресурсы/CC0/OFL/сборка](../assets/ui/combat_fonts/README.md),
[проверки](TESTING.md). Прежние preview-пакеты побайтно сохранены.

Финальный render-check: 6 PASS, 0 FAIL, 0 TIMEOUT — import/startup,
battle_presentation, presentation_contact, presentation_consequences, battle_camera_ui.
Артефакты: test_reports/demo-c1e0844894eb43a792c99283c6aace71/.
24 проверки ресурсов/контуров/пересборки PASS; независимое ревью APPROVE.
Отчёт, PNG, SHA: test_reports/combat-fonts-monogram-jersey-20261027/.
Full/core и ручной F5 не запускались. Следующий шаг — ручная F5-приёмка
читаемости в движении/zoom/DPI. Новый этап автоматически не начинать.

Разворот атакующих 46201bd реализован; прежняя ручная F5-приёмка открыта.
Контракт: BATTLE_VISUAL_SCENE_CONTRACT.md; прежние 11 PASS/APPROVE:
test_reports/demo-f452badf203a427999337faf2ba45996/ и test_reports/attack-facing-20261026/.
Full/core тогда не запускались. Очистка арта отложена U;
отзывы о Колоде/одиночном упоре открыты.

Чужие scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/
сохранены dirty; не трогать/reset/stage/commit. Сохранять core/preview/queue/RNG/save/frozen.
Без push/sidebar tasks/расписаний. [Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261027-6.md),
[HISTORY](HISTORY.md). Завершение: проверки, локальный Conventional Commit,
короткая передача; прежнюю побайтно отдельным архивом+HISTORY. В финале/при блокере
предложить новый чат и полный самодостаточный промпт: HEAD, результат, docs/artifacts,
остаток, ограничения, проверки и это же правило. Чат автоматически не создавать.
