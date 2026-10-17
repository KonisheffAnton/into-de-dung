# Техническая проверка — 2026-10-17

Base: main `8976effd1e5f82feca7d6af915f58ebfffe40ea7`.
Godot4.7.2, OpenGL Compatibility, RTX3050 Laptop; один render backend, не GPU-матрица.

`python tools/demo/isolate.py --render-check --only archer_cloth_palette current_art_zoom --screen 0`:
`test_reports/demo-0672578dd8894ec39b7e54c39bf471ec/` —20PASS/2FAIL/0timeout.
Оба отказа были в тестовых fixture: старое ожидание скрытого EnemySprite внутри
союзной фигуры и нетипизированный status_entries. Оба исправлены без изменения runtime.
Остальные20 проверок PASS, включая импорт/startup, lifecycle, прежние гаммы,
анимации, камеру и worker UI; `current_art_zoom`460/0.

Свежий `--render-check --only archer_idle archer_cloth_palette --screen 0`:
`test_reports/demo-2a9b2603cd944ae1bebd10f2dd802659/` —4PASS/0FAIL/0timeout.
Внутри Archer idle65/0, cloth206/0. Все12×6 гамм меняют RGB только внутри маски,
alpha прежняя; возврат исходной гаммы побайтный. Общий HUD действует на Лучницу
без изменения state/RNG/counters/фазы; проверены отдельный враг, классы,
изоляция материалов и fallback. Полный gate после fixture-правок не повторялся.

Python isolate23/23. Pillow-проверки: cloth12/12; deterministic idle14/14,
12 исходных PNG побайтны, цикл2.6s. Все146 отслеживаемых PNG в trials сверены
с Git HEAD: изменений0. Ведущий просмотрел12 масок и галерею12×7; внешний вид
технически соответствует области ткани. Независимое ревью фиксированного кода,
масок и рендера: APPROVE после исправления обоих fixture.

Чужая main_menu.tscn сохранила SHA256
`A64C270256EBF2EA073081200BE23028F792F42C3CA98F83A6499C1300A68668`;
остановленная серия03 не тронута. Core/preview/live/worker/queue/RNG/save/frozen прежние.
Ручные F5/editor/DPI/GPU и итоговая приёмка цвета/анимации не выполнены;
full/core не запускались для этого среза.

Прежний HANDOFF сохранён точным рабочим файлом в history-20261017-9;
SHA256 `13bf8ceddc2788e89f7cceaeec25567c6e3f0c8ed605ab3393bf04a2d58375ca`.
Нормализация CRLF→LF также совпадает с прежним Git blob.

Входные документы (символы LF; архивы отдельно):
- AGENTS.md: 4565 -> 4565 LF chars
- docs/CODEX_HANDOFF.md: 2460 -> 2497 LF chars
- docs/PROJECT_CONTEXT.md: 3491 -> 3491 LF chars
- docs/CODEX_WORKFLOW.md: 4482 -> 4482 LF chars
