# Передача — 2026-10-21: затухающий импульс отталкивания
D:\Games\into-de-dung; main; base 23adcdbdeb112df5b7aaa8c3fce382db5be47557.
По U скольжение: начальный рывок → затухание скорости до нуля за 0,24 с.
Наклон/штрихи гаснут со скоростью; одиночный и цепной сдвиг используют общий путь.
Атака/упор/падение, core и арт прежние. [Показ](BATTLE_PRESENTATION_REWORK.md),
[архитектура](ARCHITECTURE.md), [отчёт](../test_reports/push-damping-20261021/README.md).
Import/startup PASS; render push 805/0, consequences 2007/0, environment 323/0,
contact 149/0, всего 3284/0. PNG середины осмотрен; независимый review APPROVE.
Новых full/core/Python, ручных F5/editor/DPI/GPU нет; ощущение в бою ждёт U.
U вернулся к стилю: понравились приложенные прежние простые/умеренные референсы;
персонажи преимущественно фронтальные на изометрическом поле, важна читаемость.
После 3 ранних направлений показаны 2 новые сцены: руины у воды и зал над провалом.
Все концепты/референсы/промпты вне проекта:
C:/Users/Aston/.codex/generated_images/01a1503f-7a6c-76c1-b90c-bbd11fdf0311/
front-facing-scenes-20261021.json — финальные 2 сцены; style-comparison-20261021.json — ранние 3.
Выбор/внедрение стиля открыты; арт/сцены игры не менять без U.
Ранее b68776af: ножи/extra_attack, серия за 1 main; [контракт](EQUIPMENT_ATTACKS.md).
Прежние equipment 175/0, core 9424/0, worker/preview/live PASS; серия/баланс ждут U.
Четыре [диорамы](art/hub-diorama-layered-20261018/README.md) сохранены;
HTML не внедрять, playback/размещение/подсветка не приняты.
Crowd02/market05/latest smith03 выбраны; cleanup676d718 отклонён.
HUD/art, WallTrap/стрелка, воин/тайлы/боковины 30px, Лучница, камера/04/05,
баланс яда — [ART](ART_DIRECTION.md); круглые тени live, направленные/2:1 и idle A/B — preview.
Чужие dirty scenes/demo/main_menu.tscn и untracked docs/art/battlefield-reference-03-20261017/
не трогать/reset/stage/commit; SHA сцены в отчёте, manifest03 устарел.
Core/preview/live/worker/queue/RNG/save/frozen сохранять; без нового баланса.
Без push/sidebar/расписаний; следующий этап только по выбору U.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261021-2.md), [HISTORY](HISTORY.md).
После этапа — проверки, Conventional Commit, короткий HANDOFF; прежний побайтно
в отдельный архив+HISTORY. В финале/при блокере предложить новый чат и полный
промпт блоком: HEAD, результат, docs/artifacts, остаток, ограничения, проверки
и это же правило передачи. Чат автоматически не создавать; правило переносить.
