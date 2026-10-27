# Передача — 2026-10-27: Jersey 20 + Pixeloid Sans Bold

D:\Games\into-de-dung; main; base 792414defad185725faaa85850237bec55705f5a.
По U внедрён вариант03: цифры/числовые знаки Jersey 20, буквы Pixeloid Sans Bold.
Общий Label выбирает числовое подмножество + fallback прежнего Pixeloid;
Pixeloid TTF/OFL побайтно сохранены. Кегли24/20, тексты, цвета, outline/lifecycle,
сцены и боевые механики прежние. [Контракт](BATTLE_PRESENTATION_REWORK.md),
[ресурсы/OFL/сборка](../assets/ui/combat_fonts/README.md), [проверки](TESTING.md).
[Исходное превью](art/pixeloid-numerals-preview-20261027/README.md) и четыре более
ранних пакета сохранены; runtime больше не использует цифры Pixeloid.

Финальный render-check: 6 PASS, 0 FAIL, 0 TIMEOUT — import/startup,
battle_presentation, presentation_contact, presentation_consequences, battle_camera_ui.
Артефакты: test_reports/demo-9345680846994219b6dc1ad76dc43740/.
17 проверок шрифта/контуров/лицензии/пересборки PASS; 174 защищённых SHA совпали.
Отчёт/PNG/SHA: test_reports/combat-fonts-jersey20-20261027/.
Независимое ревью APPROVE; смешанные строки и верхнее лечение проверены на PNG.
Full/core/F5 не запускались. Остаток — ручная F5-приёмка движения/zoom/DPI.

Разворот атакующих 46201bd: [контракт](BATTLE_VISUAL_SCENE_CONTRACT.md),
test_reports/attack-facing-20261026/ и test_reports/demo-f452badf203a427999337faf2ba45996/
(прежние 11 PASS/APPROVE). F5 открыт; full/core не запускались.
Очистка арта отложена U; отзывы о Колоде/одиночном упоре открыты.

Чужие scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/
сохранены dirty; не трогать/reset/stage/commit. Core/preview/queue/RNG/save/frozen
сохранять; без push/sidebar tasks/расписаний. Новый этап автоматически не начинать.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261027-11.md), [HISTORY](HISTORY.md).
Завершение: проверки, локальный Conventional Commit, короткая передача;
прежнюю побайтно отдельным архивом+HISTORY. В финале/при блокере предложить новый
чат и полный самодостаточный промпт: HEAD, результат, docs/artifacts, остаток,
ограничения, проверки и это же правило. Чат автоматически не создавать.
