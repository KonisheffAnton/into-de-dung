# Передача — 2026-10-27: поиск цифр к буквам Pixeloid

D:\Games\into-de-dung; main; base faa13e70e7d4073f6aa315ee3ef448b534bf881e.
По U подготовлено только превью: буквы Pixeloid Sans Bold, цифры Jersey 10,
новые Jersey 15/20/25 и Oxanium Bold, плюс Pixeloid для сравнения.
[Лист/6 кадров/TTF/OFL/источники/метод](art/pixeloid-numerals-preview-20261027/README.md),
[владелец](ART_DIRECTION.md). Выбор и внедрение открыты; игру не меняли.
Browser-check PASS: 6 шрифтов/cmap, 42 подписи, 24 строки, 90 узлов без fallback;
фон 6 PNG сохранён вне надписей. Отчёт: test_reports/pixeloid-numerals-preview-20261027/.
Независимое ревью APPROVE; 145 защищённых SHA совпали.
Godot/full/core/F5 в этом этапе не запускались; это оптический макет.

Runtime остаётся единым Pixeloid Sans Bold из faa13e7:
[контракт](BATTLE_PRESENTATION_REWORK.md), [ресурсы/сборка](../assets/ui/combat_fonts/README.md).
Прежние 6 PASS/APPROVE: test_reports/demo-85fb3c562a59425aac2c04933d95ecc6/
и test_reports/combat-fonts-pixeloid-20261027/. F5-приёмка движения/zoom/DPI
открыта. Пользователь предпочёл прежние цифры; новый вариант пока не выбран.

Разворот атакующих 46201bd: [контракт](BATTLE_VISUAL_SCENE_CONTRACT.md),
test_reports/attack-facing-20261026/ и test_reports/demo-f452badf203a427999337faf2ba45996/
(прежние 11 PASS/APPROVE). F5 открыт; full/core не запускались.
Очистка арта отложена U; отзывы о Колоде/одиночном упоре открыты.

Чужие scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/
сохранены dirty; не трогать/reset/stage/commit. Core/preview/queue/RNG/save/frozen
сохранять; без push/sidebar tasks/расписаний. Новый этап автоматически не начинать.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261027-10.md), [HISTORY](HISTORY.md).
Завершение: проверки, локальный Conventional Commit, короткая передача;
прежнюю побайтно отдельным архивом+HISTORY. В финале/при блокере предложить новый
чат и полный самодостаточный промпт: HEAD, результат, docs/artifacts, остаток,
ограничения, проверки и это же правило. Чат автоматически не создавать.
