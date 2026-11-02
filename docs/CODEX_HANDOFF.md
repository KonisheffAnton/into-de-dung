# Передача — 2026-11-02: автоочистка тестовых копий

D:/Games/into-de-dung; main; basef9eea8b7da12dfa5aefa4c8e51d972c642de6765.
В isolate.py включена автоочистка:3 последние завершённые check/render копии,
закрепление через --keep-project. Удаляется только demo-<id>/project;
логи/PNG/профили/manifest/timing остаются. Правила и исключения —
[REPOSITORY_STATE](REPOSITORY_STATE.md#автоочистка-тестовых-копий), [тесты](TESTING.md).
Legacy/неизвестные/timeout/spawn-error/fresh/cache/экспериментальные копии защищены.
Блокировка очистки, защита junction/reparse; Windows checks ждут native Godot.
Общий размер сохраняемых отчётов не ограничен; расписание не создавалось.

[Аудит](../test_reports/auto-project-cleanup-20261102/): Python35 launcher+15 cache
PASS; retention13:11 PASS,2 skip (symlink недоступны),3 Windows junction PASS.
py_compile/diff-check PASS. Реальный native import/startup/HUD PASS, HUD300/0;
run demo-4f70297bfb8b4008bf16d53e8f4dc467. Независимое APPROVE.
Реальный render/full/core/F5/DPI не запускались. Во время native import другой
чат запустил runner; его не трогали, performance не заявлен.36 чужих файлов SHA PASS.

Прочие изменения игровых контрактов также чужие. Dirty:
scenes/demo/main_menu.tscn, scenes/demo/visuals/art_trial_unit.tscn,
tests/test_current_art_zoom.gd, tests/test_rogue_animations.gd;
untracked docs/art/battlefield-reference-03-20261017/, docs/art/rogue-size-sampling-20261102/,
tools/demo/_rogue_size_isolate_snapshot.py. Не reset/stage/commit; перепроверить Git.
Предыдущий игровой этап: [Разбойник02](art/rogue02-integration-20261101/README.md);
приёмка движения/zoom/DPI/арта и performance открыта. turn_forecast_ui26/3
не исправлялся; HUD/Колода без новой приёмки. Следующий шаг — запрос U.
Без новых генераций/интеграции, push/sidebar/расписаний. Core/preview/queue/RNG/save/frozen
не менять; один свой Godot runner, isolated project, без root import/служб/драйверов.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261102-2.md), [HISTORY](HISTORY.md).

Завершение: проверки, локальный Conventional Commit, короткий HANDOFF;
прежний побайтно отдельным архивом+HISTORY. В финале/при блокере предложить
новый чат и полный самодостаточный промпт: HEAD, результат, docs/artifacts,
остаток, ограничения, проверки и это же правило. Чат автоматически не создавать.
