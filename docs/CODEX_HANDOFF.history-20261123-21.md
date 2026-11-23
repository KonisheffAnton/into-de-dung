# Передача — 2026-11-23: десять стилей кнопок хаба

D:/Games/into-de-dung; main; старт9dd5f076, перед фиксацией961d4b76.
По U сделаны [10 Imagegen + 10 PixelLab экранов](art/hub-buttons-ten-styles-20261123/README.md):
[галерея](art/hub-buttons-ten-styles-20261123/index.html), PNG, промпты, SHA/usage.
Imagegen1672×941, PixelLab688×384/250generations. Только концепты кнопок;
runtime/темы/ассеты не менялись. Выбор U открыт. P ведущего04/07/10,
reviewer10/01/09; у PixelLab полезны04/07. Отклонения PL10:4 карточки,
прочих — лишние герои/кириллица/слабый материал; не переносить ошибки в игру.
[Проверки](../test_reports/hub-buttons-design-20261123/validation.json):
20PNG/размеры/SHA/ссылки/JS syntax PASS; Imagegen visual review APPROVE.
Browser file:// отклонён политикой; UI галереи в браузере не проверен.
Godot/import/full/core/F5/Editor/DPI/performance не запускались.
Следующий шаг — выбор U1–3 направлений, затем уточнение кнопок/состояний.
Не внедрять и не генерировать новый набор автоматически.

Статусы/полосы961d4b76 — BATTLE_PRESENTATION_REWORK; ручная приёмка открыта,
foundation141/2 с теми же baseline-отказами. Кости124d0d81 — выбор открыт;
свежие тела последним кадром смерти ещё не внедрены. Книга6566f055 реализована:
HUB_SCENES_V1; ручная приёмка/школы/развитие/финальный арт открыты.
Дух/носитель2ea6374f — концепт, runtime host_defeat; Q у DESIGN_DIRECTION.
Обводкаf9e041b0 без приёмки; карты81c968ba: full не зелёный, nested save не мигрируются.
Чужие scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/
не reset/stage/commit; остальные параллельные изменения сверять по status/HEAD.
Сохранить core/preview/queue/RNG/save/frozen,5 классов, PLAYER вправо/ENEMY влево,
возврат после атаки, правило брони,2:1↔4:3. Инициативы нет; команда3/лимит Q;
каталоги1–3 не мигрировать; H2–H5/прочие Q не начинать.
Один isolated runner; без root import/служб/драйверов/фокуса ОС/push/sidebar/расписаний.
D:/Games/trog-grounding-check-20261122 не удалять: cleanup отклонён.
[Прежняя передача побайтно](CODEX_HANDOFF.history-20261123-20.md), [HISTORY](HISTORY.md).
Завершение: проверки, локальный Conventional Commit своего, короткий HANDOFF;
прежнюю побайтно отдельно + HISTORY. В финале/при блокере предложить новый чат
и полный промпт: HEAD, результат, docs/artifacts, остаток, ограничения, проверки
и это же правило. Чат автоматически не создавать.
