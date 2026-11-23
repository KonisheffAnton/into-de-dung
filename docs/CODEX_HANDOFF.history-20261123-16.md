# Передача — 2026-11-23: кости на поле; UI в работе

D:/Games/into-de-dung; main; база8b404be8fb95e038cdccbf541199d0c0a13d6d66.
[PL29/PL34 и все20 на настоящем поле](art/bones-field-comparison-20261123/README.md):
BattleDemoBoard8×8, камера100%, воин red_bastion. PL64² scale1,
G уменьшены NEAREST для примерки. Только Sprite2D preview, выбор открыт.
Isolated import/GPU capture PASS; state/RNG/counters/revision неизменны;
10 PL совпали с исходным RGB по всем opaque-пикселям. Review APPROVE.
Core/full/lifecycle останков/F5/Editor/DPI/performance не проверены.

Следующая авторизованная UI-задача в работе: иконки статусов −10%; гладкие
цифры ТОЛЬКО статусов, НЕ HP/брони/баланса. Обычные полоски за моделями;
верхний HUD только выбранному персонажу, не цели атаки/hover/inspection.
Кодер: battle_demo_iso_visual.gd и два адресных GPU-теста. Ведущий:
интеграция/контракты/runner/review/commit. До проверок UI не объявлять готовым.

Свежий труп = последний death-кадр; PL-F3 отменён, runtime общий маркер,
fallback без death Q. ENVIRONMENT_D5; обычные свежесть/каннибализм/С2 прежние.
Защищённый труп носителя — концепт8b404be8 (DESIGN_DIRECTION): без разложения,
только воскресить/поднять, не съесть/уничтожить. Магия на трупе/поднятом;
поднял враг → контроль игрока до конца боя. Runtime ещё host_defeat/обычные тела.
Q у владельца; реализацию концепта автоматически не начинать.
Маг/прокачка/огонёк — концептfca68bb8; обводкаf9e041b0 без приёмки;
карты81c968ba — прежний full не зелёный, старые nested save не мигрируются.

Чужие scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/
не reset/stage/commit. Сверять status/HEAD и параллельные правки.
Сохранить core/preview/queue/RNG/save/frozen,5 классов F5, PLAYER вправо/ENEMY влево,
возврат после атаки, правило брони, пробу2:1↔4:3. Инициативы нет; команда3,
будущий лимит Q; каталоги1–3 не мигрировать. H2–H5/прочие Q не начинать.
Один isolated runner; без root import/служб/драйверов/фокуса ОС/push/sidebar/расписаний.
D:/Games/trog-grounding-check-20261122 не удалять: cleanup ранее отклонён.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261123-15.md), [HISTORY](HISTORY.md).
Завершение: проверки, локальный Conventional Commit только своего, короткий HANDOFF;
прежний побайтно отдельно + HISTORY. В финале/при блокере предложить новый чат
и полный промпт: HEAD, результат, docs/artifacts, остаток, ограничения, проверки
и это же правило. Чат автоматически не создавать.
