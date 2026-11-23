# Передача — 2026-11-23: полоски соседних персонажей

D:/Games/into-de-dung; main; capture base b591029d, перед фиксацией c51575bb.
По U сняты [воин и троглодит на соседних клетках](art/adjacent-unit-bars-20261123/README.md):
без выбора, выбран воин, наведение атаки. Камера100/75%, монтаж NEAREST2×.
Троглодит при наведении не выбран; готовый прогноз24→18.9, удар не исполнен.
Поза/геометрия постоянны. В этой паре нет сильного перекрытия HUD/моделей.
Runtime не менялся. [Проверки](art/adjacent-unit-bars-20261123/verification.json):
6 GPU кадров/0 отказов, core/RNG parity,1685 runtime hashes, пиксели PASS;
независимый review APPROVE. Переиспользована импортированная isolated-копия;
свежий import/full/core/F5/Editor/DPI/performance не запускались.
Следующий шаг — визуальная приёмка U; новую правку автоматически не начинать.

Статусы/полосы961d4b76: BATTLE_PRESENTATION_REWORK; приёмка открыта,
foundation141/2 baseline-отказы. Кости124d0d81 — выбор открыт;
последний кадр смерти для свежих тел ещё не внедрён.
Книга6566f055 реализована; ручная приёмка/школы/развитие/арт открыты.
Кнопкиb591029d —20 концептов, выбор открыт; matte-wood параллельно.
Дух/носительc51575bb — только концепт: DESIGN_DIRECTION; runtime host_defeat.
Обводкаf9e041b0 без приёмки; карты81c968ba: full не зелёный, nested save не мигрируются.
Чужие ART_DIRECTION, matte-wood, scenes/demo/main_menu.tscn,
docs/art/battlefield-reference-03-20261017/ не reset/stage/commit;
остальное параллельное сверять по status/HEAD.
Сохранить core/preview/queue/RNG/save/frozen,5 классов, PLAYER вправо/ENEMY влево,
возврат после атаки, правило брони,2:1↔4:3. Инициативы нет; команда3/лимит Q;
каталоги1–3 не мигрировать; H2–H5/прочие Q не начинать.
Один isolated runner; без root import/служб/драйверов/фокуса ОС/push/sidebar/расписаний.
D:/Games/trog-grounding-check-20261122 не удалять: cleanup отклонён.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261123-22.md), [HISTORY](HISTORY.md).
Завершение: проверки, локальный Conventional Commit своего, короткий HANDOFF;
прежний побайтно отдельно + HISTORY. В финале/при блокере предложить новый чат
и полный промпт: HEAD, результат, docs/artifacts, остаток, ограничения, проверки
и это же правило. Чат автоматически не создавать.
