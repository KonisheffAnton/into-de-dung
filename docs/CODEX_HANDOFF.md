# Передача — 2026-10-27: Monogram + Pixelify Sans в бою

D:\Games\into-de-dung; main; base 2b0cc6a1ff0436da97fd9d782f37b49ac6b3bf60.
По уточнению U заменена пара боевых подписей: буквы Monogram Extended,
цифры/числовые знаки Pixelify Sans Bold (700), вариант 02 прежнего сравнения.
Шейпинг включает кириллицу и Latin HP. Кегли 24/20 прежние; em букв и высота
числовой строки согласованы без изменения рисунка знаков. Runtime-сцены/скрипты,
строки, цвета и lifecycle не менялись. Прежние preview-пакеты побайтно сохранены.
[Контракт](BATTLE_PRESENTATION_REWORK.md), [ресурсы/лицензии/сборка](../assets/ui/combat_fonts/README.md),
[проверки](TESTING.md). Monogram — CC0, Pixelify — OFL; исходники в preview.

Финальный render-check: 6 PASS, 0 FAIL, 0 TIMEOUT — import/startup,
battle_presentation, presentation_contact, presentation_consequences, battle_camera_ui.
Артефакты: test_reports/demo-3285b4dcb9b34d5f850d64a0c6f25edd/.
24 проверки исходников/контуров/метрик/пересборки PASS; ревью APPROVE.
Отчёт, PNG, SHA: test_reports/combat-fonts-monogram-pixelify-20261027/.
Full/core и ручной F5 не запускались. Следующий шаг — ручная F5-приёмка
читаемости в движении/zoom/DPI. Новый этап автоматически не начинать.

Разворот атакующих 46201bd реализован; прежняя ручная F5-приёмка открыта.
Контракт: BATTLE_VISUAL_SCENE_CONTRACT.md; прежние 11 PASS/APPROVE:
test_reports/demo-f452badf203a427999337faf2ba45996/ и test_reports/attack-facing-20261026/.
Full/core тогда не запускались. Очистка арта отложена U;
отзывы о Колоде/одиночном упоре открыты.

Чужие scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/
сохранены dirty; не трогать/reset/stage/commit. Сохранять core/preview/queue/RNG/save/frozen.
Без push/sidebar tasks/расписаний. [Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261027-5.md),
[HISTORY](HISTORY.md). Завершение: проверки, локальный Conventional Commit,
короткая передача; прежнюю побайтно отдельным архивом+HISTORY. В финале/при блокере
предложить новый чат и полный самодостаточный промпт: HEAD, результат, docs/artifacts,
остаток, ограничения, проверки и это же правило. Чат автоматически не создавать.
