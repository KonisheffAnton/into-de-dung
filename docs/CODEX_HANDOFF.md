# Передача — 2026-10-31: исправление обрезки большого поля

D:\Games\into-de-dung; main; base baab77586c6a65b8643b0897d4d9967e86dffa95.
U показал, что прозрачный HUD не решил проблему: поле24×16 обрезалось старым
прямоугольником Board. Причина — _sync_layout_geometry заново включал clip_contents
для большой карты. Теперь он всегда false, включая refresh/resize/pending-геометрию.
Поле при104% продолжается под информационным HUD до края окна; кнопки/карты,
ввод BattleHudInput, масштаб/посадка/механики прежние.
Владелец: [HUD](BATTLE_HUD_SCENES_V1.md), [архитектура](ARCHITECTURE.md).

Import/startup PASS; dungeon_room_comparison1983/0, camera110/0, HUD306/0.
Ввод с новой визуальной регрессией: GPU163/0, headless155/0 (GPU skipped явно).
На той же изолированной копии старый Board дал13 ожидаемых FAIL, включая8
проверок пикселей у четырёх сторон до/после resize. Исправленный Board возвращён.
Снимок: test_reports/battle-hud-clipping-20261031/screenshots/battle-hud-large-104-under-hud.png.
Отчёт: test_reports/battle-hud-clipping-20261031/validation.json.
Gate: test_reports/demo-c72eb5ac42b74d8686dccd2e8000645f/.
Независимое APPROVE. Full/core и ручные F5/движение/zoom/DPI не запускались;
реальный цикл worker/показа не прогонялся: новый тест моделирует pending-геометрию.

Чужие scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/
сохранены33/33 SHA; не reset/stage/commit. Без push/sidebar tasks/расписаний.
Core/preview/queue/RNG/save/frozen прежние. Щитоносец17/Воин11 и их открытая
цветовая приёмка/анимации прежние; вопросы Колоды/упора/плавности не закрывались.
Далее — отзыв U по исправлению, новый срез без поручения не начинать.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261031-2.md), [HISTORY](HISTORY.md).

Завершение: проверки, локальный Conventional Commit, короткий HANDOFF;
прежний побайтно отдельным архивом+HISTORY. В финале/при блокере предложить новый
чат и полный самодостаточный промпт: HEAD, результат, docs/artifacts, остаток,
ограничения, проверки и это же правило. Чат автоматически не создавать.
