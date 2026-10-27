# Передача — 2026-10-27: единый Pixeloid Sans Bold в бою

D:\Games\into-de-dung; main; base bb426fc10aa0ad1d20ed7160c614c56f3d7cba00.
По U цифры приведены к буквам: все боевые подписи теперь Pixeloid Sans Bold,
включая кириллицу, HP, числа и знаки. Один полный TTF, отдельный Jersey удалён
из runtime. Прежние em=2448, контуры/интервалы/метрики Pixeloid сохранены;
кегли 24/20, тексты, цвета, outline и lifecycle прежние. Сцены/board не менялись.
[Контракт](BATTLE_PRESENTATION_REWORK.md), [ресурсы/OFL/сборка](../assets/ui/combat_fonts/README.md),
[проверки](TESTING.md). Все четыре preview-пакета побайтно сохранены.

Финальный render-check: 6 PASS, 0 FAIL, 0 TIMEOUT — import/startup,
battle_presentation, presentation_contact, presentation_consequences, battle_camera_ui.
Артефакты: test_reports/demo-85fb3c562a59425aac2c04933d95ecc6/.
17 проверок шрифта/контуров/лицензии/пересборки PASS; 140 baseline SHA совпали.
Независимое ревью APPROVE; PNG/SHA: test_reports/combat-fonts-pixeloid-20261027/.
Регрессия верхнего лечения проверена отдельно; подробности — отчёт этапа.
Full/core и ручной F5 не запускались. Остаток — F5-приёмка читаемости
в движении/zoom/DPI. Новый этап автоматически не начинать.

Разворот атакующих 46201bd технически завершён, F5-приёмка открыта:
[контракт](BATTLE_VISUAL_SCENE_CONTRACT.md), test_reports/attack-facing-20261026/
и test_reports/demo-f452badf203a427999337faf2ba45996/ (прежние 11 PASS/APPROVE).
Full/core тогда не запускались. Очистка арта отложена U;
отзывы о Колоде/одиночном упоре открыты.

Чужие scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/
сохранены dirty; не трогать/reset/stage/commit. Core/preview/queue/RNG/save/frozen
сохранять; без push/sidebar tasks/расписаний.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261027-9.md), [HISTORY](HISTORY.md).
Завершение: проверки, локальный Conventional Commit, короткая передача;
прежнюю побайтно отдельным архивом+HISTORY. В финале/при блокере предложить новый
чат и полный самодостаточный промпт: HEAD, результат, docs/artifacts, остаток,
ограничения, проверки и это же правило. Чат автоматически не создавать.
