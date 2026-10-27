# Передача — 2026-10-27: Tiny5 + Jersey 10 в бою

D:\Games\into-de-dung; main; base 8da9e9c4e3d03c5111564c659b558c6f95832d9c.
По U внедрён вариант 03 прежнего сравнения пар: Tiny5 Regular для букв
(включая HP), Jersey 10 Regular для цифр/числовых знаков. Общий result_number
использует FontVariation; кегль 24, последствия 20. Тексты, цвета и lifecycle
прежние. Новых боевых событий/статусов нет; остальные элементы UI не менялись.
[Контракт](BATTLE_PRESENTATION_REWORK.md), [ресурсы/OFL/сборка](../assets/ui/combat_fonts/README.md),
[проверки](TESTING.md). Три прежних preview-пакета сохранены побайтно.

Все 7 выбранных render-наборов PASS на окончательном runtime 24/20:
6 в test_reports/demo-7c92aec1752b48768d80f6f0965ed48e/;
presentation_consequences окончательно в test_reports/demo-ab13b938e940425f9ccadd4a7cad64e3/
(вместе с import/startup: 3 PASS). Ранний неверный тест рамок Label заменён
пиксельным; кегль 26 отклонён из-за обрезки у края. Полный отчёт/PNG/SHA:
test_reports/combat-fonts-integration-20261027/. Шейпинг, исходники и пересборка PASS.
Независимое ревью APPROVE. Full/core и ручной F5 не запускались.
Следующий шаг — ручная F5-приёмка читаемости в движении, zoom/DPI.
Новый этап автоматически не начинать.

Разворот атакующих 46201bd реализован; прежняя ручная F5-приёмка открыта.
Контракт: BATTLE_VISUAL_SCENE_CONTRACT.md; прежние 11 PASS/APPROVE:
test_reports/demo-f452badf203a427999337faf2ba45996/ и test_reports/attack-facing-20261026/.
Full/core тогда не запускались. Очистка арта отложена U;
отзывы о Колоде/одиночном упоре остаются открытыми.

Чужие scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/
сохранены dirty; не трогать/reset/stage/commit. Сохранять core/preview/queue/RNG/save/frozen.
Без push/sidebar tasks/расписаний. [Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261027-4.md),
[HISTORY](HISTORY.md). Завершение: проверки, локальный Conventional Commit,
короткая передача; прежнюю побайтно отдельным архивом+HISTORY. В финале/при блокере
предложить новый чат и полный самодостаточный промпт: HEAD, результат, docs/artifacts,
остаток, ограничения, проверки и это же правило. Чат автоматически не создавать.
