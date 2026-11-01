# Передача — 2026-11-01: только классы и направление команд

D:/Games/into-de-dung; main; base e69239208f6fcb494ca5d48567d8b980791c14cf.
Исправлено уточнение пользователя: новый F5 — ровно5 бойцов, Разбойник/Маг/Воин
у игрока, Щитоносец/Лучница у противника. Нет добивки NPC/повторов врагов.
Именованный класс без арта не заимствует EnemyPreset; Маг пока условная «М».
PLAYER смотрит вправо, ENEMY влево относительно исходника02/17/11; атака
временно поворачивает к цели и возвращает сторону. Idle-часы/опора сохранены.
Выбранные ранее skins/клипы не менялись, нового арта нет.
Core-команды/preview/queue/игровой RNG/save/frozen не менялись; каталоги1–3 сохранены.

Владельцы: CLASS_SHOWCASE_V1, CHARACTER_SKINS_V1, BATTLE_VISUAL_SCENE_CONTRACT;
маршрут — PROJECT_CONTEXT. [Отчёт/снимки](art/class-roster-facing-20261101/README.md).
Логи/manifests/negative control/review: test_reports/class-roster-facing-20261101/.
Прежний пакет: assets/art_presets/approved/character_skins_v1/.

Изолированные import/startup PASS; class229/0; UI37/0 headless,39/0 GPU;
skins262/0 headless,291/0 GPU; attack styles604/0 в обоих режимах; Python30/0.
Смежные PASS и независимое APPROVE — отчёт. Старое поведение в той же копии
дало ожидаемые18 FAIL без script errors; затем копия побайтно восстановлена.
Full/core здесь не повторялись; прежний core9424/0 — этап e692392.
Прежний turn_forecast_ui26/3 остаётся. Ручной F5/движение/zoom/DPI не закрыты.

Далее — отзыв пользователя о составе/направлении/скинах и ручной плейтест.
Новый срез без поручения не начинать. Стабильные60 FPS не заявлены;
[performance-остаток](performance/battle-magic-pacing-20261101.md) открыт.
Сохраняются вопросы HUD/Колоды, художественной приёмки стыков и посадки.

Чужие scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/
не reset/stage/commit;33 SHA сверены. Один Godot runner, isolated project;
без root import/служб/драйверов/принудительного фокуса. Без push/sidebar tasks/
расписаний. После коммита остаются только эти чужие пути.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261101-5.md), [HISTORY](HISTORY.md).

Завершение: проверки, локальный Conventional Commit, короткий HANDOFF;
прежний побайтно отдельным архивом+HISTORY. В финале/при блокере предложить
новый чат и полный самодостаточный промпт: HEAD, результат, docs/artifacts,
остаток, ограничения, проверки и это же правило. Чат автоматически не создавать.
