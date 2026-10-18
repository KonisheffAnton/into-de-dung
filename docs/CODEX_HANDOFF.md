# Передача — 2026-10-18: очистка диорам
D:\Games\into-de-dung; main; base d4397afe2887a9dc28a4029833e9ec52d90334c1.
[Фоны/сравнение](art/hub-diorama-cleanup-20261018/README.md): bright/muted,1672×941.
По U исправлены кровли/опоры, лодка, мост, предметы кузницы/лавки, шум воды/листвы.
Башня разрушена, без входа/наружных лестниц; маг сохранён, удалённые11людей не вернулись.
ImageGen6 вызовов, исходники/промпты сохранены; 16PNG/копии PASS,
review семи зон APPROVE для preview. В игру не внедрено; нужен отзыв U.
[Прежние фоны/позиции](art/hub-diorama-people-cutout-20261018/README.md),70a80fe:
координаты приблизительные; прозрачные наборы перерисованы/смещены, не точные слои.
[Прежние V4](art/hub-diorama-wide-20261018/README.md), [арт-направление](ART_DIRECTION.md).
WallTrap d4397af: 4пресета z1→0, панель не закрывает стоящего героя.
Import/startup PASS; hazards_ui107/0, environment_visual_contract15/0,
presentation_foundation143/0; отрицательный контроль старого z1 FAIL; review APPROVE.
[Контракт](ENVIRONMENT_HAZARDS_V1.md), [кадры](../test_reports/wall-unit-occlusion-20261018/README.md).
U принял прежний запуск/маршрут с поправкой: c981fb0 оставил конечную стрелку.
Import/startup PASS, move_forecast_ui80/0; review APPROVE; новый вид ждёт U.
[Маршрут](../test_reports/movement-route-endpoint-20261018/README.md),
[launcher9a4f98e/замеры](REPOSITORY_STATE.md).
Прежние HUD/art не приняты автоматически: [поле](../test_reports/hud-unclipped-20261018/README.md),
[воин/тайлы](art/warrior-tile-scene-20261018/README.md), боковины30px, Лучница.
Круглые тени live; направленные/2:1 и idle A/B — preview. Камера, серии04/05,
баланс яда открыты; PixelLab отменён. Поджог/яд/скрытые плашки/одежда сохранены.
Чужие scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/
не трогать/reset/stage/commit; manifest03 устарел, SHA сцены проверить при сдаче.
Core/preview/live/worker/queue/RNG/save/frozen сохранять; без нового баланса.
Без push/sidebar/расписаний. Следующий этап только по выбору U.
Новых full/core/ручных F5/editor/DPI/GPU/финальной приёмки нет.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261018-10.md), [HISTORY](HISTORY.md).
После этапа — Conventional Commit, короткий HANDOFF; прежний побайтно в отдельный
архив+HISTORY. В финале/при блокере предложить новый чат и полный промпт блоком:
HEAD, результат, docs/artifacts, остаток, ограничения, проверки и это же правило.
Чат автоматически не создавать; правило переносить дальше.
