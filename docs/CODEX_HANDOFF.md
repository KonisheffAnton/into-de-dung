# Передача — 2026-11-03: Маг и Лучница в игре

D:/Games/into-de-dung; main; base f74a863f086861e00a89d8136235246d94620ced.
Внедрены Маг02 «Капюшон звёзд» и Лучница14-04: обоим idle1/5,
смерть3; способность5 Магу,4 Лучнице. Владелец: CHARACTER_SKINS_V1.
Основной idle1, дополнительный5 после3–6 циклов; отдельные визуальные часы.
Кадры/листы побайтные, полный кадр, ArtRoot0.8. Выстрел/каст использует
выбранный клип; after ждёт восстановления/смерти. Портреты едины с боем.

[Отчёт, снимки, validation/review](art/mage-archer-integration-20261103/README.md).
Логи: test_reports/mage-archer-integration-20261103/.
Исходные пробы: docs/art/mage02-animation-20261103/ и
archer14-04-animation-20261103/. Остальные варианты не внедрены.

PASS isolated import/startup; новые маршруты415/0 headless и GPU;
skins1074/0 headless,1130/0 GPU; hub33/0 и34/0; showcase229/0,
UI45/0 и47/0. GPU coverage53/0, zoom496/0, attack styles611/0;
смежные — validation.json. Python35/0;27 PNG/693 ячейки побайтно.
Независимое APPROVE; исходные неудачные прогоны сохранены в логах.
Full/core не повторялись. Ручные F5/движение/zoom/DPI, стыки и
художественная приёмка открыты; у способности4 Лучницы исходная стрела
доходит до края. Автоматической ретуши нет. Дальше — отзыв пользователя.
Без поручения новый срез/генерацию не начинать.

F5 остаётся ровно5 классов, PLAYER вправо/ENEMY влево; атака поворачивает
к цели и возвращает сторону команды. Разбойник0.72, выбранные клипы прежние.
Каталоги1–3 не мигрируют; core/preview/queue/RNG/save/frozen сохранены.
Прежний остаток: presentation_foundation141/2, turn_forecast_ui26/3,
performance, HUD/Колода. Не считать прежние проверки повторёнными.
Чужие scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/
не reset/stage/commit. Один Godot runner, isolated project; без root import,
служб/драйверов/принудительного фокуса/push/sidebar tasks/расписаний.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261103-3.md), [HISTORY](HISTORY.md).

Завершение: проверки, локальный Conventional Commit, короткий HANDOFF;
прежний побайтно отдельным архивом+HISTORY. В финале/при блокере предложить
новый чат и полный самодостаточный промпт: HEAD, результат, docs/artifacts,
остаток, ограничения, проверки и это же правило. Чат автоматически не создавать.
