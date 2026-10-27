# Передача — 2026-10-27: Pixeloid Sans Bold + Jersey 10 в бою

D:\Games\into-de-dung; main; base 502e2e64e05b50e443991471ad719cc52b7a1a1f.
По U внедрены буквы Pixeloid Sans Bold (вариант 03); цифры Jersey сохранены
побайтно. Pixeloid em=2448 вместо1836: заглавные прежней высоты14 px при кегле24,
сетка2 px; контуры/интервалы/метрики строки исходные. Кегли24/20, тексты, цвета,
outline и lifecycle прежние; runtime-сцены/скрипты не менялись.
[Контракт](BATTLE_PRESENTATION_REWORK.md), [ресурсы/OFL/сборка](../assets/ui/combat_fonts/README.md),
[выбранное превью](art/jersey-cyrillic-preview-20261027/README.md), [проверки](TESTING.md).
Monogram удалён только из runtime; все четыре preview-пакета побайтно сохранены.

Финальный render-check: 6 PASS, 0 FAIL, 0 TIMEOUT — import/startup,
battle_presentation, presentation_contact, presentation_consequences, battle_camera_ui.
Артефакты: test_reports/demo-3bc5380f544b4662b0b8682843dcb242/.
17 проверок шрифтов/контуров/лицензий/пересборки PASS; 142 baseline SHA совпали.
Независимое ревью APPROVE; PNG/SHA: test_reports/combat-fonts-pixeloid-jersey-20261027/.
Full/core и ручной F5 не запускались. Следующий шаг — ручная F5-приёмка
читаемости в движении/zoom/DPI; новый этап автоматически не начинать.

Разворот атакующих 46201bd технически завершён, F5-приёмка открыта:
[контракт](BATTLE_VISUAL_SCENE_CONTRACT.md), test_reports/attack-facing-20261026/
и test_reports/demo-f452badf203a427999337faf2ba45996/ (прежние11 PASS/APPROVE).
Full/core тогда не запускались. Очистка арта отложена U;
отзывы о Колоде/одиночном упоре открыты.

Чужие scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/
сохранены dirty; не трогать/reset/stage/commit. Core/preview/queue/RNG/save/frozen
сохранять; без push/sidebar tasks/расписаний.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261027-8.md), [HISTORY](HISTORY.md).
Завершение: проверки, локальный Conventional Commit, короткая передача;
прежнюю побайтно отдельным архивом+HISTORY. В финале/при блокере предложить новый
чат и полный самодостаточный промпт: HEAD, результат, docs/artifacts, остаток,
ограничения, проверки и это же правило. Чат автоматически не создавать.
