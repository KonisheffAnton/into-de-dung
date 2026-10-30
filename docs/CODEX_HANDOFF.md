# Передача — 2026-10-31: прозрачный боевой HUD

D:\Games\into-de-dung; main; base a1fe6e99c1a4d8ddb6dd593c3ddc43e93c1706cd.
По U убраны подложки HUD/диагностики/прогноза. Текст пропускает мышь к полю,
кнопки/карты/полосы прокрутки сохраняют ввод. BattleHudInput передаёт события
в прежний Board по всей области окна; камера, размеры и NodePath сохранены.
Страница хаба скрыта во время боя и восстанавливается при результате/ошибке.
Владелец: [боевой HUD](BATTLE_HUD_SCENES_V1.md); [архитектура](ARCHITECTURE.md).
Core/preview/queue/RNG/save/frozen не менялись.

Import/startup PASS; battle_hud_authoring306/0, battle_camera_ui110/0,
turn_forecast_ui32/0. Новый ввод GPU113/0, headless107/0;
mage_deck_ui133/0 после исправления нижней страницы, hero_hub_ui40/0.
Launcher Python30/0. Независимое ревью фиксированного результата APPROVE.
Отчёт и снимки: test_reports/battle-hud-input-20261030/validation.json;
первичный gate: test_reports/demo-5393d8aa3efa4cf2a1a4886fb76d1095/.
Прямые финальные прогоны выполнены в той же изолированной импортированной копии.
Начальные сбои нового теста были ошибками fixture/координат, исправлены.
Full/core не запускались. Ручные F5/движение/zoom/DPI и drag scrollbar открыты.

Щитоносец17/Воин11 прежние: [пакет палитры](art/shieldbearer-palette-20261030/README.md).
Оценка цветов и авторские анимации17/11 открыты; прежние вопросы Колоды/упора/
плавности не закрывались этим этапом. Далее — отзыв по HUD; новый срез не начинать.
Чужие scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/
сохранены (33/33 SHA); не reset/stage/commit. Без push/sidebar tasks/расписаний.
[Прежняя передача побайтно](CODEX_HANDOFF.history-20261031.md), [HISTORY](HISTORY.md).

Завершение: проверки, локальный Conventional Commit, короткий HANDOFF;
прежний побайтно отдельным архивом+HISTORY. В финале/при блокере предложить
новый чат и полный самодостаточный промпт: HEAD, результат, docs/artifacts,
остаток, ограничения, проверки и это же правило. Чат автоматически не создавать.
