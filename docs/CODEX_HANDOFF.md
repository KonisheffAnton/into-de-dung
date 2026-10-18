# Передача — 2026-10-18: пустые диорамы и глубина WallTrap
D:\Games\into-de-dung; main; base70a80fe677b9ec94dd79d25280dde75480108f6f.
[Фоны/координаты/исходники](art/hub-diorama-people-cutout-20261018/README.md):
70a80fe: bright/muted-v5,1672×941; убраны группа8, кузнец, продавец и покупатель.
Маг/лавка/кузница сохранены. V4-оригиналы побайтные, места фигур приблизительные.
Прозрачные наборы перерисованы/смещены, не точные слои. ImageGen8 вызовов;
промпты/пробы/хеши сохранены. Файлы PASS; review preview APPROVE.
Арт не внедрён; приёмка за U. [Прежние V4](art/hub-diorama-wide-20261018/README.md).
WallTrap: 4 пресета z1→0, панель больше не закрывает стоящего героя.
Нативный repro/4 направления, активные шипы и передняя стена проверены;
старый z1 ломает новый пиксельный тест. Import/startup PASS, hazards_ui107/0,
environment_visual_contract15/0, presentation_foundation143/0; review APPROVE.
[Контракт](ENVIRONMENT_HAZARDS_V1.md), [отчёт/кадры](../test_reports/wall-unit-occlusion-20261018/README.md).
U принял прежний запуск/маршрут с поправкой стрелки. c981fb0: одна конечная
стрелка; pending/расчёт прежние. Import/startup PASS, move_forecast_ui80/0,
review APPROVE; новый вид ждёт U. [Отчёт](../test_reports/movement-route-endpoint-20261018/README.md).
Launcher9a4f98e: interactive кэш, --fresh чистый; check/render прежние.
[Запуск/прежние замеры](REPOSITORY_STATE.md).
Прежние HUD/art-пробы не приняты автоматически: [поле](../test_reports/hud-unclipped-20261018/README.md),
[воин/тайлы](art/warrior-tile-scene-20261018/README.md), боковины30px, Лучница.
Круглые тени внедрены; направленные/2:1 и idle A/B — preview. Вопрос камеры,
серии04/05, баланс яда открыты; PixelLab отменён. Поджог/яд/скрытые плашки/одежда сохранены.
Чужие main_menu.tscn и docs/art/battlefield-reference-03-20261017/ не трогать:
не reset/stage/commit; manifest03 устарел, SHA сцены проверять при сдаче.
Core/preview/live/worker/queue/RNG/save/frozen сохранять; без нового баланса.
Без push/sidebar/расписаний; следующий этап только после выбора U.
Новых full/core/ручных F5/editor/DPI/GPU и финальной приёмки нет.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261018-9.md), [HISTORY](HISTORY.md).
После этапа — Conventional Commit, короткий HANDOFF; прежний побайтно в отдельный
архив+HISTORY. В финале/при блокере предложить новый чат и полный промпт блоком:
HEAD, результат, docs/artifacts, остаток, ограничения, проверки и это же правило.
Чат автоматически не создавать; правило переносить дальше.
