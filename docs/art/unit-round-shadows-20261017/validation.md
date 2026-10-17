# Проверки — 2026-10-17

Base: main `1be9bd14405d7efa7a8f5d875183f872ee9a68a4`.
Godot4.7.2, OpenGL Compatibility, NVIDIA RTX3050 Laptop; один backend.

Свежий изолированный прогон:
`python tools/demo/isolate.py --godot <Godot4.7.2-console> --render-check --only current_art_zoom presentation_contact --screen 0`
— **23PASS/0FAIL/0timeout**, включая import/startup, lifecycle, классовые
анимации/смерти/гаммы, масштабы, движение/контакт/окружение, камеру и execution UI.
Внутри: unit_visual_contract33/0, current_art_zoom460/0.
Отчёт: `test_reports/demo-8122c8556e4345c89045ed95e8619f51/`.

В этом импортированном project отдельный [render_audit.gd](render_audit.gd):
**44/0**. Восьми fixture (4 класса×2 стороны) тень меняет только область овала;
непрозрачные пиксели тела/HUD прежние, выключение возвращает точный RGBA.
Реальная сцена: видимое пятно, движение на0.25/0.5/0.75, стабильная форма при
выпаде/сжатии/повороте, node reuse при refresh/resize; state/RNG/counters/revision/phase
прежние. Снимки battle/battle-before1600×1200; all-classes1024×1024.
Первый standalone-аудит12/8 не задал UNIT до `_ready`, как это делает доска;
fixture исправлен, runtime не менялся. После фона галереи повторно44/0.
Логи: `test_reports/unit-round-shadows-20261017/`.

Все157 отслеживаемых PNG под assets сверены по Git blob:0 отличий.
Исходные alpha/геометрия/посадка/тайминги/изометрия4:3 сохранены.
Ведущий просмотрел поле и галерею. [Независимое ревью](review.md): APPROVE.
Core/preview/live/worker/queue/RNG/save/frozen не изменялись.
Full/core, ручные F5/editor/DPI/GPU-матрица и финальная арт-приёмка не выполнены.

Чужая main_menu.tscn сохраняет SHA256
`A64C270256EBF2EA073081200BE23028F792F42C3CA98F83A6499C1300A68668`;
она и остановленная untracked серия03 исключены из staging/commit.
Прежний HANDOFF сохранён рабочими байтами в history-20261017-12, SHA256
`59bb326c077efeca5b1136c312a421cd1eea7c3ea23497cfe17d97187cc73bf0`;
нормализованные LF совпадают с прежним Git blob. Размеры/ссылки/diff проверены
при завершении. Без push и автоматического следующего этапа.

Входные документы (символы LF; архив отдельно):
- AGENTS:4565→4565; PROJECT_CONTEXT:3491→3491; CODEX_WORKFLOW:4482→4482.
- CODEX_HANDOFF:2487→2375,32 строки; запреты и открытая приёмка сохранены.
