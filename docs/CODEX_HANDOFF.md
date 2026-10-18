# Передача — 2026-10-18: удаление фигур из двух диорам
D:\Games\into-de-dung; main; basec44d3ad018b34284520934b2a457ea2c7298a6cc.
[Фоны/координаты/исходники](art/hub-diorama-people-cutout-20261018/README.md):
bright/muted-v5,1672×941; убраны группа8, кузнец, продавец и покупатель.
Маг/лавка/кузница сохранены. V4-оригиналы побайтные, места фигур приблизительные.
Прозрачные наборы перерисованы/смещены, не точные слои. ImageGen8 вызовов;
промпты/пробы/хеши сохранены. Файлы PASS; review preview APPROVE.
Арт не внедрён; приёмка за U. [Прежние V4](art/hub-diorama-wide-20261018/README.md).
В работе разрешённая правка перекрытия стоящего героя панелью WallTrap:
4 сцены z1→0 и regression в hazards_ui ещё не закоммичены; точный repro получен.
[Проверки](../test_reports/wall-unit-occlusion-20261018/RESULT.md); завершить документацию/commit.
U принял прежний запуск/маршрут с поправкой стрелки. c981fb0: одна конечная
стрелка; pending/расчёт прежние. Import/startup PASS, move_forecast_ui80/0,
review APPROVE; новый вид ждёт U. [Отчёт](../test_reports/movement-route-endpoint-20261018/README.md).
Launcher9a4f98e: interactive кэш, --fresh чистый; check/render прежние.
Cold55.3с/warm7.8с — подготовка, не до меню. [Запуск](REPOSITORY_STATE.md).
Прежние HUD/art-пробы не приняты автоматически: [поле](../test_reports/hud-unclipped-20261018/README.md),
[воин/тайлы](art/warrior-tile-scene-20261018/README.md), боковины30px, Лучница.
Круглые тени внедрены; направленные/2:1 и idle A/B — preview. Вопрос камеры,
серии04/05, баланс яда открыты; PixelLab отменён. Поджог/яд/скрытые плашки/одежда сохранены.
Чужие main_menu.tscn и docs/art/battlefield-reference-03-20261017/ не трогать:
не reset/stage/commit; manifest03 устарел, SHA сцены проверять при сдаче.
Core/preview/live/worker/queue/RNG/save/frozen сохранять; без нового баланса.
Без push/sidebar/расписаний; следующий этап только после выбора U.
Новых full/core/ручных F5/editor/DPI/GPU и финальной приёмки нет.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261018-8.md), [HISTORY](HISTORY.md).
После этапа — Conventional Commit, короткий HANDOFF; прежний побайтно в отдельный
архив+HISTORY. В финале/при блокере предложить новый чат и полный промпт блоком:
HEAD, результат, docs/artifacts, остаток, ограничения, проверки и это же правило.
Чат автоматически не создавать; правило переносить дальше.
