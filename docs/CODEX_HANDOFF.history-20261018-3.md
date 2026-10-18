# Передача — 2026-10-18: поле без обрезки HUD
D:\Games\into-de-dung; main; base 621048d9e26e124d6b310e2b60cff864d11968c1.
U попросил временно убрать UI-границы, закрывающие поле.
Board не обрезает рисунок; HUD выше поля. Область GUI-ввода прежняя:
видимые за ней клетки для клика нужно вернуть сдвигом/масштабом.
[Контракт](BATTLE_HUD_SCENES_V1.md), [кадры/отчёт](../test_reports/hud-unclipped-20261018/README.md).
Import/startup PASS; camera110/0, HUD306/0, execution28/0; launcher5/0.
Парные H1/deck capture и zoom PASS, state/RNG прежние. game_reviewer APPROVE.
Новых full/core/ручных F5/editor/DPI и финальной приёмки нет.
Арт-[сборка](art/warrior-tile-scene-20261018/README.md) ждёт отзыва U:
палитра первого листа/размер второго; внедрение арта не разрешено.
Дальше отзыв U о видимости; новый этап автоматически не начинать.
Ранее: [коричневые боковины](art/tile-brown-depth-20261017/README.md),
18→30px native128, gate23/0, аудит17/0,158PNG побайтно; редкие перекрытия
вручную не проверены. [Лучница](art/archer-placement-20261017/README.md):
still/idle anchor(68,95), PNG/тайминги прежние.
Яркий Защитник — [игровой эталон](../assets/art_presets/approved/defender_brighter_v1/README.md).
Круглые тени в игре; направленные/ракурс2:1 — preview.
Поджог/яд мага, спокойные выделения/скрытые плашки, одежда Лучницы сохранены;
баланс яда открыт. Idle A/B не внедрены; разворот нормальный, вопрос о камере.
Серии04/05: выбор открыт, сохранять оценки монстров, ракурс/размеры;
без подставок/спин, PixelLab отменён. Серия03 остановлена, manifest устарел; не менять/не возобновлять.
Чужой scenes/demo/main_menu.tscn не трогать/reset/stage/commit; SHA256 прежний.
Незакоммиченное вне этапа: эта сцена и docs/art/battlefield-reference-03-20261017/.
Core/preview/live/worker/queue/RNG/save/frozen сохранять. Без push/sidebar/расписаний.
Прежний HANDOFF: [побайтный архив](CODEX_HANDOFF.history-20261018-2.md), [HISTORY](HISTORY.md).
После этапа — Conventional Commit, короткий HANDOFF; прежний побайтно
в отдельный архив+HISTORY. В финале/при блокере предложить новый чат и полный
промпт блоком: HEAD, результат, docs/artifacts, остаток, ограничения, проверки
и это же правило. Чат автоматически не создавать; правило переносить дальше.
