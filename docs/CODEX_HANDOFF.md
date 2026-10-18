# Передача — 2026-10-18: заметный маршрут движения
D:\Games\into-de-dung; main; base9a4f98e2170bc357bf0439154387b9f697eed419.
Путь: gold/тёмный контур, pending пунктир, ready со стрелками;
конечная клетка gold alive / красная dead. Спокойные выделения/UI прежние.
[Контракт](BATTLE_HUD_SCENES_V1.md), [отчёт](../test_reports/movement-route-20261018/README.md).
Import/startup PASS; move_forecast_ui80/0, H1 75/100/140%, state/RNG прежние.
Review APPROVE; приёмка U открыта.
Launcher9a4f98e: interactive кэш/SHA256 sync, --fresh для чистой копии,
check/render прежние. Cold55.3с/warm7.8с подготовки, не до меню;
Python28+15 PASS, changed SVG/class/cancellation PASS, review APPROVE.
[Запуск](REPOSITORY_STATE.md), [замеры](../test_reports/interactive-launcher-20261018/README.md).
Поле без clipping HUD в1db80b3: GUI-ввод за Board прежний;
видимые за ним клетки вернуть камерой. [Проверки](../test_reports/hud-unclipped-20261018/README.md).
Арт-[сборка](art/warrior-tile-scene-20261018/README.md) ждёт отзыва U:
палитра первого листа/размер второго; внедрение арта не разрешено.
Full/core/ручных F5/editor/DPI/GPU и финальной приёмки нет.
Ранее: [боковины](art/tile-brown-depth-20261017/README.md),18→30px native128,
gate23/0,аудит17/0,158PNG побайтно; перекрытия вручную не проверены.
[Лучница](art/archer-placement-20261017/README.md): still/idle anchor(68,95), PNG/тайминги прежние.
Яркий Защитник — [эталон](../assets/art_presets/approved/defender_brighter_v1/README.md).
Круглые тени в игре; направленные/ракурс2:1 — preview.
Поджог/яд мага, скрытые плашки, одежда Лучницы сохранены; баланс яда открыт.
Idle A/B не внедрены; разворот нормальный, вопрос о камере.
Серии04/05: выбор открыт, сохранять оценки монстров, ракурс/размеры;
без подставок/спин, PixelLab отменён. Серия03 остановлена, manifest устарел; не менять.
Чужой scenes/demo/main_menu.tscn не трогать/reset/stage/commit; SHA256 прежний.
Вне этапа dirty: эта сцена и docs/art/battlefield-reference-03-20261017/.
Core/preview/live/worker/queue/RNG/save/frozen сохранять. Без push/sidebar/расписаний.
Далее — отзыв U; новый этап не начинать.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261018-5.md), [HISTORY](HISTORY.md).
После этапа — Conventional Commit, короткий HANDOFF; прежний побайтно в отдельный
архив+HISTORY. В финале/при блокере предложить новый чат и полный промпт блоком:
HEAD, результат, docs/artifacts, остаток, ограничения, проверки и это же правило.
Чат автоматически не создавать; правило переносить дальше.
