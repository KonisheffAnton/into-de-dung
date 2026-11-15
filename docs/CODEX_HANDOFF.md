# Передача — 2026-11-15: убраны буквы на персонажах

D:/Games/into-de-dung; main; база d27f0c8ceb5234664906f313bc74ebf0f0834ff3.
U попросил убрать буквенные обозначения на фигурах.
Из BattleDemoIsoVisual._draw_unit удалена первая буква имени, включая
процедурные фигуры и временные силуэты. Имена карточек/полосы/статусы прежние.
Контракт BATTLE_VISUAL_SCENE_CONTRACT; [отчёт/GPU/проверки](art/unit-letter-removal-20261115/README.md).
Import/startup и GPU unit_visual_contract/class_showcase_ui PASS99/0,
isolated92777eb2; review APPROVE. Итог в validation.json. Новых тестов нет.

Хоб-гоблин внедрён d27f0c8c: [контракт](SICK_HOBGOBLIN_V1.md),
[отчёт](art/sick-hobgoblin-integration-20261115/README.md).
Каталог4: пять классов+один враг, HP24/ход3/равновесие4/урон5/броня0.
Idle3/редкий idle2/рык1 косметический/смерть1 закрытые глаза; рост≈⅔ Воина.
Прежний прогон3733/0+37 launcher+сборки+APPROVE не является новым прогоном.
Следующий шаг — отзыв U о посадке/швах/частоте рыка/балансе.
Новые кадры атаки не делать без U. Full/core, ручной F5/Editor/DPI/performance
не выполнены этим этапом;60FPS не заявлены. Полосы/кузнец U, стрела4,
performance/HUD/Колода, presentation141/2 и forecast26/3 остаются открытыми.
Шаг Выносливости cb88eb28 и кузнец e7abaa9d описаны в прежнем HANDOFF/отчётах.
Варианты атак Воина — art/warrior-attack-single-five-20261114/, выбор/шов открыты.

Dirty main_menu.tscn и art/battlefield-reference-03-20261017 — чужие;
33 файла сверены по SHA, не трогать. Без push. H2–H5 не начинать.
Сохранить core/preview/queue/RNG/save/frozen,5классов F5, PLAYER вправо/ENEMY
влево, возврат после атаки. Инициативы нет, команда3, будущий лимит Q.
Каталоги1–3 не мигрировать. Один isolated runner, без root import,
служб/драйверов/фокуса ОС/sidebar/расписаний.
[Прежняя передача побайтно](CODEX_HANDOFF.history-20261115-21.md), [HISTORY](HISTORY.md).
Завершение: проверки, локальный Conventional Commit, короткий HANDOFF;
прежний побайтно отдельно+HISTORY. В финале/при блокере предложить новый чат
и полный промпт: HEAD,результат,docs/artifacts,остаток,ограничения,проверки
и это же правило. Чат автоматически не создавать.
