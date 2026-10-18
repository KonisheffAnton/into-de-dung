# Передача — 2026-10-18: две палитры диорамы V4
D:\Games\into-de-dung; main; basec981fb05bbf2d54146cfdcae091579dbb060084f.
U принял прежние запуск/маршрут с поправкой: стрелка только на конце.
c981fb0: одна конечная стрелка; pending/кольцо/расчёт прежние.
[Контракт](BATTLE_HUD_SCENES_V1.md), [проверки](../test_reports/movement-route-endpoint-20261018/README.md).
Чистый import/startup PASS; move_forecast_ui80/0. Review APPROVE.
Новый вид стрелки ждёт отзыва U; новых full/core/H1 zoom/ручных проверок нет.
Launcher9a4f98e: interactive кэш/SHA256 sync, --fresh чистая копия;
check/render прежние. Cold55.3с/warm7.8с подготовки, не до меню.
[Запуск](REPOSITORY_STATE.md), [замеры](../test_reports/interactive-launcher-20261018/README.md).
Сохранена отдельная арт-проба: [две палитры диорамы](art/hub-diorama-wide-20261018/README.md).
U: широкий остров, заброшенные дома, башня в скале; без наружных лестниц,
башня монументальнее, без входа и полуразрушенная. V4: bright/muted,1672×941.
ImageGen8 вызовов; оригиналы/V1–V4/промпты/хеши сохранены. Review preview APPROVE.
Финальный арт ждёт U; мелкие детали перерисованы, точной RGB/геометрии нет.
Внедрение арта не разрешено. Остальные HUD/art-пробы не приняты автоматически:
[поле без clipping](../test_reports/hud-unclipped-20261018/README.md),
[воин/тайлы](art/warrior-tile-scene-20261018/README.md): цвета первого листа/размер второго.
[Боковины](art/tile-brown-depth-20261017/README.md)30px; перекрытия/финальный арт открыты.
[Лучница](art/archer-placement-20261017/README.md): anchor(68,95), PNG/тайминги прежние.
Круглые тени внедрены; направленные/2:1 — preview. Idle A/B не внедрены;
разворот нормальный, вопрос о камере. Серии04/05 ждут выбора; PixelLab отменён.
Поджог/яд мага, скрытые плашки, одежда Лучницы сохранены; баланс яда открыт.
Чужие main_menu.tscn и docs/art/battlefield-reference-03-20261017/ не трогать:
не reset/stage/commit; manifest03 устарел. SHA сцены проверять при сдаче.
Core/preview/live/worker/queue/RNG/save/frozen сохранять; без нового баланса.
Без push/sidebar/расписаний; новый этап только после выбора U.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261018-7.md), [HISTORY](HISTORY.md).
После этапа — Conventional Commit, короткий HANDOFF; прежний побайтно в отдельный
архив+HISTORY. В финале/при блокере предложить новый чат и полный промпт блоком:
HEAD, результат, docs/artifacts, остаток, ограничения, проверки и это же правило.
Чат автоматически не создавать; правило переносить дальше.
