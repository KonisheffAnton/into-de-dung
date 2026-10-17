# Проверки — 2026-10-17

Base main `f1542591be6c9e0c7a8fdad3aed24a382a336664`.
Правка только оформления боковин floor/platform:18→30px, зелёный→коричневый.
Godot4.7.2, OpenGL Compatibility, RTX3050 Laptop.

Свежий изолированный прогон:
`python tools/demo/isolate.py --godot <Godot4.7.2> --render-check --only art_trial_battle current_art_zoom --screen 0`.
Отчёт `test_reports/demo-5ed19621014d4ab68efeb783ea554187/`:
**23PASS/0FAIL/0timeout**, включая import/startup и автоматически добавленный
visual gate. `art_trial_battle`450/0, `current_art_zoom`460/0.
Три runtime/test файла сверены с проверенной изолированной копией.

`render_audit.gd`: **17/0**, лог
`test_reports/tile-brown-depth-20261017/render-audit.log`, без ошибок/предупреждений.
Сравнение до/после проверяет пол, положительный/отрицательный уступ, WALL и VOID;
верхние внутренние пиксели и геометрия/top/picking/root сохранены.
WALL/VOID побайтно одинаковы в парных снимках. `battle.png` снят из реального
HeroHubBattleView с фиксированной фабричной сессией; новое ImageGen не применялось.

158 исходных PNG из assets сверены побайтно с base, изменений0.
Чужой `scenes/demo/main_menu.tscn` сохранён, SHA256
`A64C270256EBF2EA073081200BE23028F792F42C3CA98F83A6499C1300A68668`.
Он и остановленная untracked серия03 исключены из staging/commit. Без push.

Full/core, ручные F5/editor/DPI/GPU-матрица и финальная художественная приёмка
в этом этапе не выполнялись. Дальше только следующий отзыв U.

Независимое read-only ревью game_reviewer: **APPROVE** фиксированного diff,
снимков и проверок. Дефектов sync/reuse/picking/палитры WALL не выявлено;
редкие сочетания экстремальных высот/перекрытий вручную не проверены.

Прежний HANDOFF сохранён побайтно в `CODEX_HANDOFF.history-20261017-14.md`,
SHA256 `f00462cd4a5d1e324278a46b4a54d7a00e77e8b760e176f39fd6679fcf99be29`;
нормализованный Git blob совпадает с прежним HANDOFF. Ссылка добавлена в HISTORY.
Входные документы, символы LF (архив отдельно): AGENTS4565→4565,
PROJECT_CONTEXT3491→3491, CODEX_WORKFLOW4482→4482, HANDOFF2477→2247/30строк.
Запреты, открытые вопросы и границы приёмки сохранены; локальные ссылки и diff проверены.
